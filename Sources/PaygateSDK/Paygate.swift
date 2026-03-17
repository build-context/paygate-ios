import Foundation
import UIKit

public final class Paygate {

    /// Date-based API version (Stripe-style). Must match a version supported by the backend.
    public static let apiVersion = "2025-03-16"

    private static var apiKey: String?
    private static var baseURL: String = "https://api-oh6xuuomca-uc.a.run.app"
    private static var flowCache: [String: FlowData] = [:]
    private static var gateCache: [String: FlowData] = [:]

    static var flows: FlowRepository!
    static var gates: GateRepository!
    static var products: ProductRepository!

    /// Initialize the SDK, optionally prefetch gate and flow data, load the
    /// user's active subscriptions, and begin listening for transaction updates.
    ///
    /// - Parameters:
    ///   - apiKey: Your Paygate API key.
    ///   - baseURL: Override the default API base URL.
    ///   - gateIds: Gate IDs to prefetch at launch so `launchGate` can check
    ///     eligibility and present without a network round-trip.
    ///   - flowIds: Flow IDs to prefetch at launch so `launchFlow` can check
    ///     eligibility and present without a network round-trip.
    @MainActor
    public static func initialize(
        apiKey: String,
        baseURL: String? = nil,
        gateIds: [String]? = nil,
        flowIds: [String]? = nil
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

        // Prefetch gate flows and standalone flows concurrently.
        await withTaskGroup(of: Void.self) { group in
            for gateId in gateIds ?? [] {
                group.addTask {
                    do {
                        let flowData = try await gates.getGate(gateId)
                        await MainActor.run { gateCache[gateId] = flowData }
                    } catch {
                        print("[Paygate] Failed to prefetch gate \(gateId):", error.localizedDescription)
                    }
                }
            }
            for flowId in flowIds ?? [] {
                group.addTask {
                    do {
                        let flowData = try await flows.getFlow(flowId)
                        await MainActor.run { flowCache[flowId] = flowData }
                    } catch {
                        print("[Paygate] Failed to prefetch flow \(flowId):", error.localizedDescription)
                    }
                }
            }
        }
    }

    /// The set of App Store product IDs for which the user has an active subscription.
    public static var activeSubscriptionProductIDs: Set<String> {
        get async {
            await StoreKitManager.shared.activeSubscriptionProductIDs
        }
    }

    /// Launch a paywall flow.
    /// - Parameter flowId: The ID of the flow to present.
    /// - Returns: The purchased product ID, or `nil` if the user dismissed without purchasing.
    ///   If the user already has an active subscription for a product in this flow, returns
    ///   that product's App Store ID immediately without showing the paywall.
    @MainActor
    public static func launchFlow(
        _ flowId: String,
        bounces: Bool = false,
        presentationStyle: PaygatePresentationStyle = .sheet
    ) async throws -> String? {
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
        // productIdMap covers all products associated with this flow — both those
        // listed in productIds and those only referenced in the HTML templates.
        // Checking its values (App Store IDs) catches both cases.
        for storeId in idMap.values {
            if activeIds.contains(storeId) {
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
    ///   If the user already has an active subscription for a product in the selected flow,
    ///   returns that product's App Store ID immediately without showing the paywall.
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
            let fetched = try await gates.getGate(gateId)
            gateCache[gateId] = fetched
            flowData = fetched
        }

        let gateIdMap = flowData.productIdMap
        let activeIds = await StoreKitManager.shared.activeSubscriptionProductIDs
        // productIdMap covers all products associated with this flow — both those
        // listed in productIds and those only referenced in the HTML templates.
        // Checking its values (App Store IDs) catches both cases.
        for storeId in gateIdMap.values {
            if activeIds.contains(storeId) {
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
