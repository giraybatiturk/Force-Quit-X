#!/usr/bin/env bash
#
# make-dmg.sh — build a drag-to-Applications DMG for ForceQuitX.
#
# Produces a DMG whose window shows the app icon next to an "Applications" folder
# alias, so the user just drags across to install — the standard macOS experience.
#
# Usage:  scripts/make-dmg.sh <path-to-.app> <output.dmg>
# Example: scripts/make-dmg.sh build/export/ForceQuitX.app build/ForceQuitX-1.0.3.dmg
#
# The Applications symlink is the reliable core. The Finder window styling (size +
# icon positions) is best-effort: if Finder automation isn't available (e.g. a
# headless/CI run) it's skipped and the DMG still works as drag-to-install.

set -euo pipefail

APP="${1:?usage: make-dmg.sh <path-to-.app> <output.dmg>}"
OUT="${2:?usage: make-dmg.sh <path-to-.app> <output.dmg>}"
VOLNAME="ForceQuitX"

[ -d "$APP" ] || {
    echo "error: app bundle not found: $APP" >&2
    exit 1
}

APP_NAME="$(basename "$APP")"
STAGE="$(mktemp -d)"
RW_DMG="$(mktemp -u).dmg"
MOUNT_DIR="/Volumes/$VOLNAME"
cleanup() {
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    rm -rf "$STAGE"
    rm -f "$RW_DMG"
}
trap cleanup EXIT

# Stage the app plus an /Applications alias so the user can drag across in one window.
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Detach any stale volume of the same name so the new one keeps the exact name
# (otherwise macOS renames it "ForceQuitX 1" and the Finder styling can't find it).
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true

# Build a writable DMG we can style, then convert to a compressed read-only DMG.
# Mount it browsable at /Volumes (NOT -nobrowse / a custom mountpoint) so Finder
# can see the disk and apply the window layout below.
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW "$RW_DMG" >/dev/null
hdiutil attach "$RW_DMG" >/dev/null

# Best-effort: lay out the window so the app sits to the left of the Applications
# folder with an obvious drag target. Non-fatal if Finder scripting is unavailable.
osascript <<APPLESCRIPT >/dev/null 2>&1 || echo "note: Finder styling skipped (DMG still works as drag-to-install)" >&2
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 150, 740, 470}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set position of item "$APP_NAME" of container window to {150, 175}
        set position of item "Applications" of container window to {390, 175}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" >/dev/null
rm -f "$OUT"
hdiutil convert "$RW_DMG" -format UDZO -o "$OUT" >/dev/null

echo "built: $OUT"
