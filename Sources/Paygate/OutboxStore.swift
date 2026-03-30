import Foundation

/// Persists pending presentation bundles under Application Support until the server accepts them.
enum OutboxStore {
    private static let subpath = "Paygate/pending"

    private static func ensureDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = appSupport.appendingPathComponent(subpath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            print("[Paygate] OutboxStore: failed to create directory: \(error.localizedDescription)")
            return nil
        }
    }

    static func save(_ pending: PendingPresentation) {
        guard let dir = ensureDirectory() else { return }
        let url = dir.appendingPathComponent("\(pending.clientBatchId).json", isDirectory: false)
        do {
            let data = try JSONEncoder().encode(pending)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[Paygate] OutboxStore: save failed: \(error.localizedDescription)")
        }
    }

    /// Pending `clientBatchId` values, oldest files first (by modification date).
    static func listPendingClientBatchIds() -> [String] {
        guard let dir = ensureDirectory() else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let jsonFiles = files.filter { $0.pathExtension == "json" }
        let sorted = jsonFiles.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return da < db
        }
        return sorted.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            return name.isEmpty ? nil : name
        }
    }

    static func load(clientBatchId: String) -> PendingPresentation? {
        guard let dir = ensureDirectory() else { return nil }
        let url = dir.appendingPathComponent("\(clientBatchId).json", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PendingPresentation.self, from: data)
    }

    static func delete(clientBatchId: String) {
        guard let dir = ensureDirectory() else { return }
        let url = dir.appendingPathComponent("\(clientBatchId).json", isDirectory: false)
        try? FileManager.default.removeItem(at: url)
    }
}
