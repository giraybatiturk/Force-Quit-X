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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "ForceQuitX")
        }
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        
        registerGlobalHotKey()
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
        
        // Çalışan kullanıcı uygulamalarını al (Finder ve kendisi hariç)
        let userApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                app.localizedName != nil &&
                app.bundleIdentifier != "com.apple.finder" &&
                app.bundleIdentifier != selfBundleID
            }
            .sorted { $0.localizedName! < $1.localizedName! }
        
        // Quit All User Apps butonu
        let quitAllItem = NSMenuItem(
            title: "⚡ Quit All User Apps (\(userApps.count))",
            action: userApps.isEmpty ? nil : #selector(quitAllApps),
            keyEquivalent: ""
        )
        menu.addItem(quitAllItem)
        menu.addItem(NSMenuItem.separator())
        
        if userApps.isEmpty {
            let emptyItem = NSMenuItem(title: "No running apps", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for app in userApps {
                let menuItem = NSMenuItem(
                    title: "✕  \(app.localizedName!)",
                    action: #selector(forceQuitApp(_:)),
                    keyEquivalent: ""
                )
                menuItem.representedObject = app
                if let icon = app.icon {
                    icon.size = NSSize(width: 16, height: 16)
                    menuItem.image = icon
                }
                menu.addItem(menuItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // ⌘⌥Q kısayolunu tooltip olarak göster
        let hotkeyInfo = NSMenuItem(title: "⌘⌥Q → Quit All User Apps", action: nil, keyEquivalent: "")
        hotkeyInfo.isEnabled = false
        menu.addItem(hotkeyInfo)
        
        menu.addItem(NSMenuItem.separator())
        
        // Launch at Login toggle
        let launchAtLogin = SMAppService.mainApp.status == .enabled
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.state = launchAtLogin ? .on : .off
        menu.addItem(loginItem)
        
        menu.addItem(NSMenuItem.separator())
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
