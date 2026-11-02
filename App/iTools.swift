// File: iTools.swift
// iTools — iOS 16 and later
//
// Add the ZIPFoundation package to your Xcode project:
// https://github.com/weichsel/ZIPFoundation
//
// IMPORTANT:
// iOS apps cannot silently install or update other apps.
// This app can download IPA files, inspect them, and share them
// to a compatible sideloading app such as SideStore or AltStore.

import SwiftUI
import Foundation
import Combine
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import ZIPFoundation

// MARK: - App Entry

@main
struct iToolsApp: App {
    @StateObject private var store = ITStore()

    var body: some Scene {
        WindowGroup {
            ITMainView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(.cyan)
        }
    }
}

// MARK: - Models

struct ITTool: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String
    let details: String
    let downloadURL: String
    let githubRepo: String?
    let category: String

    static let builtIn: [ITTool] = [
        ITTool(
            id: "livecontainer",
            name: "LiveContainer",
            description: "Run compatible apps inside a container environment.",
            details: """
            LiveContainer is an iOS app that provides a container environment
            for running compatible apps. Check its official project page for
            installation instructions and supported iOS versions.
            """,
            downloadURL: "https://github.com/LiveContainer/LiveContainer/releases",
            githubRepo: "LiveContainer/LiveContainer",
            category: "Sideloading"
        ),
        ITTool(
            id: "sidestore",
            name: "SideStore",
            description: "An alternative way to sideload apps on iOS.",
            details: """
            SideStore helps install and refresh apps on iOS using your own
            Apple account and the supported SideStore setup process.
            Follow the official installation guide.
            """,
            downloadURL: "https://github.com/SideStore/SideStore/releases",
            githubRepo: "SideStore/SideStore",
            category: "Sideloading"
        ),
        ITTool(
            id: "livecontainer-sidestore",
            name: "LiveContainer + SideStore",
            description: "A combined setup guide for using both tools.",
            details: """
            This entry explains how LiveContainer and SideStore can be used
            together. They remain separate apps with separate installation
            and configuration steps. Read both projects' documentation
            before setting up the combination.
            """,
            downloadURL: "https://github.com/SideStore/SideStore",
            githubRepo: nil,
            category: "Setup"
        ),
        ITTool(
            id: "nyxian",
            name: "Nyxian IPA",
            description: "A LiveContainer-based, jailbreak-like experience.",
            details: """
            Nyxian is described by its publisher as a jailbreak-like
            experience built around LiveContainer. It is not a traditional
            device jailbreak and does not mean that iOS security protections
            have been removed.

            Compatibility with iOS 26 through 27.2, or any other version,
            must be confirmed against the actual Nyxian release. This app
            does not guarantee compatibility.
            """,
            downloadURL: "",
            githubRepo: nil,
            category: "Experimental"
        ),
        ITTool(
            id: "altstore",
            name: "AltStore",
            description: "A popular alternative app sideloading platform.",
            details: """
            AltStore lets users install compatible apps using its supported
            installation process. See the official website for current
            requirements and setup instructions.
            """,
            downloadURL: "https://altstore.io",
            githubRepo: "altstoreio/AltStore",
            category: "Sideloading"
        )
    ]
}

struct ITRelease: Decodable {
    let tag_name: String?
    let name: String?
    let html_url: String?
    let published_at: String?
}

struct ITSourceManifest: Codable {
    let name: String
    let description: String?
    let apps: [ITSourceApp]
}

struct ITSourceApp: Codable, Identifiable {
    var id: String { name }

    let name: String
    let description: String
    let downloadURL: String
    let version: String?
}

struct ITSource: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var apps: [ITSourceApp] = []
    var lastUpdated: Date?
}

struct ITReleaseStatus: Identifiable {
    var id: String { toolID }
    let toolID: String
    let toolName: String
    let version: String
    let releaseURL: String
    let publishedAt: String?
}

struct ITScanResult {
    let fileName: String
    let findings: [String]
    let inspectedFiles: Int

    var summary: String {
        findings.isEmpty
        ? "No obvious indicators found. This does not prove the IPA is safe."
        : "Potential warning signs were found. Review before installing."
    }
}

// MARK: - Main Store

@MainActor
final class ITStore: ObservableObject {
    @Published var tools: [ITTool] = ITTool.builtIn
    @Published var sources: [ITSource] = []
    @Published var releases: [ITReleaseStatus] = []
    @Published var isCheckingReleases = false
    @Published var statusMessage: String?
    @Published var downloadedFile: URL?

    private let sourcesKey = "itools.sources"

    init() {
        loadSources()
    }

    func checkReleases() async {
        guard !isCheckingReleases else { return }

        isCheckingReleases = true
        releases = []

        defer {
            isCheckingReleases = false
        }

        for tool in tools {
            guard let repo = tool.githubRepo,
                  let url = URL(string:
                    "https://api.github.com/repos/\(repo)/releases/latest"
                  ) else {
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.setValue(
                    "iTools-iOS-App",
                    forHTTPHeaderField: "User-Agent"
                )

                let (data, _) = try await URLSession.shared.data(for: request)
                let release = try JSONDecoder().decode(
                    ITRelease.self,
                    from: data
                )

                guard let version = release.tag_name,
                      let releaseURL = release.html_url else {
                    continue
                }

                releases.append(
                    ITReleaseStatus(
                        toolID: tool.id,
                        toolName: tool.name,
                        version: version,
                        releaseURL: releaseURL,
                        publishedAt: release.published_at
                    )
                )
            } catch {
                statusMessage = "Some release checks could not be completed."
            }
        }
    }

    func downloadIPA(from string: String) async {
        guard let url = URL(string: string),
              url.scheme == "https" else {
            statusMessage = "This download link is invalid or not HTTPS."
            return
        }

        do {
            let (temporaryURL, response) =
                try await URLSession.shared.download(from: url)

            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                statusMessage = "The download failed."
                return
            }

            let destination = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent(url.lastPathComponent)

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.moveItem(
                at: temporaryURL,
                to: destination
            )

            downloadedFile = destination
            statusMessage = "Download complete."
        } catch {
            statusMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    func addSource(url: String) async {
        guard let sourceURL = URL(string: url),
              sourceURL.scheme == "https" else {
            statusMessage = "Please enter a valid HTTPS source URL."
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: sourceURL)
            let manifest = try JSONDecoder().decode(
                ITSourceManifest.self,
                from: data
            )

            let source = ITSource(
                name: manifest.name,
                url: url,
                apps: manifest.apps,
                lastUpdated: Date()
            )

            sources.removeAll { $0.url == url }
            sources.append(source)
            saveSources()

            statusMessage = "Source added."
        } catch {
            statusMessage = "Could not read source: \(error.localizedDescription)"
        }
    }

    func removeSource(_ source: ITSource) {
        sources.removeAll { $0.id == source.id }
        saveSources()
    }

    private func loadSources() {
        guard let data = UserDefaults.standard.data(forKey: sourcesKey),
              let decoded = try? JSONDecoder().decode(
                [ITSource].self,
                from: data
              ) else {
            return
        }

        sources = decoded
    }

    private func saveSources() {
        guard let data = try? JSONEncoder().encode(sources) else {
            return
        }

        UserDefaults.standard.set(data, forKey: sourcesKey)
    }
}

// MARK: - Main Interface

struct ITMainView: View {
    @EnvironmentObject private var store: ITStore
    @State private var showingHelp = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView {
                ITHomeView()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }

                ITToolsView()
                    .tabItem {
                        Label("Tools", systemImage: "square.grid.2x2")
                    }

                ITSourcesView()
                    .tabItem {
                        Label("Sources", systemImage: "externaldrive")
                    }

                ITSettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }

            Button {
                showingHelp = true
            } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 58, height: 58)
                    .background(.cyan, in: Circle())
                    .shadow(radius: 8)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 75)
            .accessibilityLabel("Open Helpy assistant")
        }
        .sheet(isPresented: $showingHelp) {
            ITHelpyView()
        }
        .alert(
            "iTools",
            isPresented: Binding(
                get: { store.statusMessage != nil },
                set: { if !$0 { store.statusMessage = nil } }
            )
        ) {
            Button("OK") {
                store.statusMessage = nil
            }
        } message: {
            Text(store.statusMessage ?? "")
        }
    }
}

// MARK: - Home

struct ITHomeView: View {
    @EnvironmentObject private var store: ITStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iTools")
                            .font(.system(size: 38, weight: .bold))

                        Text("Your iOS tools, guides and downloads.")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        ITStatCard(
                            title: "Tools",
                            value: "\(store.tools.count)",
                            icon: "square.grid.2x2"
                        )

                        ITStatCard(
                            title: "Sources",
                            value: "\(store.sources.count)",
                            icon: "externaldrive"
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Featured tools")
                            .font(.title2.bold())

                        ForEach(store.tools.prefix(3)) { tool in
                            NavigationLink {
                                ITToolDetailView(tool: tool)
                            } label: {
                                ITToolRow(tool: tool)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Safety reminder", systemImage: "shield.lefthalf.filled")
                            .font(.headline)

                        Text("""
                        Only install IPA files from sources you trust.
                        A scan cannot guarantee that an app is safe.
                        """)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }
                .padding()
            }
            .navigationTitle("Home")
        }
    }
}

struct ITStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.cyan)

            Text(value)
                .font(.largeTitle.bold())

            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Tools Catalogue

struct ITToolsView: View {
    @EnvironmentObject private var store: ITStore
    @State private var searchText = ""

    private var filteredTools: [ITTool] {
        guard !searchText.isEmpty else { return store.tools }

        return store.tools.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredTools) { tool in
                NavigationLink {
                    ITToolDetailView(tool: tool)
                } label: {
                    ITToolRow(tool: tool)
                        .padding(.vertical, 5)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, prompt: "Search tools")
            .navigationTitle("Tools")
        }
    }
}

struct ITToolRow: View {
    let tool: ITTool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "app.fill")
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 48, height: 48)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tool Details

struct ITToolDetailView: View {
    @EnvironmentObject private var store: ITStore
    let tool: ITTool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "app.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 25)

                Text(tool.name)
                    .font(.largeTitle.bold())

                Text(tool.category.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)

                Text(tool.details)
                    .foregroundStyle(.secondary)

                if !tool.downloadURL.isEmpty,
                   let url = URL(string: tool.downloadURL) {
                    Link(destination: url) {
                        Label("Open official download page", systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if tool.id == "nyxian" {
                    NavigationLink("View Nyxian installation guide") {
                        ITNyxianGuideView()
                    }
                    .buttonStyle(.bordered)
                }

                if let repo = tool.githubRepo {
                    let release = store.releases.first {
                        $0.toolID == tool.id
                    }

                    if let release {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Latest GitHub release")
                                .font(.headline)

                            Text(release.version)
                                .foregroundStyle(.cyan)

                            if let url = URL(string: release.releaseURL) {
                                Link("View release", destination: url)
                            }
                        }
                    } else {
                        Text("GitHub release: \(repo)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("""
                iOS does not allow this app to install or silently update
                another app by itself. Download the IPA and use a compatible
                sideloading tool to install it.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .navigationTitle(tool.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sources

struct ITSourcesView: View {
    @EnvironmentObject private var store: ITStore
    @State private var sourceURL = ""
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add a community source")
                            .font(.headline)

                        TextField("https://example.com/source.json", text: $sourceURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()

                        Button {
                            Task {
                                isAdding = true
                                await store.addSource(url: sourceURL)
                                sourceURL = ""
                                isAdding = false
                            }
                        } label: {
                            HStack {
                                if isAdding {
                                    ProgressView()
                                }

                                Text("Add source")
                            }
                        }
                        .disabled(sourceURL.isEmpty || isAdding)
                    }
                    .padding(.vertical, 6)
                }

                Section("Community sources") {
                    if store.sources.isEmpty {
                        Text("No community sources added yet.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(store.sources) { source in
                        NavigationLink {
                            ITSourceDetailView(source: source)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name)
                                    .font(.headline)

                                Text(source.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Text("\(source.apps.count) apps")
                                    .font(.caption)
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            store.removeSource(store.sources[index])
                        }
                    }
                }

                Section {
                    Text("""
                    Community sources are not verified by iTools.
                    A source can provide misleading links or unsafe files.
                    Only add sources you trust.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sources")
        }
    }
}

struct ITSourceDetailView: View {
    let source: ITSource

    var body: some View {
        List {
            Section {
                Text(source.name)
                    .font(.headline)

                Text(source.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apps") {
                if source.apps.isEmpty {
                    Text("This source has no apps.")
                }

                ForEach(source.apps) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.name)
                            .font(.headline)

                        Text(app.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let version = app.version {
                            Text("Version: \(version)")
                                .font(.caption)
                        }

                        if let url = URL(string: app.downloadURL) {
                            Link("Open download", destination: url)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Settings and Release Checker

struct ITSettingsView: View {
    @EnvironmentObject private var store: ITStore

    var body: some View {
        NavigationStack {
            List {
                Section("Updates") {
                    Button {
                        Task {
                            await store.checkReleases()
                        }
                    } label: {
                        HStack {
                            Label("Check GitHub releases", systemImage: "arrow.clockwise")
                            Spacer()

                            if store.isCheckingReleases {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(store.isCheckingReleases)

                    if store.releases.isEmpty && !store.isCheckingReleases {
                        Text("No release information loaded yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(store.releases) { release in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(release.toolName)
                                .font(.headline)

                            Text(release.version)
                                .foregroundStyle(.cyan)

                            if let url = URL(string: release.releaseURL) {
                                Link("View release", destination: url)
                                    .font(.caption)
                            }
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "iTools")
                    LabeledContent("Minimum iOS", value: "16.0")
                    LabeledContent("Version", value: "1.0")
                }

                Section("Important") {
                    Text("""
                    iTools cannot silently install, sign, or update other apps.
                    Release checks only notify you of available releases.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - IPA Scanner

enum ITIPAScanner {
    static func scan(url: URL) throws -> ITScanResult {
        guard url.pathExtension.lowercased() == "ipa" else {
            throw NSError(
                domain: "iToolsScanner",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Please select an IPA file."
                ]
            )
        }

        let archive = try Archive(url: url, accessMode: .read)

        var findings: [String] = []
        var inspectedFiles = 0

        let suspiciousTerms = [
            "keylogger",
            "stealer",
            "credential",
            "exfiltrate",
            "backdoor"
        ]

        for entry in archive {
            inspectedFiles += 1

            let lowerName = entry.path.lowercased()

            if lowerName.contains("embedded.mobileprovision") {
                findings.append(
                    "Contains an embedded provisioning profile."
                )
            }

            if lowerName.contains("cydia") ||
               lowerName.contains("substrate") {
                findings.append(
                    "Contains a path associated with jailbreak tooling."
                )
            }

            if suspiciousTerms.contains(where: {
                lowerName.contains($0)
            }) {
                findings.append(
                    "A file path contains a suspicious keyword: \(entry.path)"
                )
            }

            if inspectedFiles >= 10000 {
                findings.append(
                    "Scan stopped at the 10,000-file inspection limit."
                )
                break
            }
        }

        return ITScanResult(
            fileName: url.lastPathComponent,
            findings: Array(Set(findings)),
            inspectedFiles: inspectedFiles
        )
    }
}

struct ITScannerView: View {
    @State private var showingImporter = false
    @State private var result: ITScanResult?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("IPA Scanner")
                .font(.largeTitle.bold())

            Text("""
            Inspect an IPA archive for basic file and path indicators.
            This is not a malware scanner and cannot prove that an IPA is safe.
            """)
            .foregroundStyle(.secondary)

            Button {
                showingImporter = true
            } label: {
                Label("Choose IPA file", systemImage: "doc.badge.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let result {
                VStack(alignment: .leading, spacing: 8) {
                    Text(result.fileName)
                        .font(.headline)

                    Text(result.summary)
                        .foregroundStyle(.cyan)

                    Text("Files inspected: \(result.inspectedFiles)")
                        .font(.caption)

                    ForEach(result.findings, id: \.self) { finding in
                        Label(finding, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                    }
                }
                .padding()
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "ipa") ?? .data
            ],
            allowsMultipleSelection: false
        ) { response in
            do {
                guard let url = try response.get().first else {
                    return
                }

                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                result = try ITIPAScanner.scan(url: url)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Nyxian Guide

struct ITNyxianGuideView: View {
    var body: some View {
        List {
            Section("Method 1 — Sideload the IPA") {
                ITGuideStep(
                    number: "1",
                    title: "Get the official Nyxian IPA",
                    detail: "Download the IPA from the project's official release page."
                )

                ITGuideStep(
                    number: "2",
                    title: "Open SideStore or AltStore",
                    detail: "Use the sideloading app's supported IPA installation process."
                )

                ITGuideStep(
                    number: "3",
                    title: "Install Nyxian",
                    detail: "Follow the installation prompts shown by your sideloading app."
                )

                ITGuideStep(
                    number: "4",
                    title: "Follow Nyxian's setup instructions",
                    detail: "If the release provides certificate export or setup features, follow its own documentation. These steps may differ by version."
                )
            }

            Section("Method 2 — Developer certificate") {
                ITGuideStep(
                    number: "1",
                    title: "Obtain legitimate signing files",
                    detail: "You need a valid developer certificate and its matching provisioning profile. Only use certificates you are authorized to use."
                )

                ITGuideStep(
                    number: "2",
                    title: "Download the files",
                    detail: "A certificate may be supplied as a .p12 file and a provisioning profile as a .mobileprovision file."
                )

                ITGuideStep(
                    number: "3",
                    title: "Use a compatible signing app",
                    detail: "Install and configure a trusted signing tool, such as a compatible release of Feather or ESign."
                )

                ITGuideStep(
                    number: "4",
                    title: "Import and sign",
                    detail: "Import your certificate and provisioning profile, then sign the IPA if your certificate and profile support it."
                )

                ITGuideStep(
                    number: "5",
                    title: "Install the signed app",
                    detail: "Use the signing app's installation flow and follow any iOS trust prompts."
                )
            }

            Section("Important safety notes") {
                Text("""
                Never share your Apple ID password, certificate password,
                private keys or account credentials with a source or stranger.
                A paid certificate is not automatically legitimate or safe.
                Check the certificate provider and the current Nyxian release
                documentation before proceeding.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Nyxian Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ITGuideStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(.cyan, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Helpy Assistant

struct ITHelpyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer = """
    Hi! I'm Helpy. Ask me about SideStore, AltStore, LiveContainer,
    Nyxian, IPA files, certificates, or ROMs.
    """

    private let faq: [(keywords: [String], answer: String)] = [
        (
            ["sidestore", "side store"],
            """
            SideStore is a sideloading tool. Start with its official
            documentation and follow the installation steps for your iOS
            version. You may need a computer for initial setup.
            """
        ),
        (
            ["altstore", "alt store"],
            """
            AltStore installs compatible apps using its supported setup.
            Visit altstore.io for the current installation instructions.
            """
        ),
        (
            ["livecontainer", "live container"],
            """
            LiveContainer provides a container environment for compatible
            apps. Check its official project documentation for setup and
            compatibility details.
            """
        ),
        (
            ["nyxian"],
            """
            Nyxian is described here as a LiveContainer-based jailbreak-like
            experience, not a traditional jailbreak. Check the specific
            release documentation for compatibility and installation steps.
            """
        ),
        (
            ["certificate", "p12", "mobileprovision", "signing"],
            """
            A .p12 file contains a signing certificate and private key.
            A .mobileprovision file contains provisioning information.
            Keep private keys and passwords secret. Only use certificates
            you are authorized to use.
            """
        ),
        (
            ["ipa", "install"],
            """
            An IPA is an iOS app package. You generally need a compatible
            signing and sideloading method to install it. iTools itself
            cannot install arbitrary IPAs directly.
            """
        ),
        (
            ["rom", "boot", "flash"],
            """
            ROM flashing depends on the device and firmware. Back up your
            data, verify the exact device model and firmware file, and use
            the manufacturer's official instructions. Flashing the wrong
            file can make a device unusable.
            """
        ),
        (
            ["safe", "virus", "malware", "scan"],
            """
            No basic IPA scan can prove a file is safe. Prefer official
            releases, verify publisher information, and avoid unknown
            repositories or modified apps.
            """
        )
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Helpy")
                            .font(.largeTitle.bold())

                        Text(answer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding()
                }

                HStack {
                    TextField("Ask Helpy something...", text: $question)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            sendQuestion()
                        }

                    Button {
                        sendQuestion()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(.cyan)
                    }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func sendQuestion() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let lower = text.lowercased()

        if let match = faq.first(where: {
            $0.keywords.contains(where: { lower.contains($0) })
        }) {
            answer = match.answer
        } else {
            answer = """
            I don't have a reliable answer for that yet. Check the official
            documentation for the tool or device you're using. Tell me whether
            your question is about installation, signing, compatibility,
            IPA files or ROM flashing and I can point you in the right direction.
            """
        }

        question = ""
    }
}

// MARK: - Share Downloaded File

struct ITActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context
    ) {}
}

// MARK: - Download and Scan Screen

struct ITDownloadToolsView: View {
    @EnvironmentObject private var store: ITStore
    @State private var showingShare = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Downloads")
                .font(.largeTitle.bold())

            if let file = store.downloadedFile {
                Text(file.lastPathComponent)
                    .font(.headline)

                Button {
                    showingShare = true
                } label: {
                    Label("Share downloaded IPA", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $showingShare) {
                    ITActivityView(items: [file])
                }
            } else {
                Text("No downloads yet.")
                    .foregroundStyle(.secondary)
            }

            NavigationLink("Open IPA Scanner") {
                ITScannerView()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }
}