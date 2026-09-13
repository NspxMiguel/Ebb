import SwiftUI

/// The app is driven from AppKit (see AppDelegate): a crowded menu bar hides a
/// SwiftUI MenuBarExtra behind the notch with no way to give it a position, and
/// a Window scene cannot be opened from outside a view (Finder reopen, launch).
@main
struct EbbApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
