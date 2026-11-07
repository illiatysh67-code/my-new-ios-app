import SwiftUI

enum ITTheme {
    static let defaultAccent = "#1687FF"

    static func background(hex: String, scheme: ColorScheme) -> Color {
        hex.isEmpty ? (scheme == .dark ? .black : .white) : Color(hex: hex)
    }
}

struct ITAppRootView: View {
    @AppStorage("itools.onboarding.complete") private var setupComplete = false
    @AppStorage("itools.accentHex") private var accentHex = ITTheme.defaultAccent
    @State private var showLaunchSplash = false
    @State private var launchScale: CGFloat = 1
    @State private var launchOpacity = 1.0
    @State private var homeScale: CGFloat = 0.78
    @State private var homeOpacity = 0.0

    var body: some View {
        ZStack {
            ITMainView()
                .opacity(setupComplete ? 1 : homeOpacity)
                .scaleEffect(setupComplete ? 1 : homeScale)

            if !setupComplete && !showLaunchSplash {
                ITOnboardingView {
                    finishSetup()
                }
            }

            if showLaunchSplash {
                Image("iToolsLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .scaleEffect(launchScale)
                    .opacity(launchOpacity)
                    .allowsHitTesting(false)
            }
        }
        .tint(Color(hex: accentHex))
    }

    private func finishSetup() {
        launchScale = 1
        launchOpacity = 1
        homeScale = 0.78
        homeOpacity = 0
        showLaunchSplash = true
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 2)) {
                launchScale = 14
                launchOpacity = 0
                homeScale = 1
                homeOpacity = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            setupComplete = true
            showLaunchSplash = false
            launchScale = 1
            launchOpacity = 1
        }
    }
}

struct ITOnboardingView: View {
    @EnvironmentObject private var store: ITStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("itools.accentHex") private var accentHex = ITTheme.defaultAccent
    @AppStorage("itools.backgroundHex") private var backgroundHex = ""

    let onComplete: () -> Void
    @State private var step = 0
    @State private var isSavingToken = false

    private var pageBackground: Color {
        ITTheme.background(hex: backgroundHex, scheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color(hex: accentHex) : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)

            ScrollView {
                Group {
                    switch step {
                    case 0: welcomePage
                    case 1: githubPage
                    default: appearancePage
                    }
                }
                .id(step)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
            }

            pageControls
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageBackground.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.24), value: step)
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 20)
            Image("iToolsLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .scaleEffect(step == 0 ? 1 : 0.94)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: step)
            VStack(alignment: .leading, spacing: 10) {
                Text("Welcome to iTools")
                    .font(.system(size: 34, weight: .bold))
                Text("Find Apple-device apps, explore sources, and follow setup guides in one place.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 36)
        }
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .leading)
    }

    private var githubPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect GitHub")
                .font(.system(size: 30, weight: .bold))
            Text("A personal access token lets iTools create repositories and publish app listings with your account's permissions. It is stored in Keychain.")
                .foregroundStyle(.secondary)
            TextField("GitHub username", text: $store.githubUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            SecureField("Personal access token", text: $store.githubToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Link("Create a GitHub token", destination: URL(string: "https://github.com/settings/personal-access-tokens")!)
            if let message = store.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task {
                    isSavingToken = true
                    let saved = await store.saveGitHubCredentials()
                    isSavingToken = false
                    if saved {
                        store.message = nil
                        withAnimation { step = 2 }
                    }
                }
            } label: {
                HStack {
                    if isSavingToken { ProgressView().tint(.white) }
                    Text("Save and continue")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSavingToken || store.githubUsername.isEmpty || store.githubToken.isEmpty)
            Spacer(minLength: 30)
        }
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Make it yours")
                .font(.system(size: 30, weight: .bold))
            Text("Choose an accent color. The background follows your device appearance unless you set a custom one.")
                .foregroundStyle(.secondary)
            ColorPicker("Accent color", selection: Binding(
                get: { Color(hex: accentHex) },
                set: { accentHex = $0.hexString ?? ITTheme.defaultAccent }
            ), supportsOpacity: false)
            ColorPicker("Background color", selection: Binding(
                get: { pageBackground },
                set: { backgroundHex = $0.hexString ?? "" }
            ), supportsOpacity: false)
            Button("Use device appearance for background") {
                backgroundHex = ""
            }
            .buttonStyle(.bordered)
            Spacer(minLength: 30)
        }
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
    }

    @ViewBuilder
    private var pageControls: some View {
        if step == 0 {
            VStack(spacing: 14) {
                Button("Get started") { withAnimation { step = 1 } }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("Skip setup") { onComplete() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        } else if step == 1 {
            HStack {
                Button("Back") { withAnimation { step = 0 } }
                    .buttonStyle(.plain)
                Spacer()
                Button("Skip GitHub setup") { withAnimation { step = 2 } }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Button("Back") { withAnimation { step = 1 } }
                    .buttonStyle(.plain)
                Spacer()
                Button("Finish setup") { onComplete() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}