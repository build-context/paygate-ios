import Foundation

/// Low-level HTTP helpers shared by all SDK network calls.
enum PaygateHTTP {

    /// Host app bundle identifier (`CFBundleIdentifier`).
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? ""
    }

    /// Applies standard SDK headers: API key, API version, and bundle id when known.
    static func applyDefaultHeaders(to request: inout URLRequest, apiKey: String) {
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(Paygate.apiVersion, forHTTPHeaderField: "Paygate-Version")
        let bid = bundleIdentifier
        if !bid.isEmpty {
            request.setValue(bid, forHTTPHeaderField: "Paygate-Bundle-Id")
        }
    }
}
