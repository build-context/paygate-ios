import XCTest
@testable import Paygate

/// Paygate finishes only the purchases it made, and a paywall can follow the
/// app's language instead of the device's.
final class OwnPurchasesTests: XCTestCase {

    func testLeavesOtherCodesTransactionsAlone() {
        XCTAssertFalse(StoreKitManager.shouldFinish(productID: "sd.annual", completesAll: false, awaiting: []))
    }

    func testFinishesItsOwnPendingPurchaseWhenItClears() {
        XCTAssertTrue(StoreKitManager.shouldFinish(productID: "ss.annual", completesAll: false, awaiting: ["ss.annual"]))
    }

    func testFinishesEverythingWhenTheAppOptsIn() {
        XCTAssertTrue(StoreKitManager.shouldFinish(productID: "sd.annual", completesAll: true, awaiting: []))
    }

    func testAwaitingSetSurvivesAndClears() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "paygate.test.\(UUID().uuidString)"))
        StoreKitManager.addAwaiting("a", defaults)
        StoreKitManager.addAwaiting("b", defaults)
        XCTAssertEqual(StoreKitManager.awaitingProductIDs(defaults), ["a", "b"])
        StoreKitManager.removeAwaiting("a", defaults)
        XCTAssertEqual(StoreKitManager.awaitingProductIDs(defaults), ["b"])
    }
}

final class LocaleTests: XCTestCase {

    func testNormalizesTags() {
        XCTAssertEqual(Paygate.normalizedLocale(" es "), "es")
        XCTAssertEqual(Paygate.normalizedLocale("pt_BR"), "pt-BR")
        XCTAssertEqual(Paygate.normalizedLocale("zh-Hant-TW"), "zh-Hant-TW")
    }

    func testRejectsWhatIsNotALanguageTag() {
        XCTAssertNil(Paygate.normalizedLocale(nil))
        XCTAssertNil(Paygate.normalizedLocale(""))
        XCTAssertNil(Paygate.normalizedLocale("es\"><script>"))
        XCTAssertNil(Paygate.normalizedLocale("e"))
    }

    func testNoLocaleLeavesThePageAsItWas() {
        XCTAssertNil(LocaleBridge.headScript(locale: nil))
        XCTAssertEqual(LocaleBridge.htmlLang(locale: nil), "en")
        XCTAssertTrue(LocaleBridge.tailScript(locale: nil).contains("navigator.language"))
    }

    func testLocaleOverridesNavigatorLanguageWithoutCreatingTheBridge() throws {
        let head = try XCTUnwrap(LocaleBridge.headScript(locale: "es"))
        XCTAssertTrue(head.contains("'language'"))
        XCTAssertTrue(head.contains("\"es\""))
        // The bridge installs its methods only when window.paygate is still
        // undefined, so the head script must never create it.
        XCTAssertFalse(head.contains("window.paygate"))
        XCTAssertTrue(LocaleBridge.tailScript(locale: "es").contains("window.paygate.locale = \"es\""))
    }

    func testJsStringCannotCloseTheScript() {
        XCTAssertEqual(LocaleBridge.jsString("a</script>"), "\"a<\\/script>\"")
    }

    func testCacheKeySeparatesLanguages() {
        XCTAssertNotEqual(
            Paygate.cacheKey("gate", storefront: "USA", locale: "es"),
            Paygate.cacheKey("gate", storefront: "USA", locale: nil)
        )
    }
}

import WebKit

/// The override has to hold in a real WebKit page, before the flow's own
/// inline script runs, and must leave `window.paygate` for the bridge.
@MainActor
final class LocaleWebViewTests: XCTestCase {

    private func evaluate(_ html: String, _ script: String) async throws -> Any? {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        // WebKit loads nothing for a view that is not in a window.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.addSubview(webView)
        window.isHidden = false
        defer { window.isHidden = true }
        let loaded = expectation(description: "loaded")
        final class Delegate: NSObject, WKNavigationDelegate {
            let done: () -> Void
            init(_ done: @escaping () -> Void) { self.done = done }
            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done() }
        }
        let delegate = Delegate { loaded.fulfill() }
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 30)
        _ = delegate
        return try await webView.evaluateJavaScript(script)
    }

    func testFlowScriptSeesTheAppLanguageAndTheBridgeStillInstalls() async throws {
        let html = """
        <!DOCTYPE html><html lang="\(LocaleBridge.htmlLang(locale: "es"))"><head>
        \(LocaleBridge.headScript(locale: "es")!)
        </head><body>
        <script>window.seenByFlow = navigator.language; window.paygateBeforeBridge = typeof window.paygate;</script>
        <script>window.paygate = window.paygate || { close: function () {} };</script>
        \(LocaleBridge.tailScript(locale: "es"))
        </body></html>
        """
        let result = try await evaluate(
            html,
            "[window.seenByFlow, window.paygateBeforeBridge, typeof window.paygate.close, window.paygate.locale, document.documentElement.lang].join('|')"
        )
        XCTAssertEqual(result as? String, "es|undefined|function|es|es")
    }
}
