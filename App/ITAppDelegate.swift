import SwiftUI
import UIKit

@main
final class ITAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let appWindow = UIWindow(frame: UIScreen.main.bounds)
        if #available(iOS 15.0, *) {
            let store = ITStore()
            let rootView = ITAppRootView().environmentObject(store)
            appWindow.rootViewController = UIHostingController(rootView: rootView)
        } else {
            appWindow.rootViewController = UINavigationController(rootViewController: ITLegacyHomeController())
        }
        appWindow.makeKeyAndVisible()
        window = appWindow
        return true
    }
}

private final class ITLegacyHomeController: UITableViewController {
    private struct AppLink {
        let name: String
        let detail: String
        let icon: String
        let url: URL
    }

    private let appLinks: [AppLink] = [
        AppLink(name: "SideStore", detail: "Sideloading and app refresh", icon: "SideStore",
                url: URL(string: "https://github.com/SideStore/SideStore/releases")!),
        AppLink(name: "AltStore", detail: "Alternative app sideloading", icon: "AltStore",
                url: URL(string: "https://altstore.io")!),
        AppLink(name: "LiveContainer", detail: "Run compatible apps in a container", icon: "LiveContainer",
                url: URL(string: "https://github.com/LiveContainer/LiveContainer/releases")!),
        AppLink(name: "LiveContainer + SideStore", detail: "Combined installation guide", icon: "SideStore",
                url: URL(string: "https://livecontainer.github.io/docs/installation/lc_sidestore")!),
        AppLink(name: "Nyxian", detail: "Nyxian IPA and installation guide", icon: "Nyxian",
                url: URL(string: ITConfig.nyxianDownload)!),
        AppLink(name: "Husk", detail: "Android apps and games on iPhone", icon: "Husk",
                url: URL(string: ITConfig.huskDownload)!)
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "iTools"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AppLink")
        tableView.rowHeight = 76
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        appLinks.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = appLinks[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "AppLink")
        cell.textLabel?.text = item.name
        cell.detailTextLabel?.text = item.detail
        cell.imageView?.image = UIImage(named: item.icon)
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        UIApplication.shared.open(appLinks[indexPath.row].url, options: [:], completionHandler: nil)
    }
}
