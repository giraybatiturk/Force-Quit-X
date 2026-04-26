# Force-Quit-X

A macOS menu-bar utility. Single click to force-quit any running app; **⌘⌥Q** force-quits all non-Finder user apps. Distributed as a notarized DMG via GitHub Releases.

## Architecture

Single source file: `ForceQuitX/ForceQuitXApp.swift` (~295 lines).

- **`ForceQuitXApp`** (SwiftUI `App`) — empty `Settings` scene; everything lives in `AppDelegate` via `@NSApplicationDelegateAdaptor`.
- **`AppDelegate`** — owns:
  - `NSStatusItem` (the menubar icon)
  - Carbon `EventHotKeyRef` + `EventHandlerRef` for the global ⌘⌥Q hotkey
  - `URLSession` calls to GitHub Releases for the in-app update check
  - `SMAppService.mainApp` toggle for launch-at-login

`ContentView.swift` exists but isn't used at runtime — the app sets `NSApp.setActivationPolicy(.accessory)` so no window ever shows.

## Invariants — don't break these

- **Carbon hot key lifecycle**: `RegisterEventHotKey` / `InstallEventHandler` results MUST be paired with `UnregisterEventHotKey` / `RemoveEventHandler`. `applicationWillTerminate` does this; `registerGlobalHotKey` re-tears-down before re-registering. Don't add a re-registration path that skips teardown.
- **Updater contract**: `normalizedVersion()` strips leading `v` and trailing `.0`s, drops prerelease/build suffixes (`1.2.0-beta+sha → 1.2.0`). The GitHub Releases `tag_name` and the bundle's `CFBundleShortVersionString` MUST normalize to comparable forms. If you change one, change the other.
- **Menubar-only**: `setActivationPolicy(.accessory)` in code; `INFOPLIST_KEY_LSUIElement = YES` in pbxproj (the project uses Xcode-generated Info.plist via `GENERATE_INFOPLIST_FILE = YES`). Both are required — without the build setting the Dock briefly flickers on launch.
- **No force-unwraps on Cocoa optionals** — `NSRunningApplication.localizedName` can be nil; use `compactMap`. `URL(string:)` can be nil; guard it.

## Style

- **4-space indent**, 120-column lines, enforced by `.swift-format` at repo root and CI lint.
- **Conventional commits** with lowercase type: `feat:`, `fix:`, `chore:`, `refactor:`, `ci:`, `docs:`. CI's lint job will fail PRs with formatting drift.
- **User-facing strings in English.** Comments may be Turkish (legacy); user-visible alerts/menu items must be English. If you see Turkish in an `NSAlert` or menu, fix it.

## Release flow

The `release-cut` skill (`/release-cut <version>`) does the full sequence:

1. Bump `MARKETING_VERSION` in `project.pbxproj`
2. Commit, tag (`v<version>`), `xcodebuild archive`, export, sign, notarize
3. Build DMG via `hdiutil`
4. `git push` + `gh release create` with the DMG attached
5. Verify the new tag is what the auto-updater will see

Before tagging, run the `release-readiness` subagent (version/signing sanity) and `info-plist-auditor` (Info.plist consistency).

After release, the `changelog-writer` subagent drafts user-facing release notes from the diff — paste those into the GitHub Release body. The `changelog` skill (`/changelog <range>`) gives a quicker mechanical grouping by commit prefix.

## CI

`.github/workflows/ci.yml` runs on every push to `main` and every PR:
- **Build**: `xcodebuild build -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- **Lint**: `xcrun swift-format lint --strict --recursive ForceQuitX`

Both jobs run on `macos-15`.

## Things that aren't here (yet)

- No tests. `normalizedVersion()` is the only thing pure enough to unit-test cheaply; if you add tests, start there.
- No localization. All English strings are hardcoded — wrap in `NSLocalizedString` if localization is ever needed.
- No crash reporter. Errors go to `NSLog` and (for SMAppService failures) `NSAlert`.

## Common gotchas

- Editing `project.pbxproj` triggers a warning hook because the file is fragile — read the diff carefully, especially around `MARKETING_VERSION` and `MACOSX_DEPLOYMENT_TARGET` (the latter was once silently set to `26.4`, an invalid value from an Xcode beta).
- `swift-format` runs automatically on `.swift` edits via the PostToolUse hook — if you see "M" on a `.swift` file you didn't touch, the formatter likely fixed something.
- The global hotkey requires the user to have granted accessibility / input monitoring permission on first launch. There's no in-app prompt for this currently.
