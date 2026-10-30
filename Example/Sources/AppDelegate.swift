import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        let main = MainViewController()
        w.rootViewController = UINavigationController(rootViewController: main)
        w.makeKeyAndVisible()
        window = w
        // `--page-base <url>`: Runa's tests serve the pages from the laptop
        if let i = CommandLine.arguments.firstIndex(of: "--page-base"), i + 1 < CommandLine.arguments.count {
            MainViewController.pageBase = URL(string: CommandLine.arguments[i + 1])
        }
        // `--self-test-search`: open the search screen for "cow milk" and run the checks (SearchSelfTest.swift).
        if CommandLine.arguments.contains("--self-test-search") {
            SearchSelfTest.enabled = true
            SearchSelfTest.main = main
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { main.openSearch(query: "cow milk") }
        }
        // `--self-test-product`: open the product screen for okra and run the checks (ProductSelfTest.swift).
        if CommandLine.arguments.contains("--self-test-product") {
            ProductSelfTest.enabled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { main.openProduct(pid: "1013592", sid: "113189", title: "Okra (bhindi) 1 Lbs", price: 3.39) }
        }
        // `--self-test`: open the chat at once and run the checks inside it (see SelfTest.swift).
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.enabled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { main.openChat(question: nil) }
        }
        return true
    }
}
