import XCTest

@testable import ForceQuitX

final class AutoQuitManagerTests: XCTestCase {

    // MARK: - isIdleBeyondTimeout

    func testNotIdleBeforeTimeout() {
        let now = Date()
        let lastActive = now.addingTimeInterval(-29 * 60)  // 29 min ago
        XCTAssertFalse(
            AutoQuitManager.isIdleBeyondTimeout(lastActive: lastActive, now: now, timeoutMinutes: 30)
        )
    }

    func testIdleExactlyAtTimeout() {
        let now = Date()
        let lastActive = now.addingTimeInterval(-30 * 60)  // exactly 30 min ago
        XCTAssertTrue(
            AutoQuitManager.isIdleBeyondTimeout(lastActive: lastActive, now: now, timeoutMinutes: 30)
        )
    }

    func testIdleBeyondTimeout() {
        let now = Date()
        let lastActive = now.addingTimeInterval(-45 * 60)  // 45 min ago
        XCTAssertTrue(
            AutoQuitManager.isIdleBeyondTimeout(lastActive: lastActive, now: now, timeoutMinutes: 30)
        )
    }

    func testJustActivatedIsNotIdle() {
        let now = Date()
        XCTAssertFalse(
            AutoQuitManager.isIdleBeyondTimeout(lastActive: now, now: now, timeoutMinutes: 15)
        )
    }

    func testRespectsCustomTimeout() {
        let now = Date()
        let lastActive = now.addingTimeInterval(-90 * 60)  // 90 min ago

        // Idle past the 60-minute setting...
        XCTAssertTrue(
            AutoQuitManager.isIdleBeyondTimeout(lastActive: lastActive, now: now, timeoutMinutes: 60)
        )
        // ...but not yet past a 2-hour setting.
        XCTAssertFalse(
            AutoQuitManager.isIdleBeyondTimeout(lastActive: lastActive, now: now, timeoutMinutes: 120)
        )
    }

    func testFutureLastActiveIsNotIdle() {
        // Clock skew guard: a lastActive in the future must never read as idle.
        let now = Date()
        let lastActive = now.addingTimeInterval(60)
        XCTAssertFalse(
            AutoQuitManager.isIdleBeyondTimeout(lastActive: lastActive, now: now, timeoutMinutes: 30)
        )
    }
}
