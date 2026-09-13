import EbbCore
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var scheduler: Scheduler
    @ObservedObject private var l10n = L10n.shared

    @State private var loginTick = 0
    @State private var loginError: String?

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
        }
        .formStyle(.grouped)
        .navigationTitle(l10n("app.general"))
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
