import Foundation

class GateRepository: PaygateRepository {

    /// - Parameter storefront: Store country to price the flow for, when known.
    func getGate(_ gateId: String, storefront: String? = nil) async throws -> GateFlowResponse {
        try await get("/sdk/gates/\(gateId)", storefront: storefront)
    }
}
