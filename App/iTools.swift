// iTools - iOS 15+
// Add SideStore.png, AltStore.png, LiveContainer.png and Nyxian.png to the asset catalog.
// Add Nyxian.ipa if the bundled Nyxian download is desired.
// Never put a GitHub token or shared password in the app binary.

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Security

// MARK: - Configuration

enum ITConfig {
    static let officialOwner = "illiatysh67-code"
    static let officialRepository = "my-new-ios-app"
    static let officialSlug = "itools.official.repo"
    static let catalogPath = "sources.json"
    static let appsPath = "itools-apps.json"
    static let nyxianDownload = "https://drive.google.com/drive/u/6/folders/1NxwSVGQjBhigWdP7gMhC_5G6LgBCFoOU"
    static let combinedTutorial = "https://livecontainer.github.io/docs/installation/lc_sidestore"
}

// MARK: - Models

struct GitHubRepo: Codable, Identifiable, Hashable {
    var id: String { fullName.lowercased() }
    var fullName: String { "\(owner)/\(repo)" }
    let name: String
    let htmlURL: String
    let owner: String
    let repo: String
    var isOfficial: Bool = false

    enum CodingKeys: String, CodingKey {
        case name, htmlURL, owner, repo, isOfficial
    }

    init(name: String, owner: String, repo: String, htmlURL: String, isOfficial: Bool = false) {
        self.name = name
        self.owner = owner
        self.repo = repo
        self.htmlURL = htmlURL
        self.isOfficial = isOfficial
    }
}

struct GitHubApp: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var details: String
    var ipaPath: String
    var iconPath: String?
    var releaseURL: String?
    var version: String?
}

struct PublicSourceIndex: Codable { var sources: [SourceEntry] }

struct SourceEntry: Codable, Identifiable {
    var id: String { url }
    let name: String
    let url: String
}

private struct PublicGitHubRelease: Decodable {
    let name: String?
    let tagName: String?
    let body: String?
    let htmlURL: String?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, body, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

// MARK: - GitHub and local account state

@MainActor
final class ITStore: ObservableObject {
    @Published var repos: [GitHubRepo] = []
    @Published var apps: [GitHubApp] = []
    @Published var message: String?
    @Published var isBusy = false
    @Published var isOfficialUnlocked = false
    @Published var githubUsername = ""
    @Published var githubToken = ""
    @Published var deviceSummary = ""

    private let defaults = UserDefaults.standard
    private let repoKey = "itools.saved.github.sources"
    private let tokenService = "com.itools.github.token"

    init() {
        if defaults.string(forKey: "itools.backgroundHex") == "#101827" {
            defaults.set("", forKey: "itools.backgroundHex")
        }
        loadLocalRepos()
        refreshDeviceSummary()
        repos.removeAll { $0.isOfficial && $0.id != officialRepo.id }
        if !repos.contains(where: { $0.isOfficial }) {
            repos.insert(officialRepo, at: 0)
            saveLocalRepos()
        }
        githubToken = readSecret(service: tokenService, account: "token") ?? ""
        githubUsername = defaults.string(forKey: "itools.github.username") ?? ""
    }

    private var officialRepo: GitHubRepo {
        GitHubRepo(name: "iTools Official", owner: ITConfig.officialOwner,
                   repo: ITConfig.officialRepository,
                   htmlURL: "https://github.com/\(ITConfig.officialOwner)/\(ITConfig.officialRepository)",
                   isOfficial: true)
    }

    func refreshDeviceSummary() {
        let device = UIDevice.current
        deviceSummary = "\(device.localizedModel) - \(device.systemName) \(device.systemVersion)"
    }

    private func readSecret(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeSecret(_ value: String, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    func saveGitHubCredentials() async -> Bool {
        let cleanToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            message = "Enter a GitHub Personal Access Token first."
            return false
        }
        let previousToken = githubToken
        githubToken = cleanToken
        do {
            let (data, _) = try await api("user")
            let profile = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let authenticatedUsername = profile?["login"] as? String else {
                throw NSError(domain: "iToolsGitHub", code: 401,
                              userInfo: [NSLocalizedDescriptionKey: "GitHub did not return an account name for this token."])
            }
            writeSecret(cleanToken, service: tokenService, account: "token")
            githubUsername = authenticatedUsername
            defaults.set(authenticatedUsername, forKey: "itools.github.username")
            isOfficialUnlocked = authenticatedUsername.caseInsensitiveCompare(ITConfig.officialOwner) == .orderedSame
            message = isOfficialUnlocked
                ? "GitHub connected as the official repository owner. Repository permissions are still enforced by GitHub."
                : "GitHub connected. The token is stored securely in Keychain."
            return true
        } catch {
            githubToken = previousToken
            isOfficialUnlocked = false
            message = error.localizedDescription
            return false
        }
    }

    private func api(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NSError(domain: "iToolsGitHub", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Add your GitHub Personal Access Token in Settings first."])
        }
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: "https://api.github.com/\(cleanPath)") else {
            throw NSError(domain: "iToolsGitHub", code: 400,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid GitHub API URL."])
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "iToolsGitHub", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No GitHub response."])
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw NSError(domain: "iToolsGitHub", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: detail ?? "GitHub API error \(http.statusCode). Check token permissions."])
        }
        return (data, http)
    }

    func addSourceURL(_ text: String, displayName: String? = nil) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host == "github.com" else {
            message = "Paste a GitHub repository URL, such as https://github.com/owner/repository."
            return
        }
        let parts = url.pathComponents.dropFirst().prefix(2).map { $0.replacingOccurrences(of: ".git", with: "") }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            message = "Paste a GitHub repository URL, such as https://github.com/owner/repository."
            return
        }
        let owner = parts[0]
        let repository = parts[1]
        let item = GitHubRepo(name: displayName?.isEmpty == false ? displayName! : repository,
                              owner: owner, repo: repository,
                              htmlURL: "https://github.com/\(owner)/\(repository)")
        guard !repos.contains(where: { $0.id == item.id }) else {
            message = "This source is already in your list."
            return
        }
        repos.append(item)
        saveLocalRepos()
        message = "Source added on this device. Submit it to the public iTools catalogue to share it with everyone."
    }

    func createGitHubRepository(from text: String, isPrivate: Bool) async {
        guard let url = URL(string: text), url.host == "github.com" else {
            message = "Enter a GitHub URL like https://github.com/yourname/new-ios-app."
            return
        }
        let parts = url.pathComponents.dropFirst().prefix(2)
        guard let name = parts.last, !name.isEmpty else {
            message = "Enter a GitHub URL like https://github.com/yourname/new-ios-app."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let (data, _) = try await api("user/repos", method: "POST",
                                          body: ["name": name, "private": isPrivate,
                                                 "auto_init": true, "description": "iTools app repository"])
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let owner = (object["owner"] as? [String: Any])?["login"] as? String ?? githubUsername
            let actualName = object["name"] as? String ?? name
            let repository = GitHubRepo(name: actualName, owner: owner, repo: actualName,
                                        htmlURL: "https://github.com/\(owner)/\(actualName)")
            if !repos.contains(where: { $0.id == repository.id }) {
                repos.append(repository)
                saveLocalRepos()
            }
            message = "GitHub repository created and added to iTools."
        } catch { message = error.localizedDescription }
    }

    private func existingSHA(owner: String, repo: String, path: String) async -> String? {
        guard let (data, _) = try? await api("repos/\(owner)/\(repo)/contents/\(path)") else { return nil }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["sha"] as? String
    }

    func uploadFile(data: Data, filename: String, to repo: GitHubRepo, message commitMessage: String) async throws {
        let path = "iTools/\(filename)"
        var body: [String: Any] = ["message": commitMessage, "content": data.base64EncodedString()]
        if let sha = await existingSHA(owner: repo.owner, repo: repo.repo, path: path) { body["sha"] = sha }
        _ = try await api("repos/\(repo.owner)/\(repo.repo)/contents/\(path)", method: "PUT", body: body)
    }

    func loadApps(for repo: GitHubRepo) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let address = "https://raw.githubusercontent.com/\(repo.owner)/\(repo.repo)/HEAD/iTools/\(ITConfig.appsPath)"
            guard let url = URL(string: address) else { throw URLError(.badURL) }
            let (catalogueData, catalogueResponse) = try await URLSession.shared.data(from: url)
            if (catalogueResponse as? HTTPURLResponse)?.statusCode == 200,
               let catalogueApps = try? JSONDecoder().decode([GitHubApp].self, from: catalogueData),
               !catalogueApps.isEmpty {
                apps = catalogueApps
                message = nil
                return
            }

            let releasesAddress = "https://api.github.com/repos/\(repo.owner)/\(repo.repo)/releases?per_page=20"
            guard let releasesURL = URL(string: releasesAddress) else { throw URLError(.badURL) }
            var request = URLRequest(url: releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            let (releaseData, releaseResponse) = try await URLSession.shared.data(for: request)
            guard let http = releaseResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                apps = []
                message = "Could not read this public repository's releases. Check that the repository is public and try again."
                return
            }
            let releases = try JSONDecoder().decode([PublicGitHubRelease].self, from: releaseData)
            apps = releases.flatMap { release in
                release.assets.filter { $0.name.lowercased().hasSuffix(".ipa") }.map { asset in
                    GitHubApp(name: asset.name, details: release.body ?? "",
                              ipaPath: asset.browserDownloadURL, iconPath: nil,
                              releaseURL: release.htmlURL,
                              version: release.tagName)
                }
            }
            message = apps.isEmpty
                ? "No public app catalogue or IPA assets were found in this repository's releases."
                : nil
        } catch {
            apps = []
            message = error.localizedDescription
        }
    }

    private func appDownloadURL(_ text: String) -> URL? {
        guard var components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased() else { return nil }

        if host == "drive.google.com" {
            let pathParts = components.path.split(separator: "/").map(String.init)
            let fileID: String?
            if let fileIndex = pathParts.firstIndex(of: "d"), pathParts.indices.contains(fileIndex + 1) {
                fileID = pathParts[fileIndex + 1]
            } else {
                fileID = components.queryItems?.first(where: { $0.name == "id" })?.value
            }
            guard let fileID, !fileID.isEmpty else { return nil }
            components.path = "/uc"
            components.queryItems = [
                URLQueryItem(name: "export", value: "download"),
                URLQueryItem(name: "id", value: fileID)
            ]
        }

        return components.url
    }

    func publishApp(name: String, details: String, version: String, downloadURL: String,
                    icon: Data?, to repo: GitHubRepo) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            guard let ipaURL = appDownloadURL(downloadURL) else {
                throw NSError(domain: "iTools", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Enter a public HTTPS link to a GitHub release asset or a shared Google Drive file. Drive folder links are not supported."])
            }
            var iconURL: String?
            if let icon {
                let safeName = name.replacingOccurrences(of: " ", with: "-")
                    .replacingOccurrences(of: "/", with: "-")
                let iconName = "\(safeName)-icon.png"
                try await uploadFile(data: icon, filename: iconName, to: repo, message: "Add \(name) icon")
                iconURL = "https://raw.githubusercontent.com/\(repo.owner)/\(repo.repo)/HEAD/iTools/\(iconName)"
            }
            let entry = GitHubApp(name: name, details: details, ipaPath: ipaURL.absoluteString,
                                  iconPath: iconURL, releaseURL: nil,
                                  version: version.isEmpty ? nil : version)
            var updatedApps = apps
            updatedApps.append(entry)
            let encoded = try JSONEncoder.pretty.encode(updatedApps)
            try await uploadFile(data: encoded, filename: ITConfig.appsPath, to: repo,
                                 message: "Update iTools app catalogue")
            apps = updatedApps
            message = "App download link added to the repository catalogue. The IPA remains hosted at \(ipaURL.host ?? "the supplied host")."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func submitSourceToOfficialCatalogue(_ repo: GitHubRepo) async {
        let body = "Please review and add this iTools source to sources.json:\n\nName: \(repo.name)\nURL: \(repo.htmlURL)\n"
        var components = URLComponents(string: "https://github.com/\(ITConfig.officialOwner)/\(ITConfig.officialRepository)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Add source: \(repo.fullName)"),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components?.url else {
            message = "Could not create the GitHub submission link."
            return
        }
        let opened = await UIApplication.shared.open(url)
        message = opened
            ? "Opened a source submission in the iTools GitHub repository. A maintainer must approve it before it appears in the shared catalogue."
            : "Could not open the GitHub issue page. Check your internet connection and try again."
    }

    func refreshOfficialCatalogue() async {
        let address = "https://raw.githubusercontent.com/\(ITConfig.officialOwner)/\(ITConfig.officialRepository)/main/\(ITConfig.catalogPath)"
        do {
            guard let url = URL(string: address) else { return }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let index = try JSONDecoder().decode(PublicSourceIndex.self, from: data)
            for source in index.sources {
                guard let url = URL(string: source.url) else { continue }
                let parts = url.pathComponents.dropFirst().prefix(2)
                guard parts.count == 2 else { continue }
                let item = GitHubRepo(name: source.name, owner: parts[0], repo: parts[1],
                                      htmlURL: "https://github.com/\(parts[0])/\(parts[1])")
                if !repos.contains(where: { $0.id == item.id }) { repos.append(item) }
            }
            saveLocalRepos()
        } catch {
            // Keep locally saved sources available when the catalogue cannot be reached.
        }
    }

    private func loadLocalRepos() {
        guard let data = defaults.data(forKey: repoKey),
              let decoded = try? JSONDecoder().decode([GitHubRepo].self, from: data) else { return }
        repos = decoded
    }

    private func saveLocalRepos() {
        if let data = try? JSONEncoder().encode(repos) { defaults.set(data, forKey: repoKey) }
    }

    func removeRepos(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where repos.indices.contains(index) && !repos[index].isOfficial {
            repos.remove(at: index)
        }
        saveLocalRepos()
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

// MARK: - App

@main
struct iToolsApp: App {
    @StateObject private var store = ITStore()
    var body: some Scene {
        WindowGroup {
            ITAppRootView()
                .environmentObject(store)
        }
    }
}

struct ITNavigationContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(StackNavigationViewStyle())
        }
    }
}

struct ITScrollContentBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

struct ITMainView: View {
    @EnvironmentObject var store: ITStore
    var body: some View {
        TabView {
            ITHomeView().tabItem { Label("Home", systemImage: "house.fill") }
            ITAppsView().tabItem { Label("Apps", systemImage: "square.grid.2x2.fill") }
            ITSourcesView().tabItem { Label("Sources", systemImage: "shippingbox.fill") }
            ITSettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .alert("iTools", isPresented: Binding(
            get: { store.message != nil },
            set: { if !$0 { store.message = nil } }
        )) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
        .task { await store.refreshOfficialCatalogue() }
    }
}

struct ITHomeView: View {
    @EnvironmentObject var store: ITStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("itools.accentHex") private var accentHex = "#1687FF"
    @AppStorage("itools.backgroundHex") private var backgroundHex = ""
    var body: some View {
        ITNavigationContainer {
            List {
                Section {
                    Text("iTools").font(.largeTitle.bold())
                    Text("Apps, GitHub repositories and community sources.")
                        .foregroundStyle(.secondary)
                }
                Section("Featured apps") {
                    ForEach(ITBuiltinApp.all) { app in
                        NavigationLink { ITBuiltinDetail(app: app) } label: { ITBuiltinRow(app: app) }
                    }
                }
                Section("Device") {
                    Label(store.deviceSummary, systemImage: "iphone")
                }
            }
            .modifier(ITScrollContentBackgroundModifier())
            .background(ITTheme.background(hex: backgroundHex, scheme: colorScheme))
            .navigationTitle("Home")
        }
        .tint(Color(hex: accentHex))
    }
}

struct ITBuiltinApp: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let detail: String
    let icon: String
    let ipaResource: String?
    let web: String?
    let tutorial: String?

    static let all: [ITBuiltinApp] = [
          .init(id: "sidestore", name: "SideStore", subtitle: "Sideload and refresh apps",
              detail: "SideStore is a sideloading tool. Use its official releases and setup documentation.",
              icon: "SideStore", ipaResource: nil,
              web: "https://github.com/SideStore/SideStore/releases", tutorial: "https://sidestore.io/"),
        .init(id: "altstore", name: "AltStore", subtitle: "Alternative app sideloading",
              detail: "AltStore is an alternative app sideloading tool. Check the official site for supported devices and setup.",
              icon: "AltStore", ipaResource: nil, web: "https://altstore.io", tutorial: "https://faq.altstore.io/"),
        .init(id: "livecontainer", name: "LiveContainer", subtitle: "Run apps in a container",
              detail: "LiveContainer provides a container environment for running compatible iOS apps. Check its documentation for compatibility.",
              icon: "LiveContainer", ipaResource: nil,
              web: "https://github.com/LiveContainer/LiveContainer/releases", tutorial: "https://github.com/LiveContainer/LiveContainer"),
          .init(id: "combined", name: "LiveContainer + SideStore", subtitle: "Install and configure both together",
              detail: "Use the combined installation guide. The two apps remain separate and both need setup.",
              icon: "Combined", ipaResource: "LiveContainer+SideStore", web: nil,
              tutorial: ITConfig.combinedTutorial),
          .init(id: "nyxian", name: "Nyxian", subtitle: "Nyxian IPA and installation guide",
              detail: "Download the Nyxian IPA from the supplied Google Drive folder, then follow the installation instructions below.",
              icon: "Nyxian", ipaResource: "Nyxian", web: ITConfig.nyxianDownload, tutorial: nil)
    ]
}

struct ITBuiltinRow: View {
    let app: ITBuiltinApp
    var body: some View {
        HStack(spacing: 12) {
            ITAppIcon(name: app.icon, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.headline)
                Text(app.subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

struct ITAppIcon: View {
    let name: String
    var size: CGFloat = 56

    private var fallbackSymbol: String {
        switch name {
        case "SideStore": "arrow.down.app.fill"
        case "AltStore": "storefront.fill"
        case "LiveContainer": "shippingbox.fill"
        case "Nyxian": "bolt.shield.fill"
        default: "square.stack.3d.up.fill"
        }
    }

    var body: some View {
        Group {
            if name == "Combined" && UIImage(named: "LiveContainer") != nil && UIImage(named: "SideStore") != nil {
                HStack(spacing: 0) {
                    Image("LiveContainer").resizable().scaledToFill().frame(width: size / 2, height: size)
                    Image("SideStore").resizable().scaledToFill().frame(width: size / 2, height: size)
                }
                .clipped()
            } else if name != "AltStore", UIImage(named: name) != nil {
                Image(name).resizable().scaledToFill()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: size, height: size)
                    .background(.cyan.opacity(0.13))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23))
    }
}

struct ITBuiltinDetail: View {
    let app: ITBuiltinApp
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ITAppIcon(name: app.icon, size: 112).frame(maxWidth: .infinity)
                Text(app.name).font(.largeTitle.bold())
                Text(app.detail).foregroundStyle(.secondary)
                Button("Get") { get() }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                if let web = app.web, let url = URL(string: web) {
                    Link("Official releases / website", destination: url)
                }
                if let tutorial = app.tutorial, let url = URL(string: tutorial) {
                    Link("Open tutorial / setup guide", destination: url)
                }
                if app.id == "nyxian" {
                    Button("Share the supplied Nyxian IPA from this app") {
                        if let file = Bundle.main.url(forResource: "Nyxian", withExtension: "ipa") {
                            shareItems = [file]
                            showShare = true
                        }
                    }
                    .buttonStyle(.bordered)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nyxian install guide").font(.title2.bold())
                        Text("Method 1: Sideloading using SideStore or AltStore").font(.headline)
                        Text("1. Sideload Nyxian.ipa onto your device.\n2. Follow the signing and installation instructions in SideStore or AltStore.")
                        Text("Method 2: Use your own paid Apple Developer certificate").font(.headline)
                        Text("Use only a certificate and provisioning profile you are authorized to use. Import them into a trusted signing tool, sign Nyxian.ipa, and install it.")
                    }
                    .font(.callout)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }
                Text("iOS does not allow ordinary apps to silently install IPA files. Get opens the share sheet so you can save or open the IPA in a compatible sideloading tool.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) { ITShareSheet(items: shareItems) }
    }

    private func get() {
        if app.id == "nyxian", let url = URL(string: ITConfig.nyxianDownload) {
            UIApplication.shared.open(url)
            return
        }
        if let resource = app.ipaResource,
           let url = Bundle.main.url(forResource: resource, withExtension: "ipa") {
            shareItems = [url]
            showShare = true
        } else if app.id == "combined" {
            if let url = URL(string: app.tutorial ?? ITConfig.combinedTutorial) {
                UIApplication.shared.open(url)
            }
        } else if let web = app.web, let url = URL(string: web) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: app.tutorial ?? ITConfig.nyxianDownload) {
            UIApplication.shared.open(url)
        }
    }
}

struct ITShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ITAppsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("itools.backgroundHex") private var backgroundHex = ""
    @State private var query = ""
    private var filtered: [ITBuiltinApp] {
        query.isEmpty ? ITBuiltinApp.all : ITBuiltinApp.all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        ITNavigationContainer {
            List(filtered) { app in
                NavigationLink { ITBuiltinDetail(app: app) } label: { ITBuiltinRow(app: app) }
            }
            .modifier(ITScrollContentBackgroundModifier())
            .background(ITTheme.background(hex: backgroundHex, scheme: colorScheme))
            .navigationTitle("Apps")
            .searchable(text: $query)
            .animation(.easeInOut(duration: 0.18), value: query)
        }
    }
}

struct ITSourcesView: View {
    @EnvironmentObject var store: ITStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("itools.accentHex") private var accentHex = "#1687FF"
    @AppStorage("itools.backgroundHex") private var backgroundHex = ""
    @State private var showAdd = false
    @State private var showCreate = false
    var body: some View {
        ITNavigationContainer {
            List {
                Section("Repositories") {
                    ForEach(store.repos) { repo in
                        NavigationLink { ITRepositoryView(repo: repo) } label: {
                            HStack {
                                Image(systemName: repo.isOfficial ? "checkmark.seal.fill" : "shippingbox.fill")
                                    .foregroundStyle(repo.isOfficial ? .cyan : .secondary)
                                VStack(alignment: .leading) {
                                    Text(repo.name).font(.headline)
                                    Text(repo.fullName).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if repo.isOfficial {
                                    Text("OFFICIAL").font(.caption2).foregroundStyle(.cyan)
                                }
                            }
                        }
                    }
                    .onDelete { store.removeRepos(at: $0) }
                }
                Section {
                    Button { showAdd = true } label: { Label("Add GitHub source URL", systemImage: "plus") }
                    Button { showCreate = true } label: { Label("Create GitHub repository", systemImage: "plus.app") }
                    Button { Task { await store.refreshOfficialCatalogue() } } label: {
                        Label("Refresh shared sources", systemImage: "arrow.clockwise")
                    }
                }
                Section {
                    Text("Sources you add are saved on this device. Submit a source for review to make it visible to every iTools user.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .modifier(ITScrollContentBackgroundModifier())
            .background(ITTheme.background(hex: backgroundHex, scheme: colorScheme))
            .navigationTitle("Sources")
            .sheet(isPresented: $showAdd) { ITAddSourceSheet() }
            .sheet(isPresented: $showCreate) { ITCreateGitHubRepoSheet() }
        }
        .tint(Color(hex: accentHex))
    }
}

struct ITAddSourceSheet: View {
    @EnvironmentObject var store: ITStore
    @Environment(\.dismiss) var dismiss
    @State private var url = ""
    var body: some View {
        ITNavigationContainer {
            Form {
                Section("GitHub repository URL") {
                    TextField("https://github.com/owner/repository", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button("Add source") { store.addSourceURL(url); dismiss() }
                    .disabled(url.isEmpty)
            }
            .navigationTitle("Add source")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct ITCreateGitHubRepoSheet: View {
    @EnvironmentObject var store: ITStore
    @Environment(\.dismiss) var dismiss
    @State private var url = ""
    @State private var isPrivate = false
    var body: some View {
        ITNavigationContainer {
            Form {
                Section("Repository URL") {
                    TextField("https://github.com/yourname/new-ios-app", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Private repository", isOn: $isPrivate)
                }
                Text("GitHub creates repositories under the account connected to the token. The URL's owner is a label; it cannot create a repository inside someone else's account.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Create on GitHub") {
                    Task { await store.createGitHubRepository(from: url, isPrivate: isPrivate); dismiss() }
                }
                .disabled(url.isEmpty || store.githubToken.isEmpty)
            }
            .navigationTitle("New GitHub repository")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct ITRepositoryView: View {
    @EnvironmentObject var store: ITStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("itools.backgroundHex") private var backgroundHex = ""
    let repo: GitHubRepo
    @State private var showUpload = false
    var body: some View {
        List {
            Section {
                Text(repo.name).font(.title2.bold())
                Text(repo.fullName).font(.caption).foregroundStyle(.secondary)
                if let url = URL(string: repo.htmlURL) { Link("Open GitHub repository", destination: url) }
            }
            Section("Apps") {
                if store.apps.isEmpty {
                    Text("No app catalogue or public IPA release assets were found in this repository.")
                }
                ForEach(store.apps) { app in
                    HStack {
                        AsyncImage(url: app.iconPath.flatMap(URL.init(string:))) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "app.fill").foregroundStyle(.cyan)
                        }
                        .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading) {
                            Text(app.name).font(.headline)
                            Text(app.details).font(.caption).foregroundStyle(.secondary)
                            if let version = app.version { Text("Version \(version)").font(.caption2) }
                            if let url = URL(string: app.ipaPath) { Link("Get", destination: url) }
                            if let release = app.releaseURL, let url = URL(string: release) {
                                Link("GitHub Releases", destination: url)
                            }
                        }
                    }
                }
            }
            Section {
                Button { showUpload = true } label: {
                    Label("Add app download link", systemImage: "link")
                }
                .disabled(store.githubToken.isEmpty)
                if repo.isOfficial && !store.isOfficialUnlocked {
                    Text("Connect a GitHub account with write access to this repository in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !repo.isOfficial {
                    Button("Submit this source to the shared catalogue") {
                        Task { await store.submitSourceToOfficialCatalogue(repo) }
                    }
                }
            }
        }
        .modifier(ITScrollContentBackgroundModifier())
        .background(ITTheme.background(hex: backgroundHex, scheme: colorScheme))
        .navigationTitle("Repository")
        .task { await store.loadApps(for: repo) }
        .refreshable { await store.loadApps(for: repo) }
        .sheet(isPresented: $showUpload) { ITUploadAppSheet(repo: repo) }
    }
}

struct ITUploadAppSheet: View {
    @EnvironmentObject var store: ITStore
    @Environment(\.dismiss) var dismiss
    let repo: GitHubRepo
    @State private var name = ""
    @State private var details = ""
    @State private var version = "1.0.1"
    @State private var downloadURL = ""
    @State private var iconData: Data?
    @State private var showIconPicker = false

    var body: some View {
        ITNavigationContainer {
            Form {
                Section("App details") {
                    TextField("App name", text: $name)
                    TextField("Description", text: $details)
                    TextField("Version number", text: $version)
                        .keyboardType(.numbersAndPunctuation)
                }
                Section("Files") {
                    TextField("Public IPA download link", text: $downloadURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("Paste a GitHub release asset URL or a shared Google Drive file link. Drive folder links are not supported.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { showIconPicker = true } label: {
                        Label(iconData == nil ? "Choose app icon from Photos" : "Change selected app icon",
                              systemImage: "photo")
                    }
                    if let iconData, let image = UIImage(data: iconData) {
                        Image(uiImage: image)
                            .resizable().scaledToFit().frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                Section("Publishing") {
                    Text("The app link and details are added to this repository's catalogue. The IPA stays hosted at the link you provide.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Publish app link") {
                    Task {
                        let published = await store.publishApp(
                            name: name,
                            details: details,
                            version: version,
                            downloadURL: downloadURL,
                            icon: iconData,
                            to: repo
                        )
                        if published { dismiss() }
                    }
                }
                .disabled(name.isEmpty || downloadURL.isEmpty || store.githubToken.isEmpty || store.isBusy ||
                          (repo.isOfficial && !store.isOfficialUnlocked))
            }
            .navigationTitle("Add app link")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showIconPicker) {
                ITPhotoPicker { image in
                    guard let image, let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
                    iconData = jpeg
                }
            }
        }
    }
}

struct ITSettingsView: View {
    @EnvironmentObject var store: ITStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("itools.accentHex") private var accentHex = "#1687FF"
    @AppStorage("itools.backgroundHex") private var backgroundHex = ""
    var body: some View {
        ITNavigationContainer {
            Form {
                Section("GitHub connection") {
                    TextField("GitHub username", text: $store.githubUsername)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("GitHub Personal Access Token", text: $store.githubToken)
                    Button("Save GitHub connection") {
                        Task { await store.saveGitHubCredentials() }
                    }
                    Link("Create a GitHub token", destination: URL(string: "https://github.com/settings/personal-access-tokens")!)
                    Text("Use a token with the repository permissions required for your actions. The token is stored in Keychain. GitHub does not accept normal account passwords for API access.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Appearance") {
                    ColorPicker("Accent colour", selection: Binding(
                        get: { Color(hex: accentHex) },
                        set: { accentHex = $0.hexString ?? "#1687FF" }
                    ), supportsOpacity: false)
                    ColorPicker("Background colour", selection: Binding(
                        get: { ITTheme.background(hex: backgroundHex, scheme: colorScheme) },
                        set: { backgroundHex = $0.hexString ?? "" }
                    ), supportsOpacity: false)
                    Button("Use device appearance for background") {
                        backgroundHex = ""
                    }
                    Button("Reset appearance") {
                        accentHex = "#1687FF"
                        backgroundHex = ""
                    }
                }
                Section("Device") {
                    Label(store.deviceSummary, systemImage: "iphone")
                    Button("Refresh device information") { store.refreshDeviceSummary() }
                }
                Section("Help") {
                    Link("iTools GitHub repository", destination: URL(string: "https://github.com/\(ITConfig.officialOwner)/\(ITConfig.officialRepository)")!)
                    Text("iOS does not permit silent IPA installation. iTools can upload, host and share IPA files, but installation must be completed with a compatible sideloading workflow.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .modifier(ITScrollContentBackgroundModifier())
            .background(ITTheme.background(hex: backgroundHex, scheme: colorScheme))
            .navigationTitle("Settings")
        }
        .tint(Color(hex: accentHex))
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(cleaned, radix: 16) ?? 0x1687FF
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }

    var hexString: String? {
        let components = UIColor(self).cgColor.components
        guard let components, components.count >= 3 else { return nil }
        let red = Int(components[0] * 255)
        let green = Int(components[1] * 255)
        let blue = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
