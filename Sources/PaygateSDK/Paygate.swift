import Foundation
import UIKit

public final class Paygate {

    private static var apiKey: String?
    private static var baseURL: String = "https://api-oh6xuuomca-uc.a.run.app"
    private static var gateCache: [String: FlowData] = [:]

    /// Initialize the SDK, load the user's current purchases, and begin
    /// listening for transaction updates.
    @MainActor
    public static func initialize(apiKey: String, baseURL: String? = nil) async {
        self.apiKey = apiKey
        if let baseURL = baseURL {
            self.baseURL = baseURL
        }
        await StoreKitManager.shared.start()
        await StoreKitManager.shared.loadPurchasedProducts()
    }

    /// The set of product IDs the user currently owns.
    public static var purchasedProductIDs: Set<String> {
        get async {
            await StoreKitManager.shared.purchasedProductIDs
        }
    }

    /// Launch a paywall flow.
    /// - Parameter flowId: The ID of the flow to present.
    /// - Returns: The purchased product ID, or `nil` if the user dismissed without purchasing.
    ///   If the user already owns a product in this flow, returns it immediately without
    ///   showing the paywall.
    @MainActor
    public static func launchFlow(
        _ flowId: String,
        bounces: Bool = false,
        presentationStyle: PaygatePresentationStyle = .sheet
    ) async throws -> String? {
        guard let apiKey = apiKey else {
            throw PaygateError.notInitialized
        }

        let flowData = try await fetchFlow(flowId: flowId, apiKey: apiKey)

        let idMap = flowData.productIdMap
        for productId in flowData.productIds {
            let storeId = idMap[productId] ?? productId
            if await StoreKitManager.shared.isPurchased(storeId) {
                return storeId
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
                bounces: bounces
            ) { result in
                switch result {
                case .dismissed:
                    continuation.resume(returning: nil)
                case .purchased(let productId):
                    continuation.resume(returning: productId)
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
    /// - Returns: The purchased product ID, or `nil` if the user dismissed without purchasing.
    ///   If the user already owns a product in the selected flow, returns it immediately.
    @MainActor
    public static func launchGate(
        _ gateId: String,
        bounces: Bool = false,
        presentationStyle: PaygatePresentationStyle = .sheet
    ) async throws -> String? {
        guard let apiKey = apiKey else {
            throw PaygateError.notInitialized
        }

        let flowData: FlowData
        if let cached = gateCache[gateId] {
            flowData = cached
        } else {
            let fetched = try await fetchGate(gateId: gateId, apiKey: apiKey)
            gateCache[gateId] = fetched
            flowData = fetched
        }

        let gateIdMap = flowData.productIdMap
        for productId in flowData.productIds {
            let storeId = gateIdMap[productId] ?? productId
            if await StoreKitManager.shared.isPurchased(storeId) {
                return storeId
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
                bounces: bounces
            ) { result in
                switch result {
                case .dismissed:
                    continuation.resume(returning: nil)
                case .purchased(let productId):
                    continuation.resume(returning: productId)
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

    // MARK: - Private

    private static func fetchFlow(flowId: String, apiKey: String) async throws -> FlowData {
        guard let url = URL(string: "\(baseURL)/api/sdk/flows/\(flowId)") else {
            throw PaygateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let detail = Self.parseErrorDetail(from: data)
            throw PaygateError.serverError(detail: detail)
        }

        return try JSONDecoder().decode(FlowData.self, from: data)
    }

    private static func fetchGate(gateId: String, apiKey: String) async throws -> FlowData {
        guard let url = URL(string: "\(baseURL)/api/sdk/gates/\(gateId)") else {
            throw PaygateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let detail = Self.parseErrorDetail(from: data)
            throw PaygateError.serverError(detail: detail)
        }

        return try JSONDecoder().decode(FlowData.self, from: data)
    }

    private static func parseErrorDetail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["detail"] as? String ?? json["error"] as? String
    }

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

// MARK: - Models

public struct FlowData: Codable {
    public let id: String
    public let name: String
    public let htmlContent: String
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

public struct ProductData: Codable {
    public let id: String
    public let name: String
    public let appStoreId: String?
    public let playStoreId: String?
}

enum PaygateResult {
    case dismissed
    case purchased(productId: String)
    case error(Error)
}

public enum PaygatePresentationStyle {
    case fullScreen
    case sheet
}

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
