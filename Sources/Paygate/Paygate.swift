import Foundation
import UIKit

public final class Paygate {

    /// Date-based API version (Stripe-style). Must match a version supported by the backend.
    public static let apiVersion = "2025-03-16"

    private static var apiKey: String?
    private static var baseURL: String = "https://api-oh6xuuomca-uc.a.run.app"
    private static var flowCache: [String: FlowData] = [:]
    private static var gateCache: [String: GateFlowResponse] = [:]

    static var flows: FlowRepository!
    static var gates: GateRepository!
    static var products: ProductRepository!

    /// Initialize the SDK, load the user's active subscriptions, and begin
    /// listening for transaction updates.
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
        let ids = await StoreKitManager.shared.activeSubscriptionProductIDs
        print("[Paygate] Active subscription product IDs:", ids.sorted().joined(separator: ", "))

        Task {
            await PresentationAnalytics.flushPendingOutbox(apiKey: apiKey, baseURL: self.baseURL)
        }
    }

    /// Current distribution channel (iOS).
    public static var currentChannel: DistributionChannel {
        #if DEBUG
        return .debug
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
            ? .testflight
            : .production
        #endif
    }

    /// The set of App Store product IDs for which the user has an active subscription.
    public static var activeSubscriptionProductIDs: Set<String> {
        get async {
            await StoreKitManager.shared.activeSubscriptionProductIDs
        }
    }

    /// Launch a paywall flow.
    /// - Parameter flowId: The ID of the flow to present.
    /// - Returns: A typed result with status, optional productId, and optional data.
    @MainActor
    public static func launchFlow(
        _ flowId: String,
        bounces: Bool = false,
        presentationStyle: PaygatePresentationStyle = .sheet
    ) async throws -> PaygateLaunchResult {
        guard let apiKey = apiKey else {
            throw PaygateError.notInitialized
        }

        let flowData: FlowData
        if let cached = flowCache[flowId] {
            flowData = cached
        } else {
            let fetched = try await flows.getFlow(flowId)
            flowCache[flowId] = fetched
            flowData = fetched
        }

        let idMap = flowData.productIdMap
        let activeIds = await StoreKitManager.shared.activeSubscriptionProductIDs
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
                gateId: nil
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

    /// Launch a gate, which randomly selects a flow based on configured weights.
    /// - Parameter gateId: The ID of the gate to present.
    /// - Returns: A typed result with status, optional productId, and optional data.
    @MainActor
    public static func launchGate(
        _ gateId: String,
        bounces: Bool = false,
        presentationStyle: PaygatePresentationStyle = .sheet
    ) async throws -> PaygateLaunchResult {
        guard let apiKey = apiKey else {
            throw PaygateError.notInitialized
        }

        let response: GateFlowResponse
        if let cached = gateCache[gateId] {
            response = cached
        } else {
            do {
                let fetched = try await gates.getGate(gateId)
                if fetched.gate.launchCache == "cache_on_first_launch" {
                    gateCache[gateId] = fetched
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

        if !response.gate.enabledChannels.isEmpty {
            let current = Paygate.currentChannel.rawValue
            if !response.gate.enabledChannels.contains(current) {
                return PaygateLaunchResult(status: .channelNotEnabled)
            }
        }

        let flowData = response.flowData
        let gateIdMap = flowData.productIdMap
        let activeIds = await StoreKitManager.shared.activeSubscriptionProductIDs
        for storeId in gateIdMap.values {
            if activeIds.contains(storeId) {
                return PaygateLaunchResult(status: .alreadySubscribed, productId: storeId)
            }
        }

        guard let presenter = topViewController() else {
            throw PaygateError.noPresentingViewController
        }

        let purchaseRequired = response.gate.requirePurchase
        let disableWebViewCache = response.gate.launchCache == "refresh_on_launch"
        return try await withCheckedThrowingContinuation { continuation in
            let paygateVC = PaygateViewController(
                flowData: flowData,
                apiKey: apiKey,
                baseURL: baseURL,
                bounces: bounces,
                gateId: gateId,
                purchaseRequired: purchaseRequired,
                disableWebViewCache: disableWebViewCache
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
