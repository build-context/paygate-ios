import Foundation

// MARK: - Distribution

public enum DistributionChannel: String {
    case production
    case testflight
    case debug
}

// MARK: - Gate

/// Gate-level metadata (enabledChannels lives on gates, not flows).
public struct GateData {
    public let enabledChannels: [String]
}

/// Response from the gate SDK endpoint: selected flow content plus gate metadata.
public struct GateFlowResponse: Decodable {
    public let gateId: String
    public let selectedFlowId: String
    public let enabledChannels: [String]

    public let id: String
    public let name: String
    public let pages: [FlowPage]
    public let bridgeScript: String
    public let productIds: [String]
    public let products: [ProductData]?

    private enum CodingKeys: String, CodingKey {
        case gateId, selectedFlowId, enabledChannels
        case id, name, pages, bridgeScript, productIds, products
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gateId = try c.decode(String.self, forKey: .gateId)
        selectedFlowId = try c.decode(String.self, forKey: .selectedFlowId)
        enabledChannels = try c.decodeIfPresent([String].self, forKey: .enabledChannels) ?? []
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        pages = try c.decodeIfPresent([FlowPage].self, forKey: .pages) ?? []
        bridgeScript = try c.decodeIfPresent(String.self, forKey: .bridgeScript) ?? ""
        productIds = try c.decode([String].self, forKey: .productIds)
        products = try c.decodeIfPresent([ProductData].self, forKey: .products)
    }

    /// Gate metadata.
    public var gate: GateData {
        GateData(enabledChannels: enabledChannels)
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

public enum PaygateResult {
    case dismissed(data: [String: Any]?)
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
        }
    }
}
