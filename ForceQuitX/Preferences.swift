import Foundation

enum Preferences {

    // MARK: - Existing Keys

    static let skippedUpdateVersionKey = "SkippedUpdateVersion"
    static let forceQuitAllConfirmedKey = "ForceQuitAllConfirmedV1"

    // MARK: - Auto Quit

    static let autoQuitEnabledKey = "AutoQuitEnabled"
    static let autoQuitTimeoutMinutesKey = "AutoQuitTimeoutMinutes"
    static let autoQuitExcludedBundleIDsKey = "AutoQuitExcludedBundleIDs"
    static let autoQuitUsesForceTerminateKey = "AutoQuitUsesForceTerminate"

    static var autoQuitEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoQuitEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoQuitEnabledKey) }
    }

    static var autoQuitTimeoutMinutes: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: autoQuitTimeoutMinutesKey)
            return val > 0 ? val : 30
        }
        set { UserDefaults.standard.set(newValue, forKey: autoQuitTimeoutMinutesKey) }
    }

    static var autoQuitExcludedBundleIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: autoQuitExcludedBundleIDsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: autoQuitExcludedBundleIDsKey) }
    }

    static var autoQuitUsesForceTerminate: Bool {
        get { UserDefaults.standard.bool(forKey: autoQuitUsesForceTerminateKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoQuitUsesForceTerminateKey) }
    }

    // MARK: - Background Apps

    static let showBackgroundAppsKey = "ShowBackgroundApps"

    static var showBackgroundApps: Bool {
        get { UserDefaults.standard.bool(forKey: showBackgroundAppsKey) }
        set { UserDefaults.standard.set(newValue, forKey: showBackgroundAppsKey) }
    }

    // MARK: - Custom Shortcuts

    static let customHotKeyCodeKey = "CustomHotKeyCode"
    static let customHotKeyModifiersKey = "CustomHotKeyModifiers"

    static var customHotKeyCode: Int {
        get { UserDefaults.standard.integer(forKey: customHotKeyCodeKey) }
        set { UserDefaults.standard.set(newValue, forKey: customHotKeyCodeKey) }
    }

    static var customHotKeyModifiers: Int {
        get { UserDefaults.standard.integer(forKey: customHotKeyModifiersKey) }
        set { UserDefaults.standard.set(newValue, forKey: customHotKeyModifiersKey) }
    }

    // MARK: - Appearance

    static let menuAppearanceKey = "MenuAppearance"
    static let iconStyleKey = "IconStyle"

    static var menuAppearance: String {
        get { UserDefaults.standard.string(forKey: menuAppearanceKey) ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: menuAppearanceKey) }
    }

    static var iconStyle: String {
        get { UserDefaults.standard.string(forKey: iconStyleKey) ?? "custom" }
        set { UserDefaults.standard.set(newValue, forKey: iconStyleKey) }
    }
}
