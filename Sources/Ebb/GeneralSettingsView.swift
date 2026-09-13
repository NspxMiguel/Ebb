import EbbCore
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var scheduler: Scheduler
    @ObservedObject private var l10n = L10n.shared

    @State private var loginTick = 0
    @State private var loginError: String?
    @State private var groqDraft = ""
    @State private var groqSaved = false
    @State private var groqError: String?

    var body: some View {
        Form {
            Section(l10n("app.general")) {
                Toggle(l10n("app.auto_cleanup"), isOn: $scheduler.autoCleanup)

                Picker(l10n("app.interval"), selection: $scheduler.intervalMinutes) {
                    ForEach([15, 30, 60, 180], id: \.self) { minutes in
                        Text(l10n("app.interval.minutes", minutes)).tag(minutes)
                    }
                }
                .disabled(!scheduler.autoCleanup)
                Text(l10n("app.interval.footnote"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle(l10n("app.open_at_login"), isOn: loginBinding)
                    .id(loginTick)

                if let loginError {
                    Text(l10n("app.login.error", loginError))
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Picker(
                    l10n("app.language"),
                    selection: Binding(
                        get: { l10n.language },
                        set: { l10n.set($0) }
                    )
                ) {
                    Text(l10n("app.language.system")).tag(Language.system)
                    Text(l10n("app.language.pt")).tag(Language.pt)
                    Text(l10n("app.language.en")).tag(Language.en)
                }
            }

            Section(l10n("app.summary")) {
                if let reason = SummaryEngine.onDeviceUnavailableReason {
                    Text(reason)
                        .foregroundStyle(.secondary)
                } else {
                    Text(l10n("app.summary.on_device"))
                        .foregroundStyle(.secondary)
                }

                SecureField(l10n("app.summary.groq_key"), text: $groqDraft)

                HStack {
                    Button(l10n("app.save")) { saveGroqKey() }
                        .disabled(groqDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(l10n("app.summary.groq_remove")) { removeGroqKey() }
                        .disabled(!groqSaved)
                }

                Text(groqSaved ? l10n("app.summary.groq_saved") : l10n("app.summary.groq_missing"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let groqError {
                    Text(groqError)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                if let groqURL = URL(string: "https://console.groq.com/keys") {
                    Link(l10n("app.summary.groq_link"), destination: groqURL)
                }
                Text(l10n("app.summary.groq_privacy"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n("app.general"))
        .onAppear { refreshGroqSaved() }
    }

    private func refreshGroqSaved() {
        groqSaved = SummaryEngine.groqKey() != nil
    }

    private func saveGroqKey() {
        let key = groqDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        groqError = nil
        do {
            try SummaryEngine.setGroqKey(key)
            groqDraft = ""
            refreshGroqSaved()
        } catch {
            groqError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func removeGroqKey() {
        groqError = nil
        SummaryEngine.removeGroqKey()
        groqDraft = ""
        refreshGroqSaved()
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                loginError = nil
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    loginError = error.localizedDescription
                }
                loginTick += 1
            }
        )
    }
}
