import SwiftUI
import Security

struct Credentials: Codable {
    let username: String
    let password: String
}

enum Account {
    private static let service = "com.example.itools.account"

    static func save(_ credentials: Credentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func matches(username: String, password: String) -> Bool {
        guard let saved = load() else { return false }
        return saved.username.caseInsensitiveCompare(username) == .orderedSame && saved.password == password
    }

    static func createIfNeeded(username: String, password: String) -> Bool {
        if let saved = load() {
            return saved.username.caseInsensitiveCompare(username) == .orderedSame && saved.password == password
        }

        save(Credentials(username: username, password: password))
        return true
    }
}

struct RootView: View {
    @State private var signedIn = false

    var body: some View {
        if signedIn {
            ContentView()
        } else {
            LoginView { signedIn = true }
        }
    }
}

struct ContentView: View {
    var body: some View {
        ITMainView()
    }
}

struct LoginView: View {
    let onSuccess: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var message = ""

    private var hasAccount: Bool { Account.load() != nil }

    var body: some View {
        VStack(spacing: 16) {
            Text("iTools")
                .font(.largeTitle.bold())
                .padding(.bottom, 8)

            TextField("Username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            SecureField("Password (4+ characters)", text: $password)
                .textFieldStyle(.roundedBorder)

            Button(hasAccount ? "Sign In" : "Create Account") {
                submit()
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.isEmpty || password.count < 4)

            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
        .padding(32)
    }

    private func submit() {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        if Account.createIfNeeded(username: trimmedUser, password: trimmedPassword) {
            onSuccess()
        } else {
            message = "Wrong username or password."
        }
    }
}
