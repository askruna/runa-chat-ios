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
        // `--self-test`: open the chat at once and run the checks inside it (see SelfTest.swift).
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.enabled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { main.openChat(question: nil) }
        }
        return true
    }
}
