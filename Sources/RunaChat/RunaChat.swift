import UIKit
import WebKit
import SafariServices

/// Runa Chat — the AI shopping assistant as a screen in your app.
///
/// ```swift
/// var options = RunaChat.Options(client: "quicklly", zip: "60610")   // your client key from Runa
/// options.userId = "12345"
/// RunaChat.open(from: self, options: options, delegate: self)
///
/// extension MyViewController: RunaChatDelegate {
///     func runaChat(_ chat: RunaChatViewController, setQuantity quantity: Int, of product: RunaChat.Product) { /* your add-to-cart */ }
///     func runaChatCart(_ chat: RunaChatViewController) -> [RunaChat.CartItem] { /* what is in your cart */ }
/// }
/// ```
///
/// The chat is hosted and updated by Runa and shown full screen; improvements reach your users without app releases.
/// The app answers the two delegate calls above (the others are optional). Everything runs on the main thread.
///
/// Also in this library: `RunaSearchView`, Ask Quicklly's answer above your own search results, `RunaProductView`,
/// the bundle and the Ask Quicklly line under your product details, and `RunaChat.orderPlaced`, which reports an order
/// so the sales Ask Quicklly brought are counted.
public enum RunaChat {

    /// Who the client is and who / where the shopper is. The client key and the ZIP are required.
    public struct Options {
        /// Your client key from Runa, e.g. "quicklly".
        public var client: String
        /// The delivery ZIP. The chat shows the stores that deliver there.
        public var zip: String
        /// The customer id, or a stable id for guests. Keeps the conversation and analytics per shopper.
        public var userId: String?
        /// The "Shopping in" label, shown in the chat's store picker.
        public var address: String?
        public var city: String?
        public var state: String?
        /// Open scoped to one store (store slug, e.g. "quicklly_desi-india-bazaar").
        public var storeId: String?
        /// A question the chat sends right away ("What can I cook with paneer?").
        public var question: String?
        /// Print every message between the app and the page.
        public var debug = false
        /// Your testers' builds: show what is still in preview for shoppers (e.g. `RunaProductView` before it is live).
        public var preview = false
        /// Runa's own use: a test page instead of the client's live page (the chat page; the search and order
        /// pages are taken from the same folder).
        public var pageURLOverride: URL?
        /// Where a chat started, for the client's analytics: "search_answers" when opened from `RunaSearchView`,
        /// "product_page" from `RunaProductView`.
        var entry: String?

        public init(client: String, zip: String) {
            self.client = client.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.zip = zip
            assert(self.client.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil, "RunaChat: the client key is the one Runa gave you, e.g. \"quicklly\"")
        }

        /// The chat page for this client. Runa hosts it; the key is all the app needs to know.
        var pageURL: URL { pageURL(for: "chat-app.html") }

        /// One of this client's pages: chat-app.html, search-app.html (RunaSearchView), product-app.html (RunaProductView),
        /// order-app.html (orderPlaced).
        func pageURL(for page: String) -> URL {
            if let o = pageURLOverride { return o.deletingLastPathComponent().appendingPathComponent(page) }
            return URL(string: "https://\(client).askruna.ai/app/\(page)")!
        }
    }

    /// An order the shopper just placed in your app, for `orderPlaced`.
    public struct Order {
        public var orderNumber: String
        /// What the shopper pays for the products, before delivery fee and tip.
        public var total: Double
        public var currency = "USD"
        public var lines: [OrderLine]

        /// - Parameters:
        ///   - orderNumber: your order number, e.g. "QD237954" (an order is reported once per number)
        ///   - total: what the shopper pays for the products, before delivery fee and tip
        ///   - lines: one per product: your product id, store id, unit price and quantity
        public init(orderNumber: String, total: Double, lines: [OrderLine]) {
            self.orderNumber = orderNumber
            self.total = total
            self.lines = lines
        }
    }

    /// One line of an `Order`.
    public struct OrderLine {
        public let pid: String
        public let sid: String
        public let price: Double
        public let quantity: Int
        public init(pid: String, sid: String, price: Double, quantity: Int) {
            self.pid = pid
            self.sid = sid
            self.price = price
            self.quantity = quantity
        }
    }

    /// A product the chat wants in the cart. Ids are Quicklly's numeric ids, as strings.
    public struct Product {
        public let pid: String
        public let sid: String
        public let title: String
        public let price: Double?
        public let image: String
        public let storeName: String
        public let storeSlug: String
        public let url: URL?
        public let fastDelivery: Bool
        /// The store's terms for the shopper's ZIP, from Quicklly's own store list. nil = unknown.
        public let minOrder: Double?
        public let deliveryFee: Double?
        /// Their delivery label for the store, e.g. "Delivery In 3 hours or less" or "5:30 PM - 8:30 PM".
        public let deliveryRange: String
        public let instantDelivery: Bool
        public let storeImage: String
        /// The whole message payload, for anything not listed above.
        public let raw: [String: Any]

        init(_ p: [String: Any]) {
            raw = p
            pid = p["pid"] as? String ?? String(describing: p["pid"] ?? "")
            sid = p["sid"] as? String ?? String(describing: p["sid"] ?? "")
            title = p["title"] as? String ?? ""
            price = (p["price"] as? NSNumber)?.doubleValue
            image = p["image"] as? String ?? ""
            storeName = p["storeName"] as? String ?? ""
            storeSlug = p["storeSlug"] as? String ?? ""
            url = (p["url"] as? String).flatMap { URL(string: $0) }
            fastDelivery = (p["fastdelivery"] as? String) == "1"
            minOrder = (p["minOrder"] as? NSNumber)?.doubleValue
            deliveryFee = (p["deliveryFee"] as? NSNumber)?.doubleValue
            deliveryRange = p["deliveryRange"] as? String ?? ""
            instantDelivery = p["instantDelivery"] as? Bool ?? false
            storeImage = p["storeImage"] as? String ?? ""
        }
    }

    /// One line of the app's cart.
    public struct CartItem {
        public let pid: String
        public let sid: String
        public let quantity: Int

        public init(pid: String, sid: String, quantity: Int) {
            self.pid = pid
            self.sid = sid
            self.quantity = quantity
        }
    }

    /// Open the chat: pushed when `from` is in a navigation controller, otherwise presented full screen.
    @discardableResult
    public static func open(from: UIViewController, options: Options, delegate: RunaChatDelegate) -> RunaChatViewController {
        let chat = RunaChatViewController(options: options, delegate: delegate)
        if let nav = from.navigationController {
            nav.pushViewController(chat, animated: true)
        } else {
            chat.modalPresentationStyle = .fullScreen
            from.present(chat, animated: true)
        }
        return chat
    }

    /// Call after the cart changes outside the chat (cart screen, product screen) while the chat may be open.
    public static func notifyCartChanged() {
        RunaChatViewController.current?.sendCart()
        RunaSearchView.all.forEach { $0.sendCart() }
        RunaProductView.all.forEach { $0.sendCart() }
    }

    /// The shopper changed the delivery address. An open chat re-scopes to it and starts a new conversation.
    public static func updateAddress(zip: String, address: String?, city: String?, state: String?) {
        RunaChatViewController.current?.sendAddress(zip: zip, address: address, city: city, state: state)
        RunaSearchView.all.forEach { $0.sendAddress(zip: zip, address: address, city: city, state: state) }
        RunaProductView.all.forEach { $0.sendAddress(zip: zip, address: address, city: city, state: state) }
    }

    /// Report an order right after checkout, so the products Ask Quicklly brought to it are counted as its sales
    /// (what it added or opened in the 7 days before, the same rule as on your website). Call it once per order,
    /// on the main thread, with the same client key and userId as the chat; it returns at once and works in the
    /// background (a few seconds, no UI). The optional completion hears whether it was reported, and why not.
    public static func orderPlaced(options: Options, order: Order, completion: ((_ reported: Bool, _ reason: String?) -> Void)? = nil) {
        OrderReporter(options: options, order: order, completion: completion).start()
    }

    /// Every page gets who and where the shopper is and which app build asks.
    static func shopperQuery(_ o: Options) -> [URLQueryItem] {
        var q: [URLQueryItem] = []
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
        if o.debug { put("debug", "1") }
        return q
    }

    static func url(_ base: URL, _ items: [URLQueryItem]) -> URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        c.queryItems = (c.queryItems ?? []) + items
        // "+" is a space to the page's URLSearchParams: keep it literal
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url ?? base
    }

    static func originOf(_ u: URL) -> String { "\(u.scheme ?? "https")://\(u.host ?? "")" }

    static func json(_ type: String, _ payload: [String: Any], requestId: String? = nil) -> String? {
        var msg: [String: Any] = ["type": type, "payload": payload, "v": bridgeVersion]
        if let r = requestId { msg["requestId"] = r }
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let s = String(data: data, encoding: .utf8),
              let lit = try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed) else { return nil }
        return String(data: lit, encoding: .utf8)
    }

    static func parse(_ body: Any) -> (type: String, payload: [String: Any], requestId: String?)? {
        var msg: [String: Any]?
        if let s = body as? String, let data = s.data(using: .utf8) {
            msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } else {
            msg = body as? [String: Any]
        }
        guard let m = msg, let type = m["type"] as? String else { return nil }
        return (type, m["payload"] as? [String: Any] ?? [:], m["requestId"] as? String)
    }

    static let bridgeVersion = "1.2"   // 1.2: the product view (product, viewport)

    /// The fallback when the app does not handle a link itself: an in-app browser sheet (SFSafariViewController,
    /// with its own Done button), so the shopper never leaves the app. Anything that is not http(s) goes to the system.
    static func openInApp(_ url: URL, from vc: UIViewController?) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let vc = vc else {
            UIApplication.shared.open(url)
            return
        }
        let sheet = SFSafariViewController(url: url)
        sheet.modalPresentationStyle = .pageSheet
        (vc.presentedViewController ?? vc).present(sheet, animated: true)
    }

    /// Optional: call once early (e.g. when the grocery tab opens) so the first open of the chat is faster.
    public static func warmUp() {
        _ = warmWebView
    }

    private static let warmWebView: WKWebView = {
        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.loadHTMLString("", baseURL: nil)
        return wv
    }()
}

/// What the app does for the chat. Only `setQuantity` and `runaChatCart` are required.
public protocol RunaChatDelegate: AnyObject {
    /// Set this product's quantity in the app's cart. Absolute: 0 removes the line.
    func runaChat(_ chat: RunaChatViewController, setQuantity quantity: Int, of product: RunaChat.Product)

    /// What is in the app's cart right now.
    func runaChatCart(_ chat: RunaChatViewController) -> [RunaChat.CartItem]

    /// The shopper tapped a product card. Open your product screen and return true;
    /// return false to open the product's web page in the browser instead.
    func runaChat(_ chat: RunaChatViewController, openProduct product: RunaChat.Product) -> Bool

    /// An outside link (a recipe, a web page). Return false to open it in Safari.
    func runaChat(_ chat: RunaChatViewController, openLink url: URL) -> Bool

    /// The chat screen was closed (the ✕, swipe back, or your own pop/dismiss).
    func runaChatDidClose(_ chat: RunaChatViewController)

    /// Every message from the chat page, after the library handled it — e.g. for analytics ("setQty", "track"…).
    func runaChat(_ chat: RunaChatViewController, didReceive type: String, payload: [String: Any])
}

public extension RunaChatDelegate {
    func runaChat(_ chat: RunaChatViewController, openProduct product: RunaChat.Product) -> Bool { false }
    func runaChat(_ chat: RunaChatViewController, openLink url: URL) -> Bool { false }
    func runaChatDidClose(_ chat: RunaChatViewController) {}
    func runaChat(_ chat: RunaChatViewController, didReceive type: String, payload: [String: Any]) {}
}
