import EbbCore
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var store: AccountStore
    @ObservedObject private var l10n = L10n.shared

    @State private var selection: SidebarItem = .general
    @State private var showingAdd = false
    @State private var didBootstrap = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
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
                    selection = .general
                } label: {
                    Label(l10n("app.general"), systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(10)
                .background(selection == .general ? Color.accentColor.opacity(0.12) : Color.clear)
            }
        } detail: {
            switch selection {
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
            if !didBootstrap {
                didBootstrap = true
                if let first = store.accounts.first {
                    selection = .account(first.id)
                }
            }
        }
        .onChange(of: store.accounts.map(\.id)) { _, ids in
            if case .account(let id) = selection, !ids.contains(id) {
                selection = ids.first.map { .account($0) } ?? .general
            }
        }
    }
}
