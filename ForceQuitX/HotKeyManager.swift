import AppKit
import Carbon

protocol HotKeyDelegate: AnyObject {
    func hotKeyTriggered()
}

class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private weak var delegate: HotKeyDelegate?

    private(set) var keyCode: UInt32
    private(set) var modifiers: UInt32

    init(delegate: HotKeyDelegate) {
        self.delegate = delegate

        let savedKeyCode = Preferences.customHotKeyCode
        let savedModifiers = Preferences.customHotKeyModifiers
        if savedKeyCode > 0 && savedModifiers > 0 {
            self.keyCode = UInt32(savedKeyCode)
            self.modifiers = UInt32(savedModifiers)
        } else {
            self.keyCode = UInt32(kVK_ANSI_Q)
            self.modifiers = UInt32(cmdKey | optionKey)
        }
    }

    // MARK: - Registration

    func register() {
        // Tear down any prior registration so re-entry doesn't leak.
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let ptr = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(ptr).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.delegate?.hotKeyTriggered()
                }
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

        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if regStatus != noErr {
            NSLog("ForceQuitX: RegisterEventHotKey failed: \(regStatus)")
        }
    }

    func unregister() {
        if let h = hotKeyRef {
            UnregisterEventHotKey(h)
            hotKeyRef = nil
        }
        if let e = eventHandlerRef {
            RemoveEventHandler(e)
            eventHandlerRef = nil
        }
    }

    // MARK: - Update Binding

    func updateBinding(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        self.keyCode = keyCode
        self.modifiers = modifiers
        Preferences.customHotKeyCode = Int(keyCode)
        Preferences.customHotKeyModifiers = Int(modifiers)
        register()
    }

    // MARK: - Display String

    func displayString() -> String {
        return Self.displayString(keyCode: keyCode, modifiers: modifiers)
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    // MARK: - Key Code Lookup

    private static func keyCodeToString(_ keyCode: UInt32) -> String {
        // Common virtual key codes to readable strings
        let keyMap: [UInt32: String] = [
            // Letters
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            // Numbers
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            // Function keys
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            // Special keys
            UInt32(kVK_Space): "Space", UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
            UInt32(kVK_Tab): "⇥", UInt32(kVK_Return): "↩",
            // Arrows
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
            // Symbols
            UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
            UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
            UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
            UInt32(kVK_ANSI_Grave): "`",
        ]
        return keyMap[keyCode] ?? "Key\(keyCode)"
    }
}

// MARK: - NSEvent Modifier Conversion

extension NSEvent {
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifierFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { carbon |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
