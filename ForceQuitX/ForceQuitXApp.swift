import AppKit
import Carbon
import ServiceManagement
import SwiftUI

@main
struct ForceQuitXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var eventHandlerRef: EventHandlerRef?
    var latestVersion: String?

    private func normalizedVersion(_ version: String) -> String {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let icon = NSImage(named: "MenubarIcon")
            icon?.isTemplate = true
            icon?.accessibilityDescription = "ForceQuitX"
            button.image =
                icon
                ?? NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "ForceQuitX")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        registerGlobalHotKey()
        checkForUpdates()
    }

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

            // Honor "Skip This Version" until a newer one ships.
            let skippedVersion = UserDefaults.standard.string(forKey: "SkippedUpdateVersion")
            if skippedVersion == normalizedLatest { return }

            DispatchQueue.main.async { self.latestVersion = normalizedLatest }
        }.resume()
    }

    @objc func openReleasesPage() {
        guard let url = URL(string: "https://github.com/giraybatiturk/Force-Quit-X/releases/latest") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func skipCurrentUpdate() {
        guard let version = latestVersion else { return }
        UserDefaults.standard.set(version, forKey: "SkippedUpdateVersion")
        latestVersion = nil
    }

    func registerGlobalHotKey() {
        // Tear down any prior registration so re-entry doesn't leak.
        if let h = hotKeyRef {
            UnregisterEventHotKey(h)
            hotKeyRef = nil
        }
        if let e = eventHandlerRef {
            RemoveEventHandler(e)
            eventHandlerRef = nil
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let ptr = userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                DispatchQueue.main.async { delegate.openMenu() }
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            NSLog("ForceQuitX: InstallEventHandler failed: \(installStatus)")
            return
        }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = 0x4651_5831  // "FQX1"
        hotKeyID.id = 1

        // Global hotkey: ⌘⌥Q
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Q),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if regStatus != noErr {
            NSLog("ForceQuitX: RegisterEventHotKey failed: \(regStatus)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let h = hotKeyRef {
            UnregisterEventHotKey(h)
            hotKeyRef = nil
        }
        if let e = eventHandlerRef {
            RemoveEventHandler(e)
            eventHandlerRef = nil
        }
    }

    func openMenu() {
        quitAllApps()
    }

    // NSMenuDelegate: menü açılmadan önce listeyi güncelle
    func menuWillOpen(_ menu: NSMenu) {
        buildMenu(menu)
    }

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
        // No keyEquivalent here — the global Carbon hotkey (⌘⌥Q) already triggers quitAllApps,
        // and registering the same combo on a menu item conflicts with it while the menu is open.
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

        // — Running apps section title —
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

        // — App list —
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

        menu.addItem(NSMenuItem(title: "Go to Creator ↗", action: #selector(openCreatorLink), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ForceQuitX", action: #selector(quitSelf), keyEquivalent: "q"))
    }

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
        // Capture the frontmost app BEFORE showing the modal — activating ForceQuitX
        // for the alert would otherwise make ForceQuitX itself the frontmost.
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
        let suppressKey = "ForceQuitAllConfirmedV1"
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

        // Make Cancel the Enter-key default so accidental Enter presses don't quit everything.
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
