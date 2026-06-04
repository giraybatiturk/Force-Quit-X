# ForceQuitX

A lightweight macOS menu-bar utility for force-quitting apps fast.

Single-click the ✕ next to any running app to force-quit it, or hit **⌘⌥Q** to
force-quit every non-Finder user app at once. Lives entirely in the menu bar — no
Dock icon, no window in your way.

> Distributed as a notarized DMG via [GitHub Releases](../../releases). Not on the
> Mac App Store — force-quitting other apps requires capabilities the App Store
> sandbox forbids.

## Features

- **Per-app force quit** — each running app has a dedicated kill button; the row
  body is inert so a stray click can't fat-finger a quit.
- **Force Quit All** (**⌘⌥Q**, customizable) — terminates all non-Finder user apps,
  with a confirmation you can suppress.
- **Force Quit All Except Frontmost** — keep what you're working in, close the rest.
- **Auto Quit idle apps** — automatically force-quit apps idle past a timeout
  (15 min – 4 h), with a per-app exclusion list.
- **Background processes** — optionally list and quit `.accessory`/`.prohibited`
  agents (critical `com.apple.*` processes are hidden).
- **Custom global shortcut** — rebind the hotkey to any modifier combo.
- **Theme** — System / Light / Dark.
- **Launch at Login** and **automatic updates** (via Sparkle).

## Requirements

- macOS 15.6 or later

## Install

1. Download the latest `ForceQuitX-x.y.z.dmg` from the
   [Releases](../../releases) page.
2. Open the DMG and drag **ForceQuitX** to Applications.
3. Launch it — the ✕ icon appears in your menu bar.

### Accessibility permission

The global **⌘⌥Q** shortcut needs Accessibility permission. On first launch
ForceQuitX points you to **System Settings → Privacy & Security → Accessibility** —
enable ForceQuitX there, then relaunch.

## Build from source

```bash
git clone https://github.com/giraybatiturk/Force-Quit-X.git
cd Force-Quit-X
open ForceQuitX.xcodeproj
```

In Xcode, set **Signing & Capabilities → Team** to your own Apple Developer team
(the committed `DEVELOPMENT_TEAM` is the maintainer's and won't work for you), then
build and run the `ForceQuitX` scheme.

CI builds and lints on every push:

```bash
xcodebuild build -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcrun swift-format lint --strict --recursive ForceQuitX
xcodebuild test  -project ForceQuitX.xcodeproj -scheme ForceQuitX -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## Updates

ForceQuitX updates itself with [Sparkle](https://sparkle-project.org), reading
[`appcast.xml`](appcast.xml) hosted in this repo. Updates are verified against the
EdDSA public key in `Info.plist` (`SUPublicEDKey`).

**For maintainers / forkers:** the appcast is signed with an EdDSA *private* key
that is **not** in this repo (it lives in the maintainer's login Keychain). If you
fork and ship your own builds, generate your own key pair with Sparkle's
`generate_keys`, replace `SUPublicEDKey` in `Info.plist`, point `SUFeedURL` at your
own appcast, and sign each DMG with `sign_update`.

## Contributing

Issues and PRs welcome. The project uses Conventional Commits and `swift-format`
(`.swift-format` at the repo root) — CI fails on formatting drift. User-facing
strings are English.

## License

[MIT](LICENSE) © 2026 Giray Batıtürk

## Acknowledgements

- [Sparkle](https://github.com/sparkle-project/Sparkle) — software update framework (MIT)
