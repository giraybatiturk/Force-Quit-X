import AppKit

struct BackgroundAppInfo {
    let app: NSRunningApplication
    let name: String
    let bundleID: String?
}

enum BackgroundAppProvider {

    /// Critical system processes that should never be shown or force-quit.
    private static let hiddenBundlePrefixes: [String] = [
        "com.apple.WindowServer",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.SystemUIServer",
        "com.apple.finder",
        "com.apple.coreservicesd",
        "com.apple.launchd",
        "com.apple.kernel",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
    ]

    static func backgroundApps() -> [BackgroundAppInfo] {
        let selfBundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .compactMap { app -> BackgroundAppInfo? in
                guard app.activationPolicy == .accessory || app.activationPolicy == .prohibited,
                    let name = app.localizedName,
                    !name.isEmpty,
                    app.bundleIdentifier != selfBundleID
                else { return nil }

                // Hide critical system processes
                if let bundleID = app.bundleIdentifier {
                    for prefix in hiddenBundlePrefixes {
                        if bundleID == prefix || bundleID.hasPrefix(prefix + ".") {
                            return nil
                        }
                    }
                }

                return BackgroundAppInfo(app: app, name: name, bundleID: app.bundleIdentifier)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
