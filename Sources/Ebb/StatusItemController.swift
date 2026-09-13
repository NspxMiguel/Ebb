import AppKit
import Combine
import EbbCore
import SwiftUI

/// The menu bar icon and its popover.
@MainActor
final class StatusItemController: NSObject {
    static let autosaveName = "EbbStatusItem"

    private let item: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    init(store: AccountStore, scheduler: Scheduler) {
        // On a full menu bar a new item is born at the far left, under the
        // notch, and never shows up. Writing the preferred position before the
        // item exists (the same key macOS saves on a ⌘-drag) puts it next to
        // the clock instead. Only the first time: after that the user owns it.
        let positionKey = "NSStatusItem Preferred Position \(Self.autosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(1, forKey: positionKey)
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Self.autosaveName
        item.behavior = []
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopover()
                .environmentObject(store)
                .environmentObject(scheduler)
                .tint(EbbAccent.color))

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.setAccessibilityLabel("Ebb")
        }
        updateIcon(failed: false)

        store.$accounts
            .map { accounts in accounts.contains { $0.isEnabled && $0.lastRun?.succeeded == false } }
            .removeDuplicates()
            .sink { [weak self] failed in self?.updateIcon(failed: failed) }
            .store(in: &cancellables)
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateIcon(failed: Bool) {
        let name = failed ? "exclamationmark.triangle" : "water.waves"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Ebb")
        image?.isTemplate = true
        item.button?.image = image
    }
}
