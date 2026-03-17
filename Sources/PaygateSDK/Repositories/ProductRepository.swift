import Foundation

class ProductRepository: PaygateRepository {

    func getProduct(_ productId: String) async throws -> ProductData {
        try await get("/api/sdk/products/\(productId)")
    }
}
