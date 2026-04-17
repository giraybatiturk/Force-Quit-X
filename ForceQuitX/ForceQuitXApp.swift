import SwiftUI
import AppKit
import Carbon
import ServiceManagement

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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "ForceQuitX")
        }
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        
        registerGlobalHotKey()
        checkForUpdates()
    }
    
    func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/giraybatiturk/Force-Quit-X/releases/latest") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }
            let latest = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            if latest.compare(current, options: .numeric) == .orderedDescending {
                DispatchQueue.main.async { self?.latestVersion = latest }
            }
        }.resume()
    }
    
    @objc func openReleasesPage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/giraybatiturk/Force-Quit-X/releases/latest")!)
    }
    
    func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        InstallEventHandler(
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
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = 0x46515831 // "FQX1"
        hotKeyID.id = 1
        
        // Global kısayol: ⌘⌥Q
        RegisterEventHotKey(
            UInt32(kVK_ANSI_Q),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
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
        
        let userApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                app.localizedName != nil &&
                app.bundleIdentifier != "com.apple.finder" &&
                app.bundleIdentifier != selfBundleID
            }
            .sorted { $0.localizedName! < $1.localizedName! }
        
        // — App header —
        let headerItem = NSMenuItem()
        headerItem.attributedTitle = NSAttributedString(
            string: "ForceQuitX",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
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
                    .foregroundColor: NSColor.systemOrange
                ]
            )
            menu.addItem(updateItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // — Force Quit All —
        let quitAllItem = NSMenuItem(
            title: "Force Quit All\(userApps.isEmpty ? "" : " (\(userApps.count) apps)")",
            action: userApps.isEmpty ? nil : #selector(quitAllApps),
            keyEquivalent: "q"
        )
        quitAllItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(quitAllItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // — Running apps section title —
        let sectionItem = NSMenuItem()
        sectionItem.attributedTitle = NSAttributedString(
            string: userApps.isEmpty ? "NO RUNNING APPS" : "RUNNING APPS",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        sectionItem.isEnabled = false
        menu.addItem(sectionItem)
        
        // — App list —
        for app in userApps {
            let menuItem = NSMenuItem(
                title: app.localizedName!,
                action: #selector(forceQuitApp(_:)),
                keyEquivalent: ""
            )
            menuItem.representedObject = app
            
            let attrTitle = NSMutableAttributedString(
                string: app.localizedName! + "\n",
                attributes: [.font: NSFont.systemFont(ofSize: 13)]
            )
            attrTitle.append(NSAttributedString(
                string: "Force Quit",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.secondaryLabelColor
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
        let selfBundleID = Bundle.main.bundleIdentifier
        let userApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular &&
            app.bundleIdentifier != "com.apple.finder" &&
            app.bundleIdentifier != selfBundleID
        }
        for app in userApps where !app.isTerminated {
            app.forceTerminate()
        }
    }
    
    @objc func openCreatorLink() {
        NSWorkspace.shared.open(URL(string: "https://giraybatiturk.com")!)
    }
    
    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Launch at Login hatası: \(error)")
        }
    }
    
    @objc func quitSelf() {
        NSApplication.shared.terminate(nil)
    }
}
