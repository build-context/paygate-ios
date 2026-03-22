import UIKit
import WebKit

/// View controller that presents a Paygate flow in a WKWebView.
/// Handles the JS bridge for close and purchase events.
public class PaygateViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {

    private let flowData: FlowData
    private let apiKey: String
    private let baseURL: String
    private let bounces: Bool
    private let gateId: String?
    private let purchaseRequired: Bool
    private let disableWebViewCache: Bool
    private let productIdMap: [String: String]
    private let completion: (PaygateResult) -> Void
    private var didInvokeCompletion = false
    private var webView: WKWebView!
    private var spinner: UIActivityIndicatorView!

    init(
        flowData: FlowData,
        apiKey: String,
        baseURL: String,
        bounces: Bool = false,
        gateId: String? = nil,
        purchaseRequired: Bool = false,
        disableWebViewCache: Bool = false,
        completion: @escaping (PaygateResult) -> Void
    ) {
        self.flowData = flowData
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.bounces = bounces
        self.gateId = gateId
        self.purchaseRequired = purchaseRequired
        self.disableWebViewCache = disableWebViewCache
        self.productIdMap = flowData.productIdMap
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupWebView()
        setupSpinner()
        loadFlowContent()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // User may have swiped to dismiss the sheet; ensure continuation is always resumed
        if isBeingDismissed, !didInvokeCompletion {
            invokeCompletionOnce(.dismissed(data: nil))
        }
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()

        // For refresh_on_launch gates, use non-persistent data store so the WebView
        // does not cache any subresources (images, etc.) — ensuring fresh content.
        if disableWebViewCache {
            config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        }

        // Add JS bridge message handler
        let contentController = WKUserContentController()
        contentController.add(self, name: "paygate")

        // Disable text selection in the paywall
        let disableSelectionScript = WKUserScript(
            source: """
            (function() {
                var style = document.createElement('style');
                style.textContent = '* { -webkit-user-select: none !important; user-select: none !important; -webkit-touch-callout: none !important; }';
                document.head.appendChild(style);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(disableSelectionScript)

        config.userContentController = contentController

        // Allow inline media playback
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.scrollView.bounces = bounces
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupSpinner() {
        spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func loadFlowContent() {
        let pageDivs = flowData.pages.enumerated().map { i, page in
            let hidden = i > 0 ? " style=\"display:none\"" : ""
            return "<div id=\"page_\(page.id)\" class=\"paygate-page\"\(hidden)>\(page.htmlContent)</div>"
        }.joined(separator: "\n")

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
        <title>Flow</title>
        </head>
        <body>
        \(pageDivs)
        \(flowData.bridgeScript)
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: baseURL))
    }

    // MARK: - WKScriptMessageHandler

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "paygate",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        switch action {
        case "close":
            let data = body["data"] as? [String: Any]
            dismissFlow(result: .dismissed(data: data))

        case "skip":
            let data = body["data"] as? [String: Any]
            if purchaseRequired {
                dismissFlow(result: .dismissed(data: data))
            } else {
                if let gateId = gateId {
                    SkipPersistence.recordSkipped(gateId: gateId)
                }
                dismissFlow(result: .skipped(data: data))
            }

        case "purchase":
            if let productId = body["productId"] as? String {
                let data = body["data"] as? [String: Any]
                handlePurchase(productId: productId, data: data)
            }

        default:
            print("[Paygate] Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func invokeCompletionOnce(_ result: PaygateResult) {
        guard !didInvokeCompletion else { return }
        didInvokeCompletion = true
        completion(result)
    }

    private func dismissFlow(result: PaygateResult) {
        invokeCompletionOnce(result)
        dismiss(animated: true)
    }

    private func handlePurchase(productId: String, data: [String: Any]? = nil) {
        let storeProductId = productIdMap[productId] ?? productId
        print("[Paygate] Purchase requested: \(productId) → App Store ID: \(storeProductId)")

        trackEvent(eventType: "purchase_initiated", metadata: ["productId": productId])

        Task {
            do {
                let purchased = try await StoreKitManager.shared.purchase(storeProductId)
                if let purchasedId = purchased {
                    print("[Paygate] Purchase completed: \(purchasedId)")
                    trackEvent(eventType: "purchase_completed", metadata: ["productId": purchasedId])
                    dismissFlow(result: .purchased(productId: purchasedId, data: data))
                } else {
                    print("[Paygate] Purchase cancelled by user")
                }
            } catch {
                print("[Paygate] Purchase error: \(error.localizedDescription)")
                dismissFlow(result: .error(error))
            }
        }
    }

    private func trackEvent(eventType: String, metadata: [String: String] = [:]) {
        guard let url = URL(string: "\(baseURL)/sdk/flows/\(flowData.id)/events") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        PaygateHTTP.applyDefaultHeaders(to: &request, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "eventType": eventType,
            "metadata": metadata,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                print("[Paygate] Error tracking event: \(error.localizedDescription)")
            }
        }.resume()
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()
        spinner.removeFromSuperview()
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Only allow the initial HTML load and same-origin navigation
        if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
            decisionHandler(.allow)
        } else {
            // Open external links in Safari
            if let url = navigationAction.request.url {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
