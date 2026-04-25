---
name: release-cut
description: Cut a new ForceQuitX release — bump MARKETING_VERSION in project.pbxproj, commit, tag, build a notarized DMG, and publish a GitHub Release with auto-generated notes. Invoke as `/release-cut <version>` (e.g. `/release-cut 1.3.0`).
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
- Read current `MARKETING_VERSION` from `ForceQuitX.xcodeproj/project.pbxproj`.
- Confirm new version > current (string compare with `.numeric` option, same logic as `normalizedVersion()` in the app).
- Update `MARKETING_VERSION` in `project.pbxproj` (replace_all — there are usually two occurrences for Debug/Release configs).
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

### 7. Push and publish
- Show the user a summary: version, commit SHA, tag, DMG path.
- ASK before pushing. Then:
  - `git push origin main`
  - `git push origin v<new-version>`
  - `gh release create v<new-version> build/ForceQuitX-<new-version>.dmg --generate-notes --title "ForceQuitX <new-version>"`

### 8. Verify the updater contract
- After the release is published, hit `https://api.github.com/repos/giraybatiturk/Force-Quit-X/releases/latest` and confirm `tag_name` matches `v<new-version>`. This is what every existing user's app will see.

## Failure handling

If any step fails after step 2 (commit), do NOT delete the commit or tag without asking. Show the user where it failed and the cleanup commands available (`git tag -d`, `git reset --soft HEAD^`).
