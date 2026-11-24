import Foundation

/// Hands the app's language to a flow.
///
/// A paywall is a web page, so it sees the device's language, not the app's,
/// and a reader who picked Español in the app got an English paywall on an
/// English phone. Flows already pick their text from `navigator.language`, so
/// that is what this sets: every flow follows the app with no HTML change.
///
/// Two scripts, because of where the bridge runs. The page HTML comes first
/// in the document and its inline scripts run as it is parsed, before the
/// bridge defines `window.paygate`. So:
/// - `headScript` runs before any flow script and makes `navigator.language`
///   (and `navigator.languages`) report the app's language. It must **not**
///   create `window.paygate`: the bridge only installs its methods when that
///   is still undefined.
/// - `tailScript` runs after the bridge and sets `paygate.locale`, the app's
///   language when it set one, otherwise the device's.
enum LocaleBridge {

    /// `nil` when the app set no language: the page keeps the device's.
    static func headScript(locale: String?) -> String? {
        guard let locale else { return nil }
        let l = jsString(locale)
        return """
        <script>
        (function () {
          var l = \(l);
          try {
            Object.defineProperty(navigator, 'language', { get: function () { return l; }, configurable: true });
            Object.defineProperty(navigator, 'languages', { get: function () { return [l]; }, configurable: true });
          } catch (e) {}
          document.documentElement.lang = l;
        })();
        </script>
        """
    }

    static func tailScript(locale: String?) -> String {
        let value = locale.map(jsString) ?? "(navigator.language || 'en')"
        return "<script>if (window.paygate) { window.paygate.locale = \(value); }</script>"
    }

    /// The `lang` attribute of the page: the app's language, else English as
    /// before.
    static func htmlLang(locale: String?) -> String {
        locale ?? "en"
    }

    /// A JSON string literal, which is also a safe JS string literal. The tag
    /// is already validated, but a literal never relies on that.
    static func jsString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data("[\"en\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
            .replacingOccurrences(of: "</", with: "<\\/")
    }
}
