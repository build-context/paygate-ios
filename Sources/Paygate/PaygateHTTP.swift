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
        request.setValue("apple", forHTTPHeaderField: "Paygate-Platform")
        request.setValue(Paygate.currentChannel.rawValue, forHTTPHeaderField: "Paygate-Channel")
        // The override is sent, not applied locally, so the server can refuse it
        // on production and say so in its logs. A client that silently dropped
        // it would leave a developer staring at the wrong price with nothing to
        // explain why.
        if let override = Paygate.storefrontOverride {
            request.setValue(override, forHTTPHeaderField: "Paygate-Storefront-Override")
        }
    }

    /// Adds the reader's store country, when it is known.
    ///
    /// Separate from `applyDefaultHeaders` because reading it is async and only
    /// the render calls need it — see `Paygate.currentStorefront`.
    static func applyStorefront(to request: inout URLRequest, storefront: String?) {
        guard let storefront, !storefront.isEmpty else { return }
        request.setValue(storefront, forHTTPHeaderField: "Paygate-Storefront")
    }
}
