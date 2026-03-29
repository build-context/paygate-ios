import StoreKit

public actor StoreKitManager {
    public static let shared = StoreKitManager()

    public private(set) var activeSubscriptionProductIDs: Set<String> = []
    private var updateListenerTask: Task<Void, Never>?

    public func start() {
        updateListenerTask?.cancel()
        updateListenerTask = Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    await StoreKitManager.shared.handle(transaction)
                }
            }
        }
    }

    /// Refreshes transactions from the App Store and updates `activeSubscriptionProductIDs`.
    public func syncPurchases() async throws {
        try await AppStore.sync()
        await loadPurchasedProducts()
    }

    public func loadPurchasedProducts() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue,
               transaction.revocationDate == nil,
               isSubscription(transaction.productType) {
                active.insert(transaction.productID)
            }
        }
        activeSubscriptionProductIDs = active
    }

    public func purchase(_ productID: String) async throws -> String? {
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            print(
                "[Paygate] StoreKit returned no Product for appStoreId=\(productID). " +
                    "Confirm this exact ID exists in App Store Connect for this app's bundle ID, is cleared for sale / sandbox testing, " +
                    "and (for local runs) the Xcode scheme has a StoreKit Configuration file attached."
            )
            throw PaygateError.productNotFound
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            if isSubscription(product.type) {
                activeSubscriptionProductIDs.insert(transaction.productID)
            }
            return transaction.productID
        case .userCancelled:
            return nil
        case .pending:
            return nil
        @unknown default:
            return nil
        }
    }

    public func isPurchased(_ productID: String) -> Bool {
        activeSubscriptionProductIDs.contains(productID)
    }

    private func handle(_ transaction: Transaction) {
        if transaction.revocationDate == nil, isSubscription(transaction.productType) {
            activeSubscriptionProductIDs.insert(transaction.productID)
        } else {
            activeSubscriptionProductIDs.remove(transaction.productID)
        }
        Task { await transaction.finish() }
    }

    private func isSubscription(_ type: Product.ProductType) -> Bool {
        type == .autoRenewable || type == .nonRenewable
    }
}
