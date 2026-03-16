import StoreKit

actor StoreKitManager {
    static let shared = StoreKitManager()

    private(set) var purchasedProductIDs: Set<String> = []
    private var updateListenerTask: Task<Void, Never>?

    func start() {
        updateListenerTask?.cancel()
        updateListenerTask = Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    await StoreKitManager.shared.handle(transaction)
                }
            }
        }
    }

    func loadPurchasedProducts() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue,
               transaction.revocationDate == nil {
                purchased.insert(transaction.productID)
            }
        }
        purchasedProductIDs = purchased
    }

    func purchase(_ productID: String) async throws -> String? {
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw PaygateError.productNotFound
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            purchasedProductIDs.insert(transaction.productID)
            return transaction.productID
        case .userCancelled:
            return nil
        case .pending:
            return nil
        @unknown default:
            return nil
        }
    }

    func isPurchased(_ productID: String) -> Bool {
        purchasedProductIDs.contains(productID)
    }

    private func handle(_ transaction: Transaction) {
        if transaction.revocationDate == nil {
            purchasedProductIDs.insert(transaction.productID)
        } else {
            purchasedProductIDs.remove(transaction.productID)
        }
        Task { await transaction.finish() }
    }
}
