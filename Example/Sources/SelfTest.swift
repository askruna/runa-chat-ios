import UIKit
import WebKit
import SafariServices
import RunaChat

/// Test only (`--self-test` launch argument): after the page says `ready`, runs a script inside the
/// chat's real WKWebView that walks a shopper's path and reports each check back through the bridge
/// as `selfTestStep` messages, logged as "[SelfTest] PASS/FAIL …". The script also asks the app to
/// act like a shopper would elsewhere in the app (`selfTestBump`: change the cart; `selfTestPop`: go
/// back from the product screen; `selfTestKeyboard`: a keyboard appears).
enum SelfTest {
    static var enabled = false

    static func handle(type: String, payload: [String: Any], chat: RunaChatViewController) {
        guard enabled else { return }
        switch type {
        case "ready":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { webView(in: chat.view)?.evaluateJavaScript(script, completionHandler: nil) }
        case "selfTestStep":
            NSLog("[SelfTest] %@", payload["line"] as? String ?? "")
        case "selfTestDone":
            NSLog("[SelfTest] DONE pass=%@ fail=%@", String(describing: payload["pass"] ?? 0), String(describing: payload["fail"] ?? 0))
        case "selfTestBump":
            SampleCart.bumpFirst((payload["delta"] as? NSNumber)?.intValue ?? 0)
            RunaChat.notifyCartChanged()
        case "selfTestPop":
            chat.navigationController?.popToViewController(chat, animated: true)
        case "selfTestSheet":
            // Did the library show its in-app browser sheet (the openLink fallback)? Answer into the page, then close it.
            let sheet = chat.presentedViewController is SFSafariViewController
            webView(in: chat.view)?.evaluateJavaScript("window.__runaSelfTestSheet = " + (sheet ? "true" : "false") + ";", completionHandler: nil)
            chat.presentedViewController?.dismiss(animated: false)
        case "selfTestKeyboard":
            // Stand in for the real keyboard (the simulator cannot be tapped from a script): the same
            // notification iOS posts, with a 336 pt keyboard at the bottom of the screen.
            let h: CGFloat = 336
            let screen = UIScreen.main.bounds
            let frame = CGRect(x: 0, y: screen.height - h, width: screen.width, height: h)
            NotificationCenter.default.post(name: UIResponder.keyboardWillChangeFrameNotification, object: nil, userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: frame),
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.1,
            ])
        case "selfTestKeyboardHide":
            let screen = UIScreen.main.bounds
            NotificationCenter.default.post(name: UIResponder.keyboardWillChangeFrameNotification, object: nil, userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: CGRect(x: 0, y: screen.height, width: screen.width, height: 336)),
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.1,
            ])
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
      var pass = 0, fail = 0;
      function ok(c, label) { if (c) pass++; else fail++; post('selfTestStep', { line: (c ? 'PASS ' : 'FAIL ') + label }); }
      function qty() { var n = $('.runa-c__pcard-qty-n'); return n ? n.textContent.trim() : ''; }
      (async function () {
        try {
          ok(!!(await waitFor(function () { return $('.runa-c__window--app'); }, 20000)), 'chat rendered in app mode');
          var ua = navigator.userAgent;
          ok(/AppleWebKit/.test(ua) && !/Chrome\\//.test(ua), 'engine: WebKit ' + (ua.match(/OS [\\d_]+/) || ['?'])[0]);
          var h = $('.runa-c__window-head').cloneNode(true); h.querySelectorAll('select,button').forEach(function (n) { n.remove(); });
          var ht = h.textContent.replace(/\\s+/g, ' ').trim();
          ok(ht === 'Ask Quicklly', 'header text: "' + ht + '"');
          var close = $('.runa-c__window-close').getBoundingClientRect();
          ok(close.left >= 0 && close.right <= window.innerWidth, 'close button on screen');
          var opts = await waitFor(function () { var o = document.querySelectorAll('.runa-c__store-select option'); return o.length > 1 ? o : null; }, 15000);
          ok(!!opts, 'store picker: ' + (opts ? opts.length - 1 : 0) + ' stores, "' + (opts ? opts[0].textContent : '') + '"');
          var q = new URLSearchParams(location.search);
          ok(q.get('platform') === 'ios' && q.get('zip') === '60610' && q.get('userId') === 'sample-user-1' && !!q.get('appVersion'), 'URL built from Options: platform=' + q.get('platform') + ' zip=' + q.get('zip') + ' userId=' + q.get('userId') + ' appVersion=' + q.get('appVersion'));

          // Keyboard: the library shrinks the page above it
          var before = window.innerHeight;
          post('selfTestKeyboard', {});
          await sleep(900);
          var input = $('.runa-c__composer-text');
          var r = input.getBoundingClientRect();
          ok(window.innerHeight <= before - 250 && r.bottom <= window.innerHeight, 'keyboard: page shrank ' + before + ' → ' + window.innerHeight + ', input bottom ' + Math.round(r.bottom) + ' stays visible');
          post('selfTestKeyboardHide', {});
          await sleep(600);
          ok(window.innerHeight === before, 'keyboard hidden: page back to ' + window.innerHeight);

          // A turn, like a shopper
          var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(input, 'basmati rice');
          input.dispatchEvent(new Event('input', { bubbles: true }));
          await sleep(400);
          $('.runa-c__composer-send').click();
          ok(!!(await waitFor(function () { return $('.runa-c__pcard-add'); }, 90000)), 'turn answered with product cards');
          await sleep(800);

          // ADD → delegate setQuantity → cart snapshot → stepper
          $('.runa-c__pcard-add').click();
          ok(await waitFor(function () { return qty() === '1'; }, 8000), 'ADD → delegate setQuantity → stepper shows 1');
          post('selfTestBump', { delta: 2 });
          ok(await waitFor(function () { return qty() === '3'; }, 8000), 'app changed its cart + notifyCartChanged → stepper shows 3');
          post('selfTestBump', { delta: -3 });
          ok(await waitFor(function () { return !!$('.runa-c__pcard-add') && qty() === ''; }, 8000), 'app removed the line → card back to ADD');

          // Card tap → openProduct → the app's product screen; back
          $('.runa-c__pcard-title').click();
          await sleep(1500);
          post('selfTestPop', {});
          await sleep(1200);

          // Outside link → openLink, never a navigation inside the chat
          var href = location.href;
          window.open('https://www.quicklly.com/', '_blank');
          await sleep(800);
          ok(location.href === href, 'outside link did not navigate the chat');

          // Outside link the app does NOT handle → the library's in-app browser sheet, never Safari
          window.__runaSelfTestSheet = undefined;
          window.open('https://www.quicklly.com/runa-fallback-test', '_blank');
          await sleep(1500);
          post('selfTestSheet', {});
          var sheet = await waitFor(function () { return typeof window.__runaSelfTestSheet === 'boolean' ? { v: window.__runaSelfTestSheet } : null; }, 5000);
          ok(!!(sheet && sheet.v), 'openLink not handled by the app → in-app browser sheet (SFSafariViewController)');
          await sleep(600);

          // ✕ → close
          $('.runa-c__window-close').click();
        } catch (e) {
          ok(false, 'exception: ' + (e && e.message));
        }
        post('selfTestDone', { pass: pass, fail: fail });
      })();
    })(); true;
    """
}
