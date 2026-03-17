import Foundation

class GateRepository: PaygateRepository {

    func getGate(_ gateId: String) async throws -> FlowData {
        try await get("/api/sdk/gates/\(gateId)")
    }
}
