import Foundation

/// A random identifier for this install of the host app, created on first use
/// and kept in `UserDefaults`.
///
/// It exists so the server can give one reader the same flow every time a gate
/// is launched. Without it, a gate's weighted choice was rolled afresh on every
/// fetch: a price test showed the same person different prices on different
/// days, and nobody was really in one arm.
///
/// It is not an advertising or device identifier. It is a UUID this SDK made
/// up, it is never shared with another app, and it goes away when the app is
/// deleted — a reinstall is a new install, and may land in a different arm.
enum InstallId {
    static let defaultsKey = "paygate_install_id"

    private static let lock = NSLock()
    private static var cached: String?

    /// This install's id, creating and persisting one on first use.
    static var current: String {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let id = resolve(in: .standard)
        cached = id
        return id
    }

    /// Reads the stored id from `defaults`, or creates and stores a new one.
    ///
    /// Separate from ``current`` so it can be tested against a throwaway
    /// suite instead of the host app's own defaults.
    static func resolve(in defaults: UserDefaults) -> String {
        if let stored = defaults.string(forKey: defaultsKey), !stored.isEmpty {
            return stored
        }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: defaultsKey)
        return fresh
    }
}
