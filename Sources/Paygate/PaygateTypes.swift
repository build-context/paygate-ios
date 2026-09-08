import Foundation

// MARK: - Distribution

/// Which kind of build this is, as far as a gate's per-channel settings care.
///
/// Three, and deliberately not one per store. `testing` was called `testflight`
/// until the Android SDK could take money and the name stopped being true: Play
/// has no TestFlight, so half the clients could never match that entry. The
/// server no longer sends or accepts the old name — see `gateChannels.ts`.
public enum DistributionChannel: String {
    /// A shipped build, installed from the App Store or Play.
    case production

    /// A build under test: TestFlight on iOS, and on Android an install that
    /// did not come from Play, or whatever ``Paygate/channelOverride`` says.
    case testing

    /// A build compiled for debugging — `#if DEBUG` here, `FLAG_DEBUGGABLE`
    /// on Android.
    case debug
}

// MARK: - Appearance

/// Which color scheme a flow renders in.
///
/// A `WKWebView`'s `prefers-color-scheme` follows the operating system, not
/// your app — so an app with its own light/dark setting shows a paywall that
/// can disagree with the screen behind it. Pinning this fixes that.
///
/// Set on the gate in the Paygate console, and overridable per launch: an
/// appearance passed to ``Paygate/launchGate(_:bounces:presentationStyle:appearance:)``
/// wins, because only the app knows whether it has a theme preference of its own.
public enum PaygateAppearance: String, Sendable {
    /// Follow the device's light/dark setting. The default.
    case system
    /// Render light regardless of the device setting.
    case light
    /// Render dark regardless of the device setting.
    case dark

    /// Parses a server value, falling back to ``system`` for anything
    /// unrecognized — an API that grows a fourth value must not break a paywall
    /// built against three.
    init(serverValue: String?) {
        self = PaygateAppearance(rawValue: serverValue?.lowercased() ?? "") ?? .system
    }
}

// MARK: - Gate

/// How the SDK caches a gate's content on a given channel.
public enum PaygateLaunchCache: String, Sendable {
    /// Fetch once, then reuse for the rest of the process. The default.
    case cacheOnFirstLaunch = "cache_on_first_launch"
    /// Re-fetch on every launch, so console edits appear without a reinstall.
    case refreshOnLaunch = "refresh_on_launch"

    /// Parses a server value, falling back to ``cacheOnFirstLaunch`` for
    /// anything unrecognized — an API that grows a third value must not break a
    /// paywall built against two.
    init(serverValue: String?) {
        self = PaygateLaunchCache(rawValue: serverValue?.lowercased() ?? "") ?? .cacheOnFirstLaunch
    }
}

/// One distribution channel's settings on a gate: whether the gate shows there,
/// and how it caches there.
///
/// Caching is per channel because that is where it varies. A debug build wants
/// ``PaygateLaunchCache/refreshOnLaunch`` so flow edits appear immediately;
/// production wants ``PaygateLaunchCache/cacheOnFirstLaunch`` so the paywall
/// does not wait on the network.
public struct GateChannel: Decodable {
    public let channel: String
    public let enabled: Bool
    public let launchCache: PaygateLaunchCache

    private enum CodingKeys: String, CodingKey {
        case channel, enabled, launchCache
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channel = try c.decode(String.self, forKey: .channel)
        // Absent means enabled. A gate that hides itself is the costlier
        // reading of a field an older or newer server did not send.
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        launchCache = PaygateLaunchCache(serverValue: try? c.decodeIfPresent(String.self, forKey: .launchCache))
    }

    public init(channel: String, enabled: Bool, launchCache: PaygateLaunchCache) {
        self.channel = channel
        self.enabled = enabled
        self.launchCache = launchCache
    }
}

/// Gate-level metadata (channels, requirePurchase and appearance live on gates,
/// not flows).
public struct GateData {
    /// One entry per channel the server knows about.
    public let channels: [GateChannel]
    public let requirePurchase: Bool
    public let appearance: PaygateAppearance

    /// This build's channel entry, or `nil` if the gate says nothing about it.
    public func channel(for channel: DistributionChannel) -> GateChannel? {
        channels.first { $0.channel == channel.rawValue }
    }

    /// Whether the gate shows on `channel`.
    ///
    /// A gate that lists no channels at all shows everywhere. That is what an
    /// empty `enabledChannels` meant before per-channel config, and it is the
    /// only safe reading of a response this build does not understand: the
    /// alternative is a paywall that silently never appears.
    public func isEnabled(on channel: DistributionChannel) -> Bool {
        if channels.isEmpty { return true }
        guard let entry = self.channel(for: channel) else { return true }
        return entry.enabled
    }

    /// How to cache on `channel`.
    public func launchCache(on channel: DistributionChannel) -> PaygateLaunchCache {
        self.channel(for: channel)?.launchCache ?? .cacheOnFirstLaunch
    }
}

/// Response from the gate SDK endpoint: selected flow content plus gate metadata.
public struct GateFlowResponse: Decodable {
    public let gateId: String
    public let selectedFlowId: String
    public let channels: [GateChannel]
    public let requirePurchase: Bool
    public let appearance: PaygateAppearance

    public let id: String
    public let name: String
    public let pages: [FlowPage]
    public let bridgeScript: String
    public let productIds: [String]
    public let products: [ProductData]?

    private enum CodingKeys: String, CodingKey {
        case gateId, selectedFlowId, channels, requirePurchase, appearance
        case id, name, pages, bridgeScript, productIds, products
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gateId = try c.decode(String.self, forKey: .gateId)
        selectedFlowId = try c.decode(String.self, forKey: .selectedFlowId)
        channels = try c.decodeIfPresent([GateChannel].self, forKey: .channels) ?? []
        if let rawBool = try? c.decodeIfPresent(Bool.self, forKey: .requirePurchase) {
            requirePurchase = rawBool
        } else if let rawStr = try? c.decodeIfPresent(String.self, forKey: .requirePurchase) {
            requirePurchase = rawStr.lowercased() == "true"
        } else {
            requirePurchase = false
        }
        appearance = PaygateAppearance(serverValue: try? c.decodeIfPresent(String.self, forKey: .appearance))
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        pages = try c.decodeIfPresent([FlowPage].self, forKey: .pages) ?? []
        bridgeScript = try c.decodeIfPresent(String.self, forKey: .bridgeScript) ?? ""
        productIds = try c.decode([String].self, forKey: .productIds)
        products = try c.decodeIfPresent([ProductData].self, forKey: .products)
    }

    /// Gate metadata.
    public var gate: GateData {
        GateData(channels: channels, requirePurchase: requirePurchase, appearance: appearance)
    }

    /// Flow content for presentation.
    public var flowData: FlowData {
        FlowData(id: id, name: name, pages: pages, bridgeScript: bridgeScript, productIds: productIds, products: products)
    }
}

// MARK: - Flow

/// A single page in a flow. Matches SDK API response: `{ id, htmlContent }`.
public struct FlowPage: Codable {
    public let id: String
    public let htmlContent: String
}

public struct FlowData: Codable {
    public let id: String
    public let name: String
    public let pages: [FlowPage]
    public let bridgeScript: String
    public let productIds: [String]
    public let products: [ProductData]?

    /// Maps Paygate product IDs to App Store product IDs.
    public var productIdMap: [String: String] {
        var map: [String: String] = [:]
        for product in products ?? [] {
            if let appStoreId = product.appStoreId, !appStoreId.isEmpty {
                map[product.id] = appStoreId
            }
        }
        return map
    }
}

// MARK: - Product

public struct ProductData: Codable {
    public let id: String
    public let name: String
    public let appStoreId: String?
    public let playStoreId: String?
}

// MARK: - Result & Presentation

/// Status returned from launchFlow/launchGate for developer handling.
public enum PaygateLaunchStatus: String {
    case purchased
    case alreadySubscribed
    case dismissed
    case skipped
    case channelNotEnabled
    /// Monthly presentation quota exceeded for this project (`data` may include `used` and `limit`).
    case planLimitReached
}

/// Typed result from launchFlow/launchGate.
public struct PaygateLaunchResult {
    public let status: PaygateLaunchStatus
    public let productId: String?
    public let data: [String: Any]?

    public init(status: PaygateLaunchStatus, productId: String? = nil, data: [String: Any]? = nil) {
        self.status = status
        self.productId = productId
        self.data = data
    }
}

public enum PaygateResult {
    case dismissed(data: [String: Any]?)
    case skipped(data: [String: Any]?)
    case purchased(productId: String, data: [String: Any]?)
    case error(Error)
}

public enum PaygatePresentationStyle {
    case fullScreen
    case sheet
}

// MARK: - Error

public enum PaygateError: LocalizedError {
    case notInitialized
    case invalidURL
    case noData
    case serverError(detail: String? = nil)
    case noPresentingViewController
    case productNotFound
    /// Monthly presentation quota exceeded (HTTP 403, `code: presentation_limit_exceeded`).
    case presentationLimitExceeded(used: Int?, limit: Int?)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Paygate SDK not initialized. Call Paygate.initialize(apiKey:) first."
        case .invalidURL:
            return "Invalid API URL."
        case .noData:
            return "No data received from server."
        case .serverError(let detail):
            if let detail, !detail.isEmpty {
                return "Server returned an error: \(detail)"
            }
            return "Server returned an error."
        case .noPresentingViewController:
            return "No view controller available to present from."
        case .productNotFound:
            return "Product not found on the App Store."
        case .presentationLimitExceeded(let used, let limit):
            var parts: [String] = ["Presentation limit reached for this billing period."]
            if let u = used, let l = limit {
                parts.append("Used \(u) of \(l).")
            }
            return parts.joined(separator: " ")
        }
    }
}
