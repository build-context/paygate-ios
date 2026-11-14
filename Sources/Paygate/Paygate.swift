import Foundation
import StoreKit
import UIKit

public final class Paygate {

    /// Date-based API version (Stripe-style). Must match a version supported by the backend.
    public static let apiVersion = "2026-09-07"

    private static var apiKey: String?
    /// The Cloud Run hostname, not `api.usepaygate.com`.
    ///
    /// The custom domain's DNS is in place (it CNAMEs to `ghs.googlehosted.com`)
    /// but the mapping is not serving yet — TLS does not complete, so every
    /// request fails before it reaches the API. This is compiled into shipped
    /// apps and cannot be fixed remotely, so it stays on the hostname that
    /// actually answers until the mapping is live.
    ///
    /// Switch back once `curl https://api.usepaygate.com/health` returns 200.
    /// Cloud Run keeps serving this hostname indefinitely, so already-shipped
    /// builds continue to work either way.
    private static var baseURL: String = "https://api-crtw3ydz4q-uc.a.run.app"
    private static var flowCache: [String: FlowData] = [:]
    private static var gateCache: [String: GateFlowResponse] = [:]

    static var flows: FlowRepository!
    static var gates: GateRepository!
    static var products: ProductRepository!

    /// Initialize the SDK, load what the user owns (subscriptions and
    /// lifetime unlocks), and begin listening for transaction updates.
    ///
    /// - Parameters:
    ///   - apiKey: Your Paygate API key.
    ///   - baseURL: Override the default API base URL.
    @MainActor
    public static func initialize(
        apiKey: String,
        baseURL: String? = nil
    ) async {
        self.apiKey = apiKey
        if let baseURL = baseURL {
            self.baseURL = baseURL
        }

        flows = FlowRepository(baseURL: self.baseURL, apiKey: apiKey)
        gates = GateRepository(baseURL: self.baseURL, apiKey: apiKey)
        products = ProductRepository(baseURL: self.baseURL, apiKey: apiKey)

        await StoreKitManager.shared.start()
        await StoreKitManager.shared.loadPurchasedProducts()
        let ids = await StoreKitManager.shared.activeEntitlementProductIDs
        print("[Paygate] Entitled product IDs:", ids.sorted().joined(separator: ", "))

        Task {
            await PresentationAnalytics.flushPendingOutbox(apiKey: apiKey, baseURL: self.baseURL)
        }
    }

    /// Force a store country for previewing prices, e.g. `"CA"`.
    ///
    /// **Testing only, and it stops working on the `production` channel.** The
    /// server refuses an override on production and logs that it did — a
    /// preview switch left on in a shipped build would show every reader a
    /// price nobody is charged, which is the rejection storefront pricing
    /// exists to prevent rather than cause.
    ///
    /// Set it before launching a gate; leave it `nil` to use the real store
    /// country.
    public static var storefrontOverride: String?

    /// The reader's App Store country, e.g. `"CA"` — `nil` until StoreKit
    /// answers.
    ///
    /// Read fresh on every launch rather than cached once per process: a user
    /// can change their App Store country mid-session, and a stale value here
    /// prices the paywall for a country they have left.
    public static var currentStorefront: String? {
        get async {
            await Storefront.current?.countryCode
        }
    }

    /// A random id for this install, created on first use and persisted.
    ///
    /// Sent with every request so a gate gives this reader the same flow —
    /// and so the same price — on every launch, rather than re-rolling its
    /// weights each time. Deleting the app discards it.
    ///
    /// Not an advertising identifier and not shared with anything else; it is
    /// exposed only so you can log it alongside your own analytics or quote it
    /// in a support conversation.
    public static var installId: String {
        InstallId.current
    }

    /// Your own id for the signed-in user, if you have one.
    ///
    /// When set, a gate assigns its flow by this instead of by ``installId``,
    /// so one person sees the same flow on their phone and their iPad, and
    /// after a reinstall. Optional: without it, assignment is per install.
    ///
    /// Setting it moves a reader **once**, from their install's flow to their
    /// user's, so set it as early as you know who they are — ideally before
    /// the first gate launch. Clearing it (sign-out) moves them back to the
    /// install's flow.
    ///
    /// Sent as a request header. Use an opaque id (a database key, a UUID),
    /// not an email address.
    public static var appUserId: String? {
        didSet {
            // A gate cached for this process was assigned to the old id.
            if appUserId != oldValue { gateCache.removeAll() }
        }
    }

    /// ``appUserId`` as sent: trimmed, and `nil` when empty or too long for
    /// the server to accept.
    static var normalizedAppUserId: String? {
        guard let trimmed = appUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.count <= 256,
              !trimmed.contains(where: \.isNewline) else { return nil }
        return trimmed
    }

    /// Cache key for a fetched flow or gate.
    ///
    /// The storefront is part of the key because the server bakes resolved
    /// prices into the HTML. Keyed by id alone, a gate set to
    /// `cache_on_first_launch` would serve whatever country happened to open it
    /// first to everyone afterwards — the same wrong-price bug, with a harder
    /// repro.
    static func cacheKey(_ id: String, storefront: String?) -> String {
        // The platform is constant within a build, so it adds nothing here.
        "\(id)|\(storefront ?? "-")"
    }

    /// Force the distribution channel, whatever this build actually is.
    ///
    /// **Rarely needed on iOS**, because ``currentChannel`` can tell a
    /// TestFlight build from a shipped one on its own — a TestFlight install
    /// carries a `sandboxReceipt`. It exists for parity with Android, where the
    /// equivalent is not detectable at all: Play tells an installed app nothing
    /// about which track served it, so an app there has to say so itself.
    ///
    /// Set it before ``launchGate(_:bounces:presentationStyle:appearance:)``.
    /// Unlike `storefrontOverride` this is **not** refused in production — it
    /// selects which of your own gate settings apply, and cannot reprice
    /// anything or reveal a paywall a gate has switched off.
    public static var channelOverride: DistributionChannel?

    /// Current distribution channel (iOS).
    ///
    /// An explicit ``channelOverride`` wins over everything: an app that knows
    /// what it shipped is a better authority than any inference here.
    public static var currentChannel: DistributionChannel {
        if let channelOverride { return channelOverride }
        #if DEBUG
        return .debug
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
            ? .testing
            : .production
        #endif
    }

    /// App Store product IDs the user owns right now: active subscriptions
    /// and non-consumables (lifetime unlocks). Consumables are not included.
    ///
    /// Read from StoreKit's on-device record, so it answers offline.
    public static var activeEntitlementProductIDs: Set<String> {
        get async {
            await StoreKitManager.shared.activeEntitlementProductIDs
        }
    }

    /// The old name for ``activeEntitlementProductIDs``. It now includes
    /// lifetime unlocks as well as subscriptions: before 0.6.0 a non-consumable
    /// never appeared here, so an app checking it locked out lifetime buyers.
    @available(*, deprecated, renamed: "activeEntitlementProductIDs")
    public static var activeSubscriptionProductIDs: Set<String> {
        get async {
            await StoreKitManager.shared.activeEntitlementProductIDs
        }
    }

    /// Restore purchases, for a "Restore purchases" row in your own settings.
    ///
    /// Syncs with the App Store (which may ask for the Apple Account
    /// password) and returns what the user owns afterwards — empty when there
    /// is nothing to restore. Throws `StoreKitError.userCancelled` if they
    /// cancel that prompt. If the sync fails for another reason but the device
    /// already knows of a purchase, that purchase is returned rather than the
    /// error; only "failed, and nothing known" throws.
    ///
    /// A paywall's own Restore button (`paygate.restore()` in the flow) does
    /// not need this; the SDK handles it.
    @discardableResult
    public static func restorePurchases() async throws -> Set<String> {
        do {
            try await StoreKitManager.shared.syncPurchases()
        } catch StoreKitError.userCancelled {
            throw StoreKitError.userCancelled
        } catch {
            let known = await StoreKitManager.shared.activeEntitlementProductIDs
            if known.isEmpty { throw error }
            print("[Paygate] restorePurchases: sync failed (\(error.localizedDescription)); " +
                  "returning the purchases already on this device")
            return known
        }
        return await StoreKitManager.shared.activeEntitlementProductIDs
    }

    /// Launch a paywall flow.
    /// - Parameters:
    ///   - flowId: The ID of the flow to present.
    ///   - appearance: Color scheme to pin the flow to. Flows carry no
    ///     appearance of their own — that setting lives on the gate — so this
    ///     defaults to `.system`, which follows the device.
    /// - Returns: A typed result with status, optional productId, and optional data.
    @MainActor
    public static func launchFlow(
        _ flowId: String,
        bounces: Bool = false,
        presentationStyle: PaygatePresentationStyle = .sheet,
        appearance: PaygateAppearance = .system
    ) async throws -> PaygateLaunchResult {
        guard let apiKey = apiKey else {
            throw PaygateError.notInitialized
        }

        // Never block the launch on StoreKit. If the storefront is not known
        // yet the server falls back to the template's key — a paywall that
        // renders late is worse than one showing the fallback price.
        let storefront = await Paygate.currentStorefront
        let flowKey = Paygate.cacheKey(flowId, storefront: storefront)

        let flowData: FlowData
        if let cached = flowCache[flowKey] {
            flowData = cached
        } else {
            let fetched = try await flows.getFlow(flowId, storefront: storefront)
            flowCache[flowKey] = fetched
            flowData = fetched
        }

        let idMap = flowData.productIdMap
        let activeIds = await StoreKitManager.shared.activeEntitlementProductIDs
        for storeId in idMap.values {
            if activeIds.contains(storeId) {
                return PaygateLaunchResult(status: .alreadySubscribed, productId: storeId)
            }
        }

        guard let presenter = topViewController() else {
            throw PaygateError.noPresentingViewController
        }

        return try await withCheckedThrowingContinuation { continuation in
            let paygateVC = PaygateViewController(
                flowData: flowData,
                apiKey: apiKey,
                baseURL: baseURL,
                bounces: bounces,
                gateId: nil,
                appearance: appearance
            ) { result in
                switch result {
                case .dismissed(let data):
                    continuation.resume(returning: PaygateLaunchResult(status: .dismissed, data: data))
                case .skipped(let data):
                    continuation.resume(returning: PaygateLaunchResult(status: .dismissed, data: data))
                case .purchased(let productId, let data):
                    continuation.resume(returning: PaygateLaunchResult(status: .purchased, productId: productId, data: data))
                case .error(let error):
                    continuation.resume(throwing: error)
                }
            }
            switch presentationStyle {
            case .fullScreen:
                paygateVC.modalPresentationStyle = .fullScreen
                paygateVC.modalTransitionStyle = .coverVertical
            case .sheet:
                paygateVC.modalPresentationStyle = .pageSheet
                if #available(iOS 15.0, *),
                   let sheet = paygateVC.sheetPresentationController {
                    sheet.detents = [.large()]
                    sheet.prefersGrabberVisible = true
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                }
            }
            presenter.present(paygateVC, animated: true)
        }
    }

    /// Launch a gate, which shows one of its flows chosen by the configured
    /// weights. The choice is sticky: the same reader (``appUserId`` if set,
    /// otherwise ``installId``) gets the same flow every time, until the
    /// gate's weights change.
    /// - Parameters:
    ///   - gateId: The ID of the gate to present.
    ///   - appearance: Overrides the appearance configured on the gate. Pass
    ///     this when your app has its own light/dark setting: a WebView follows
    ///     the device, not your app, so leaving it to the gate means the paywall
    ///     can disagree with the screen behind it. `nil` (the default) uses
    ///     whatever the gate is set to.
    /// - Returns: A typed result with status, optional productId, and optional data.
    @MainActor
    public static func launchGate(
        _ gateId: String,
        bounces: Bool = false,
        presentationStyle: PaygatePresentationStyle = .sheet,
        appearance: PaygateAppearance? = nil
    ) async throws -> PaygateLaunchResult {
        guard let apiKey = apiKey else {
            throw PaygateError.notInitialized
        }

        let channel = Paygate.currentChannel
        // Never block the launch on StoreKit — see launchFlow.
        let storefront = await Paygate.currentStorefront
        let gateKey = Paygate.cacheKey(gateId, storefront: storefront)

        let response: GateFlowResponse
        if let cached = gateCache[gateKey] {
            response = cached
        } else {
            do {
                let fetched = try await gates.getGate(gateId, storefront: storefront)
                // Caching is decided by this build's channel, so a debug build
                // set to refresh re-fetches while the shipped app still caches.
                if fetched.gate.launchCache(on: channel) == .cacheOnFirstLaunch {
                    gateCache[gateKey] = fetched
                }
                response = fetched
            } catch let error as PaygateError {
                if case .presentationLimitExceeded(let used, let limit) = error {
                    var data: [String: Any] = [:]
                    if let u = used { data["used"] = u }
                    if let l = limit { data["limit"] = l }
                    return PaygateLaunchResult(status: .planLimitReached, data: data.isEmpty ? nil : data)
                }
                throw error
            }
        }

        if !response.gate.isEnabled(on: channel) {
            return PaygateLaunchResult(status: .channelNotEnabled)
        }

        let flowData = response.flowData
        let gateIdMap = flowData.productIdMap
        let activeIds = await StoreKitManager.shared.activeEntitlementProductIDs
        for storeId in gateIdMap.values {
            if activeIds.contains(storeId) {
                return PaygateLaunchResult(status: .alreadySubscribed, productId: storeId)
            }
        }

        guard let presenter = topViewController() else {
            throw PaygateError.noPresentingViewController
        }

        let purchaseRequired = response.gate.requirePurchase
        let disableWebViewCache = response.gate.launchCache(on: channel) == .refreshOnLaunch
        // The caller wins. Only the app knows whether it has a theme setting of
        // its own, and the gate's value is a default for the apps that do not.
        let resolvedAppearance = appearance ?? response.gate.appearance
        return try await withCheckedThrowingContinuation { continuation in
            let paygateVC = PaygateViewController(
                flowData: flowData,
                apiKey: apiKey,
                baseURL: baseURL,
                bounces: bounces,
                gateId: gateId,
                purchaseRequired: purchaseRequired,
                disableWebViewCache: disableWebViewCache,
                appearance: resolvedAppearance,
                storefront: storefront
            ) { result in
                switch result {
                case .dismissed(let data):
                    continuation.resume(returning: PaygateLaunchResult(status: .dismissed, data: data))
                case .skipped(let data):
                    continuation.resume(returning: PaygateLaunchResult(status: .skipped, data: data))
                case .purchased(let productId, let data):
                    continuation.resume(returning: PaygateLaunchResult(status: .purchased, productId: productId, data: data))
                case .error(let error):
                    continuation.resume(throwing: error)
                }
            }
            switch presentationStyle {
            case .fullScreen:
                paygateVC.modalPresentationStyle = .fullScreen
                paygateVC.modalTransitionStyle = .coverVertical
            case .sheet:
                paygateVC.modalPresentationStyle = .pageSheet
                if #available(iOS 15.0, *),
                   let sheet = paygateVC.sheetPresentationController {
                    sheet.detents = [.large()]
                    sheet.prefersGrabberVisible = true
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                }
            }
            presenter.present(paygateVC, animated: true)
        }
    }

    /// Purchase a product by its Paygate product ID.
    /// Resolves the App Store product ID from the backend, then triggers StoreKit.
    /// - Returns: The App Store product ID on success, or `nil` if the user cancelled.
    @MainActor
    public static func purchase(_ productId: String) async throws -> String? {
        guard products != nil else {
            throw PaygateError.notInitialized
        }

        let product = try await products.getProduct(productId)
        guard let appStoreId = product.appStoreId, !appStoreId.isEmpty else {
            throw PaygateError.productNotFound
        }
        return try await StoreKitManager.shared.purchase(appStoreId)
    }

    // MARK: - Private

    @MainActor
    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        var vc = window.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }
}
