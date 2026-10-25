# Runa Chat for iOS

The Runa AI shopping assistant ("Ask Quicklly") in your iOS app: the chat as a screen, Ask
Quicklly in search as a view above your search results, and one call after checkout so orders
count what Ask Quicklly sold. One package, three delegate methods to connect it to your cart and
your product screen.

The chat itself is hosted and updated by Runa and shown full screen by the library's own view
controller, so improvements reach your users without app releases. The app provides only what the
app alone can do: who and where the shopper is, adding to the cart, what is in the cart, and
opening your product screen.

- Swift, UIKit + WebKit + SafariServices only, no other dependencies
- iOS 13+, tested on iOS 16.4
- Swift Package Manager or CocoaPods

## Install

**Swift Package Manager** — Xcode → File → Add Package Dependencies → paste
`https://github.com/askruna/runa-chat-ios` (or add it to your `Package.swift`):

```swift
.package(url: "https://github.com/askruna/runa-chat-ios", from: "1.1.1")
```

**CocoaPods**

```ruby
pod 'RunaChat', :git => 'https://github.com/askruna/runa-chat-ios.git', :tag => '1.1.1'
```

## Use

```swift
import RunaChat

var options = RunaChat.Options(client: "quicklly",                      // your client key from Runa
                               zip: "60610")                            // the delivery ZIP (required)
options.userId = "12345"                                                // customer id, or a stable id for guests
options.address = "1140 N Wells St, Chicago"; options.city = "Chicago"; options.state = "IL"
RunaChat.open(from: self, options: options, delegate: self)             // pushed, or presented full screen

extension MyViewController: RunaChatDelegate {
    func runaChat(_ chat: RunaChatViewController, setQuantity quantity: Int, of product: RunaChat.Product) {
        // your add-to-cart: product.pid (product id), product.sid (store id), quantity (absolute; 0 = remove)
    }
    func runaChatCart(_ chat: RunaChatViewController) -> [RunaChat.CartItem] {
        // what is in your cart now: one CartItem(pid:sid:quantity:) per line
    }
    func runaChat(_ chat: RunaChatViewController, openProduct product: RunaChat.Product) -> Bool {
        // open your product screen for product.pid / product.sid, then return true
        return true
    }
}
```

**Required** — three delegate methods:

| method | when | what you do |
| --- | --- | --- |
| `runaChat(_:setQuantity:of:)` | the shopper tapped ADD or changed a quantity | set that product's quantity in your cart (`pid`, `sid`; absolute, `0` removes) |
| `runaChatCart(_:)` | the chat needs to draw its steppers | return your cart: one `CartItem(pid:sid:quantity:)` per line |
| `runaChat(_:openProduct:) -> Bool` | the shopper tapped a product card | open your own product screen for that `pid` / `sid` and return `true` (left out, the product's web page opens in an in-app browser sheet — a safety net only) |

**Optional** — leave them out and the defaults apply:

| method | when | default |
| --- | --- | --- |
| `runaChat(_:openLink:) -> Bool` | an outside link — rare in the chat (a recipe page, a size guide) | opens in an in-app browser sheet (`SFSafariViewController`, with a Done button); return `true` to show it your own way |
| `runaChatDidClose(_:)` | the chat screen closed | — |
| `runaChat(_:didReceive:payload:)` | every message from the page, e.g. for analytics | — |

Two more calls you may need:

- `RunaChat.notifyCartChanged()` — call after the cart changes outside the chat (your cart or
  product screen) while the chat may be open; the chat updates its quantities.
- `RunaChat.updateAddress(zip:address:city:state:)` — the shopper changed the delivery
  address; an open chat re-scopes to it and starts a new conversation.

Optional: `RunaChat.warmUp()` early (e.g. when the grocery tab opens) makes the first open of the
chat faster. `options.question` opens the chat with a question already sent (deep links, "ask
about this product"); `options.debug = true` prints every message. You can also create
`RunaChatViewController(options:delegate:)` yourself and push or present it where you like.

`setQuantity` is called with everything the chat knows about the product (`title`, `price`,
`image`, `storeName`, `storeImage`, `url`, `fastDelivery`, and `raw` with the whole payload) and the
store's terms for the shopper's ZIP (`minOrder`, `deliveryFee`, `deliveryRange`, `instantDelivery`),
so a new store row can be drawn without a lookup. Prices, images and terms come from Runa's index
(refreshed nightly) and are for display: add the line through your usual add-to-cart call with
`pid` and `sid`, so your server prices it as it always does.

Everything runs on the main thread. Keyboard, safe areas, the navigation bar, outside links,
the loading screen (the Ask Quicklly mark) and the error state are the library's job — see https://quicklly.askruna.ai/app/docs/.

## Ask Quicklly in search (1.1.0)

A view for your search screen, under the search field and above your own "N products found":
it shows the products the shopper meant (milk when "cow milk" lists butter first), a line about
them and follow-up chips. A chip opens the chat screen with that question.

```swift
let answer = RunaSearchView(options: options, delegate: self)   // the same Options as the chat
answer.chatDelegate = self                                       // your RunaChatDelegate: a chip opens the chat
resultsStack.insertArrangedSubview(answer, at: 0)                // above your results, full width

// on every search the shopper makes, with what your own results show:
answer.search("cow milk", resultCount: 76, firstTitles: titles)  // titles: your first product names (≤ 10)
answer.clear()                                                   // the search field was cleared

extension SearchViewController: RunaSearchViewDelegate {
    func runaSearch(_ view: RunaSearchView, setQuantity quantity: Int, of product: RunaChat.Product) { /* your add-to-cart */ }
    func runaSearchCart(_ view: RunaSearchView) -> [RunaChat.CartItem] { /* your cart */ }
    func runaSearch(_ view: RunaSearchView, openProduct product: RunaChat.Product) -> Bool { /* your product screen */ return true }
}
```

- The view sizes itself through `intrinsicContentSize` (Auto Layout, stack views): a one-line
  working state, then the answer (about 380 pt); with nothing to show it hides itself. For a table
  header or manual layout, `runaSearch(_:didChangeHeight:)` tells you when it changes.
- `resultCount` and `firstTitles` are optional, but they let Ask Quicklly see what your results
  already show and answer the gap instead of repeating them.
- A new search reuses the view (no reload). Its product row scrolls sideways inside the view.
- Optional delegate methods: `runaSearch(_:openChatWith:) -> Bool` (open the chat yourself; by
  default the library opens it from the view controller the view is in, with `chatDelegate`),
  `runaSearch(_:openLink:) -> Bool`, `runaSearch(_:didReceive:payload:)`.
- `notifyCartChanged()` and `updateAddress(…)` reach the search view too.

## Orders (1.1.0)

After your checkout succeeds, report the order. The library hands it to Runa's order page in a
web view the shopper never sees; it counts the products the shopper added from Ask Quicklly or
opened from it in the last 30 days, the same rule as on quicklly.com, and lets go.

```swift
let order = RunaChat.Order(orderNumber: "QD237898", total: 54.32, lines: [   // your order number, the total paid
    RunaChat.OrderLine(pid: "706824", sid: "112333", price: 7.59, quantity: 2),   // unit price paid
    RunaChat.OrderLine(pid: "905", sid: "112333", price: 15.45, quantity: 1),
])
RunaChat.orderPlaced(options: options, order: order) { reported, reason in }   // completion optional
```

Send only the order number, the amounts and the lines: no names, addresses or payment details.
An order is counted once (the same order number again is ignored).

## Sample app

`Example/` is a small app standing in for a retailer's app: a cart, a product screen, an
"Ask Quicklly" button, a search screen with Ask Quicklly in search (`SearchViewController`) and a
"Place order" button. Everything a retailer writes is in `MainViewController` (`options()`,
`openChat`, `placeOrder`) and `SearchViewController`.

```
cd Example && xcodegen generate        # https://github.com/yonaskolb/XcodeGen
open RunaChatSample.xcodeproj
```

Launched with the `--self-test` argument it opens the chat and runs the checks in
`SelfTest.swift` against the real chat screen; `--self-test-search` does the same for the search
view and `orderPlaced` (`SearchSelfTest.swift`). The results are printed to the console:
`tests/run-simulator.sh` and `MODE=search tests/run-simulator.sh` run them on a simulator.

## Documentation

The integration guide, the test checklist and a live demo: https://quicklly.askruna.ai/app/docs/.
The chat and the search answers are hosted and updated by Runa, so improvements reach your users
without an app release; the library only needs the three delegate methods above.

## Versions

- **1.1.1** — the chat's loading screen: the Ask Quicklly mark (the search answer's sparkle in a spinning ring) instead of a plain spinner, until the chat has drawn.
- **1.1.0** — `RunaSearchView` (Ask Quicklly in search), `RunaChat.orderPlaced`.
- **1.0.3** — in-app browser fallback for outside links; `openProduct` required.

## License

MIT
