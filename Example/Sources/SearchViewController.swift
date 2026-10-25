import UIKit
import RunaChat

/// Stands in for the app's search screen: the search field, Ask Quicklly in search right under it, then the app's
/// own "N products found" and results. The integration is the RunaSearchView lines marked below.
final class SearchViewController: UIViewController, UITextFieldDelegate {
    private let field = UITextField()
    private(set) var answer: RunaSearchView!
    let foundLabel = UILabel()
    private let resultsStack = UIStackView()
    private let initialQuery: String?
    weak var chat: RunaChatDelegate?

    init(query: String?, chat: RunaChatDelegate) {
        self.initialQuery = query
        self.chat = chat
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search"
        view.backgroundColor = .white

        field.borderStyle = .roundedRect
        field.placeholder = "Search"
        field.returnKeyType = .search
        field.accessibilityIdentifier = "search field"
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(field)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        // ─── Ask Quicklly in search: under the search field, above your results ─────────────
        answer = RunaSearchView(options: MainViewController.options(), delegate: self)
        answer.chatDelegate = chat                      // a chip opens the chat with this delegate
        stack.addArrangedSubview(answer)                // full width; it sizes itself to its answer

        foundLabel.font = .systemFont(ofSize: 16)
        let foundWrap = UIView()
        foundLabel.translatesAutoresizingMaskIntoConstraints = false
        foundWrap.addSubview(foundLabel)
        NSLayoutConstraint.activate([
            foundLabel.topAnchor.constraint(equalTo: foundWrap.topAnchor, constant: 10),
            foundLabel.bottomAnchor.constraint(equalTo: foundWrap.bottomAnchor, constant: -6),
            foundLabel.leadingAnchor.constraint(equalTo: foundWrap.leadingAnchor, constant: 14),
            foundLabel.trailingAnchor.constraint(equalTo: foundWrap.trailingAnchor, constant: -14),
        ])
        stack.addArrangedSubview(foundWrap)
        resultsStack.axis = .vertical
        resultsStack.spacing = 10
        resultsStack.isLayoutMarginsRelativeArrangement = true
        resultsStack.layoutMargins = UIEdgeInsets(top: 4, left: 14, bottom: 14, right: 14)
        stack.addArrangedSubview(resultsStack)

        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])

        if let q = initialQuery { field.text = q; runSearch() }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { runSearch(); return true }

    func runSearch(_ text: String? = nil) {
        if let t = text { field.text = t }
        let q = (field.text ?? "").trimmingCharacters(in: .whitespaces)
        let titles = Self.appResults(q)
        foundLabel.text = "\(titles.count) products found for item '\(q)'"
        resultsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        titles.forEach { t in let l = UILabel(); l.text = "• " + t; l.numberOfLines = 0; resultsStack.addArrangedSubview(l) }
        NSLog("[Sample] app search '%@' → %d results", q, titles.count)
        answer.search(q, resultCount: titles.count, firstTitles: Array(titles.prefix(10)))   // ← on every search
    }

    /// Your own search results (here: canned, like the Quicklly app's own results for these searches).
    static func appResults(_ q: String) -> [String] {
        let s = q.lowercased()
        if s.contains("milk") { return ["Amul Water Buffalo And Cow Milk Butter 3.5OZ", "Amul Water Buffalo Cow Milk Butter 500GM", "Milk-Organic Valley 2% Reduced Fat 1GALLON", "Amul Butter Water Buffalo And Cow Milk 17.64OZ"] }
        if s.contains("rice") { return ["Royal Basmati Rice 10 lb", "Deep Basmati Rice 10 lb", "Tilda Pure Basmati 5 lb"] }
        return []
    }
}

extension SearchViewController: RunaSearchViewDelegate {
    func runaSearch(_ view: RunaSearchView, setQuantity quantity: Int, of product: RunaChat.Product) {
        NSLog("[Sample] search setQuantity pid=%@ sid=%@ qty=%d title=%@", product.pid, product.sid, quantity, product.title)
        SampleCart.set(pid: product.pid, sid: product.sid, title: product.title, price: product.price, qty: quantity)   // your add-to-cart
    }

    func runaSearchCart(_ view: RunaSearchView) -> [RunaChat.CartItem] {
        SampleCart.snapshot                                                                                            // your cart
    }

    func runaSearch(_ view: RunaSearchView, openProduct product: RunaChat.Product) -> Bool {
        NSLog("[Sample] search openProduct pid=%@ sid=%@", product.pid, product.sid)
        navigationController?.pushViewController(ProductViewController(product: product), animated: true)
        return true
    }

    func runaSearch(_ view: RunaSearchView, didChangeHeight height: CGFloat) {
        NSLog("[Sample] search view height %.0f", height)
    }

    func runaSearch(_ view: RunaSearchView, didReceive type: String, payload: [String: Any]) {
        SearchSelfTest.handle(type: type, payload: payload, screen: self)   // test-only
    }
}
