import UIKit
import WebKit

/// Ask Quicklly on your product screen: what goes with the product — "Recipes" (the dishes it is for, every ingredient
/// from the same store, one "Add all") or "Goes great with" — and the Ask Quicklly line under it, as on quicklly.com's
/// product pages.
///
/// ```swift
/// let bundle = RunaProductView(options: options, delegate: self)        // the same Options as the chat
/// bundle.chatDelegate = self                                            // your RunaChatDelegate: the Ask Quicklly line opens the chat
/// detailsStack.addArrangedSubview(bundle)                               // under your product details, full width
/// bundle.show(productId: "1013592", storeId: "113189", title: "Okra (bhindi) 1 Lbs")   // the product on screen
/// ```
///
/// The view is as tall as its content (`intrinsicContentSize`) and appears once it has something to show; a product
/// with nothing to suggest leaves it hidden. ADD, "Add all" and the steppers go through your `setQuantity` / cart
/// delegate methods, a product tap through `openProduct`, and the Ask Quicklly line opens the chat screen with its
/// question. Main thread only.
public final class RunaProductView: UIView {

    private static let views = NSHashTable<RunaProductView>.weakObjects()
    static var all: [RunaProductView] { views.allObjects }

    public weak var delegate: RunaProductViewDelegate?
    /// The chat the Ask Quicklly line opens is driven by this delegate (usually the same object as for your chat button).
    public weak var chatDelegate: RunaChatDelegate?
    /// The view's height in points, whenever it changes (0 = hidden).
    public private(set) var height: CGFloat = 0

    private var options: RunaChat.Options
    private var webView: WKWebView?
    private var origin = ""
    private var pageReady = false
    private var loadedKey = ""
    private var pending: [String: Any]?
    private var scrollObservations: [NSKeyValueObservation] = []
    private var lastViewport = ""

    public init(options: RunaChat.Options, delegate: RunaProductViewDelegate) {
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

    /// The product on your screen: its id and its store's id as on quicklly.com (/grocery-store/<handle>/<id>), and its
    /// name. The name is optional but recommended: a food product without a bundle still gets the Ask Quicklly line.
    /// Call again when the screen shows another product (the view is reused).
    public func show(productId: String, storeId: String, title: String? = nil) {
        let pid = productId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pid.range(of: "^[0-9]+$", options: .regularExpression) != nil else { clear(); return }
        let payload: [String: Any] = ["pid": pid, "sid": storeId.trimmingCharacters(in: .whitespacesAndNewlines),
                                      "title": (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)]
        guard webView != nil else { load(payload); return }
        if pageReady { post("product", payload) } else { pending = payload }
    }

    /// Hide the view (e.g. the product screen is being reused for something else). The next `show` shows it again.
    public func clear() {
        if pageReady { post("product", [:]) }
        setHeight(0)
    }

    // MARK: - Where the shopper sees it

    // The page types the Ask Quicklly line once it is in the middle of the screen (the website's rule — the WebView
    // cannot know where the app scrolled it): the view follows the scroll views around it and tells the page.
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        scrollObservations = []
        guard window != nil else { return }
        var v: UIView? = superview
        while let s = v {
            if let scroll = s as? UIScrollView {
                scrollObservations.append(scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in self?.sendViewport() })
            }
            v = s.superview
        }
        sendViewport()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        sendViewport()
    }

    /// The part of the view inside the middle of the screen — clear of its top 20% and bottom 15% — in the page's CSS
    /// px (points), sent when it changes. Empty (top = bottom = 0): off screen or hidden.
    private func sendViewport() {
        guard pageReady, let window = window else { return }
        var top = 0, bottom = 0
        if !isHidden, height > 0 {
            let frame = convert(bounds, to: window)
            let bandTop = window.bounds.height * 0.20, bandBottom = window.bounds.height * 0.85
            let vTop = max(frame.minY, bandTop), vBottom = min(frame.maxY, bandBottom)
            if vBottom > vTop { top = Int((vTop - frame.minY).rounded()); bottom = Int((vBottom - frame.minY).rounded()) }
        }
        let key = "\(top),\(bottom)"
        guard key != lastViewport else { return }
        lastViewport = key
        post("viewport", ["top": top, "bottom": bottom])
    }

    // MARK: - WebView

    private func load(_ first: [String: Any]) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()      // shared with the chat: the shopper id and what Ask Quicklly showed
        config.userContentController.add(ProductMessageProxy(self), name: "runa")
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
        items.append(URLQueryItem(name: "pid", value: first["pid"] as? String))
        if let sid = first["sid"] as? String, !sid.isEmpty { items.append(URLQueryItem(name: "sid", value: sid)) }
        if let t = first["title"] as? String, !t.isEmpty { items.append(URLQueryItem(name: "title", value: t)) }
        if options.preview { items.append(URLQueryItem(name: "preview", value: "1")) }
        let url = RunaChat.url(options.pageURL(for: "product-app.html"), items)
        origin = RunaChat.originOf(url)
        loadedKey = Self.key(first)
        wv.load(URLRequest(url: url))
    }

    private static func key(_ p: [String: Any]) -> String { "\(p["pid"] as? String ?? "")|\(p["sid"] as? String ?? "")" }

    // MARK: - Page → app

    fileprivate func handle(_ body: Any, from frame: WKFrameInfo) {
        guard frame.isMainFrame, RunaChat.originOf(webView?.url ?? URL(string: "about:blank")!) == origin,
              let (type, payload, _) = RunaChat.parse(body) else { return }
        if options.debug { print("[RunaChat] product page→app \(type) \(payload)") }
        switch type {
        case "ready":
            pageReady = true
            sendCart()
            lastViewport = ""
            sendViewport()
            if let p = pending { pending = nil; if Self.key(p) != loadedKey { post("product", p) } }
        case "resize":
            setHeight(CGFloat((payload["height"] as? NSNumber)?.doubleValue ?? 0))
        case "setQty":
            let product = RunaChat.Product(payload)
            delegate?.runaProduct(self, setQuantity: max(0, (payload["qty"] as? NSNumber)?.intValue ?? 0), of: product)
            sendCart()      // the acknowledgement: the page redraws its steppers and "Add all" from it
        case "openProduct":
            let product = RunaChat.Product(payload)
            if delegate?.runaProduct(self, openProduct: product) != true, let url = product.url { RunaChat.openInApp(url, from: hostViewController) }
        case "openChat":
            // the Ask Quicklly line: the chat screen with its question already sent, credited to the product page
            let text = (payload["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let entry = (payload["entry"] as? String) ?? "product_page"
            if delegate?.runaProduct(self, openChatWith: text.isEmpty ? nil : text) != true { openChat(text, entry: entry) }
        case "openExternal":
            if let s = payload["url"] as? String, let url = URL(string: s) { openLink(url) }
        default:
            break
        }
        delegate?.runaProduct(self, didReceive: type, payload: payload)
    }

    private func openChat(_ text: String, entry: String) {
        guard let from = hostViewController, let chat = chatDelegate ?? (delegate as? RunaChatDelegate) else {
            if options.debug { print("[RunaChat] product view: set chatDelegate so the Ask Quicklly line can open the chat") }
            return
        }
        var o = options
        o.question = text.isEmpty ? nil : text
        o.entry = entry
        RunaChat.open(from: from, options: o, delegate: chat)
    }

    private func openLink(_ url: URL) {
        if delegate?.runaProduct(self, openLink: url) == true { return }
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
        delegate?.runaProduct(self, didChangeHeight: h)
        DispatchQueue.main.async { [weak self] in self?.sendViewport() }
    }

    // MARK: - App → page

    func sendCart() {
        guard pageReady, let delegate = delegate else { return }
        post("cart", ["items": delegate.runaProductCart(self).map { ["pid": $0.pid, "sid": $0.sid, "qty": $0.quantity] as [String: Any] }])
    }

    func sendAddress(zip: String, address: String?, city: String?, state: String?) {
        options.zip = zip; options.address = address; options.city = city; options.state = state
        guard pageReady else { return }
        post("addressChanged", ["zip": zip, "address": address ?? "", "city": city ?? "", "state": state ?? ""])
    }

    private func post(_ type: String, _ payload: [String: Any]) {
        guard let literal = RunaChat.json(type, payload) else { return }
        if options.debug && type != "viewport" { print("[RunaChat] product app→page \(type) \(payload)") }
        webView?.evaluateJavaScript("window.RunaBridge&&window.RunaBridge.receive(\(literal));", completionHandler: nil)
    }
}

/// What the app does for the product view: the same three jobs as for the chat. `setQuantity`, `runaProductCart` and
/// `openProduct` are required; the rest have defaults.
public protocol RunaProductViewDelegate: AnyObject {
    /// Set this product's quantity in the app's cart. Absolute: 0 removes the line.
    func runaProduct(_ view: RunaProductView, setQuantity quantity: Int, of product: RunaChat.Product)
    /// What is in the app's cart right now.
    func runaProductCart(_ view: RunaProductView) -> [RunaChat.CartItem]
    /// The shopper tapped a product. Open your product screen and return true (false: its web page in a sheet).
    func runaProduct(_ view: RunaProductView, openProduct product: RunaChat.Product) -> Bool
    /// The Ask Quicklly line. Return true if you open the chat yourself; by default the library opens it (with
    /// `chatDelegate`) from the view controller the product view is in.
    func runaProduct(_ view: RunaProductView, openChatWith question: String?) -> Bool
    /// An outside link. Return false to show it in an in-app browser sheet.
    func runaProduct(_ view: RunaProductView, openLink url: URL) -> Bool
    /// The view changed height (points; 0 = hidden) — for anything not laid out by Auto Layout.
    func runaProduct(_ view: RunaProductView, didChangeHeight height: CGFloat)
    /// Every message from the page, after the library handled it.
    func runaProduct(_ view: RunaProductView, didReceive type: String, payload: [String: Any])
}

public extension RunaProductViewDelegate {
    func runaProduct(_ view: RunaProductView, openProduct product: RunaChat.Product) -> Bool { false }
    func runaProduct(_ view: RunaProductView, openChatWith question: String?) -> Bool { false }
    func runaProduct(_ view: RunaProductView, openLink url: URL) -> Bool { false }
    func runaProduct(_ view: RunaProductView, didChangeHeight height: CGFloat) {}
    func runaProduct(_ view: RunaProductView, didReceive type: String, payload: [String: Any]) {}
}

extension RunaProductView: WKNavigationDelegate, WKUIDelegate {
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
private final class ProductMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: RunaProductView?
    init(_ target: RunaProductView) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handle(message.body, from: message.frameInfo)
    }
}
