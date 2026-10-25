import UIKit
import WebKit

/// Ask Quicklly in search: the assistant's answer above your own search results — the products the shopper meant
/// (e.g. milk when the search for "cow milk" lists butter first), a line about them and a few follow-up chips.
///
/// ```swift
/// let answer = RunaSearchView(options: options, delegate: self)   // the same Options as the chat
/// answer.chatDelegate = self                                       // your RunaChatDelegate: a chip opens the chat
/// resultsStack.insertArrangedSubview(answer, at: 0)                // above your results, full width
/// answer.search("cow milk", resultCount: 76, firstTitles: titles)  // on every search the shopper makes
/// ```
///
/// The view is as tall as its answer (`intrinsicContentSize`) and changes height as the answer arrives (a one-line
/// working state, then the products); with nothing to show it hides itself. ADD and the quantity steppers go through
/// your `setQuantity` / cart delegate methods, a product tap through `openProduct`, and a chip opens the chat screen
/// with that question. Main thread only.
public final class RunaSearchView: UIView {

    private static let views = NSHashTable<RunaSearchView>.weakObjects()
    static var all: [RunaSearchView] { views.allObjects }

    public weak var delegate: RunaSearchViewDelegate?
    /// The chat a chip opens is driven by this delegate (usually the same object as for your chat button).
    public weak var chatDelegate: RunaChatDelegate?
    /// The view's height in points, whenever it changes (0 = hidden).
    public private(set) var height: CGFloat = 0

    private var options: RunaChat.Options
    private var webView: WKWebView?
    private var origin = ""
    private var pageReady = false
    private var loadedQuery = ""
    private var pending: [String: Any]?

    public init(options: RunaChat.Options, delegate: RunaSearchViewDelegate) {
        self.options = options
        self.delegate = delegate
        super.init(frame: .zero)
        backgroundColor = .white
        isHidden = true
        Self.views.add(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("use init(options:delegate:)") }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "runa")
    }

    public override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: height) }

    /// The shopper searched. `resultCount` and `firstTitles` are what your own results show — how many products your
    /// search found and the first few product names (up to 10, top to bottom). Optional, but they let Ask Quicklly
    /// tell when your results already answer the search, and say so instead of repeating them.
    public func search(_ query: String, resultCount: Int? = nil, firstTitles: [String] = []) {
        let q = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        if q.isEmpty { clear(); return }
        var payload: [String: Any] = ["query": q, "titles": Array(firstTitles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(10))]
        if let n = resultCount { payload["results"] = n }
        guard webView != nil else { load(payload); return }
        if pageReady { post("search", payload) } else { pending = payload }
    }

    /// Hide the answer (e.g. the search field was cleared). The next `search` shows it again.
    public func clear() {
        if pageReady { post("search", [:]) }
        setHeight(0)
    }

    // MARK: - WebView

    private func load(_ first: [String: Any]) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()      // shared with the chat: the shopper id and what Ask Quicklly showed
        config.userContentController.add(SearchMessageProxy(self), name: "runa")
        let wv = WKWebView(frame: bounds, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.scrollView.isScrollEnabled = false      // the view is as tall as the page; the product row scrolls inside it
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.backgroundColor = .white
        wv.isOpaque = false
        #if DEBUG
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        #endif
        wv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: topAnchor),
            wv.bottomAnchor.constraint(equalTo: bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        webView = wv
        var items = RunaChat.shopperQuery(options)
        items.append(URLQueryItem(name: "q", value: first["query"] as? String))
        if let n = first["results"] as? Int { items.append(URLQueryItem(name: "results", value: String(n))) }
        if let t = first["titles"] as? [String], !t.isEmpty { items.append(URLQueryItem(name: "titles", value: t.map { $0.replacingOccurrences(of: "|", with: " ") }.joined(separator: "|"))) }
        let url = RunaChat.url(options.pageURL(for: "search-app.html"), items)
        origin = RunaChat.originOf(url)
        loadedQuery = first["query"] as? String ?? ""
        wv.load(URLRequest(url: url))
    }

    // MARK: - Page → app

    fileprivate func handle(_ body: Any, from frame: WKFrameInfo) {
        guard frame.isMainFrame, RunaChat.originOf(webView?.url ?? URL(string: "about:blank")!) == origin,
              let (type, payload, _) = RunaChat.parse(body) else { return }
        if options.debug { print("[RunaChat] search page→app \(type) \(payload)") }
        switch type {
        case "ready":
            pageReady = true
            sendCart()
            if let p = pending { pending = nil; if (p["query"] as? String) != loadedQuery { post("search", p) } }
        case "resize":
            setHeight(CGFloat((payload["height"] as? NSNumber)?.doubleValue ?? 0))
        case "setQty":
            let product = RunaChat.Product(payload)
            delegate?.runaSearch(self, setQuantity: max(0, (payload["qty"] as? NSNumber)?.intValue ?? 0), of: product)
            sendCart()      // the acknowledgement: the page redraws its steppers from it
        case "openProduct":
            let product = RunaChat.Product(payload)
            if delegate?.runaSearch(self, openProduct: product) != true, let url = product.url { RunaChat.openInApp(url, from: hostViewController) }
        case "openChat":
            // a chip or "Ask me anything": the chat screen with the question already sent, credited to Ask Quicklly in search
            let text = (payload["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if delegate?.runaSearch(self, openChatWith: text.isEmpty ? nil : text) != true { openChat(text) }
        case "openExternal":
            if let s = payload["url"] as? String, let url = URL(string: s) { openLink(url) }
        default:
            break
        }
        delegate?.runaSearch(self, didReceive: type, payload: payload)
    }

    private func openChat(_ text: String) {
        guard let from = hostViewController, let chat = chatDelegate ?? (delegate as? RunaChatDelegate) else {
            if options.debug { print("[RunaChat] search view: set chatDelegate so a chip can open the chat") }
            return
        }
        var o = options
        o.question = text.isEmpty ? nil : text
        o.entry = "search_answers"
        RunaChat.open(from: from, options: o, delegate: chat)
    }

    private func openLink(_ url: URL) {
        if delegate?.runaSearch(self, openLink: url) == true { return }
        RunaChat.openInApp(url, from: hostViewController)
    }

    private var hostViewController: UIViewController? {
        var r: UIResponder? = self
        while let next = r?.next { if let vc = next as? UIViewController { return vc }; r = next }
        return nil
    }

    private func setHeight(_ h: CGFloat) {
        let h = max(0, h.rounded(.up))
        guard h != height || isHidden != (h == 0) else { return }
        height = h
        isHidden = h == 0
        invalidateIntrinsicContentSize()
        delegate?.runaSearch(self, didChangeHeight: h)
    }

    // MARK: - App → page

    func sendCart() {
        guard pageReady, let delegate = delegate else { return }
        post("cart", ["items": delegate.runaSearchCart(self).map { ["pid": $0.pid, "sid": $0.sid, "qty": $0.quantity] as [String: Any] }])
    }

    func sendAddress(zip: String, address: String?, city: String?, state: String?) {
        options.zip = zip; options.address = address; options.city = city; options.state = state
        guard pageReady else { return }
        post("addressChanged", ["zip": zip, "address": address ?? "", "city": city ?? "", "state": state ?? ""])
    }

    private func post(_ type: String, _ payload: [String: Any]) {
        guard let literal = RunaChat.json(type, payload) else { return }
        if options.debug { print("[RunaChat] search app→page \(type) \(payload)") }
        webView?.evaluateJavaScript("window.RunaBridge&&window.RunaBridge.receive(\(literal));", completionHandler: nil)
    }
}

/// What the app does for the search view: the same three jobs as for the chat. `setQuantity`, `runaSearchCart` and
/// `openProduct` are required; the rest have defaults.
public protocol RunaSearchViewDelegate: AnyObject {
    /// Set this product's quantity in the app's cart. Absolute: 0 removes the line.
    func runaSearch(_ view: RunaSearchView, setQuantity quantity: Int, of product: RunaChat.Product)
    /// What is in the app's cart right now.
    func runaSearchCart(_ view: RunaSearchView) -> [RunaChat.CartItem]
    /// The shopper tapped a product. Open your product screen and return true (false: its web page in a sheet).
    func runaSearch(_ view: RunaSearchView, openProduct product: RunaChat.Product) -> Bool
    /// A chip or "Ask me anything". Return true if you open the chat yourself; by default the library opens it
    /// (with `chatDelegate`) from the view controller the search view is in.
    func runaSearch(_ view: RunaSearchView, openChatWith question: String?) -> Bool
    /// An outside link. Return false to show it in an in-app browser sheet.
    func runaSearch(_ view: RunaSearchView, openLink url: URL) -> Bool
    /// The view changed height (points; 0 = hidden) — for a table header or anything not laid out by Auto Layout.
    func runaSearch(_ view: RunaSearchView, didChangeHeight height: CGFloat)
    /// Every message from the page, after the library handled it.
    func runaSearch(_ view: RunaSearchView, didReceive type: String, payload: [String: Any])
}

public extension RunaSearchViewDelegate {
    func runaSearch(_ view: RunaSearchView, openProduct product: RunaChat.Product) -> Bool { false }
    func runaSearch(_ view: RunaSearchView, openChatWith question: String?) -> Bool { false }
    func runaSearch(_ view: RunaSearchView, openLink url: URL) -> Bool { false }
    func runaSearch(_ view: RunaSearchView, didChangeHeight height: CGFloat) {}
    func runaSearch(_ view: RunaSearchView, didReceive type: String, payload: [String: Any]) {}
}

extension RunaSearchView: WKNavigationDelegate, WKUIDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        if let u = url, RunaChat.originOf(u) == origin || u.scheme == "about" { decisionHandler(.allow); return }
        if let url = url { openLink(url) }
        decisionHandler(.cancel)
    }

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { openLink(url) }
        return nil
    }
}

/// Breaks the WKUserContentController → handler → view retain cycle.
private final class SearchMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: RunaSearchView?
    init(_ target: RunaSearchView) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handle(message.body, from: message.frameInfo)
    }
}
