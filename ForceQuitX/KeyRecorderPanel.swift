import AppKit
import Carbon

class KeyRecorderPanel: NSPanel {

    var onKeyRecorded: ((UInt32, UInt32) -> Void)?
    var onClose: (() -> Void)?

    private let instructionLabel = NSTextField(labelWithString: "Press a key combination…")
    private let currentBindingLabel = NSTextField(labelWithString: "")
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset to Default", target: nil, action: nil)

    private let currentKeyCode: UInt32
    private let currentModifiers: UInt32

    private var eventMonitor: Any?

    init(currentKeyCode: UInt32, currentModifiers: UInt32) {
        self.currentKeyCode = currentKeyCode
        self.currentModifiers = currentModifiers
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isMovableByWindowBackground = true
        self.title = "Record Shortcut"
        self.becomesKeyOnlyIfNeeded = false
        // Owner (AppDelegate) holds the strong reference; don't let AppKit release
        // the panel on close, which would over-release and crash.
        self.isReleasedWhenClosed = false
        setupViews()
    }

    private func setupViews() {
        guard let contentView else { return }

        instructionLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        instructionLabel.alignment = .center
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(instructionLabel)

        let displayStr = HotKeyManager.displayString(keyCode: currentKeyCode, modifiers: currentModifiers)
        currentBindingLabel.stringValue = "Current: \(displayStr)"
        currentBindingLabel.font = NSFont.systemFont(ofSize: 12)
        currentBindingLabel.textColor = NSColor.secondaryLabelColor
        currentBindingLabel.alignment = .center
        currentBindingLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(currentBindingLabel)

        cancelButton.target = self
        cancelButton.action = #selector(cancelRecording)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.keyEquivalent = "\u{1b}"  // Escape
        contentView.addSubview(cancelButton)

        resetButton.target = self
        resetButton.action = #selector(resetToDefault)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(resetButton)

        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            instructionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            currentBindingLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 8),
            currentBindingLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            currentBindingLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            cancelButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            cancelButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            resetButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            resetButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
        ])
    }

    func showRecorder() {
        NSApp.activate(ignoringOtherApps: true)
        center()
        makeKeyAndOrderFront(nil)

        // A local key-down monitor captures every keystroke while the recorder is
        // open — including ⌘-bearing combos, which are delivered as key equivalents
        // and never reach a window's keyDown. This sidesteps key-window / responder
        // issues entirely. Removed on close.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                self.updateLivePreview(event)
                return nil
            }
            self.handleRecorded(event)
            return nil  // swallow so it doesn't beep or hit a menu equivalent
        }
    }

    /// Live feedback: show the modifier glyphs as they're held, before the final
    /// key commits the shortcut.
    private func updateLivePreview(_ event: NSEvent) {
        let glyphs = Self.modifierGlyphs(event.carbonModifiers)
        instructionLabel.stringValue = glyphs.isEmpty ? "Press a key combination…" : glyphs
    }

    private static func modifierGlyphs(_ carbon: UInt32) -> String {
        var parts: [String] = []
        if carbon & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbon & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbon & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbon & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    // MARK: - Key Capture

    private func handleRecorded(_ event: NSEvent) {
        // Escape cancels (the Cancel button's key equivalent never fires while the
        // monitor is swallowing events).
        if event.keyCode == UInt16(kVK_Escape) {
            close()
            return
        }

        let carbon = event.carbonModifiers
        let modifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        guard carbon & modifierMask != 0 else {
            NSSound.beep()  // require at least one modifier
            return
        }

        onKeyRecorded?(UInt32(event.keyCode), carbon)
        close()
    }

    // MARK: - Lifecycle

    override func close() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        super.close()
        onClose?()
        onClose = nil
    }

    // MARK: - Actions

    @objc private func cancelRecording() {
        close()
    }

    @objc private func resetToDefault() {
        // Default: ⌘⌥Q
        onKeyRecorded?(UInt32(kVK_ANSI_Q), UInt32(cmdKey | optionKey))
        close()
    }
}
