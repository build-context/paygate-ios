import Foundation

// MARK: - Distribution

public enum DistributionChannel: String {
    case production
    case testflight
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

/// Gate-level metadata (enabledChannels, requirePurchase, launchCache and
/// appearance live on gates, not flows).
public struct GateData {
    public let enabledChannels: [String]
    public let requirePurchase: Bool
    public let launchCache: String
    public let appearance: PaygateAppearance
}

/// Response from the gate SDK endpoint: selected flow content plus gate metadata.
public struct GateFlowResponse: Decodable {
    public let gateId: String
    public let selectedFlowId: String
    public let enabledChannels: [String]
    public let requirePurchase: Bool
    public let launchCache: String
    public let appearance: PaygateAppearance

    public let id: String
    public let name: String
    public let pages: [FlowPage]
    public let bridgeScript: String
    public let productIds: [String]
    public let products: [ProductData]?

    private enum CodingKeys: String, CodingKey {
        case gateId, selectedFlowId, enabledChannels, requirePurchase, launchCache, appearance
        case id, name, pages, bridgeScript, productIds, products
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gateId = try c.decode(String.self, forKey: .gateId)
        selectedFlowId = try c.decode(String.self, forKey: .selectedFlowId)
        enabledChannels = try c.decodeIfPresent([String].self, forKey: .enabledChannels) ?? []
        if let rawBool = try? c.decodeIfPresent(Bool.self, forKey: .requirePurchase) {
            requirePurchase = rawBool
        } else if let rawStr = try? c.decodeIfPresent(String.self, forKey: .requirePurchase) {
            requirePurchase = rawStr.lowercased() == "true"
        } else {
            requirePurchase = false
        }
        launchCache = try c.decodeIfPresent(String.self, forKey: .launchCache) ?? "cache_on_first_launch"
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
        GateData(enabledChannels: enabledChannels, requirePurchase: requirePurchase, launchCache: launchCache, appearance: appearance)
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
