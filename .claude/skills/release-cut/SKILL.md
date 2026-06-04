---
name: release-cut
description: Cut a new ForceQuitX release — bump MARKETING_VERSION + CURRENT_PROJECT_VERSION, commit, tag, build a notarized DMG, sign it for Sparkle and update appcast.xml, then publish a GitHub Release. Invoke as `/release-cut <version>` (e.g. `/release-cut 1.3.0`).
disable-model-invocation: true
---

# release-cut

Cuts a new ForceQuitX release end-to-end. The argument is the new semver version (no leading `v`).

## Preconditions

Before doing anything, verify:
1. `git status` is clean. If not, STOP and tell the user to commit/stash first.
2. Current branch is `main`. If not, ask before proceeding.
3. The version argument is valid semver (`X.Y.Z` or `X.Y`).
4. `gh auth status` succeeds. If not, tell the user to run `gh auth login`.
5. `xcodebuild -version` succeeds.

If any precondition fails, STOP and report — do not partially execute.

## Steps

### 1. Bump version
- Read current `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `ForceQuitX.xcodeproj/project.pbxproj`.
- Confirm new version > current (string compare with `.numeric` option).
- Update `MARKETING_VERSION` to the new version (replace_all — two occurrences, Debug/Release).
- **Also bump `CURRENT_PROJECT_VERSION` by +1** (replace_all). This becomes Sparkle's `sparkle:version` (CFBundleVersion) and MUST increase every release or Sparkle won't offer the update.
- Show the diff to the user before committing.

### 2. Commit
- `git add ForceQuitX.xcodeproj/project.pbxproj`
- `git commit -m "chore: bump version to <new-version>"`
- Match the style of `git log --oneline -10` (conventional commits with lowercase type).

### 3. Tag
- `git tag v<new-version>`
- Do NOT push yet — confirm with the user first.

### 4. Build & archive
- `xcodebuild -project ForceQuitX.xcodeproj -scheme ForceQuitX -configuration Release -archivePath build/ForceQuitX.xcarchive archive`
- `xcodebuild -exportArchive -archivePath build/ForceQuitX.xcarchive -exportPath build/export -exportOptionsPlist <plist>` — if no exportOptions.plist exists, generate one with method=`developer-id` and ask the user for the Team ID.

### 5. Sign & notarize check
- `codesign -dv --verbose=2 build/export/ForceQuitX.app` — must show Developer ID.
- If the user has notarytool credentials configured (`xcrun notarytool history` works), submit the app/DMG for notarization. Otherwise, instruct the user how to do it manually.

### 6. Build DMG
- `hdiutil create -volname "ForceQuitX" -srcfolder build/export/ForceQuitX.app -ov -format UDZO build/ForceQuitX-<new-version>.dmg`

### 7. Sign for Sparkle & update the appcast
- Locate the Sparkle `sign_update` tool (installed via SPM):
  `find ~/Library/Developer/Xcode/DerivedData -name sign_update -path '*sparkle*' | head -1`
- Run it on the DMG: `<sign_update> build/ForceQuitX-<new-version>.dmg`
  → prints `sparkle:edSignature="…" length="…"`. (Signs with the EdDSA private key in the login Keychain — if it errors about a missing key, the maintainer must restore/regenerate it.)
- Append a new `<item>` to `appcast.xml` (project root), filling in:
  - `<sparkle:version>` = the new `CURRENT_PROJECT_VERSION` (build number)
  - `<sparkle:shortVersionString>` = `<new-version>` (MARKETING_VERSION)
  - `<sparkle:minimumSystemVersion>` = `MACOSX_DEPLOYMENT_TARGET`
  - `<enclosure url=…>` = `https://github.com/giraybatiturk/Force-Quit-X/releases/download/v<new-version>/ForceQuitX-<new-version>.dmg`, plus the `sparkle:edSignature` and `length` from `sign_update`
  - `<description>` = the release notes (CDATA HTML)
- `git add appcast.xml` and include it in the release commit (or a follow-up `chore: update appcast` commit).

### 8. Push and publish
- Show the user a summary: version, build number, commit SHA, tag, DMG path, appcast item.
- ASK before pushing. Then:
  - `git push origin main` (this publishes `appcast.xml`, which Sparkle reads)
  - `git push origin v<new-version>`
  - `gh release create v<new-version> build/ForceQuitX-<new-version>.dmg --generate-notes --title "ForceQuitX <new-version>"`
  - The enclosure URL must resolve to the DMG asset just uploaded — verify the filename matches.

### 9. Verify the updater contract
- Fetch the raw appcast: `curl -s https://raw.githubusercontent.com/giraybatiturk/Force-Quit-X/main/appcast.xml` and confirm the new `<item>` is present with the higher `sparkle:version` and a valid `enclosure` URL/signature. This is what every existing user's Sparkle reads (raw.githubusercontent caches ~5 min).

## Failure handling

If any step fails after step 2 (commit), do NOT delete the commit or tag without asking. Show the user where it failed and the cleanup commands available (`git tag -d`, `git reset --soft HEAD^`).
