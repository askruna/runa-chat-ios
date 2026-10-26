import UIKit
import WebKit

/// `RunaChat.orderPlaced`: loads Runa's order page in a WebView the shopper never sees, hands it the order once the
/// page says `ready`, and lets go when the page answers `done` (or after 20 s). The page reads what Ask Quicklly
/// showed, opened and added from the storage the chat and the search view share and reports the order with Ask
/// Quicklly's sales in it — the same rule and the same event as on the website.
final class OrderReporter: NSObject {

    private static var running: [OrderReporter] = []      // kept alive until done
    private let options: RunaChat.Options
    private let order: RunaChat.Order
    private let completion: ((Bool, String?) -> Void)?
    private var webView: WKWebView?
    private var origin = ""
    private var finished = false

    init(options: RunaChat.Options, order: RunaChat.Order, completion: ((Bool, String?) -> Void)?) {
        self.options = options
        self.order = order
        self.completion = completion
    }

    func start() {
        Self.running.append(self)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(OrderMessageProxy(self), name: "runa")
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.navigationDelegate = self
        // In the window but invisible: a WebView outside any window may have its timers paused by WebKit.
        wv.alpha = 0
        wv.isUserInteractionEnabled = false
        keyWindow?.addSubview(wv)
        webView = wv
        // No personal data (1.1.2): the customer id the chat already uses, the platform and app version — not the ZIP,
        // delivery address, city or state the chat is given.
        let keep: Set<String> = ["userId", "platform", "appVersion", "debug"]
        let url = RunaChat.url(options.pageURL(for: "order-app.html"), RunaChat.shopperQuery(options).filter { keep.contains($0.name) })
        if options.debug { print("[RunaChat] order page \(url.absoluteString)") }
        origin = RunaChat.originOf(url)
        wv.load(URLRequest(url: url))
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.finish(false, "timeout") }
    }

    private var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    fileprivate func handle(_ body: Any, from frame: WKFrameInfo) {
        guard !finished, frame.isMainFrame, let u = webView?.url, RunaChat.originOf(u) == origin,
              let (type, payload, _) = RunaChat.parse(body) else { return }
        if options.debug { print("[RunaChat] order page→app \(type) \(payload)") }
        switch type {
        case "ready":
            let items: [[String: Any]] = order.lines.map { ["pid": $0.pid, "sid": $0.sid, "price": $0.price, "qty": $0.quantity] }
            let p: [String: Any] = ["orderNumber": order.orderNumber, "total": order.total, "currency": order.currency, "items": items]
            if let literal = RunaChat.json("orderPlaced", p, requestId: "order") {
                webView?.evaluateJavaScript("window.RunaBridge&&window.RunaBridge.receive(\(literal));", completionHandler: nil)
            }
        case "done":
            finish(payload["ok"] as? Bool ?? false, payload["reason"] as? String)
        default:
            break
        }
    }

    private func finish(_ ok: Bool, _ reason: String?) {
        guard !finished else { return }
        finished = true
        if options.debug { print("[RunaChat] orderPlaced \(ok ? "reported" : "not reported: \(reason ?? "")")") }
        completion?(ok, reason)
        // a moment for the page's own request to leave before the WebView goes (it is sent with keepalive)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "runa")
            webView?.removeFromSuperview()
            webView = nil
            Self.running.removeAll { $0 === self }
        }
    }
}

extension OrderReporter: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false, "page not loaded")
    }
}

private final class OrderMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: OrderReporter?
    init(_ target: OrderReporter) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handle(message.body, from: message.frameInfo)
    }
}
