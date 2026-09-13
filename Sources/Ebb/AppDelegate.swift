import AppKit
import EbbCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static weak var shared: AppDelegate?

    let store: AccountStore
    let scheduler: Scheduler
    let navigation = AppNavigation()
    private var statusItem: StatusItemController?
    private var mainWindow: NSWindow?
    private var summaryWindow: NSWindow?
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
        if let directory = ProcessInfo.processInfo.environment["EBB_SNAPSHOT_DIR"], !directory.isEmpty {
            snapshotAndQuit(to: URL(fileURLWithPath: directory))
        }
    }

    /// Developer aid (EBB_SNAPSHOT_DIR): writes the main window to main.png and
    /// quits, so the interface can be checked and screenshotted from a script.
    private func snapshotAndQuit(to directory: URL) {
        showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            // A process may capture its own windows without Screen Recording
            // permission; cacheDisplay would miss SwiftUI's layer content.
            if let window = self?.mainWindow,
                let image = CGWindowListCreateImage(
                    .null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                    [.boundsIgnoreFraming, .bestResolution])
            {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("main.png"))
            }
            NSApp.terminate(nil)
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

    func showMainWindow(selecting item: SidebarItem? = nil) {
        statusItem?.closePopover()
        if mainWindow == nil {
            if let item {
                navigation.sidebar = item
            } else if let first = store.accounts.first {
                navigation.sidebar = .account(first.id)
            }
            let root = MainWindow()
                .environmentObject(store)
                .environmentObject(scheduler)
                .environmentObject(navigation)
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
        } else if let item {
            navigation.sidebar = item
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// `accountID` nil: every enabled account; otherwise that account only.
    func showSummaryWindow(accountID: UUID?) {
        statusItem?.closePopover()
        let root = SummaryView(accountID: accountID)
            .environmentObject(store)
            .tint(EbbAccent.color)
            .frame(minWidth: 480, minHeight: 360)
        let hosting = NSHostingController(rootView: root)
        hosting.sceneBridgingOptions = [.toolbars, .title]
        if let window = summaryWindow {
            window.contentViewController = hosting
            window.title = L10n.shared("app.summary")
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.contentViewController = hosting
        window.title = L10n.shared("app.summary")
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 520))
        window.center()
        window.setFrameAutosaveName("EbbSummaryWindow")
        summaryWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
