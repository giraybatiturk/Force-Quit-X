import AppKit

struct BackgroundAppInfo {
    let app: NSRunningApplication
    let name: String
    let bundleID: String?
}

enum BackgroundAppProvider {

    /// Critical system processes that should never be shown or force-quit.
    static let hiddenBundlePrefixes: [String] = [
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

    /// Pure predicate used by `backgroundApps()` — extracted so it can be unit-tested
    /// without depending on `NSWorkspace.shared.runningApplications`.
    static func shouldInclude(
        activationPolicy: NSApplication.ActivationPolicy,
        bundleIdentifier: String?,
        localizedName: String?,
        selfBundleID: String?
    ) -> Bool {
        guard activationPolicy == .accessory || activationPolicy == .prohibited,
            let name = localizedName,
            !name.isEmpty,
            bundleIdentifier != selfBundleID
        else { return false }

        if let bundleID = bundleIdentifier {
            for prefix in hiddenBundlePrefixes {
                if bundleID == prefix || bundleID.hasPrefix(prefix + ".") {
                    return false
                }
            }
        }

        return true
    }

    static func backgroundApps() -> [BackgroundAppInfo] {
        let selfBundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .compactMap { app -> BackgroundAppInfo? in
                guard
                    shouldInclude(
                        activationPolicy: app.activationPolicy,
                        bundleIdentifier: app.bundleIdentifier,
                        localizedName: app.localizedName,
                        selfBundleID: selfBundleID
                    )
                else { return nil }

                return BackgroundAppInfo(app: app, name: app.localizedName ?? "", bundleID: app.bundleIdentifier)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
