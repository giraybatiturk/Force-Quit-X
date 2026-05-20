import AppKit
import XCTest

@testable import ForceQuitX

final class BackgroundAppProviderTests: XCTestCase {

    private let selfBundleID = "com.giraybatiturk.forcequitx"

    // MARK: - activation policy

    func testIncludesAccessoryApps() {
        XCTAssertTrue(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .accessory,
                bundleIdentifier: "com.example.menubartool",
                localizedName: "MenuBar Tool",
                selfBundleID: selfBundleID
            )
        )
    }

    func testIncludesProhibitedApps() {
        XCTAssertTrue(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .prohibited,
                bundleIdentifier: "com.example.daemon",
                localizedName: "Daemon",
                selfBundleID: selfBundleID
            )
        )
    }

    func testExcludesRegularApps() {
        XCTAssertFalse(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .regular,
                bundleIdentifier: "com.example.regularapp",
                localizedName: "Regular App",
                selfBundleID: selfBundleID
            )
        )
    }

    // MARK: - name guards

    func testExcludesNilName() {
        XCTAssertFalse(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .accessory,
                bundleIdentifier: "com.example.unnamed",
                localizedName: nil,
                selfBundleID: selfBundleID
            )
        )
    }

    func testExcludesEmptyName() {
        XCTAssertFalse(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .accessory,
                bundleIdentifier: "com.example.empty",
                localizedName: "",
                selfBundleID: selfBundleID
            )
        )
    }

    // MARK: - self filter

    func testExcludesSelf() {
        XCTAssertFalse(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .accessory,
                bundleIdentifier: selfBundleID,
                localizedName: "ForceQuitX",
                selfBundleID: selfBundleID
            )
        )
    }

    func testIncludesUnknownBundleIDWhenSelfBundleIDIsNil() {
        // bundleIdentifier == selfBundleID with both nil would exclude — verify guard.
        XCTAssertFalse(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .accessory,
                bundleIdentifier: nil,
                localizedName: "Anonymous",
                selfBundleID: nil
            )
        )
    }

    func testIncludesAppWithoutBundleIDWhenSelfBundleIDKnown() {
        XCTAssertTrue(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .accessory,
                bundleIdentifier: nil,
                localizedName: "Anonymous Accessory",
                selfBundleID: selfBundleID
            )
        )
    }

    // MARK: - critical-prefix exclusion

    func testExcludesExactCriticalBundleID() {
        for prefix in BackgroundAppProvider.hiddenBundlePrefixes {
            XCTAssertFalse(
                BackgroundAppProvider.shouldInclude(
                    activationPolicy: .accessory,
                    bundleIdentifier: prefix,
                    localizedName: "Critical",
                    selfBundleID: selfBundleID
                ),
                "expected \(prefix) to be excluded"
            )
        }
    }

    func testExcludesChildOfCriticalBundleID() {
        XCTAssertFalse(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .accessory,
                bundleIdentifier: "com.apple.dock.helper",
                localizedName: "Dock Helper",
                selfBundleID: selfBundleID
            )
        )
        XCTAssertFalse(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .accessory,
                bundleIdentifier: "com.apple.finder.subprocess",
                localizedName: "Finder Sub",
                selfBundleID: selfBundleID
            )
        )
    }

    func testDoesNotExcludeBundleIDThatOnlySharesPrefixString() {
        // "com.apple.dockable" does NOT start with "com.apple.dock." — must not be excluded.
        XCTAssertTrue(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .accessory,
                bundleIdentifier: "com.apple.dockable",
                localizedName: "Dockable",
                selfBundleID: selfBundleID
            )
        )
    }

    func testIncludesUnrelatedAppleBundleIDs() {
        XCTAssertTrue(
            BackgroundAppProvider.shouldInclude(
                activationPolicy: .accessory,
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                selfBundleID: selfBundleID
            )
        )
    }
}
