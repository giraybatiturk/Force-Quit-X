import AppKit
import ServiceManagement
import SwiftUI

struct ExcludedAppRow: Identifiable {
    let id: String  // bundleID
    let name: String
    let icon: NSImage?
}

struct SettingsWindow: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showBackgroundApps = Preferences.showBackgroundApps
    @State private var menuAppearance = Preferences.menuAppearance

    @State private var autoQuitEnabled = Preferences.autoQuitEnabled
    @State private var timeoutMinutes = Preferences.autoQuitTimeoutMinutes
    @State private var excludedApps: [ExcludedAppRow] = []

    @State private var shortcutDisplay = HotKeyManager.savedDisplayString()

    @State private var latestVersion: String? = (NSApp.delegate as? AppDelegate)?.latestVersion
    @State private var isCheckingForUpdates: Bool = (NSApp.delegate as? AppDelegate)?.isCheckingForUpdates ?? false
    @State private var lastUpdateCheck: Date? = (NSApp.delegate as? AppDelegate)?.lastUpdateCheck

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty || build == short ? "v\(short)" : "v\(short) (\(build))"
    }

    private var addableApps: [NSRunningApplication] {
        let excluded = Set(excludedApps.map(\.id))
        let selfBundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular,
                    let bundleID = app.bundleIdentifier,
                    app.localizedName != nil,
                    bundleID != "com.apple.finder",
                    bundleID != selfBundleID,
                    !excluded.contains(bundleID)
                else { return false }
                return true
            }
            .sorted {
                ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "")
                    == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                Section("General") {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            toggleLaunchAtLogin(enabled: newValue)
                        }

                    Toggle("Show Background Processes", isOn: $showBackgroundApps)
                        .onChange(of: showBackgroundApps) { _, newValue in
                            Preferences.showBackgroundApps = newValue
                        }
                }

                Section("Auto Quit") {
                    Toggle("Auto Quit Idle Apps", isOn: $autoQuitEnabled)
                        .onChange(of: autoQuitEnabled) { _, newValue in
                            Preferences.autoQuitEnabled = newValue
                            appDelegate?.autoQuitManager?.isEnabled = newValue
                        }

                    Picker("Timeout", selection: $timeoutMinutes) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("4 hours").tag(240)
                    }
                    .onChange(of: timeoutMinutes) { _, newValue in
                        Preferences.autoQuitTimeoutMinutes = newValue
                        appDelegate?.autoQuitManager?.timeoutMinutes = newValue
                    }
                }

                Section("Excluded Apps") {
                    if excludedApps.isEmpty {
                        Text("No excluded apps. Excluded apps will never be auto-quit.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(excludedApps) { row in
                            HStack(spacing: 8) {
                                if let icon = row.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                } else {
                                    Image(systemName: "app.dashed")
                                        .frame(width: 18, height: 18)
                                }
                                Text(row.name)
                                Spacer()
                                Button {
                                    removeExclusion(row.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from exclusions")
                            }
                        }
                    }

                    HStack {
                        Menu("Add App...") {
                            if addableApps.isEmpty {
                                Text("No running apps available")
                            } else {
                                ForEach(addableApps, id: \.processIdentifier) { app in
                                    Button(app.localizedName ?? "") {
                                        if let bundleID = app.bundleIdentifier {
                                            addExclusion(bundleID)
                                        }
                                    }
                                }
                            }
                        }
                        Button("Add Frontmost") {
                            excludeFrontmost()
                        }
                        Spacer()
                        if !excludedApps.isEmpty {
                            Button("Clear All") {
                                clearExclusions()
                            }
                            .foregroundColor(.red)
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Menu Theme", selection: $menuAppearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: menuAppearance) { _, newValue in
                        Preferences.menuAppearance = newValue
                    }
                }

                Section("Keyboard Shortcut") {
                    HStack {
                        Text("Global Hotkey")
                        Spacer()
                        Text(shortcutDisplay)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                    }

                    Button("Change Shortcut...") {
                        appDelegate?.showKeyRecorder()
                    }
                }

                Section("Updates") {
                    HStack {
                        if let latest = latestVersion {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Update available — v\(latest)")
                                    .font(.callout.weight(.semibold))
                                    .foregroundColor(.orange)
                                Text("You are on \(appVersion).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Download") {
                                Self.openURL("https://github.com/giraybatiturk/Force-Quit-X/releases/latest")
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Skip") {
                                appDelegate?.skipCurrentUpdate()
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("You're up to date")
                                    .font(.callout)
                                if let last = lastUpdateCheck {
                                    Text("Last checked \(Self.relative(from: last))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Not checked yet")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                appDelegate?.checkForUpdatesAction()
                            } label: {
                                if isCheckingForUpdates {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Checking...")
                                    }
                                } else {
                                    Text("Check for Updates")
                                }
                            }
                            .disabled(isCheckingForUpdates)
                        }
                    }
                }

                Section {
                    Button("Visit Creator Website ↗") {
                        Self.openURL("https://giraybatiturk.com")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 440, height: 640)
        .onAppear {
            refreshExcluded()
            shortcutDisplay = HotKeyManager.savedDisplayString()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotKeyChanged)) { _ in
            shortcutDisplay = HotKeyManager.savedDisplayString()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateCheckStateChanged)) { _ in
            latestVersion = appDelegate?.latestVersion
            isCheckingForUpdates = appDelegate?.isCheckingForUpdates ?? false
            lastUpdateCheck = appDelegate?.lastUpdateCheck
        }
    }

    private static func relative(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func openURL(_ string: String) {
        guard let url = URL(string: string) else {
            NSLog("ForceQuitX: invalid URL: \(string)")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(url, configuration: config) { runningApp, error in
            if let error {
                NSLog("ForceQuitX: open URL failed (\(string)): \(error.localizedDescription)")
            } else if runningApp == nil {
                NSLog("ForceQuitX: open URL returned no app (\(string))")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
            Text("ForceQuitX")
                .font(.system(size: 18, weight: .semibold))
            Text(appVersion)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Exclusion helpers

    private func refreshExcluded() {
        let ids = Preferences.autoQuitExcludedBundleIDs
        excludedApps = ids.map { bid in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
            let name: String
            if let url {
                let raw = FileManager.default.displayName(atPath: url.path)
                name = raw.hasSuffix(".app") ? String(raw.dropLast(4)) : raw
            } else {
                name = bid
            }
            let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            return ExcludedAppRow(id: bid, name: name, icon: icon)
        }
    }

    private func persist(_ ids: [String]) {
        Preferences.autoQuitExcludedBundleIDs = ids
        appDelegate?.autoQuitManager?.excludedBundleIDs = Set(ids)
        refreshExcluded()
    }

    private func addExclusion(_ bundleID: String) {
        var ids = Preferences.autoQuitExcludedBundleIDs
        guard !ids.contains(bundleID) else { return }
        ids.append(bundleID)
        persist(ids)
    }

    private func removeExclusion(_ bundleID: String) {
        var ids = Preferences.autoQuitExcludedBundleIDs
        ids.removeAll { $0 == bundleID }
        persist(ids)
    }

    private func excludeFrontmost() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        addExclusion(bundleID)
    }

    private func clearExclusions() {
        persist([])
    }

    private func toggleLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at Login failed: \(error.localizedDescription)")
        }
    }
}
