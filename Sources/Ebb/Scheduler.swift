import AppKit
import Combine
import EbbCore
import Foundation

/// Timer-driven automatic cleanup. Shared by the popover and the main window.
@MainActor
final class Scheduler: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastResults: [AccountRunResult] = []

    @Published var autoCleanup: Bool {
        didSet {
            Settings.defaults.set(autoCleanup, forKey: AppSettingKey.autoCleanup)
            rescheduleTimer()
        }
    }

    @Published var intervalMinutes: Int {
        didSet {
            Settings.defaults.set(intervalMinutes, forKey: AppSettingKey.intervalMinutes)
            rescheduleTimer()
        }
    }

    private let store: AccountStore
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastRunAt: Date?
    private var launchTask: Task<Void, Never>?

    init(store: AccountStore) {
        self.store = store
        let defaults = Settings.defaults
        if defaults.object(forKey: AppSettingKey.autoCleanup) == nil {
            defaults.set(true, forKey: AppSettingKey.autoCleanup)
            autoCleanup = true
        } else {
            autoCleanup = defaults.bool(forKey: AppSettingKey.autoCleanup)
        }
        let stored = defaults.object(forKey: AppSettingKey.intervalMinutes) as? Int
        let allowed = [15, 30, 60, 180]
        if let stored, allowed.contains(stored) {
            intervalMinutes = stored
        } else {
            defaults.set(60, forKey: AppSettingKey.intervalMinutes)
            intervalMinutes = 60
        }

        rescheduleTimer()
        startLaunchDelay()
        observeWake()
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        launchTask?.cancel()
    }

    /// Runs enabled accounts. No-ops if a run is already in flight.
    @discardableResult
    func run(mode: CleanupMode = .expired, dryRun: Bool = false, only: UUID? = nil) async -> [AccountRunResult] {
        guard !isRunning else { return lastResults }
        isRunning = true
        defer { isRunning = false }
        store.reload()
        let results = await Runner.run(store: store, mode: mode, dryRun: dryRun, only: only)
        if !dryRun {
            lastResults = results
            lastRunAt = Date()
        }
        return results
    }

    /// Serializes work that talks to IMAP (danger zone) with the timer.
    func runExclusive<T>(_ body: () async throws -> T) async rethrows -> T? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }
        return try await body()
    }

    func runScheduled() async {
        guard autoCleanup else { return }
        await run(mode: .expired, dryRun: false)
    }

    func runIfStale() async {
        guard autoCleanup else { return }
        let interval = TimeInterval(intervalMinutes * 60)
        if let lastRunAt, Date().timeIntervalSince(lastRunAt) < interval { return }
        await runScheduled()
    }

    private func startLaunchDelay() {
        launchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.runScheduled()
        }
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard autoCleanup else { return }
        let interval = TimeInterval(max(intervalMinutes, 1) * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runScheduled()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.runIfStale()
            }
        }
    }
}
