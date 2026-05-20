import AppKit
import ApplicationServices

enum AccessibilityHelper {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func isTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    static func promptIfNeededOnFirstLaunch() {
        guard !Preferences.accessibilityPromptShown else { return }
        Preferences.accessibilityPromptShown = true
        guard !isTrusted() else { return }
        showPermissionAlert(
            informativeText:
                "ForceQuitX needs Accessibility permission so the global shortcut can trigger Force Quit All from any app.\n\nOpen System Settings, enable ForceQuitX under Privacy & Security → Accessibility, then relaunch the app."
        )
    }

    static func notifyHotKeyRegistrationFailed() {
        showPermissionAlert(
            informativeText:
                "The global shortcut could not be registered. This usually means another app has claimed the same combination, or that ForceQuitX needs Accessibility permission.\n\nOpen System Settings, enable ForceQuitX under Privacy & Security → Accessibility, then relaunch the app. If the shortcut is taken, change it from Settings → Shortcut."
        )
    }

    private static func showPermissionAlert(informativeText: String) {
        let work = {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Enable Accessibility for ForceQuitX"
            alert.informativeText = informativeText
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(settingsURL)
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
