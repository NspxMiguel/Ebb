import AppKit
import EbbCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static weak var shared: AppDelegate?

    let store: AccountStore
    let scheduler: Scheduler
    private var statusItem: StatusItemController?
    private var mainWindow: NSWindow?
    private var launchedAsLoginItem = false

    override init() {
        L10n.shared.register(AppStrings.table)
        let store = AccountStore()
        self.store = store
        scheduler = Scheduler(store: store)
        super.init()
        AppDelegate.shared = self
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Only the launch event still carries this; by didFinishLaunching it is gone.
        if let event = NSAppleEventManager.shared().currentAppleEvent,
            event.eventID == kAEOpenApplication,
            event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        {
            launchedAsLoginItem = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = StatusItemController(store: store, scheduler: scheduler)
        // Opened by hand (Finder, Launchpad, Spotlight): show the window, so the
        // app is visible even when the menu bar has no room for its icon. Started
        // at login: stay quietly in the menu bar.
        if !launchedAsLoginItem {
            showMainWindow()
        }
    }

    /// Opening the app again while it runs lands here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func showMainWindow() {
        statusItem?.closePopover()
        if mainWindow == nil {
            let root = MainWindow()
                .environmentObject(store)
                .environmentObject(scheduler)
                .tint(EbbAccent.color)
                .frame(minWidth: 640, minHeight: 420)
            let hosting = NSHostingController(rootView: root)
            hosting.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false)
            window.contentViewController = hosting
            window.title = L10n.shared("app.name")
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 780, height: 560))
            window.center()
            window.setFrameAutosaveName("EbbMainWindow")
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }
}
