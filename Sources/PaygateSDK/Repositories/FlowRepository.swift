import Foundation

class FlowRepository: PaygateRepository {

    func getFlow(_ flowId: String) async throws -> FlowData {
        try await get("/api/sdk/flows/\(flowId)")
    }
}
