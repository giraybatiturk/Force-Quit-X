import XCTest

@testable import ForceQuitX

final class VersionComparatorTests: XCTestCase {

    // MARK: - normalize

    func testNormalizeStripsLeadingVPrefix() {
        XCTAssertEqual(VersionComparator.normalize("v1.2.3"), "1.2.3")
        XCTAssertEqual(VersionComparator.normalize("V1.2.3"), "1.2.3")
    }

    func testNormalizeStripsTrailingZeroComponents() {
        XCTAssertEqual(VersionComparator.normalize("1.2.0"), "1.2")
        XCTAssertEqual(VersionComparator.normalize("1.0.0"), "1")
        XCTAssertEqual(VersionComparator.normalize("v1.0.0"), "1")
    }

    func testNormalizePreservesNonZeroTail() {
        XCTAssertEqual(VersionComparator.normalize("1.2.3"), "1.2.3")
        XCTAssertEqual(VersionComparator.normalize("1.0.3"), "1.0.3")
    }

    func testNormalizeStripsPrereleaseAndBuildSuffixes() {
        XCTAssertEqual(VersionComparator.normalize("1.2.0-beta"), "1.2")
        XCTAssertEqual(VersionComparator.normalize("1.2.3-rc.1"), "1.2.3")
        XCTAssertEqual(VersionComparator.normalize("1.2.3+sha.abc"), "1.2.3")
        XCTAssertEqual(VersionComparator.normalize("v1.2.0-beta+sha"), "1.2")
    }

    func testNormalizeReturnsZeroForAllZerosOrEmpty() {
        XCTAssertEqual(VersionComparator.normalize("0.0.0"), "0")
        XCTAssertEqual(VersionComparator.normalize("v0.0"), "0")
        XCTAssertEqual(VersionComparator.normalize(""), "0")
    }

    func testNormalizeReturnsZeroForNonNumericInput() {
        XCTAssertEqual(VersionComparator.normalize("abc"), "0")
        XCTAssertEqual(VersionComparator.normalize("v"), "0")
    }

    // MARK: - isNewer

    func testIsNewerDetectsHigherPatch() {
        XCTAssertTrue(VersionComparator.isNewer("1.2.4", than: "1.2.3"))
        XCTAssertFalse(VersionComparator.isNewer("1.2.3", than: "1.2.4"))
    }

    func testIsNewerDetectsHigherMinor() {
        XCTAssertTrue(VersionComparator.isNewer("1.3.0", than: "1.2.9"))
    }

    func testIsNewerDetectsHigherMajor() {
        XCTAssertTrue(VersionComparator.isNewer("2.0.0", than: "1.99.99"))
    }

    func testIsNewerEqualVersionsReturnsFalse() {
        XCTAssertFalse(VersionComparator.isNewer("1.2.3", than: "1.2.3"))
        XCTAssertFalse(VersionComparator.isNewer("1.0.0", than: "1"))
        XCTAssertFalse(VersionComparator.isNewer("v1.2.0", than: "1.2"))
    }

    func testIsNewerIgnoresLeadingVPrefix() {
        XCTAssertTrue(VersionComparator.isNewer("v1.2.4", than: "1.2.3"))
        XCTAssertTrue(VersionComparator.isNewer("1.2.4", than: "v1.2.3"))
    }

    func testIsNewerUsesNumericCompareNotLexicographic() {
        // Without numeric comparison "1.10" would sort before "1.2" lexically.
        XCTAssertTrue(VersionComparator.isNewer("1.10.0", than: "1.2.0"))
        XCTAssertTrue(VersionComparator.isNewer("1.10", than: "1.9"))
    }

    func testIsNewerHandlesPrereleaseAsBaseCore() {
        // "1.2.0-beta" normalises to "1.2"; "1.2.0" normalises to "1.2" → equal, not newer.
        XCTAssertFalse(VersionComparator.isNewer("1.2.0-beta", than: "1.2.0"))
        XCTAssertTrue(VersionComparator.isNewer("1.2.1-beta", than: "1.2.0"))
    }
}
