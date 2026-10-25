import UIKit
import RunaChat

/// Stands in for the app's own cart (in Quicklly's app: its cart store).
final class SampleCart {
    struct Line { let pid: String; let sid: String; let title: String; let price: Double?; var qty: Int }
    static var lines: [Line] = []

    static func set(pid: String, sid: String, title: String, price: Double?, qty: Int) {
        lines.removeAll { $0.pid == pid }
        if qty > 0 { lines.append(Line(pid: pid, sid: sid, title: title, price: price, qty: qty)) }
    }
    static func qty(_ pid: String) -> Int { lines.first { $0.pid == pid }?.qty ?? 0 }
    static func bumpFirst(_ delta: Int) {
        guard let l = lines.first else { return }
        set(pid: l.pid, sid: l.sid, title: l.title, price: l.price, qty: l.qty + delta)
    }
    static var count: Int { lines.reduce(0) { $0 + $1.qty } }
    static var snapshot: [RunaChat.CartItem] { lines.map { RunaChat.CartItem(pid: $0.pid, sid: $0.sid, quantity: $0.qty) } }
}

/// A stand-in for the Quicklly app: a cart, a product screen, a search screen with Ask Quicklly in search
/// (SearchViewController), an "Ask Quicklly" button and a checkout. Everything a retailer writes is `options()`,
/// `openChat`, `placeOrder` and the delegate extensions.
final class MainViewController: UIViewController {
    private let cartLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Quicklly (sample app)"
        view.backgroundColor = .white
        RunaChat.warmUp()

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
        cartLabel.numberOfLines = 0
        stack.addArrangedSubview(cartLabel)
        let ask = UIButton(type: .system)
        ask.setTitle("Ask Quicklly", for: .normal)
        ask.titleLabel?.font = .boldSystemFont(ofSize: 20)
        ask.addTarget(self, action: #selector(askTapped), for: .touchUpInside)
        stack.addArrangedSubview(ask)
        let deep = UIButton(type: .system)
        deep.setTitle("Ask about paneer (deep link)", for: .normal)
        deep.addTarget(self, action: #selector(deepTapped), for: .touchUpInside)
        stack.addArrangedSubview(deep)
        let search = UIButton(type: .system)
        search.setTitle("Search", for: .normal)
        search.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        stack.addArrangedSubview(search)
        let order = UIButton(type: .system)
        order.setTitle("Place order", for: .normal)
        order.addTarget(self, action: #selector(orderTapped), for: .touchUpInside)
        stack.addArrangedSubview(order)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    func refresh() {
        cartLabel.text = "Cart: \(SampleCart.count) item(s)" + SampleCart.lines.map { "\n  \($0.qty) × \($0.title) (pid \($0.pid))" }.joined()
    }

    @objc private func askTapped() { openChat(question: nil) }
    @objc private func deepTapped() { openChat(question: "What can I cook tonight with paneer?") }
    @objc private func searchTapped() { openSearch(query: nil) }
    @objc private func orderTapped() { placeOrder(completion: nil) }

    func openSearch(query: String?) {
        navigationController?.pushViewController(SearchViewController(query: query, chat: self), animated: true)
    }

    /// Runa's own tests: the folder the pages are served from (`--page-base http://…/`). nil = the live pages.
    static var pageBase: URL?

    // ─── This is the whole integration ────────────────────────────────────────────────────

    /// Who and where the shopper is — the same for the chat, the search view and the order report.
    static func options() -> RunaChat.Options {
        var options = RunaChat.Options(client: "quicklly", zip: "60610")   // the client key from Runa
        options.userId = "sample-user-1"
        options.address = "1140 N Wells St, Chicago"
        options.city = "Chicago"
        options.state = "IL"
        options.debug = true
        if let base = pageBase { options.pageURLOverride = base.appendingPathComponent("chat-app.html") }   // Runa's tests only
        return options
    }

    func openChat(question: String?) {
        var options = Self.options()
        options.question = question
        RunaChat.open(from: self, options: options, delegate: self)
    }

    /// After your checkout succeeds: the order number, what was paid for the products, and the lines.
    func placeOrder(completion: ((Bool, String?) -> Void)?) {
        let lines = SampleCart.lines.map { RunaChat.OrderLine(pid: $0.pid, sid: $0.sid, price: $0.price ?? 0, quantity: $0.qty) }
        let total = (SampleCart.lines.reduce(0) { $0 + ($1.price ?? 0) * Double($1.qty) } * 100).rounded() / 100
        let order = RunaChat.Order(orderNumber: "SAMPLE-\(Int(Date().timeIntervalSince1970))", total: total, lines: lines)
        RunaChat.orderPlaced(options: Self.options(), order: order) { reported, reason in
            NSLog("[Sample] order reported=%d reason=%@ lines=%d", reported ? 1 : 0, reason ?? "nil", lines.count)
            completion?(reported, reason)
        }
        NSLog("[Sample] placeOrder %d line(s), total %.2f", lines.count, total)
        SampleCart.lines = []
        refresh()
    }
}

extension MainViewController: RunaChatDelegate {
    func runaChat(_ chat: RunaChatViewController, setQuantity quantity: Int, of product: RunaChat.Product) {
        NSLog("[Sample] setQuantity pid=%@ sid=%@ qty=%d title=%@ minOrder=%@ deliveryFee=%@ range=%@ instant=%d", product.pid, product.sid, quantity, product.title,
              product.minOrder.map { String($0) } ?? "nil", product.deliveryFee.map { String($0) } ?? "nil", product.deliveryRange, product.instantDelivery ? 1 : 0)
        SampleCart.set(pid: product.pid, sid: product.sid, title: product.title, price: product.price, qty: quantity)   // your add-to-cart
    }

    func runaChatCart(_ chat: RunaChatViewController) -> [RunaChat.CartItem] {
        SampleCart.snapshot                                                                                            // your cart
    }

    func runaChat(_ chat: RunaChatViewController, openProduct product: RunaChat.Product) -> Bool {
        NSLog("[Sample] openProduct pid=%@ sid=%@", product.pid, product.sid)
        chat.navigationController?.pushViewController(ProductViewController(product: product), animated: true)
        return true
    }

    func runaChat(_ chat: RunaChatViewController, openLink url: URL) -> Bool {
        NSLog("[Sample] openLink %@", url.absoluteString)
        if SelfTest.enabled && url.path.hasSuffix("runa-fallback-test") { return false }   // test only: let the library's in-app sheet show
        return true      // handled (a real app would open an in-app browser)
    }

    func runaChatDidClose(_ chat: RunaChatViewController) {
        NSLog("[Sample] chat closed")
    }

    func runaChat(_ chat: RunaChatViewController, didReceive type: String, payload: [String: Any]) {
        SelfTest.handle(type: type, payload: payload, chat: chat)   // test-only; a real app ignores or logs these
        SearchSelfTest.chatMessage(type: type, payload: payload, chat: chat)   // test-only
    }
}

/// Stands in for the app's product screen: what openProduct lands on.
final class ProductViewController: UIViewController {
    private let product: RunaChat.Product
    init(product: RunaChat.Product) { self.product = product; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Product"
        view.backgroundColor = .white
        let label = UILabel()
        label.numberOfLines = 0
        label.text = "\(product.title)\npid \(product.pid) · store \(product.sid)"
        let plus = UIButton(type: .system)
        plus.setTitle("+1 in cart", for: .normal)
        plus.addTarget(self, action: #selector(plusTapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, plus])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    @objc func plusTapped() {
        SampleCart.set(pid: product.pid, sid: product.sid, title: product.title, price: product.price, qty: SampleCart.qty(product.pid) + 1)
        NSLog("[Sample] product screen +1 → qty %d", SampleCart.qty(product.pid))
        RunaChat.notifyCartChanged()
    }
}
