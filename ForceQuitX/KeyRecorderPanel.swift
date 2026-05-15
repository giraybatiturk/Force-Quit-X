import AppKit
import Carbon

class KeyRecorderPanel: NSPanel {

    var onKeyRecorded: ((UInt32, UInt32) -> Void)?

    private let instructionLabel = NSTextField(labelWithString: "Press a key combination…")
    private let currentBindingLabel = NSTextField(labelWithString: "")
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset to Default", target: nil, action: nil)

    private let currentKeyCode: UInt32
    private let currentModifiers: UInt32

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
        setupViews()
    }

    private func setupViews() {
        guard let contentView else { return }

        instructionLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
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
    }

    // MARK: - Key Capture

    override func keyDown(with event: NSEvent) {
        let carbon = event.carbonModifiers

        // Require at least one modifier key
        let modifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        guard carbon & modifierMask != 0 else {
            NSSound.beep()
            return
        }

        let keyCode = UInt32(event.keyCode)
        onKeyRecorded?(keyCode, carbon)
        close()
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
