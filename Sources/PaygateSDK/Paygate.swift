import Foundation
import UIKit

public final class Paygate {

    private static var apiKey: String?
    private static var baseURL: String = "https://api-oh6xuuomca-uc.a.run.app"

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
    public static func launch(_ flowId: String) async throws -> String? {
        guard let apiKey = apiKey else {
            throw PaygateError.notInitialized
        }

        let flowData = try await fetchFlow(flowId: flowId, apiKey: apiKey)

        for productId in flowData.productIds {
            if await StoreKitManager.shared.isPurchased(productId) {
                return productId
            }
        }

        guard let presenter = topViewController() else {
            throw PaygateError.noPresentingViewController
        }

        return try await withCheckedThrowingContinuation { continuation in
            let paygateVC = PaygateViewController(
                flowData: flowData,
                apiKey: apiKey,
                baseURL: baseURL
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
            paygateVC.modalPresentationStyle = .fullScreen
            paygateVC.modalTransitionStyle = .coverVertical
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
            throw PaygateError.serverError
        }

        return try JSONDecoder().decode(FlowData.self, from: data)
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
}

enum PaygateResult {
    case dismissed
    case purchased(productId: String)
    case error(Error)
}

public enum PaygateError: LocalizedError {
    case notInitialized
    case invalidURL
    case noData
    case serverError
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
        case .serverError:
            return "Server returned an error."
        case .noPresentingViewController:
            return "No view controller available to present from."
        case .productNotFound:
            return "Product not found on the App Store."
        }
    }
}
