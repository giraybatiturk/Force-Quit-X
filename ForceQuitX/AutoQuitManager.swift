import AppKit

class AutoQuitManager {
    private var lastActiveTimestamps: [String: Date] = [:]
    private var pollingTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?

    // Config is derived live from Preferences — the single source of truth. The
    // settings layer only writes Preferences; this manager re-reads on each poll
    // and reacts to enable/disable via the defaults observer below. No mirrored
    // state to keep in sync, so no "write to two places" bug class.
    var timeoutMinutes: Int { Preferences.autoQuitTimeoutMinutes }
    var excludedBundleIDs: Set<String> { Set(Preferences.autoQuitExcludedBundleIDs) }

    // MARK: - Lifecycle

    init() {
        // Reconfigure whenever a preference changes (cheap: just reconciles the
        // timer with Preferences.autoQuitEnabled). Picks up the initial enabled
        // state too, so AppDelegate just constructs the manager.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyEnabledState()
        }
        applyEnabledState()
    }

    deinit {
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
            defaultsObserver = nil
        }
        stop()
    }

    /// Reconcile the polling state with `Preferences.autoQuitEnabled`. Idempotent —
    /// only starts/stops on an actual transition, so repeated calls are harmless.
    func applyEnabledState() {
        if Preferences.autoQuitEnabled {
            if pollingTimer == nil { start() }
        } else if pollingTimer != nil {
            stop()
        }
    }

    func start() {
        // Idempotent: always stop first
        stop()

        // Seed timestamps for all currently running regular apps
        let now = Date()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let bid = app.bundleIdentifier {
                lastActiveTimestamps[bid] = now
            }
        }

        // Observe frontmost app changes
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                let bundleID = app.bundleIdentifier
            else { return }
            self?.lastActiveTimestamps[bundleID] = Date()
        }

        // Poll every 60 seconds
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkIdleApps()
        }
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        lastActiveTimestamps.removeAll()
    }

    // MARK: - Idle Check

    /// Pure predicate behind `checkIdleApps()` — extracted so the idle-window math
    /// can be unit-tested without depending on `NSWorkspace`/`Date()` wall-clock.
    static func isIdleBeyondTimeout(lastActive: Date, now: Date, timeoutMinutes: Int) -> Bool {
        let timeout = TimeInterval(timeoutMinutes * 60)
        return now.timeIntervalSince(lastActive) >= timeout
    }

    private func checkIdleApps() {
        let now = Date()
        let selfBundleID = Bundle.main.bundleIdentifier
        let protectedBundleIDs: Set<String> = ["com.apple.finder"]

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier,
                bundleID != selfBundleID,
                !protectedBundleIDs.contains(bundleID),
                !excludedBundleIDs.contains(bundleID)
            else { continue }

            // First time we've seen this app — seed it so the idle window starts now.
            // Without this, an app launched after start() that's never activated would
            // keep getting a fresh "now" baseline and never reach the timeout.
            let lastActive: Date
            if let recorded = lastActiveTimestamps[bundleID] {
                lastActive = recorded
            } else {
                lastActiveTimestamps[bundleID] = now
                continue
            }
            if Self.isIdleBeyondTimeout(lastActive: lastActive, now: now, timeoutMinutes: timeoutMinutes)
                && !app.isTerminated
            {
                NSLog("ForceQuitX: Auto-quitting idle app: \(app.localizedName ?? bundleID)")
                app.forceTerminate()
                lastActiveTimestamps.removeValue(forKey: bundleID)
            }
        }

        // Purge entries for apps that are no longer running
        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        lastActiveTimestamps = lastActiveTimestamps.filter { runningBundleIDs.contains($0.key) }
    }
}
