import Foundation

enum SkipPersistence {
    private static let key = "paygate_skipped_gates"

    static func recordSkipped(gateId: String) {
        var set = skippedGateIds
        set.insert(gateId)
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    static func isSkipped(gateId: String) -> Bool {
        skippedGateIds.contains(gateId)
    }

    private static var skippedGateIds: Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(arr)
    }
}
