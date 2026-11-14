import Foundation

/// Tells Paygate which gate and paywall a purchase came from.
///
/// The store's server notification says what a purchase was worth; only the
/// app knows which paywall sold it, and only for the moment the purchase
/// returns. This report is that second half (`POST /sdk/purchases`). Without
/// it every purchase reaches Paygate's revenue ledger as unattributed, and a
/// gate's price test cannot be read.
///
/// It carries no price — money only ever comes from the store — and it is
/// queued on disk first, so an app that is killed or offline right after a
/// purchase still reports it on a later launch. The server is idempotent per
/// purchase, so sending one twice is harmless.
struct PendingPurchaseReport: Codable {
    let id: String
    let provider: String
    let originalTransactionId: String
    let transactionId: String
    let gateId: String
    let flowId: String
    let storeProductId: String
    let appUserId: String?
    /// The presentation batch the purchase happened in, linking the two rows.
    let clientBatchId: String?
}

enum PurchaseReporter {
    private static let subpath = "Paygate/purchases"

    /// Queue a report and try to send it now.
    static func report(_ report: PendingPurchaseReport, apiKey: String, baseURL: String) {
        save(report)
        Task {
            if await submit(report, apiKey: apiKey, baseURL: baseURL) {
                delete(id: report.id)
            }
        }
    }

    /// Send reports left from earlier launches. Called from `Paygate.initialize`.
    static func flushPending(apiKey: String, baseURL: String) async {
        for report in loadAll() {
            if await submit(report, apiKey: apiKey, baseURL: baseURL) {
                delete(id: report.id)
            }
        }
    }

    /// True when the report is done with: accepted, or refused in a way a
    /// retry cannot fix (a 4xx — say the gate was deleted). False keeps it
    /// queued for the next launch.
    static func submit(_ report: PendingPurchaseReport, apiKey: String, baseURL: String) async -> Bool {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/sdk/purchases") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        PaygateHTTP.applyDefaultHeaders(to: &request, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "provider": report.provider,
            "originalTransactionId": report.originalTransactionId,
            "transactionId": report.transactionId,
            "gateId": report.gateId,
            "flowId": report.flowId,
            "storeProductId": report.storeProductId,
        ]
        if let appUserId = report.appUserId { body["appUserId"] = appUserId }
        if let batch = report.clientBatchId { body["clientBatchId"] = batch }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if (200 ... 299).contains(http.statusCode) { return true }
            if (400 ... 499).contains(http.statusCode) && http.statusCode != 429 {
                print("[Paygate] Purchase report refused (HTTP \(http.statusCode)); not retrying")
                return true
            }
            print("[Paygate] Purchase report: HTTP \(http.statusCode); will retry")
            return false
        } catch {
            print("[Paygate] Purchase report: \(error.localizedDescription); will retry")
            return false
        }
    }

    // MARK: - Disk

    private static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = base.appendingPathComponent(subpath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func save(_ report: PendingPurchaseReport) {
        guard let dir = directory(), let data = try? JSONEncoder().encode(report) else { return }
        try? data.write(to: dir.appendingPathComponent("\(report.id).json"), options: .atomic)
    }

    private static func loadAll() -> [PendingPurchaseReport] {
        guard let dir = directory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(PendingPurchaseReport.self, from: Data(contentsOf: $0)) }
    }

    private static func delete(id: String) {
        guard let dir = directory() else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).json"))
    }
}
