import AppKit

class AutoQuitManager {
    private var lastActiveTimestamps: [String: Date] = [:]
    private var pollingTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?

    var timeoutMinutes: Int = Preferences.autoQuitTimeoutMinutes
    var usesForceTerminate: Bool = Preferences.autoQuitUsesForceTerminate
    var excludedBundleIDs: Set<String> = Set(Preferences.autoQuitExcludedBundleIDs)

    var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    // MARK: - Lifecycle

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
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
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

    private func checkIdleApps() {
        let now = Date()
        let timeout = TimeInterval(timeoutMinutes * 60)
        let selfBundleID = Bundle.main.bundleIdentifier
        let protectedBundleIDs: Set<String> = ["com.apple.finder"]

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier,
                bundleID != selfBundleID,
                !protectedBundleIDs.contains(bundleID),
                !excludedBundleIDs.contains(bundleID)
            else { continue }

            let lastActive = lastActiveTimestamps[bundleID] ?? now
            if now.timeIntervalSince(lastActive) >= timeout && !app.isTerminated {
                NSLog("ForceQuitX: Auto-quitting idle app: \(app.localizedName ?? bundleID)")
                if usesForceTerminate {
                    app.forceTerminate()
                } else {
                    app.terminate()
                }
                lastActiveTimestamps.removeValue(forKey: bundleID)
            }
        }

        // Purge entries for apps that are no longer running
        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        lastActiveTimestamps = lastActiveTimestamps.filter { runningBundleIDs.contains($0.key) }
    }
}
