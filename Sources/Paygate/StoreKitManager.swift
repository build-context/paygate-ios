import StoreKit

public actor StoreKitManager {
    public static let shared = StoreKitManager()

    /// App Store product IDs the user is entitled to right now: active
    /// subscriptions **and** non-consumables (lifetime unlocks).
    ///
    /// This used to hold subscriptions only, so someone who bought a lifetime
    /// unlock was never entitled — the gate kept showing and Restore found
    /// nothing. Consumables are left out: they are used up, not owned.
    public private(set) var activeEntitlementProductIDs: Set<String> = []

    /// The old name, kept so existing callers compile. It now includes
    /// non-consumables too — a caller asking "is this user paying?" wants them.
    @available(*, deprecated, renamed: "activeEntitlementProductIDs")
    public var activeSubscriptionProductIDs: Set<String> { activeEntitlementProductIDs }

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

    /// Asks the App Store for this account's purchases (Restore), then
    /// re-reads entitlements.
    ///
    /// `AppStore.sync()` can prompt for the Apple Account password. If the user
    /// cancels that prompt this throws `StoreKitError.userCancelled`. Any other
    /// failure (offline, say) still re-reads entitlements before rethrowing:
    /// StoreKit keeps them on the device, so a lifetime unlock can be restored
    /// even when the sync itself fails.
    public func syncPurchases() async throws {
        do {
            try await AppStore.sync()
        } catch {
            await loadPurchasedProducts()
            throw error
        }
        await loadPurchasedProducts()
    }

    public func loadPurchasedProducts() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue,
               Self.grantsEntitlement(
                   type: transaction.productType,
                   revocationDate: transaction.revocationDate,
                   expirationDate: transaction.expirationDate
               ) {
                active.insert(transaction.productID)
            }
        }
        activeEntitlementProductIDs = active
    }

    /// Whether a transaction entitles the user to its product.
    ///
    /// Subscriptions (auto-renewable and non-renewing) and non-consumables
    /// do; consumables never do. A refund or revocation ends it, and so does a
    /// passed expiration date — `Transaction.updates` can deliver an expired
    /// renewal, which used to be added as active.
    static func grantsEntitlement(
        type: Product.ProductType,
        revocationDate: Date?,
        expirationDate: Date?,
        now: Date = Date()
    ) -> Bool {
        guard type == .autoRenewable || type == .nonRenewable || type == .nonConsumable else {
            return false
        }
        if revocationDate != nil { return false }
        if let expirationDate, expirationDate <= now { return false }
        return true
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
            if Self.grantsEntitlement(
                type: product.type,
                revocationDate: transaction.revocationDate,
                expirationDate: transaction.expirationDate
            ) {
                activeEntitlementProductIDs.insert(transaction.productID)
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
        activeEntitlementProductIDs.contains(productID)
    }

    private func handle(_ transaction: Transaction) async {
        if Self.grantsEntitlement(
            type: transaction.productType,
            revocationDate: transaction.revocationDate,
            expirationDate: transaction.expirationDate
        ) {
            activeEntitlementProductIDs.insert(transaction.productID)
        } else {
            // Re-read rather than remove: an update for one transaction
            // (a refunded or expired period) does not mean the product is no
            // longer owned — a later renewal of it may still be active.
            await loadPurchasedProducts()
        }
        await transaction.finish()
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
