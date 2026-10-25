import UIKit
import WebKit
import RunaChat

/// Test only (`--self-test-search` launch argument): the search screen opens for "cow milk"; once the search view's
/// page says `ready`, a script inside its real WKWebView walks a shopper's path — the answer, ADD, a cart change made
/// by the app, a product tap, a chip into the chat, a new search typed in the app — and the app checks its side (the
/// view's height and place, the product screen, the chat's question). Then a checkout: `RunaChat.orderPlaced`.
/// Every check is logged as "[SelfTest] PASS/FAIL …", the end as "[SelfTest] DONE pass=… fail=…".
enum SearchSelfTest {
    static var enabled = false
    static weak var main: MainViewController?
    private static var started = false
    private static var expectedAsk = ""
    private static var askedAnything = false
    private static var chatShown = false     // after the follow-up's chat: "Ask me anything" opens an empty chat
    private static var pass = 0, fail = 0

    static func step(_ line: String) {
        if line.hasPrefix("PASS") { pass += 1 } else if line.hasPrefix("FAIL") { fail += 1 }
        NSLog("[SelfTest] %@", line)
    }
    static func check(_ ok: Bool, _ label: String) { step((ok ? "PASS " : "FAIL ") + label) }

    // MARK: the search view's messages

    static func handle(type: String, payload: [String: Any], screen: SearchViewController) {
        guard enabled else { return }
        switch type {
        case "ready":
            guard !started else { return }
            started = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { webView(in: screen.answer)?.evaluateJavaScript(searchScript, completionHandler: nil) }
        case "selfTestStep":
            step(payload["line"] as? String ?? "")
        case "selfTestHeight":
            // the native view is as tall as the page's answer and sits right above the app's "N products found"
            let css = CGFloat((payload["css"] as? NSNumber)?.doubleValue ?? 0)
            let h = screen.answer.height
            check(h > 100 && abs(h - css.rounded(.up)) <= 2, String(format: "native view sized to the answer: %.0f pt (page %.0f css px)", h, css))
            screen.view.layoutIfNeeded()
            let viewBottom = screen.answer.convert(screen.answer.bounds, to: screen.view).maxY
            let rowTop = screen.foundLabel.superview!.convert(screen.foundLabel.superview!.bounds, to: screen.view).minY
            check(abs(viewBottom - rowTop) <= 1, String(format: "the view sits right above \"%@\" (view bottom %.0f, row top %.0f)", screen.foundLabel.text ?? "", viewBottom, rowTop))
        case "selfTestShot":
            NSLog("[SelfTest] SHOT %@", payload["name"] as? String ?? "")   // the runner takes a screenshot
        case "selfTestBump":
            SampleCart.bumpFirst((payload["delta"] as? NSNumber)?.intValue ?? 0)
            RunaChat.notifyCartChanged()
        case "selfTestProductCheck":
            check(screen.navigationController?.topViewController is ProductViewController, "product tap → delegate openProduct → the app's product screen")
            screen.navigationController?.popToViewController(screen, animated: false)
        case "selfTestChip":
            expectedAsk = payload["ask"] as? String ?? ""
        case "selfTestOrder":
            // checkout on the app's home: what the shopper added from Ask Quicklly in search is in the cart
            guard let main = main else { return }
            screen.navigationController?.popToViewController(main, animated: false)
            let lines = SampleCart.lines.count
            main.placeOrder { reported, reason in
                check(reported, "orderPlaced → the order page reported the order (\(lines) line(s)) \(reason ?? "")")
                NSLog("[SelfTest] DONE pass=%d fail=%d", pass, fail)
            }
        default:
            break
        }
    }

    // MARK: the chat screen a chip opened

    static func chatMessage(type: String, payload: [String: Any], chat: RunaChatViewController) {
        guard enabled else { return }
        switch type {
        case "ready":
            let ask = (try? String(data: JSONSerialization.data(withJSONObject: [expectedAsk]), encoding: .utf8)) ?? "[\"\"]"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { webView(in: chat.view)?.evaluateJavaScript("window.__runaAsk = \(ask)[0];" + chatScript, completionHandler: nil) }
        case "selfTestStep":
            step(payload["line"] as? String ?? "")
        case "selfTestShot":
            NSLog("[SelfTest] SHOT %@", payload["name"] as? String ?? "")
        case "shown":
            chatShown = true
        case "selfTestChatDone":
            let gone = SelfTest.loadingView(in: chat.view).map { $0.isHidden } ?? false
            check(chatShown && gone, "the chat's loading screen went once the chat drew (shown=\(chatShown), gone=\(gone))")
            chatShown = false
            // back to the search screen, where the shopper types a new search
            guard let nav = chat.navigationController, let screen = nav.viewControllers.first(where: { $0 is SearchViewController }) as? SearchViewController else {
                check(false, "chat was opened on the search screen's navigation stack"); return
            }
            nav.popToViewController(screen, animated: false)
            if !askedAnything {
                // "Ask me anything" in the answer → the chat screen with no question, credited to Ask Quicklly in search
                askedAnything = true
                expectedAsk = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    webView(in: screen.answer)?.evaluateJavaScript("(function(){var b=document.querySelector('.runa-sb .runa-sb__chip--ask'); if(!b) return false; b.click(); return true;})()") { r, _ in
                        if (r as? Bool) != true { check(false, "\"Ask me anything\" button in the answer"); screen.runSearch("basmati rice") }
                    }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { screen.runSearch("basmati rice") }
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

    // Runs in the search view's page. Long waits: the page is paused while the chat covers it.
    static let searchScript = """
    (function () {
      if (window.__runaSelfTest) return; window.__runaSelfTest = true;
      function post(type, payload) { window.webkit.messageHandlers.runa.postMessage(JSON.stringify({ type: type, payload: payload || {} })); }
      function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
      function $(s) { return document.querySelector(s); }
      async function waitFor(fn, ms) { var end = Date.now() + ms; while (Date.now() < end) { try { var v = fn(); if (v) return v; } catch (e) {} await sleep(250); } return null; }
      function ok(c, label) { post('selfTestStep', { line: (c ? 'PASS ' : 'FAIL ') + label }); }
      function qty() { var n = $('.runa-sb .runa-c__pcard-qty-n'); return n ? n.textContent.trim() : ''; }
      function height() { return document.getElementById('root_quicklly_chat').getBoundingClientRect().height; }
      async function shot(name) { await sleep(800); post('selfTestShot', { name: name }); await sleep(2500); }
      (async function () {
        try {
          var q = Object.fromEntries(new URLSearchParams(location.search));
          ok(q.q === 'cow milk' && q.results === '4' && /^Amul Water Buffalo/.test(q.titles || '') && q.zip === '60610' && q.platform === 'ios',
            'page URL from search(): q=' + q.q + ' results=' + q.results + ' platform=' + q.platform);
          ok(!!(await waitFor(function () { return $('.runa-sb .runa-c__pcard'); }, 90000)), 'the answer shows products');
          await sleep(500);
          post('selfTestHeight', { css: height() });   // the app must hear the height within half a second of the answer
          await sleep(1000);
          var first = $('.runa-sb .runa-c__pcard-title').textContent.trim();
          var n = document.querySelectorAll('.runa-sb .runa-c__pcard').length;
          ok(n >= 3 && /milk/i.test(first) && !/butter/i.test(first), 'answer: ' + n + ' products, first "' + first + '" (the app\\'s own first result is butter)');
          await shot('search-answer');

          $('.runa-sb .runa-c__pcard-add').click();
          ok(!!(await waitFor(function () { return qty() === '1'; }, 8000)), 'ADD → delegate setQuantity → stepper shows 1 (from the cart)');
          post('selfTestBump', { delta: 1 });
          ok(!!(await waitFor(function () { return qty() === '2'; }, 8000)), 'app changed the cart + notifyCartChanged() → stepper shows 2');
          await shot('search-added');

          $('.runa-sb .runa-c__pcard-title').click();
          await sleep(1500);
          post('selfTestProductCheck');
          await sleep(1500);

          var chip = $('.runa-sb .runa-pdp__chip:not(.runa-sb__chip--ask)');
          ok(!!chip, 'the answer has follow-up chips');
          post('selfTestChip', { ask: chip.getAttribute('data-ask') });
          await sleep(300);
          chip.click();

          var second = await waitFor(function () { return $('.runa-sb[data-query="basmati rice"] .runa-c__pcard'); }, 240000);
          await sleep(500);
          var t2 = second ? $('.runa-sb .runa-c__pcard-title').textContent.trim() : '';
          ok(/rice/i.test(t2), 'a new search typed in the app → new answer in the same view, first "' + t2 + '"');
          post('selfTestHeight', { css: height() });
          await shot('search-second');
          post('selfTestOrder');
        } catch (e) {
          ok(false, 'search script error: ' + e.message);
          post('selfTestOrder');
        }
      })();
    })();
    """

    // Runs in the chat page a chip opened; window.__runaAsk is the chip's question.
    static let chatScript = """
    (function () {
      if (window.__runaSelfTest) return; window.__runaSelfTest = true;
      function post(type, payload) { window.webkit.messageHandlers.runa.postMessage(JSON.stringify({ type: type, payload: payload || {} })); }
      function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
      async function waitFor(fn, ms) { var end = Date.now() + ms; while (Date.now() < end) { try { var v = fn(); if (v) return v; } catch (e) {} await sleep(250); } return null; }
      function ok(c, label) { post('selfTestStep', { line: (c ? 'PASS ' : 'FAIL ') + label }); }
      (async function () {
        var q = Object.fromEntries(new URLSearchParams(location.search));
        if (!window.__runaAsk) {
          ok(!q.q && q.entry === 'search_answers', '"Ask me anything" → chat opened without a question (q=' + (q.q || 'none') + '), entry=' + q.entry);
          ok(!!(await waitFor(function () { return document.querySelector('.runa-c__window--app .runa-c__composer-text'); }, 30000)), 'chat rendered in app mode, message box ready');
          await sleep(1500);
          // the shopper's own messages: the earlier conversation is restored (its answer may still be arriving), nothing new is sent
          var m1 = document.querySelectorAll('.runa-c__msg-block--user').length;
          await sleep(4000);
          var m2 = document.querySelectorAll('.runa-c__msg-block--user').length;
          var box = (document.querySelector('.runa-c__composer-text').value || '').trim();
          ok(m1 === m2 && box === '', 'nothing sent by itself: shopper messages ' + m1 + ' → ' + m2 + ' over 4 s, the message box is empty' + (box ? ' (it holds "' + box + '")' : ''));
          post('selfTestShot', { name: 'search-ask-chat' });
          await sleep(2500);
          post('selfTestChatDone');
          return;
        }
        ok(!!window.__runaAsk && q.q === window.__runaAsk && q.entry === 'search_answers', 'chip → chat opened with q="' + q.q + '", entry=' + q.entry);
        ok(!!(await waitFor(function () { return document.querySelector('.runa-c__window--app'); }, 30000)), 'chat rendered in app mode');
        ok(!!(await waitFor(function () { return document.body.innerText.indexOf(window.__runaAsk) >= 0; }, 20000)), 'the question was sent as the first message');
        post('selfTestChatDone');
      })();
    })();
    """
}
