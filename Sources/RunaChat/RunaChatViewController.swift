import UIKit
import WebKit

/// The chat screen: a full-screen WKWebView on Runa's page plus the JSON message bridge
/// (window.webkit.messageHandlers.runa → app, window.RunaBridge.receive ← app).
/// Opened by `RunaChat.open`, or push/present it yourself.
public final class RunaChatViewController: UIViewController {

    private static let bridgeVersion = "1.0"
    private static let backTimeout: TimeInterval = 0.4

    static weak var current: RunaChatViewController?

    private let options: RunaChat.Options
    private weak var delegate: RunaChatDelegate?
    private let pageURL: URL
    private let origin: String

    private var webView: WKWebView!
    private var bottomConstraint: NSLayoutConstraint!
    private var spinner: UIActivityIndicatorView!
    private var errorView: UIView!
    private var pageReady = false
    private var navBarWasHidden: Bool?

    public init(options: RunaChat.Options, delegate: RunaChatDelegate) {
        self.options = options
        self.delegate = delegate
        self.pageURL = Self.buildURL(options)
        self.origin = Self.originOf(pageURL)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("use init(options:delegate:)") }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "runa")
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - View

    public override func loadView() {
        let root = UIView()
        root.backgroundColor = .white

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()                 // persistent: the conversation and the shopper id live in localStorage
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(MessageProxy(self), name: "runa")   // → window.webkit.messageHandlers.runa
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = .white
        webView.isOpaque = false
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }   // Safari Web Inspector, debug builds only
        #endif
        webView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(webView)
        bottomConstraint = root.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bottomConstraint,
        ])

        spinner = UIActivityIndicatorView(style: .large)
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])

        errorView = buildErrorView()
        errorView.isHidden = true
        errorView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(errorView)
        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            errorView.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor),
            errorView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])

        view = root
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        Self.current = self
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        spinner.startAnimating()
        webView.load(URLRequest(url: pageURL))
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let nav = navigationController {
            if navBarWasHidden == nil { navBarWasHidden = nav.isNavigationBarHidden }
            nav.setNavigationBarHidden(true, animated: animated)     // the page has its own header
            nav.interactivePopGestureRecognizer?.delegate = self      // keep swipe-back working without the bar
        }
        if pageReady { sendCart() }   // back from the app's cart or product screen
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent, let nav = navigationController, let wasHidden = navBarWasHidden, !wasHidden {
            nav.setNavigationBarHidden(false, animated: animated)
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            if Self.current === self { Self.current = nil }
            delegate?.runaChatDidClose(self)
        }
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 13.0, *) { return .darkContent }
        return .default
    }

    // MARK: - Keyboard: the page shrinks above it, so the composer stays visible

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let window = view.window else { return }
        let frameInView = view.convert(end, from: window)
        let overlap = max(0, view.bounds.maxY - frameInView.minY - view.safeAreaInsets.bottom)
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        bottomConstraint.constant = overlap
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    // MARK: - Error view

    private func buildErrorView() -> UIView {
        let box = UIStackView()
        box.axis = .vertical
        box.alignment = .center
        box.spacing = 12
        box.isLayoutMarginsRelativeArrangement = true
        box.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        let bg = UIView()
        bg.backgroundColor = .white
        bg.addSubview(box)
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            box.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            box.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
        ])
        let label = UILabel()
        label.text = "We couldn't load the assistant.\nPlease check your connection."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = UIColor(white: 0.2, alpha: 1)
        box.addArrangedSubview(label)
        let retry = UIButton(type: .system)
        retry.setTitle("Try again", for: .normal)
        retry.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        box.addArrangedSubview(retry)
        let close = UIButton(type: .system)
        close.setTitle("Close", for: .normal)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        box.addArrangedSubview(close)
        return bg
    }

    @objc private func retryTapped() {
        errorView.isHidden = true
        spinner.startAnimating()
        pageReady = false
        webView.load(URLRequest(url: pageURL))
    }

    @objc private func closeTapped() { close() }

    private func showError() {
        spinner.stopAnimating()
        errorView.isHidden = false
    }

    // MARK: - Page → app

    fileprivate func handle(_ body: Any, from frame: WKFrameInfo) {
        // Only our page talks to the app.
        guard frame.isMainFrame, let host = frame.securityOrigin.host as String?, pageURL.host == host else { return }
        var msg: [String: Any]?
        if let s = body as? String, let data = s.data(using: .utf8) {
            msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } else {
            msg = body as? [String: Any]
        }
        guard let message = msg, let type = message["type"] as? String else { return }
        let payload = message["payload"] as? [String: Any] ?? [:]
        if options.debug { print("[RunaChat] page→app \(type) \(payload)") }

        switch type {
        case "ready":
            pageReady = true
            sendCart()
        case "setQty":
            let product = RunaChat.Product(payload)
            let qty = max(0, (payload["qty"] as? NSNumber)?.intValue ?? 0)
            delegate?.runaChat(self, setQuantity: qty, of: product)
            sendCart()      // the acknowledgement: the page redraws its steppers from it
        case "openProduct":
            let product = RunaChat.Product(payload)
            if delegate?.runaChat(self, openProduct: product) != true, let url = product.url {
                UIApplication.shared.open(url)
            }
        case "openExternal":
            if let s = payload["url"] as? String, let url = URL(string: s) { openLink(url) }
        case "close":
            close()
        case "backHandled":
            break   // iOS has no hardware back; the page's own menus close with a tap
        default:
            break
        }
        delegate?.runaChat(self, didReceive: type, payload: payload)
    }

    private func openLink(_ url: URL) {
        if delegate?.runaChat(self, openLink: url) == true { return }
        UIApplication.shared.open(url)
    }

    /// Close the chat screen (pop when pushed, dismiss when presented).
    public func close() {
        if let nav = navigationController, nav.viewControllers.contains(self) {
            if nav.viewControllers.first === self { nav.dismiss(animated: true) } else { nav.popViewController(animated: true) }
        } else if presentingViewController != nil {
            dismiss(animated: true)
        }
    }

    // MARK: - App → page

    func sendCart() {
        guard pageReady, let delegate = delegate else { return }
        let items: [[String: Any]] = delegate.runaChatCart(self).map { ["pid": $0.pid, "sid": $0.sid, "qty": $0.quantity] }
        post("cart", ["items": items])
    }

    func sendAddress(zip: String, address: String?, city: String?, state: String?) {
        guard pageReady else { return }
        post("addressChanged", ["zip": zip, "address": address ?? "", "city": city ?? "", "state": state ?? ""])
    }

    private func post(_ type: String, _ payload: [String: Any], requestId: String? = nil) {
        var msg: [String: Any] = ["type": type, "payload": payload, "v": Self.bridgeVersion]
        if let r = requestId { msg["requestId"] = r }
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let json = String(data: data, encoding: .utf8),
              let lit = try? JSONSerialization.data(withJSONObject: json, options: .fragmentsAllowed),
              let literal = String(data: lit, encoding: .utf8) else { return }
        if options.debug { print("[RunaChat] app→page \(type) \(payload)") }
        webView.evaluateJavaScript("window.RunaBridge&&window.RunaBridge.receive(\(literal));", completionHandler: nil)
    }

    // MARK: - URL

    private static func buildURL(_ o: RunaChat.Options) -> URL {
        var c = URLComponents(url: o.pageURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        var q = c.queryItems ?? []
        func put(_ k: String, _ v: String?) {
            let t = v?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { q.append(URLQueryItem(name: k, value: t)) }
        }
        put("zip", o.zip)
        put("userId", o.userId)
        put("platform", "ios")
        put("appVersion", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        put("address", o.address)
        put("city", o.city)
        put("state", o.state)
        put("storeId", o.storeId)
        put("q", o.question)
        if o.debug { put("debug", "1") }
        c.queryItems = q
        return c.url ?? o.pageURL
    }

    private static func originOf(_ u: URL) -> String {
        "\(u.scheme ?? "https")://\(u.host ?? "")"
    }

    private func isOurOrigin(_ u: URL?) -> Bool {
        guard let u = u else { return false }
        return Self.originOf(u) == origin
    }
}

// MARK: - WKNavigationDelegate / WKUIDelegate: the WebView stays on the chat page

extension RunaChatViewController: WKNavigationDelegate, WKUIDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        if isOurOrigin(url) || url?.scheme == "about" { decisionHandler(.allow); return }
        if let url = url { openLink(url) }
        decisionHandler(.cancel)
    }

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { openLink(url) }    // target=_blank → the app, never a popup
        return nil
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        showError()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        showError()
    }
}

extension RunaChatViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}

/// Breaks the WKUserContentController → handler → view controller retain cycle.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: RunaChatViewController?
    init(_ target: RunaChatViewController) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handle(message.body, from: message.frameInfo)
    }
}
