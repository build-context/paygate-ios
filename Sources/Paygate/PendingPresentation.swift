import Foundation

/// Serializable bundle for `POST /sdk/presentations` (camelCase JSON keys).
struct PendingPresentation: Codable, Equatable {
    let clientBatchId: String
    let gateId: String
    let flowId: String
    let openedAt: Int64
    var closedAt: Int64?
    var dismissReason: String?
    /// Store country the flow's prices were resolved for, when known.
    ///
    /// Optional so rows persisted by an older build still decode. Recorded at
    /// render time rather than read again on submit: this batch is sent on
    /// dismissal, and a user who changed App Store country in between would
    /// otherwise be filed under a country whose prices they never saw.
    var storefront: String?
    var events: [PresentationEvent]
}

struct PresentationEvent: Codable, Equatable {
    let eventType: String
    let occurredAt: Int64
    let metadata: [String: String]
}
