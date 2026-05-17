import AppKit
import Carbon
import ServiceManagement
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var latestVersion: String?
    var lastUpdateCheck: Date?
    var isCheckingForUpdates = false
    var hotKeyManager: HotKeyManager?
    var autoQuitManager: AutoQuitManager?

    private var settingsWindow: NSWindow?
    private var updateCheckTimer: Timer?

    // Track whether we're showing all background apps (not capped at 25)
    private var showAllBackgroundApps = false

    func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        // Drop any prerelease/build suffix (e.g. "1.2.0-beta.1+sha" -> "1.2.0").
        let core = trimmed.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? trimmed
        let numericComponents = core.split(separator: ".").map(String.init)
            .filter { Int($0) != nil }
        guard !numericComponents.isEmpty else { return "0" }

        let lastNonZeroIndex = numericComponents.lastIndex { Int($0) != 0 }
        guard let lastNonZeroIndex else { return "0" }
        return numericComponents[...lastNonZeroIndex].joined(separator: ".")
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        enableLaunchAtLoginIfFirstRun()

        applyIconStyle()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hotKeyManager = HotKeyManager(delegate: self)
        hotKeyManager?.register()

        autoQuitManager = AutoQuitManager()
        if Preferences.autoQuitEnabled {
            autoQuitManager?.isEnabled = true
        }

        checkForUpdates()
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) {
            [weak self] _ in
            self?.checkForUpdates()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregister()
        autoQuitManager?.stop()
        updateCheckTimer?.invalidate()
        updateCheckTimer = nil
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

    // MARK: - Menu Appearance

    private func applyMenuAppearance(_ menu: NSMenu) {
        switch Preferences.menuAppearance {
        case "light":
            menu.appearance = NSAppearance(named: .aqua)
        case "dark":
            menu.appearance = NSAppearance(named: .darkAqua)
        default:
            menu.appearance = nil
        }
    }

    // MARK: - Update Check

    func checkForUpdates(ignoreSkipped: Bool = false) {
        guard !isCheckingForUpdates,
            let url = URL(string: "https://api.github.com/repos/giraybatiturk/Force-Quit-X/releases/latest"),
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return }

        isCheckingForUpdates = true
        NotificationCenter.default.post(name: .updateCheckStateChanged, object: nil)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.setValue(
            "ForceQuitX/\(currentVersion) (+https://github.com/giraybatiturk/Force-Quit-X)",
            forHTTPHeaderField: "User-Agent"
        )

        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            DispatchQueue.main.async {
                self.isCheckingForUpdates = false
                self.lastUpdateCheck = Date()
                NotificationCenter.default.post(name: .updateCheckStateChanged, object: nil)
            }

            if let error {
                NSLog("ForceQuitX: update check failed: \(error.localizedDescription)")
                return
            }
            guard let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tagName = json["tag_name"] as? String
            else { return }
            let normalizedLatest = self.normalizedVersion(tagName)
            let normalizedCurrent = self.normalizedVersion(currentVersion)

            guard normalizedLatest.compare(normalizedCurrent, options: .numeric) == .orderedDescending
            else {
                DispatchQueue.main.async {
                    if self.latestVersion != nil {
                        self.latestVersion = nil
                        NotificationCenter.default.post(name: .updateCheckStateChanged, object: nil)
                    }
                }
                return
            }

            if !ignoreSkipped {
                let skippedVersion = UserDefaults.standard.string(
                    forKey: Preferences.skippedUpdateVersionKey)
                if skippedVersion == normalizedLatest { return }
            }

            DispatchQueue.main.async {
                self.latestVersion = normalizedLatest
                NotificationCenter.default.post(name: .updateCheckStateChanged, object: nil)
            }
        }.resume()
    }

    @objc func checkForUpdatesAction() {
        checkForUpdates(ignoreSkipped: true)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        applyMenuAppearance(menu)
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

        // — Update banner (if available) —
        if let latest = latestVersion {
            let updateItem = NSMenuItem(
                title: "Download Update v\(latest)",
                action: #selector(openReleasesPage),
                keyEquivalent: ""
            )
            updateItem.attributedTitle = NSAttributedString(
                string: "Update v\(latest) Available",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor.systemOrange,
                ]
            )
            let badge = NSImage(
                systemSymbolName: "arrow.down.circle.fill",
                accessibilityDescription: "Update available")
            badge?.size = NSSize(width: 16, height: 16)
            updateItem.image = badge
            menu.addItem(updateItem)

            let skipItem = NSMenuItem(
                title: "Skip v\(latest)",
                action: #selector(skipCurrentUpdate),
                keyEquivalent: ""
            )
            skipItem.indentationLevel = 1
            menu.addItem(skipItem)
            menu.addItem(NSMenuItem.separator())
        }

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
            let menuItem = NSMenuItem(
                title: name,
                action: #selector(forceQuitApp(_:)),
                keyEquivalent: ""
            )
            menuItem.representedObject = app
            if isFrontmost {
                menuItem.attributedTitle = NSAttributedString(
                    string: name,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
                    ]
                )
            }
            if let icon = app.icon {
                icon.size = NSSize(width: 18, height: 18)
                menuItem.image = icon
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
                let menuItem = NSMenuItem(
                    title: bgApp.name,
                    action: #selector(forceQuitApp(_:)),
                    keyEquivalent: ""
                )
                menuItem.representedObject = bgApp.app
                menuItem.attributedTitle = NSAttributedString(
                    string: bgApp.name,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
                if let icon = bgApp.app.icon {
                    icon.size = NSSize(width: 16, height: 16)
                    menuItem.image = icon
                } else {
                    let fallback = NSImage(
                        systemSymbolName: "app.dashed",
                        accessibilityDescription: bgApp.name)
                    fallback?.size = NSSize(width: 16, height: 16)
                    menuItem.image = fallback
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
        menu.addItem(
            NSMenuItem(title: "Settings...", action: #selector(showSettingsWindow), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Quit ForceQuitX", action: #selector(quitSelf), keyEquivalent: "q"))
    }

    // MARK: - Actions: Update

    @objc func openReleasesPage() {
        guard let url = URL(string: "https://github.com/giraybatiturk/Force-Quit-X/releases/latest")
        else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            if let error {
                NSLog("ForceQuitX: open releases page failed: \(error.localizedDescription)")
            }
        }
    }

    @objc func skipCurrentUpdate() {
        guard let version = latestVersion else { return }
        UserDefaults.standard.set(version, forKey: Preferences.skippedUpdateVersionKey)
        latestVersion = nil
        NotificationCenter.default.post(name: .updateCheckStateChanged, object: nil)
    }

    // MARK: - Actions: Force Quit

    @objc func forceQuitApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
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

    // MARK: - Actions: Auto Quit

    @objc func toggleAutoQuit() {
        Preferences.autoQuitEnabled.toggle()
        autoQuitManager?.isEnabled = Preferences.autoQuitEnabled
    }

    @objc func setAutoQuitTimeout(_ sender: NSMenuItem) {
        Preferences.autoQuitTimeoutMinutes = sender.tag
        autoQuitManager?.timeoutMinutes = sender.tag
    }

    @objc func excludeFrontmostFromAutoQuit() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        var excluded = Preferences.autoQuitExcludedBundleIDs
        if !excluded.contains(bundleID) {
            excluded.append(bundleID)
            Preferences.autoQuitExcludedBundleIDs = excluded
            autoQuitManager?.excludedBundleIDs = Set(excluded)
        }
    }

    @objc func clearAutoQuitExclusions() {
        Preferences.autoQuitExcludedBundleIDs = []
        autoQuitManager?.excludedBundleIDs = []
    }

    // MARK: - Actions: Background Apps

    @objc func toggleShowBackgroundApps() {
        Preferences.showBackgroundApps.toggle()
        showAllBackgroundApps = false
    }

    @objc func toggleShowAllBackgroundApps() {
        showAllBackgroundApps.toggle()
    }

    // MARK: - Actions: Appearance

    @objc func setMenuAppearance(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Preferences.menuAppearance = value
    }

    // MARK: - Actions: Shortcut

    @objc func showKeyRecorder() {
        let panel = KeyRecorderPanel(
            currentKeyCode: hotKeyManager?.keyCode ?? UInt32(kVK_ANSI_Q),
            currentModifiers: hotKeyManager?.modifiers ?? UInt32(cmdKey | optionKey)
        )
        panel.onKeyRecorded = { [weak self] keyCode, modifiers in
            self?.hotKeyManager?.updateBinding(keyCode: keyCode, modifiers: modifiers)
        }
        panel.showRecorder()
    }

    // MARK: - Actions: General

    @objc func openCreatorLink() {
        guard let url = URL(string: "https://giraybatiturk.com") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("ForceQuitX: Launch at Login toggle failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Launch at Login Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Settings Window

    @objc func showSettingsWindow() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: SettingsWindow())
            let window = NSWindow(contentViewController: hostingController)
            window.title = "ForceQuitX Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setFrameAutosaveName("ForceQuitXSettings")
            window.center()
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitSelf() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - HotKeyDelegate

extension AppDelegate: HotKeyDelegate {
    func hotKeyTriggered() {
        quitAllApps()
    }
}

extension Notification.Name {
    static let updateCheckStateChanged = Notification.Name("UpdateCheckStateChanged")
}
