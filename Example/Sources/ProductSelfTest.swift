import UIKit
import WebKit
import RunaChat

/// Test only (`--self-test-product` launch argument): the product screen opens for okra (store 113189); once the
/// product view's page says `ready`, a script inside its real WKWebView walks a shopper's path — the bundle, the Ask
/// Quicklly line waiting below the fold, the app scrolling it into the middle of the screen (it types once), "Add all",
/// a product tap, the line into the chat — and the app checks its side (the view's height, the delegate calls, the
/// product screen, the chat's question and entry). Every check is logged as "[SelfTest] PASS/FAIL …", the end as
/// "[SelfTest] DONE pass=… fail=…".
enum ProductSelfTest {
    static var enabled = false
    static var setQuantityCalls = 0
    private static var started = false
    private static var pass = 0, fail = 0

    static func step(_ line: String) {
        if line.hasPrefix("PASS") { pass += 1 } else if line.hasPrefix("FAIL") { fail += 1 }
        NSLog("[SelfTest] %@", line)
    }
    static func check(_ ok: Bool, _ label: String) { step((ok ? "PASS " : "FAIL ") + label) }

    static func handle(type: String, payload: [String: Any], screen: ProductViewController) {
        guard enabled else { return }
        switch type {
        case "ready":
            guard !started else { return }
            started = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { webView(in: screen.bundle)?.evaluateJavaScript(script, completionHandler: nil) }
        case "selfTestStep":
            step(payload["line"] as? String ?? "")
        case "selfTestHeight":
            let css = CGFloat((payload["css"] as? NSNumber)?.doubleValue ?? 0)
            let h = screen.bundle.height
            check(h > 150 && abs(h - css.rounded(.up)) <= 2, String(format: "native view sized to the bundle: %.0f pt (page %.0f css px)", h, css))
        case "selfTestScroll":
            // the shopper scrolls the product screen until the Ask Quicklly line is in the middle of the screen
            screen.view.layoutIfNeeded()
            let lineY = screen.bundle.convert(screen.bundle.bounds, to: screen.scroll).maxY - 50
            let target = max(0, lineY - screen.scroll.bounds.height * 0.5)
            screen.scroll.setContentOffset(CGPoint(x: 0, y: target), animated: true)
        case "selfTestShot":
            NSLog("[SelfTest] SHOT %@", payload["name"] as? String ?? "")
        case "selfTestAddAll":
            let n = (payload["n"] as? NSNumber)?.intValue ?? -1
            check(setQuantityCalls == n, "\"Add all\" → \(setQuantityCalls) delegate setQuantity calls for \(n) products")
        case "selfTestProductCheck":
            let top = screen.navigationController?.topViewController
            check(top is ProductViewController && top !== screen, "product tap → delegate openProduct → the app's product screen")
            screen.navigationController?.popToViewController(screen, animated: false)
        case "selfTestChatCheck":
            // the line opened the chat (library default, chatDelegate): its question and the product-page credit
            guard let nav = screen.navigationController, let chat = nav.topViewController as? RunaChatViewController, let wv = webView(in: chat.view) else {
                check(false, "the Ask Quicklly line → the chat screen"); NSLog("[SelfTest] DONE pass=%d fail=%d", pass, fail); return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                wv.evaluateJavaScript("JSON.stringify(Object.fromEntries(new URLSearchParams(location.search)))") { r, _ in
                    let q = (try? JSONSerialization.jsonObject(with: Data(((r as? String) ?? "{}").utf8))) as? [String: String] ?? [:]
                    check(q["q"] == "Plan a meal with Okra (bhindi) 1 Lbs" && q["entry"] == "product_page", "the Ask Quicklly line → the chat screen q=\"\(q["q"] ?? "")\" entry=\(q["entry"] ?? "")")
                    nav.popToViewController(screen, animated: false)
                    NSLog("[SelfTest] DONE pass=%d fail=%d", pass, fail)
                }
            }
        default:
            break
        }
    }

    private static func webView(in view: UIView) -> WKWebView? {
        if let wv = view as? WKWebView { return wv }
        for sub in view.subviews { if let wv = webView(in: sub) { return wv } }
        return nil
    }

    static let script = """
    (function () {
      if (window.__runaSelfTest) return; window.__runaSelfTest = true;
      function post(type, payload) { window.webkit.messageHandlers.runa.postMessage(JSON.stringify({ type: type, payload: payload || {} })); }
      function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
      function $(s) { return document.querySelector(s); }
      async function waitFor(fn, ms) { var end = Date.now() + ms; while (Date.now() < end) { try { var v = fn(); if (v) return v; } catch (e) {} await sleep(250); } return null; }
      function ok(c, label) { post('selfTestStep', { line: (c ? 'PASS ' : 'FAIL ') + label }); }
      function height() { return document.getElementById('root_quicklly_chat').getBoundingClientRect().height; }
      async function shot(name) { await sleep(800); post('selfTestShot', { name: name }); await sleep(2500); }
      (async function () {
        try {
          var q = Object.fromEntries(new URLSearchParams(location.search));
          ok(q.pid === '1013592' && q.sid === '113189' && q.title === 'Okra (bhindi) 1 Lbs' && q.preview === '1' && q.zip === '60610' && q.platform === 'ios',
            'page URL from show(): pid=' + q.pid + ' sid=' + q.sid + ' title=' + q.title + ' preview=' + q.preview + ' platform=' + q.platform);
          ok(!!(await waitFor(function () { return $('.runa-pb .runa-c__pcard'); }, 60000)), 'the bundle shows products');
          await sleep(800);
          post('selfTestHeight', { css: height() });
          var heading = $('.runa-pb .runa-pdp__title').textContent.trim();
          var n = document.querySelectorAll('.runa-pb .runa-c__pcard').length;
          ok(heading === 'Recipes' && n >= 2, 'bundle: "' + heading + '" with ' + n + ' products');
          var line = $('.runa-pb__line');
          ok(line && line.dataset.done === '0' && !localStorage.getItem('runaAskLineTyped'), 'the line below the fold: nothing typed yet');
          post('selfTestScroll');
          ok(!!(await waitFor(function () { return $('.runa-pb__line').dataset.done === '1'; }, 30000)) && !!localStorage.getItem('runaAskLineTyped'),
            'scrolled into the middle of the screen → the line typed once and settled on "' + $('.runa-pb__line-q').textContent.replace(/\\u200b/g, '') + '"');
          await shot('product-bundle');

          $('.runa-pb__all').click();
          ok(!!(await waitFor(function () { return /^✓ All \\d+ in your cart$/.test($('.runa-pb__all').innerText.trim()); }, 10000)), '"Add all" → "' + $('.runa-pb__all').innerText.trim() + '" (from the cart snapshots)');
          post('selfTestAddAll', { n: n });
          await sleep(500);

          $('.runa-pb .runa-c__pcard-title').click();
          await sleep(1500);
          post('selfTestProductCheck');
          await sleep(1500);

          var b = $('.runa-pb__line'); var r = b.getBoundingClientRect();
          b.click();
          await sleep(2500);
          post('selfTestChatCheck');
        } catch (e) { ok(false, 'script error ' + e); }
      })();
    })();
    """
}
