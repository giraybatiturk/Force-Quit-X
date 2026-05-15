import AppKit
import Carbon
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var latestVersion: String?
    var hotKeyManager: HotKeyManager?
    var autoQuitManager: AutoQuitManager?

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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregister()
        autoQuitManager?.stop()
    }

    // MARK: - Icon Style

    func applyIconStyle() {
        guard let button = statusItem.button else { return }
        switch Preferences.iconStyle {
        case "sfSymbolX":
            button.image = NSImage(
                systemSymbolName: "xmark.circle.fill", accessibilityDescription: "ForceQuitX")
        case "sfSymbolPower":
            button.image = NSImage(
                systemSymbolName: "power", accessibilityDescription: "ForceQuitX")
        default:
            let icon = NSImage(named: "MenubarIcon")
            icon?.isTemplate = true
            icon?.accessibilityDescription = "ForceQuitX"
            button.image =
                icon
                ?? NSImage(
                    systemSymbolName: "xmark.circle.fill", accessibilityDescription: "ForceQuitX")
        }
        button.image?.isTemplate = true
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

    func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/giraybatiturk/Force-Quit-X/releases/latest"),
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return }

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
            if let error {
                NSLog("ForceQuitX: update check failed: \(error.localizedDescription)")
                return
            }
            guard let self, let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tagName = json["tag_name"] as? String
            else { return }
            let normalizedLatest = self.normalizedVersion(tagName)
            let normalizedCurrent = self.normalizedVersion(currentVersion)

            guard normalizedLatest.compare(normalizedCurrent, options: .numeric) == .orderedDescending
            else { return }

            let skippedVersion = UserDefaults.standard.string(forKey: Preferences.skippedUpdateVersionKey)
            if skippedVersion == normalizedLatest { return }

            DispatchQueue.main.async { self.latestVersion = normalizedLatest }
        }.resume()
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

        // — App header —
        let headerItem = NSMenuItem()
        headerItem.attributedTitle = NSAttributedString(
            string: "ForceQuitX",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // — Update available —
        if let latest = latestVersion {
            let updateItem = NSMenuItem(
                title: "Update Available (v\(latest)) ↗",
                action: #selector(openReleasesPage),
                keyEquivalent: ""
            )
            updateItem.attributedTitle = NSAttributedString(
                string: "⬆ Update Available  v\(latest)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.systemOrange,
                ]
            )
            menu.addItem(updateItem)

            let skipItem = NSMenuItem(
                title: "Skip This Version",
                action: #selector(skipCurrentUpdate),
                keyEquivalent: ""
            )
            skipItem.attributedTitle = NSAttributedString(
                string: "Skip v\(latest)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
            skipItem.indentationLevel = 1
            menu.addItem(skipItem)
        }

        menu.addItem(NSMenuItem.separator())

        // — Force Quit All —
        let quitAllItem = NSMenuItem(
            title: "Force Quit All\(userApps.isEmpty ? "" : " (\(userApps.count) apps)")",
            action: userApps.isEmpty ? nil : #selector(quitAllApps),
            keyEquivalent: ""
        )
        menu.addItem(quitAllItem)

        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let exceptFrontmostCount = userApps.filter { $0.app.bundleIdentifier != frontmostBundleID }.count
        let quitExceptFrontmostItem = NSMenuItem(
            title:
                "Force Quit All Except Frontmost\(exceptFrontmostCount > 0 ? " (\(exceptFrontmostCount) apps)" : "")",
            action: exceptFrontmostCount > 0 ? #selector(quitAllAppsExceptFrontmost) : nil,
            keyEquivalent: ""
        )
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
            let menuItem = NSMenuItem(
                title: name,
                action: #selector(forceQuitApp(_:)),
                keyEquivalent: ""
            )
            menuItem.representedObject = app

            let attrTitle = NSMutableAttributedString(
                string: name + "\n",
                attributes: [.font: NSFont.systemFont(ofSize: 13)]
            )
            attrTitle.append(
                NSAttributedString(
                    string: "Force Quit",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 10),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                ))
            menuItem.attributedTitle = attrTitle

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

        // — Auto Quit section —
        menu.addItem(NSMenuItem.separator())
        buildAutoQuitSection(menu)

        menu.addItem(NSMenuItem.separator())

        // — Settings —
        let launchAtLogin = SMAppService.mainApp.status == .enabled
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.state = launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        let bgToggle = NSMenuItem(
            title: "Show Background Processes",
            action: #selector(toggleShowBackgroundApps),
            keyEquivalent: ""
        )
        bgToggle.state = Preferences.showBackgroundApps ? .on : .off
        menu.addItem(bgToggle)

        // — Change Shortcut —
        let shortcutDisplay = hotKeyManager?.displayString() ?? "⌘⌥Q"
        let shortcutItem = NSMenuItem(
            title: "Change Shortcut  \(shortcutDisplay)",
            action: #selector(showKeyRecorder),
            keyEquivalent: ""
        )
        menu.addItem(shortcutItem)

        // — Appearance submenu —
        let appearanceSubmenu = NSMenu()
        for (title, value) in [
            ("System Default", "system"), ("Always Light", "light"), ("Always Dark", "dark"),
        ] {
            let item = NSMenuItem(title: title, action: #selector(setMenuAppearance(_:)), keyEquivalent: "")
            item.representedObject = value
            item.state = Preferences.menuAppearance == value ? .on : .off
            appearanceSubmenu.addItem(item)
        }
        appearanceSubmenu.addItem(NSMenuItem.separator())
        for (title, value) in [
            ("Icon: Custom X", "custom"), ("Icon: Circle X", "sfSymbolX"), ("Icon: Power", "sfSymbolPower"),
        ] {
            let item = NSMenuItem(title: title, action: #selector(setIconStyle(_:)), keyEquivalent: "")
            item.representedObject = value
            item.state = Preferences.iconStyle == value ? .on : .off
            appearanceSubmenu.addItem(item)
        }
        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        appearanceItem.submenu = appearanceSubmenu
        menu.addItem(appearanceItem)

        menu.addItem(
            NSMenuItem(title: "Go to Creator ↗", action: #selector(openCreatorLink), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Quit ForceQuitX", action: #selector(quitSelf), keyEquivalent: "q"))
    }

    // MARK: - Auto Quit Menu Section

    private func buildAutoQuitSection(_ menu: NSMenu) {
        let autoQuitHeader = NSMenuItem()
        autoQuitHeader.attributedTitle = NSAttributedString(
            string: "AUTO QUIT",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        autoQuitHeader.isEnabled = false
        menu.addItem(autoQuitHeader)

        let toggleItem = NSMenuItem(
            title: "Auto Quit Idle Apps",
            action: #selector(toggleAutoQuit),
            keyEquivalent: ""
        )
        toggleItem.state = Preferences.autoQuitEnabled ? .on : .off
        menu.addItem(toggleItem)

        // Timeout submenu
        let timeoutSubmenu = NSMenu()
        let currentTimeout = Preferences.autoQuitTimeoutMinutes
        for (label, minutes) in [
            ("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240),
        ] {
            let item = NSMenuItem(title: label, action: #selector(setAutoQuitTimeout(_:)), keyEquivalent: "")
            item.tag = minutes
            item.state = currentTimeout == minutes ? .on : .off
            timeoutSubmenu.addItem(item)
        }
        let timeoutItem = NSMenuItem(title: "Timeout: \(formatTimeout(currentTimeout))", action: nil, keyEquivalent: "")
        timeoutItem.submenu = timeoutSubmenu
        menu.addItem(timeoutItem)

        // Termination mode submenu
        let terminationSubmenu = NSMenu()
        let usesForce = Preferences.autoQuitUsesForceTerminate
        let gracefulItem = NSMenuItem(
            title: "Graceful (Save Prompt)", action: #selector(setTerminationGraceful), keyEquivalent: "")
        gracefulItem.state = usesForce ? .off : .on
        terminationSubmenu.addItem(gracefulItem)
        let forceItem = NSMenuItem(
            title: "Force (Immediate)", action: #selector(setTerminationForce), keyEquivalent: "")
        forceItem.state = usesForce ? .on : .off
        terminationSubmenu.addItem(forceItem)
        let terminationItem = NSMenuItem(
            title: "Termination: \(usesForce ? "Force" : "Graceful")", action: nil, keyEquivalent: "")
        terminationItem.submenu = terminationSubmenu
        menu.addItem(terminationItem)

        // Exclude frontmost
        let excludeItem = NSMenuItem(
            title: "Exclude Frontmost App",
            action: Preferences.autoQuitEnabled ? #selector(excludeFrontmostFromAutoQuit) : nil,
            keyEquivalent: ""
        )
        menu.addItem(excludeItem)

        // Clear exclusions
        let excluded = Preferences.autoQuitExcludedBundleIDs
        let clearItem = NSMenuItem(
            title: excluded.isEmpty ? "Clear Exclusions" : "Clear Exclusions (\(excluded.count))",
            action: excluded.isEmpty ? nil : #selector(clearAutoQuitExclusions),
            keyEquivalent: ""
        )
        menu.addItem(clearItem)
    }

    private func formatTimeout(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    // MARK: - Actions: Update

    @objc func openReleasesPage() {
        guard let url = URL(string: "https://github.com/giraybatiturk/Force-Quit-X/releases/latest") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func skipCurrentUpdate() {
        guard let version = latestVersion else { return }
        UserDefaults.standard.set(version, forKey: Preferences.skippedUpdateVersionKey)
        latestVersion = nil
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

    @objc func setTerminationGraceful() {
        Preferences.autoQuitUsesForceTerminate = false
        autoQuitManager?.usesForceTerminate = false
    }

    @objc func setTerminationForce() {
        Preferences.autoQuitUsesForceTerminate = true
        autoQuitManager?.usesForceTerminate = true
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

    @objc func setIconStyle(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Preferences.iconStyle = value
        applyIconStyle()
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
