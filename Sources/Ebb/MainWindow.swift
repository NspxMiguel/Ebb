import EbbCore
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var navigation: AppNavigation
    @ObservedObject private var l10n = L10n.shared

    @State private var showingAdd = false

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.sidebar) {
                Section(l10n("app.accounts")) {
                    ForEach(store.accounts) { account in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.username)
                            Text(l10n("provider.\(account.provider.rawValue)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.account(account.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label(l10n("app.add_account"), systemImage: "plus")
                    }
                    .help(l10n("app.add_account"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    navigation.sidebar = .general
                } label: {
                    Label(l10n("app.general"), systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(10)
                .background(navigation.sidebar == .general ? Color.accentColor.opacity(0.12) : Color.clear)
            }
        } detail: {
            switch navigation.sidebar {
            case .account(let id):
                AccountDetailView(accountID: id)
            case .general:
                GeneralSettingsView()
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddAccountSheet()
                .environmentObject(store)
        }
        .onAppear {
            store.reload()
        }
        .onChange(of: store.accounts.map(\.id)) { _, ids in
            if case .account(let id) = navigation.sidebar, !ids.contains(id) {
                navigation.sidebar = ids.first.map { .account($0) } ?? .general
            }
        }
    }
}
