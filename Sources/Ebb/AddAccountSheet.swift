import EbbCore
import SwiftUI

struct AddAccountSheet: View {
    @EnvironmentObject private var store: AccountStore
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ProviderKind = .gmail
    @State private var username = ""
    @State private var password = ""
    @State private var host = ""
    @State private var port = 993
    @State private var testing = false
    @State private var testMessage: String?
    @State private var testFailed = false
    @State private var saveError: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Picker(l10n("app.provider"), selection: $kind) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(l10n("provider.\(kind.rawValue)")).tag(kind)
                    }
                }

                TextField(l10n("app.username"), text: $username, prompt: Text(usernameHint))
                    .textContentType(.username)

                SecureField(l10n("app.password"), text: $password)
                    .textContentType(.password)

                if let url = Provider.preset(kind)?.appPasswordURL {
                    Link(l10n("app.password.link"), destination: url)
                    Text(passwordHowTo)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(passwordHowTo)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if kind == .custom {
                    TextField(l10n("app.host"), text: $host)
                    TextField(l10n("app.port"), value: $port, format: .number)
                }

                HStack {
                    Button(l10n("app.test_login")) {
                        Task { await testLogin() }
                    }
                    .disabled(!canTest || testing)

                    if testing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let testMessage {
                    Text(testMessage)
                        .foregroundStyle(testFailed ? .red : .secondary)
                }

                if let saveError {
                    Text(saveError)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(l10n("app.add_account"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n("app.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n("app.save")) {
                        Task { await save() }
                    }
                    .disabled(!canSave || saving)
                }
            }
            .frame(minWidth: 420, minHeight: 360)
        }
    }

    private var usernameHint: String {
        switch kind {
        case .gmail: return l10n("app.username.hint.gmail")
        case .icloud: return l10n("app.username.hint.icloud")
        case .custom: return l10n("app.username.hint.custom")
        }
    }

    private var passwordHowTo: String {
        switch kind {
        case .gmail: return l10n("app.password.howto.gmail")
        case .icloud: return l10n("app.password.howto.icloud")
        case .custom: return l10n("app.password.howto.custom")
        }
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canTest: Bool {
        !trimmedUsername.isEmpty && !password.isEmpty && (kind != .custom || !trimmedHost.isEmpty)
    }

    private var canSave: Bool { canTest }

    private func makeAccount() -> Account {
        let endpoint: ServerEndpoint?
        if kind == .custom {
            endpoint = ServerEndpoint(host: trimmedHost, port: port, useTLS: true)
        } else {
            endpoint = nil
        }
        return Account(provider: kind, username: trimmedUsername, endpoint: endpoint)
    }

    private func testLogin() async {
        testing = true
        testMessage = nil
        defer { testing = false }
        let cleaner = Cleaner(account: makeAccount(), password: password)
        do {
            try await cleaner.testLogin()
            testFailed = false
            testMessage = l10n("app.test_login.ok")
        } catch {
            testFailed = true
            testMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        saveError = nil
        defer { saving = false }
        let account = makeAccount()
        do {
            try CredentialStore.setPassword(password, for: account.id)
            try store.add(account)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
