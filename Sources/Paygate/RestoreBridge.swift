import Foundation

/// How a flow hears the outcome of `paygate.restore()`.
///
/// Restore used to be silent whenever it did not unlock anything: no message,
/// and nothing the flow HTML could react to. A reader who tapped Restore with
/// nothing to restore saw nothing happen, which looks exactly like a broken
/// button (and is an App Review rejection risk).
///
/// Now the SDK reports every outcome back to the page:
///
/// ```js
/// paygate.onRestore = function (result) {
///   // result.status: "restored" | "nothing_found" | "cancelled" | "error"
///   // result.productId (restored), result.message (error)
/// };
/// // or
/// paygate.restore().then(function (result) { ... });
/// ```
///
/// A flow that sets `paygate.onRestore` shows its own message. One that does
/// not gets a native alert from the SDK for `nothing_found` and `error`, so
/// existing flows stop being silent without anyone editing them.
///
/// Injected by the SDK after the server's bridge script rather than added to
/// that script, so it works against today's API with no deploy, and the
/// Android SDK injects the same script. Kept in step with
/// `RestoreBridge.kt` on Android.
enum RestoreBridge {

    enum Status: String {
        case restored
        case nothingFound = "nothing_found"
        case cancelled
        case error
    }

    /// Wraps `paygate.restore` so it returns a Promise, and adds the
    /// `_restoreResult` entry point native code calls with the outcome.
    /// `_restoreResult` returns true when the flow handled the result itself
    /// (it defines `paygate.onRestore`), so the SDK knows not to show its own
    /// message.
    static let script = """
    <script>
    (function () {
      var pg = window.paygate;
      if (!pg || pg.__restoreResultInstalled) return;
      pg.__restoreResultInstalled = true;
      var waiting = [];
      var originalRestore = pg.restore;
      pg.restore = function (overrideData) {
        var promise;
        if (typeof Promise !== 'undefined') {
          promise = new Promise(function (resolve) { waiting.push(resolve); });
        }
        originalRestore.apply(pg, arguments);
        return promise;
      };
      pg._restoreResult = function (result) {
        var resolvers = waiting;
        waiting = [];
        for (var i = 0; i < resolvers.length; i++) {
          try { resolvers[i](result); } catch (e) {}
        }
        if (typeof pg.onRestore === 'function') {
          try { pg.onRestore(result); } catch (e) {}
          return true;
        }
        return false;
      };
    })();
    </script>
    """

    /// The JavaScript that delivers one result to the page. Evaluates to
    /// `true` when the flow handled it.
    static func deliverScript(status: Status, productId: String? = nil, message: String? = nil) -> String {
        var result: [String: String] = ["status": status.rawValue]
        if let productId { result["productId"] = productId }
        if let message { result["message"] = message }
        let json = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"status\":\"\(status.rawValue)\"}"
        return "(window.paygate && typeof window.paygate._restoreResult === 'function') " +
            "? window.paygate._restoreResult(\(json)) === true : false"
    }

    /// The SDK's own message when the flow shows none. `nil` for outcomes
    /// that need no message: a restore that worked closes the flow, and a
    /// cancelled one was the reader's own choice.
    ///
    /// Copy states the fact and the next step, without apology.
    static func fallbackAlert(for status: Status) -> (title: String, message: String)? {
        switch status {
        case .nothingFound:
            return (
                "No purchases to restore",
                "This Apple Account has no purchases to restore for this app. " +
                    "If you bought with a different Apple Account, sign in with that one and try again."
            )
        case .error:
            return (
                "Couldn't restore purchases",
                "Check your connection and try again."
            )
        case .restored, .cancelled:
            return nil
        }
    }
}
