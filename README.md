# Runa Chat for iOS

The Runa AI shopping assistant ("Ask Quicklly") as a screen in your iOS app. One package, one
call to open it, three delegate methods to connect it to your cart and your product screen.

The chat itself is hosted and updated by Runa and shown full screen by the library's own view
controller, so improvements reach your users without app releases. The app provides only what the
app alone can do: who and where the shopper is, adding to the cart, what is in the cart, and
opening your product screen.

- Swift, UIKit + WebKit only, no other dependencies
- iOS 13+, tested on iOS 16.4
- Swift Package Manager or CocoaPods

## Install

**Swift Package Manager** — Xcode → File → Add Package Dependencies → paste
`https://github.com/askruna/runa-chat-ios` (or add it to your `Package.swift`):

```swift
.package(url: "https://github.com/askruna/runa-chat-ios", from: "1.0.3")
```

**CocoaPods**

```ruby
pod 'RunaChat', :git => 'https://github.com/askruna/runa-chat-ios.git', :tag => '1.0.3'
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
loading and error states are the library's job — see https://quicklly.askruna.ai/app/docs/.

## Sample app

`Example/` is a small app standing in for a retailer's app: a cart, a product screen and an
"Ask Quicklly" button. Everything a retailer writes is in `MainViewController`.

```
cd Example && xcodegen generate        # https://github.com/yonaskolb/XcodeGen
open RunaChatSample.xcodeproj
```

Launched with the `--self-test` argument it opens the chat and runs the checks in
`SelfTest.swift` against the real chat screen; the results are printed to the console
(`tests/run-simulator.sh` does this on a simulator).

## Documentation

The integration guide, the test checklist and a live demo: https://quicklly.askruna.ai/app/docs/.
The chat itself is hosted and updated by Runa, so improvements reach your users without an app
release; the library only needs the three delegate methods above.

## License

MIT
