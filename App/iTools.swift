// iTools.swift — iOS 16+
// Add these two IPA files to your Xcode target's Copy Bundle Resources,
// renaming them exactly:
//   Nyxian.ipa
//   LiveContainer+SideStore.ipa
//
// Add your own Supabase project URL and anon/public key below.
// Never put a service-role key or account password in this app.
//
// Required Supabase setup SQL is included at the bottom of this file.

import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers
import UIKit
import Security

// MARK: - Configuration

enum ITConfig {
    static let supabaseURL = ""
    static let supabaseAnonKey = ""
    static let storageBucket = "itools-files"
    static let officialRepoSlug = "itools.official.repo"
}

// MARK: - Models

struct ITTool: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let description: String
    let symbol: String
    let localIPA: String?
    let webURL: String?

    static let all: [ITTool] = [
        .init(id: "livecontainer", name: "LiveContainer",
              subtitle: "Run compatible apps in a container",
              description: "A container environment for running compatible iOS apps. Check the project's documentation for supported versions and setup.",
              symbol: "shippingbox.fill", localIPA: nil,
              webURL: "https://github.com/LiveContainer/LiveContainer/releases"),
        .init(id: "sidestore", name: "SideStore",
              subtitle: "Sideload and refresh apps",
              description: "A sideloading tool with its own setup and refresh process. Follow the official guide for your iOS version.",
              symbol: "arrow.down.app.fill", localIPA: nil,
              webURL: "https://github.com/SideStore/SideStore/releases"),
        .init(id: "combined", name: "LiveContainer + SideStore",
              subtitle: "Combined setup",
              description: "A guide and IPA entry for using LiveContainer and SideStore together. They remain separate apps and need their own setup.",
              symbol: "square.stack.3d.up.fill",
              localIPA: "LiveContainer+SideStore", webURL: nil),
        .init(id: "nyxian", name: "Nyxian IPA",
              subtitle: "Your included Nyxian IPA",
              description: "Nyxian is presented as a LiveContainer-based, jailbreak-like experience, not a traditional jailbreak. Compatibility depends on the exact release. The included IPA reports a minimum iOS version of 18.0.",
              symbol: "bolt.shield.fill", localIPA: "Nyxian", webURL: nil),
        .init(id: "altstore", name: "AltStore",
              subtitle: "Alternative app sideloading",
              description: "Install compatible apps through AltStore's supported process. See the official site for current requirements.",
              symbol: "storefront.fill", localIPA: nil,
              webURL: "https://altstore.io")
    ]
}

struct ITRepo: Codable, Identifiable {
    let id: UUID
    let title: String
    let slug: String
    let is_public: Bool
    let owner_id: UUID?
}

struct ITRepoApp: Codable, Identifiable {
    let id: UUID
    let repo_id: UUID
    let name: String
    let description: String
    let ipa_url: String
    let icon_url: String?
}

struct ITAuthResult: Decodable {
    let access_token: String?
    let user: ITAuthUser?
}
struct ITAuthUser: Decodable {
    let id: UUID
}

// MARK: - Supabase REST client

@MainActor
final class ITCloud: ObservableObject {
    @Published var token: String?
    @Published var accountEmail: String?
    @Published var publicRepos: [ITRepo] = []
    @Published var selectedRepoApps: [ITRepoApp] = []
    @Published var message: String?

    private var base: String { ITConfig.supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    private var configured: Bool {
        !ITConfig.supabaseURL.isEmpty &&
        !ITConfig.supabaseAnonKey.isEmpty &&
        !ITConfig.supabaseURL.contains("YOUR-PROJECT") &&
        !ITConfig.supabaseAnonKey.contains("YOUR_")
    }

    private func makeRequest(path: String, method: String = "GET",
                             body: Data? = nil, contentType: String = "application/json",
                             extraHeaders: [String: String] = [:]) throws -> URLRequest {
        guard configured, let url = URL(string: base + path) else {
            throw NSError(domain: "iTools", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Add your Supabase URL and anon key in ITConfig first."])
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(ITConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        let credential = token ?? ITConfig.supabaseAnonKey
        request.setValue(
            ["Bearer", credential].joined(separator: " "),
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        extraHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw NSError(domain: "iToolsCloud", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: detail])
        }
        return data
    }

    func signUp(email: String, password: String) async {
        do {
            let body = try JSONSerialization.data(withJSONObject: [
                "email": email, "password": password
            ])
            let request = try makeRequest(path: "/auth/v1/signup", method: "POST", body: body)
            let data = try await send(request)
            let result = try JSONDecoder().decode(ITAuthResult.self, from: data)
            token = result.access_token
            accountEmail = email
            message = token == nil
                ? "Check your email to confirm your account, then sign in."
                : "Account created."
        } catch { message = error.localizedDescription }
    }

    func signIn(email: String, password: String) async {
        do {
            let body = try JSONSerialization.data(withJSONObject: [
                "email": email, "password": password
            ])
            let request = try makeRequest(
                path: "/auth/v1/token?grant_type=password",
                method: "POST", body: body
            )
            let data = try await send(request)
            let result = try JSONDecoder().decode(ITAuthResult.self, from: data)
            guard let newToken = result.access_token else {
                throw NSError(domain: "iTools", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Sign-in needs email confirmation or a valid account."])
            }
            token = newToken
            accountEmail = email
            message = "Signed in."
        } catch { message = error.localizedDescription }
    }

    func resetPassword(email: String) async {
        do {
            let body = try JSONSerialization.data(withJSONObject: ["email": email])
            let request = try makeRequest(
                path: "/auth/v1/recover",
                method: "POST",
                body: body
            )
            _ = try await send(request)
            message = "Password reset email sent. Open the link in your email to choose a new password."
        } catch {
            message = error.localizedDescription
        }
    }

    func signOut() {
        token = nil
        accountEmail = nil
        publicRepos = []
        selectedRepoApps = []
    }

    func fetchPublicRepos() async {
        if !configured {
            publicRepos = [
                ITRepo(
                    id: UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID(),
                    title: "iTools Official",
                    slug: ITConfig.officialRepoSlug,
                    is_public: true,
                    owner_id: nil
                )
            ]
            return
        }
        do {
            let request = try makeRequest(
                path: "/rest/v1/repos?select=id,title,slug,is_public,owner_id&is_public=eq.true&order=title.asc"
            )
            let data = try await send(request)
            publicRepos = try JSONDecoder().decode([ITRepo].self, from: data)
        } catch { message = error.localizedDescription }
    }

    func createRepo(title: String, slug: String, isPublic: Bool) async {
        do {
            let body = try JSONSerialization.data(withJSONObject: [
                "title": title, "slug": slug, "is_public": isPublic
            ])
            let request = try makeRequest(
                path: "/rest/v1/repos", method: "POST", body: body,
                extraHeaders: ["Prefer": "return=representation"]
            )
            _ = try await send(request)
            message = "Repository created."
            await fetchPublicRepos()
        } catch { message = error.localizedDescription }
    }

    func updateRepo(id: UUID, title: String, slug: String, isPublic: Bool) async {
        do {
            let body = try JSONSerialization.data(withJSONObject: [
                "title": title, "slug": slug, "is_public": isPublic
            ])
            let request = try makeRequest(
                path: "/rest/v1/repos?id=eq.\(id.uuidString)",
                method: "PATCH", body: body,
                extraHeaders: ["Prefer": "return=minimal"]
            )
            _ = try await send(request)
            message = "Repository updated."
            await fetchPublicRepos()
        } catch { message = error.localizedDescription }
    }

    func fetchApps(repoID: UUID) async {
        do {
            let request = try makeRequest(
                path: "/rest/v1/apps?select=id,repo_id,name,description,ipa_url,icon_url&repo_id=eq.\(repoID.uuidString)&order=name.asc"
            )
            let data = try await send(request)
            selectedRepoApps = try JSONDecoder().decode([ITRepoApp].self, from: data)
        } catch { message = error.localizedDescription }
    }

    func upload(data: Data, fileName: String, contentType: String) async throws -> String {
        let safeName = fileName.replacingOccurrences(of: "/", with: "_")
        let path = "\(UUID().uuidString)-\(safeName)"
        let request = try makeRequest(
            path: "/storage/v1/object/\(ITConfig.storageBucket)/\(path)",
            method: "POST", body: data, contentType: contentType,
            extraHeaders: ["x-upsert": "false"]
        )
        _ = try await send(request)
        return "\(base)/storage/v1/object/public/\(ITConfig.storageBucket)/\(path)"
    }

    func publishApp(repoID: UUID, name: String, description: String,
                    ipaData: Data, ipaName: String, iconData: Data?) async {
        do {
            let ipaURL = try await upload(
                data: ipaData, fileName: ipaName,
                contentType: "application/octet-stream"
            )
            var iconURL: String? = nil
            if let iconData {
                iconURL = try await upload(
                    data: iconData, fileName: "\(UUID().uuidString).jpg",
                    contentType: "image/jpeg"
                )
            }
            var object: [String: Any] = [
                "repo_id": repoID.uuidString,
                "name": name,
                "description": description,
                "ipa_url": ipaURL
            ]
            if let iconURL { object["icon_url"] = iconURL }
            let body = try JSONSerialization.data(withJSONObject: object)
            let request = try makeRequest(
                path: "/rest/v1/apps", method: "POST", body: body
            )
            _ = try await send(request)
            message = "App published to the repository."
            await fetchApps(repoID: repoID)
        } catch { message = error.localizedDescription }
    }
}

// MARK: - Main App

@main
struct iToolsApp: App {
    @StateObject private var cloud = ITCloud()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(cloud)
                .preferredColorScheme(.dark)
                .tint(.cyan)
        }
    }
}

struct ITMainView: View {
    @EnvironmentObject var cloud: ITCloud
    var body: some View {
        TabView {
            ITHomeView().tabItem { Label("Home", systemImage: "house.fill") }
            ITToolsView().tabItem { Label("Apps", systemImage: "square.grid.2x2.fill") }
            ITSourcesView().tabItem { Label("Sources", systemImage: "shippingbox.fill") }
            ITAccountView().tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .alert("iTools", isPresented: Binding(
            get: { cloud.message != nil },
            set: { if !$0 { cloud.message = nil } }
        )) {
            Button("OK") { cloud.message = nil }
        } message: { Text(cloud.message ?? "") }
    }
}

struct ITHomeView: View {
    @EnvironmentObject var cloud: ITCloud
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("iTools").font(.system(size: 38, weight: .bold))
                    Text("Apps, sources and community repositories.")
                        .foregroundStyle(.secondary)
                    HStack {
                        stat("Apps", "\(ITTool.all.count)", "square.grid.2x2")
                        stat("Public sources", "\(cloud.publicRepos.count)", "globe")
                    }
                    Text("Featured apps").font(.title2.bold())
                    ForEach(ITTool.all) { tool in
                        NavigationLink { ITToolDetailView(tool: tool) } label: {
                            ITToolRow(tool: tool)
                        }.buttonStyle(.plain)
                    }
                    NavigationLink("Scan an IPA") { ITScannerView() }
                        .buttonStyle(.borderedProminent)
                    Text("Only install files you trust. A basic scan cannot prove an IPA is safe.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.navigationTitle("Home")
        }
        .task { await cloud.fetchPublicRepos() }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading) {
            Image(systemName: icon).foregroundStyle(.cyan)
            Text(value).font(.largeTitle.bold())
            Text(title).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
    }
}

struct ITToolsView: View {
    @State private var search = ""
    private var filtered: [ITTool] {
        search.isEmpty ? ITTool.all : ITTool.all.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.subtitle.localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        NavigationStack {
            List(filtered) { tool in
                NavigationLink { ITToolDetailView(tool: tool) } label: {
                    ITToolRow(tool: tool)
                }
            }
            .navigationTitle("Apps")
            .searchable(text: $search)
        }
    }
}

struct ITToolRow: View {
    let tool: ITTool
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: tool.symbol)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 54, height: 54)
                .background(.cyan.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name).font(.headline).foregroundStyle(.primary)
                Text(tool.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 5)
    }
}

struct ITToolDetailView: View {
    @EnvironmentObject var cloud: ITCloud
    let tool: ITTool
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var downloading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 58)).foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                Text(tool.name).font(.largeTitle.bold())
                Text(tool.description).foregroundStyle(.secondary)
                Button {
                    getApp()
                } label: {
                    HStack {
                        if downloading { ProgressView().tint(.white) }
                        Text("Get")
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(downloading)

                if let urlString = tool.webURL, let url = URL(string: urlString) {
                    Link("Open official project page", destination: url)
                        .buttonStyle(.bordered)
                }
                if tool.id == "nyxian" {
                    Text("Included Nyxian IPA: version 0.11.6.1. Its embedded Info.plist declares minimum iOS 18.0.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("iOS does not let a normal app install an IPA directly. Get shares the IPA so you can open it with a compatible sideloading tool.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }.padding()
        }
        .navigationTitle(tool.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let shareURL { ITShareSheet(items: [shareURL]) }
        }
    }

    private func getApp() {
        if let resource = tool.localIPA,
           let file = Bundle.main.url(forResource: resource, withExtension: "ipa") {
            shareURL = file
            showShare = true
            return
        }
        if let string = tool.webURL, let url = URL(string: string) {
            UIApplication.shared.open(url)
        } else {
            cloud.message = "The IPA resource is missing. Add the IPA to Copy Bundle Resources in Xcode."
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

// MARK: - Sources and repositories

struct ITSourcesView: View {
    @EnvironmentObject var cloud: ITCloud
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            List {
                Section("Official source") {
                    NavigationLink {
                        ITOfficialRepoView()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.cyan)
                            VStack(alignment: .leading) {
                                Text("iTools Official").font(.headline)
                                Text(ITConfig.officialRepoSlug).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Public community repositories") {
                    if cloud.publicRepos.isEmpty {
                        Text("No public community repositories loaded.").foregroundStyle(.secondary)
                    }
                    ForEach(cloud.publicRepos) { repo in
                        NavigationLink {
                            ITRepoDetailView(repo: repo)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(repo.title).font(.headline)
                                Text(repo.slug).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sources")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .refreshable { await cloud.fetchPublicRepos() }
            .sheet(isPresented: $showCreate) { ITCreateRepoView() }
        }
    }
}

struct ITOfficialRepoView: View {
    @EnvironmentObject var cloud: ITCloud
    @State private var repo: ITRepo?
    @State private var apps: [ITRepoApp] = []
    var body: some View {
        List {
            Section {
                Text("iTools Official")
                    .font(.title2.bold())
                Text("Official public repository: \(ITConfig.officialRepoSlug)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Apps") {
                if apps.isEmpty { Text("The official repository has not been connected yet.") }
                ForEach(apps) { app in
                    ITPublishedAppRow(app: app)
                }
            }
        }
        .navigationTitle("iTools Official")
        .task {
            await cloud.fetchPublicRepos()
            repo = cloud.publicRepos.first { $0.slug == ITConfig.officialRepoSlug }
            if let repo { await cloud.fetchApps(repoID: repo.id); apps = cloud.selectedRepoApps }
        }
    }
}

struct ITCreateRepoView: View {
    @EnvironmentObject var cloud: ITCloud
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var slug = ""
    @State private var isPublic = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Repository details") {
                    TextField("Repository name", text: $title)
                    TextField("Unique link / slug", text: $slug)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Make repository public", isOn: $isPublic)
                }
                Section {
                    Text("Public repositories can be discovered by other iTools users. Only upload apps and artwork you have permission to distribute.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Create repository") {
                    Task {
                        await cloud.createRepo(title: title, slug: slug, isPublic: isPublic)
                        dismiss()
                    }
                }
                .disabled(title.isEmpty || slug.isEmpty || cloud.token == nil)
            }
            .navigationTitle("New repository")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct ITRepoDetailView: View {
    @EnvironmentObject var cloud: ITCloud
    @Environment(\.dismiss) var dismiss
    let repo: ITRepo
    @State private var apps: [ITRepoApp] = []
    @State private var showUpload = false
    @State private var showEdit = false

    var body: some View {
        List {
            Section {
                Text(repo.title).font(.title2.bold())
                Text(repo.slug).font(.caption).foregroundStyle(.secondary)
                Label(repo.is_public ? "Public repository" : "Private repository",
                      systemImage: repo.is_public ? "globe" : "lock")
            }
            Section("Apps") {
                if apps.isEmpty { Text("No apps published yet.") }
                ForEach(apps) { ITPublishedAppRow(app: $0) }
            }
            if cloud.token != nil {
                Section {
                    Button { showUpload = true } label: {
                        Label("Upload app / IPA", systemImage: "plus.app.fill")
                    }
                    Button { showEdit = true } label: {
                        Label("Edit repository", systemImage: "pencil")
                    }
                }
            }
        }
        .navigationTitle("Repository")
        .task { await cloud.fetchApps(repoID: repo.id); apps = cloud.selectedRepoApps }
        .sheet(isPresented: $showUpload) { ITUploadAppView(repo: repo) }
        .sheet(isPresented: $showEdit) { ITEditRepoView(repo: repo) }
    }
}

struct ITPublishedAppRow: View {
    let app: ITRepoApp
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: app.icon_url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "app.fill").foregroundStyle(.cyan)
            }
            .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading) {
                Text(app.name).font(.headline)
                Text(app.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let url = URL(string: app.ipa_url) { Link("Get", destination: url) }
            }
        }
    }
}

struct ITEditRepoView: View {
    @EnvironmentObject var cloud: ITCloud
    @Environment(\.dismiss) var dismiss
    let repo: ITRepo
    @State private var title = ""
    @State private var slug = ""
    @State private var isPublic = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("Repository name", text: $title)
                TextField("Repository link / slug", text: $slug)
                    .textInputAutocapitalization(.never)
                Toggle("Public", isOn: $isPublic)
                Button("Save changes") {
                    Task {
                        await cloud.updateRepo(id: repo.id, title: title, slug: slug, isPublic: isPublic)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit repository")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
            .onAppear {
                title = repo.title
                slug = repo.slug
                isPublic = repo.is_public
            }
        }
    }
}

struct ITUploadAppView: View {
    @EnvironmentObject var cloud: ITCloud
    @Environment(\.dismiss) var dismiss
    let repo: ITRepo
    @State private var name = ""
    @State private var description = ""
    @State private var ipaData: Data?
    @State private var ipaName = ""
    @State private var iconData: Data?
    @State private var showingIPA = false
    @State private var showingIcon = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                appInformationSection
                fileSelectionSection
                publishButton
            }
            .navigationTitle("Upload app")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
            .fileImporter(isPresented: $showingIPA,
                          allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
                          onCompletion: importIPA)
            .fileImporter(isPresented: $showingIcon,
                          allowedContentTypes: [.image],
                          onCompletion: importIcon)
        }
    }

    private var appInformationSection: some View {
        Section("App information") {
            TextField("App name", text: $name)
            TextField("Description", text: $description, axis: .vertical)
        }
    }

    private var fileSelectionSection: some View {
        Section("Files") {
            Button { showingIPA = true } label: {
                Label(ipaName.isEmpty ? "Choose IPA file" : ipaName,
                      systemImage: "doc.zipper")
            }
            Button { showingIcon = true } label: {
                Label(iconData == nil ? "Choose app icon image" : "Icon selected",
                      systemImage: "photo")
            }
        }
    }

    private var publishButton: some View {
        Button(action: publishApp) {
            HStack {
                if busy { ProgressView() }
                Text("Publish app")
            }
        }
        .disabled(name.isEmpty || ipaData == nil || cloud.token == nil || busy)
    }

    private func publishApp() {
        guard let ipaData else { return }
        busy = true
        Task {
            await cloud.publishApp(
                repoID: repo.id,
                name: name,
                description: description,
                ipaData: ipaData,
                ipaName: ipaName,
                iconData: iconData
            )
            busy = false
            dismiss()
        }
    }

    private func importIPA(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            ipaData = try Data(contentsOf: url)
            ipaName = url.lastPathComponent
        } catch {
            cloud.message = error.localizedDescription
        }
    }

    private func importIcon(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let image = UIImage(data: try Data(contentsOf: url)),
                  let jpeg = image.jpegData(compressionQuality: 0.85) else {
                throw NSError(
                    domain: "iTools",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey: "The selected icon image could not be read."
                    ]
                )
            }
            iconData = jpeg
        } catch {
            cloud.message = error.localizedDescription
        }
    }
}

// MARK: - Account

struct ITAccountView: View {
    @EnvironmentObject var cloud: ITCloud
    @State private var email = ""
    @State private var password = ""
    @State private var createAccount = false

    var body: some View {
        NavigationStack {
            Form {
                if cloud.token == nil {
                    Section(createAccount ? "Create account" : "Sign in") {
                        TextField("Email address", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                        Button(createAccount ? "Create account" : "Sign in") {
                            Task {
                                if createAccount {
                                    await cloud.signUp(email: email, password: password)
                                } else {
                                    await cloud.signIn(email: email, password: password)
                                }
                                password = ""
                            }
                        }
                        .disabled(email.isEmpty || password.count < 6)
                        if !createAccount {
                            Button("Forgot password?") {
                                Task {
                                    await cloud.resetPassword(
                                        email: email.trimmingCharacters(in: .whitespacesAndNewlines)
                                    )
                                }
                            }
                            .disabled(!email.contains("@"))
                        }
                        Button(createAccount ? "I already have an account" : "Create a new account") {
                            createAccount.toggle()
                        }
                        if let message = cloud.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("Account") {
                        Label("Signed in", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Account status: active")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Your account name and password are hidden in Settings.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Sign out", role: .destructive) { cloud.signOut() }
                    }
                }
                Section("Privacy") {
                    Text("Passwords are sent only to your configured authentication provider over HTTPS. They are never written into the app source or displayed in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Account")
        }
    }
}

// MARK: - Simple IPA scanner

struct ITScannerView: View {
    @State private var showingPicker = false
    @State private var report = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("IPA quick check").font(.largeTitle.bold())
            Text("Checks the IPA archive structure and selected suspicious file-path terms. It cannot detect all malware or certify safety.")
                .foregroundStyle(.secondary)
            Button("Choose IPA") { showingPicker = true }.buttonStyle(.borderedProminent)
            Text(report).font(.callout)
            Spacer()
        }.padding()
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let text = String(decoding: data.prefix(2_000_000), as: UTF8.self).lowercased()
                let terms = ["keylogger", "stealer", "backdoor", "exfiltrate"]
                let hits = terms.filter { text.contains($0) }
                report = hits.isEmpty
                    ? "No obvious keyword indicators found. This does NOT mean the IPA is safe."
                    : "Warning: found keyword indicators: \(hits.joined(separator: ", ")). Review this IPA carefully."
            } catch { report = error.localizedDescription }
        }
    }
}

/*
SUPABASE SETUP — run this SQL in your Supabase SQL Editor.

create table public.repos (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  slug text not null unique,
  is_public boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.apps (
  id uuid primary key default gen_random_uuid(),
  repo_id uuid not null references public.repos(id) on delete cascade,
  name text not null,
  description text not null default '',
  ipa_url text not null,
  icon_url text,
  created_at timestamptz not null default now()
);

alter table public.repos enable row level security;
alter table public.apps enable row level security;

create policy "public repos are readable"
on public.repos for select using (is_public = true or auth.uid() = owner_id);

create policy "users create their own repos"
on public.repos for insert with check (auth.uid() = owner_id);

create policy "owners update repos"
on public.repos for update using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

create policy "apps in public repos are readable"
on public.apps for select using (
  exists (select 1 from public.repos r
          where r.id = repo_id and (r.is_public = true or r.owner_id = auth.uid()))
);

create policy "owners publish apps"
on public.apps for insert with check (
  exists (select 1 from public.repos r
          where r.id = repo_id and r.owner_id = auth.uid())
);

-- Create a Storage bucket named itools-files and set it to PUBLIC.
-- For production, add Storage policies so authenticated users can upload,
-- and validate file size/type on the server.
--
-- Create the pre-added official repo record from a trusted admin session:
-- title = 'iTools Official'
-- slug = 'itools.official.repo'
-- is_public = true
-- owner_id = the UUID of the official publisher account.
--
-- IMPORTANT: the app must use the Supabase anon/public key only.
-- Never use a service_role key in an iOS app. The account password supplied
-- in chat is intentionally not embedded in this source.
*/
