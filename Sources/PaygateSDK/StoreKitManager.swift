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

    /// Fetches products from the App Store and prints a console summary (ids, names, prices, missing ids).
    public func logAppStoreProducts(for appStoreIDs: [String]) async {
        let unique = Array(Set(appStoreIDs)).filter { !$0.isEmpty }
        guard !unique.isEmpty else {
            print("[Paygate] logAppStoreProducts: no App Store product IDs to fetch")
            return
        }
        do {
            let products = try await Product.products(for: unique)
            logFetchedProducts(products, requested: unique)
        } catch {
            print(
                "[Paygate] Product.products(for:) failed: \(error.localizedDescription) " +
                    "requestedIds=\(unique.sorted().joined(separator: ", "))"
            )
        }
    }

    public func purchase(_ productID: String) async throws -> String? {
        let products = try await Product.products(for: [productID])
        logFetchedProducts(products, requested: [productID])
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
            let transaction: Transaction
            switch verification {
            case .verified(let t):
                transaction = t
            case .unverified(let t, let error):
                print("[Paygate] Transaction verification failed: \(error). Processing purchase anyway (common in sandbox/TestFlight).")
                transaction = t
            }
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

    private func logFetchedProducts(_ products: [Product], requested: [String]) {
        let fetchedIDs = Set(products.map(\.id))
        let missing = Set(requested).subtracting(fetchedIDs)
        print(
            "[Paygate] App Store products fetched: returned=\(products.count) requested=\(requested.count) " +
                "ids=\(requested.sorted().joined(separator: ", "))"
        )
        for p in products.sorted(by: { $0.id < $1.id }) {
            print(
                "[Paygate]   • id=\(p.id) name=\(p.displayName) " +
                    "displayPrice=\(p.displayPrice) type=\(String(describing: p.type))"
            )
        }
        if !missing.isEmpty {
            print(
                "[Paygate] App Store did not return Product for id(s): " +
                    "\(missing.sorted().joined(separator: ", "))"
            )
        }
    }
}
