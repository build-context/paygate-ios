import Foundation

class GateRepository: PaygateRepository {

    func getGate(_ gateId: String) async throws -> GateFlowResponse {
        try await get("/sdk/gates/\(gateId)")
    }
}
