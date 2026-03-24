import Foundation

/// Serializable bundle for `POST /sdk/presentations` (camelCase JSON keys).
struct PendingPresentation: Codable, Equatable {
    let clientBatchId: String
    let gateId: String
    let flowId: String
    let openedAt: Int64
    var closedAt: Int64?
    var dismissReason: String?
    var events: [PresentationEvent]
}

struct PresentationEvent: Codable, Equatable {
    let eventType: String
    let occurredAt: Int64
    let metadata: [String: String]
}
