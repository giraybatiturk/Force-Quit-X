import Carbon
import XCTest

@testable import ForceQuitX

final class HotKeyManagerTests: XCTestCase {

    // MARK: - displayString

    func testDefaultShortcut() {
        let display = HotKeyManager.displayString(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(cmdKey | optionKey)
        )
        XCTAssertEqual(display, "⌥⌘Q")
    }

    func testModifierOrderIsCanonical() {
        // Apple's canonical glyph order is ⌃⌥⇧⌘ regardless of input order.
        let display = HotKeyManager.displayString(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        XCTAssertEqual(display, "⌃⌥⇧⌘A")
    }

    func testSingleModifier() {
        let display = HotKeyManager.displayString(
            keyCode: UInt32(kVK_ANSI_W),
            modifiers: UInt32(cmdKey)
        )
        XCTAssertEqual(display, "⌘W")
    }

    func testFunctionKey() {
        let display = HotKeyManager.displayString(
            keyCode: UInt32(kVK_F5),
            modifiers: UInt32(controlKey)
        )
        XCTAssertEqual(display, "⌃F5")
    }

    func testSpecialKeyGlyph() {
        let display = HotKeyManager.displayString(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        XCTAssertEqual(display, "⇧⌘Space")
    }

    func testUnknownKeyCodeFallback() {
        // Key codes absent from the lookup table fall back to "Key<n>".
        let display = HotKeyManager.displayString(keyCode: 9999, modifiers: UInt32(cmdKey))
        XCTAssertEqual(display, "⌘Key9999")
    }
}
