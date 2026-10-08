import UIKit
import WebKit

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
        /// Runa's own use: a test page instead of the client's live page.
        public var pageURLOverride: URL?

        public init(client: String, zip: String) {
            self.client = client.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.zip = zip
            assert(self.client.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil, "RunaChat: the client key is the one Runa gave you, e.g. \"quicklly\"")
        }

        /// The chat page for this client. Runa hosts it; the key is all the app needs to know.
        var pageURL: URL {
            pageURLOverride ?? URL(string: "https://\(client).askruna.ai/app/chat-app.html")!
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
    }

    /// The shopper changed the delivery address. An open chat re-scopes to it and starts a new conversation.
    public static func updateAddress(zip: String, address: String?, city: String?, state: String?) {
        RunaChatViewController.current?.sendAddress(zip: zip, address: address, city: city, state: state)
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
