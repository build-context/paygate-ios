import Foundation

/// Buffers gate-session events locally and submits one `POST /sdk/presentations` per session.
final class PresentationEventBuffer {
    private let queue = DispatchQueue(label: "com.paygate.presentation.buffer")
    private var pending: PendingPresentation
    private let apiKey: String
    private let baseURL: String

    init(gateId: String, flowId: String, apiKey: String, baseURL: String) {
        let openedAt = Int64(Date().timeIntervalSince1970 * 1000)
        let batchId = UUID().uuidString
        self.pending = PendingPresentation(
            clientBatchId: batchId,
            gateId: gateId,
            flowId: flowId,
            openedAt: openedAt,
            closedAt: nil,
            dismissReason: nil,
            events: [
                PresentationEvent(
                    eventType: "gate_opened",
                    occurredAt: openedAt,
                    metadata: ["gateId": gateId, "flowId": flowId]
                ),
            ]
        )
        self.apiKey = apiKey
        self.baseURL = baseURL
        OutboxStore.save(pending)
    }

    func append(eventType: String, metadata: [String: String] = [:]) {
        queue.async {
            let ts = Int64(Date().timeIntervalSince1970 * 1000)
            self.pending.events.append(PresentationEvent(eventType: eventType, occurredAt: ts, metadata: metadata))
            OutboxStore.save(self.pending)
        }
    }

    /// Appends terminal analytics, persists, then attempts network flush. Deletes local file on 2xx.
    func finalizeAndFlush(result: PaygateResult) {
        queue.async {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let (reason, terminalType, meta) = Self.terminalInfo(for: result)
            self.pending.closedAt = now
            self.pending.dismissReason = reason
            self.pending.events.append(
                PresentationEvent(eventType: terminalType, occurredAt: now, metadata: meta)
            )
            OutboxStore.save(self.pending)
            let batchId = self.pending.clientBatchId
            let body = self.pending
            let key = self.apiKey
            let url = self.baseURL
            Task {
                let ok = await PresentationAnalytics.submit(pending: body, apiKey: key, baseURL: url)
                if ok {
                    OutboxStore.delete(clientBatchId: batchId)
                }
            }
        }
    }

    private static func terminalInfo(for result: PaygateResult) -> (reason: String, eventType: String, meta: [String: String]) {
        switch result {
        case .dismissed:
            return ("dismissed", "gate_dismissed", [:])
        case .skipped:
            return ("skipped", "gate_skipped", [:])
        case .purchased(let productId, _):
            return ("purchased", "gate_purchased", ["productId": productId])
        case .error(let err):
            return ("error", "gate_error", ["message": err.localizedDescription])
        }
    }
}

enum PresentationAnalytics {
    /// Retry pending bundles from previous launches (non-blocking).
    static func flushPendingOutbox(apiKey: String, baseURL: String) async {
        let ids = OutboxStore.listPendingClientBatchIds()
        for id in ids {
            guard let pending = OutboxStore.load(clientBatchId: id) else { continue }
            let ok = await submit(pending: pending, apiKey: apiKey, baseURL: baseURL)
            if ok {
                OutboxStore.delete(clientBatchId: id)
            } else {
                print("[Paygate] flushPendingOutbox: will retry later for batch \(id)")
            }
        }
    }

    static func submit(pending: PendingPresentation, apiKey: String, baseURL: String) async -> Bool {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/sdk/presentations") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        PaygateHTTP.applyDefaultHeaders(to: &request, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(pending)
        } catch {
            print("[Paygate] submit: encode failed: \(error.localizedDescription)")
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if (200 ... 299).contains(http.statusCode) {
                return true
            }
            print("[Paygate] submit: HTTP \(http.statusCode)")
            return false
        } catch {
            print("[Paygate] submit: \(error.localizedDescription)")
            return false
        }
    }
}
