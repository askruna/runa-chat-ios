# Runa Chat for iOS

The Runa AI shopping assistant ("Ask Quicklly") as a screen in your iOS app. One package, one
call to open it, two delegate methods to connect it to your cart.

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
.package(url: "https://github.com/askruna/runa-chat-ios", from: "1.0.2")
```

**CocoaPods**

```ruby
pod 'RunaChat', '~> 1.0'
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
}
```

That is the whole integration. Optional delegate methods:

| method | when | default |
| --- | --- | --- |
| `runaChat(_:openProduct:) -> Bool` | the shopper tapped a product card | opens the product's web page in Safari; return `true` after showing your own product screen |
| `runaChat(_:openLink:) -> Bool` | an outside link (a recipe, a web page) | opens in Safari |
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
so a new store row can be created without a lookup. The recommended
pattern is to look the product up by `pid` + `sid` with the same API your product screen uses
and add it through your normal add-to-cart path, so prices, tax and inventory always come from
your own system.

Everything runs on the main thread. The library handles the keyboard, safe areas and the notch,
hides the navigation bar on its screen (the page has its own header; swipe-back still works),
outside links, loading and error states, and keeps the web view on the chat page only.

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
release; the library only needs the two delegate methods above.

## License

MIT
