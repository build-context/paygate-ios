import Foundation

class FlowRepository: PaygateRepository {

    /// - Parameter storefront: Store country to price the flow for, when known.
    func getFlow(_ flowId: String, storefront: String? = nil, locale: String? = nil) async throws -> FlowData {
        try await get("/sdk/flows/\(flowId)", storefront: storefront, locale: locale)
    }
}
