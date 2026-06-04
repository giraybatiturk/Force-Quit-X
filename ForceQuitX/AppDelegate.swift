import AppKit
import Carbon
import ServiceManagement
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    /// Reliable handle to the live delegate. `NSApp.delegate as? AppDelegate` can
    /// return nil under `@NSApplicationDelegateAdaptor`, so views reach the delegate
    /// through this instead. Set in `applicationDidFinishLaunching`.
    static private(set) var shared: AppDelegate?

    var statusItem: NSStatusItem!
    var hotKeyManager: HotKeyManager?
    var autoQuitManager: AutoQuitManager?

    /// Sparkle auto-updater. Started in `applicationDidFinishLaunching`; the feed
    /// URL, public key, and check cadence come from Info.plist (SUFeedURL,
    /// SUPublicEDKey, SUScheduledCheckInterval).
    private(set) lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private var settingsWindow: NSWindow?
    private var keyRecorderPanel: KeyRecorderPanel?

    // Track whether we're showing all background apps (not capped at 25)
    private var showAllBackgroundApps = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        enableLaunchAtLoginIfFirstRun()

        applyAppearance()
        applyIconStyle()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hotKeyManager = HotKeyManager(delegate: self)
        let hotKeyRegistered = hotKeyManager?.register() ?? false

        // Surface Accessibility permission once on first launch; if the hot key
        // outright failed to bind, prompt regardless so the user has a path forward.
        if !hotKeyRegistered {
            AccessibilityHelper.notifyHotKeyRegistrationFailed()
        } else {
            AccessibilityHelper.promptIfNeededOnFirstLaunch()
        }

        autoQuitManager = AutoQuitManager()
        if Preferences.autoQuitEnabled {
            autoQuitManager?.isEnabled = true
        }

        // Start Sparkle (scheduled checks run on SUScheduledCheckInterval).
        _ = updaterController
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregister()
        autoQuitManager?.stop()
    }

    private func enableLaunchAtLoginIfFirstRun() {
        guard !Preferences.launchAtLoginDefaulted else { return }
        Preferences.launchAtLoginDefaulted = true
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("ForceQuitX: default Launch at Login register failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Icon Style

    func applyIconStyle() {
        guard let button = statusItem.button else { return }
        let icon =
            NSImage(named: "MenubarIcon")
            ?? NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "ForceQuitX")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        icon?.accessibilityDescription = "ForceQuitX"
        button.image = icon
    }

    // MARK: - Appearance

    /// Applies the saved theme app-wide so the change is visible immediately (the
    /// open Settings window, the menu next time it opens). A per-menu appearance
    /// isn't reliably honored for status-bar menus, and isn't visible live anyway.
    func applyAppearance() {
        switch Preferences.menuAppearance {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Best-effort: force the status menu's own appearance to match the theme.
        // (macOS may still render status-bar menus with the system appearance,
        // especially on Tahoe — the app windows are themed via NSApp.appearance.)
        switch Preferences.menuAppearance {
        case "light": menu.appearance = NSAppearance(named: .aqua)
        case "dark": menu.appearance = NSAppearance(named: .darkAqua)
        default: menu.appearance = nil
        }
        buildMenu(menu)
    }

    // MARK: - Build Menu

    func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let selfBundleID = Bundle.main.bundleIdentifier

        let userApps: [(app: NSRunningApplication, name: String)] = NSWorkspace.shared.runningApplications
            .compactMap { app in
                guard app.activationPolicy == .regular,
                    let name = app.localizedName,
                    app.bundleIdentifier != "com.apple.finder",
                    app.bundleIdentifier != selfBundleID
                else { return nil }
                return (app, name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // — Force Quit All —
        let quitAllItem = NSMenuItem(
            title: "Force Quit All\(userApps.isEmpty ? "" : "  (\(userApps.count))")",
            action: userApps.isEmpty ? nil : #selector(quitAllApps),
            keyEquivalent: ""
        )
        if let img = NSImage(systemSymbolName: "xmark.octagon.fill", accessibilityDescription: nil) {
            img.size = NSSize(width: 16, height: 16)
            quitAllItem.image = img
        }
        menu.addItem(quitAllItem)

        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let exceptFrontmostCount = userApps.filter { $0.app.bundleIdentifier != frontmostBundleID }.count
        let quitExceptFrontmostItem = NSMenuItem(
            title:
                "Force Quit All Except Frontmost\(exceptFrontmostCount > 0 ? "  (\(exceptFrontmostCount))" : "")",
            action: exceptFrontmostCount > 0 ? #selector(quitAllAppsExceptFrontmost) : nil,
            keyEquivalent: ""
        )
        if let img = NSImage(systemSymbolName: "xmark.octagon", accessibilityDescription: nil) {
            img.size = NSSize(width: 16, height: 16)
            quitExceptFrontmostItem.image = img
        }
        menu.addItem(quitExceptFrontmostItem)

        menu.addItem(NSMenuItem.separator())

        // — Running apps section —
        let sectionItem = NSMenuItem()
        sectionItem.attributedTitle = NSAttributedString(
            string: userApps.isEmpty ? "NO RUNNING APPS" : "RUNNING APPS",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        sectionItem.isEnabled = false
        menu.addItem(sectionItem)

        for (app, name) in userApps {
            let isFrontmost = app.bundleIdentifier == frontmostBundleID
            let menuItem = NSMenuItem()
            menuItem.representedObject = app
            menuItem.view = AppMenuItemView(
                icon: app.icon,
                title: name,
                isFrontmost: isFrontmost,
                isBackground: false
            ) { [weak self] in
                self?.forceQuit(app)
            }
            menu.addItem(menuItem)
        }

        // — Background processes section —
        if Preferences.showBackgroundApps {
            menu.addItem(NSMenuItem.separator())

            let bgApps = BackgroundAppProvider.backgroundApps()

            let bgHeader = NSMenuItem()
            bgHeader.attributedTitle = NSAttributedString(
                string: bgApps.isEmpty
                    ? "NO BACKGROUND PROCESSES"
                    : "BACKGROUND PROCESSES (\(bgApps.count))",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
            bgHeader.isEnabled = false
            menu.addItem(bgHeader)

            let maxVisible = showAllBackgroundApps ? bgApps.count : 25
            let visibleApps = bgApps.prefix(maxVisible)

            for bgApp in visibleApps {
                let app = bgApp.app
                let icon =
                    app.icon
                    ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: bgApp.name)
                let menuItem = NSMenuItem()
                menuItem.representedObject = app
                menuItem.view = AppMenuItemView(
                    icon: icon,
                    title: bgApp.name,
                    isFrontmost: false,
                    isBackground: true
                ) { [weak self] in
                    self?.forceQuit(app)
                }
                menu.addItem(menuItem)
            }

            if bgApps.count > 25 && !showAllBackgroundApps {
                let showAllItem = NSMenuItem(
                    title: "Show All (\(bgApps.count))",
                    action: #selector(toggleShowAllBackgroundApps),
                    keyEquivalent: ""
                )
                showAllItem.attributedTitle = NSAttributedString(
                    string: "Show All (\(bgApps.count))",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                        .foregroundColor: NSColor.controlAccentColor,
                    ]
                )
                menu.addItem(showAllItem)
            }
        }

        menu.addItem(NSMenuItem.separator())
        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = updaterController
        menu.addItem(checkForUpdatesItem)
        menu.addItem(
            NSMenuItem(title: "Settings...", action: #selector(showSettingsWindow), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Quit ForceQuitX", action: #selector(quitSelf), keyEquivalent: "q"))
    }

    // MARK: - Actions: Force Quit

    private func forceQuit(_ app: NSRunningApplication) {
        if !app.isTerminated {
            app.forceTerminate()
        }
    }

    @objc func quitAllApps() {
        guard
            confirmForceQuitAll(
                messageText: "Force Quit All Running Apps?",
                informativeText:
                    "This will immediately terminate all running apps without saving. Any unsaved work will be lost."
            )
        else { return }
        performQuitAllApps(excluding: nil)
    }

    @objc func quitAllAppsExceptFrontmost() {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        guard
            confirmForceQuitAll(
                messageText: "Force Quit All Apps Except the Frontmost?",
                informativeText:
                    "This will immediately terminate all running apps except the one currently in front. Any unsaved work in those apps will be lost."
            )
        else { return }
        performQuitAllApps(excluding: frontmostBundleID)
    }

    private func confirmForceQuitAll(messageText: String, informativeText: String) -> Bool {
        let defaults = UserDefaults.standard
        let suppressKey = Preferences.forceQuitAllConfirmedKey
        if defaults.bool(forKey: suppressKey) { return true }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")

        let suppress = NSButton(checkboxWithTitle: "Don't ask again", target: nil, action: nil)
        suppress.state = .off
        alert.accessoryView = suppress

        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"

        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        if suppress.state == .on {
            defaults.set(true, forKey: suppressKey)
        }
        return true
    }

    private func performQuitAllApps(excluding excludedBundleID: String?) {
        let selfBundleID = Bundle.main.bundleIdentifier
        let userApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && app.bundleIdentifier != "com.apple.finder"
                && app.bundleIdentifier != selfBundleID
                && app.bundleIdentifier != excludedBundleID
        }
        for app in userApps where !app.isTerminated {
            app.forceTerminate()
        }
    }

    // MARK: - Actions: Background Apps

    @objc func toggleShowAllBackgroundApps() {
        showAllBackgroundApps.toggle()
    }

    // MARK: - Actions: Shortcut

    @objc func showKeyRecorder() {
        let panel = KeyRecorderPanel(
            currentKeyCode: hotKeyManager?.keyCode ?? UInt32(kVK_ANSI_Q),
            currentModifiers: hotKeyManager?.modifiers ?? UInt32(cmdKey | optionKey)
        )
        panel.onKeyRecorded = { [weak self] keyCode, modifiers in
            let success = self?.hotKeyManager?.updateBinding(keyCode: keyCode, modifiers: modifiers) ?? false
            if !success {
                AccessibilityHelper.notifyHotKeyRegistrationFailed()
            }
        }
        // Hold a strong reference so the panel isn't relying on AppKit's implicit
        // window retention (the panel sets isReleasedWhenClosed = false). Drop it
        // when the panel closes so we don't keep a stale window around.
        panel.onClose = { [weak self] in
            self?.keyRecorderPanel = nil
        }
        keyRecorderPanel = panel
        panel.showRecorder()
    }

    // MARK: - Settings Window

    @objc func showSettingsWindow() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: SettingsWindow())
            let window = NSWindow(contentViewController: hostingController)
            window.title = "ForceQuitX Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setFrameAutosaveName("ForceQuitXSettings")
            window.delegate = self
            window.center()
            settingsWindow = window
        }

        // Become a regular app while Settings is open so it gets a Dock icon and
        // shows up in ⌘-Tab — otherwise an accessory app's window is impossible to
        // resurface once it falls behind another app. Reverted on close.
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitSelf() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Drop back to a menubar-only accessory app once Settings closes so the
        // Dock icon disappears again.
        guard notification.object as? NSWindow == settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - HotKeyDelegate

extension AppDelegate: HotKeyDelegate {
    func hotKeyTriggered() {
        quitAllApps()
    }
}
