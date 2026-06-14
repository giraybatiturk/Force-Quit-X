# Force-Quit-X — User Journeys & Stories

> Behaviour-grounded user stories for Force-Quit-X. Each story maps to real code in
> `ForceQuitX/`. The verification column records how each story is checked:
> **unit** (automated XCTest), **code** (verified by inspection), **manual** (requires
> GUI interaction — clicking the menu, dialogs, System Settings panes).

**Persona:** a macOS power user dealing with frozen / unresponsive apps who wants a
one-click force-quit from the menu bar instead of Activity Monitor or the ⌘⌥Esc dialog.

---

## Epic 1 — Install & First Launch (Onboarding)

Journey: download DMG → drag to Applications → first launch → menu-bar icon appears.

| ID | Story | Verify |
|----|-------|--------|
| S1.1 | As a user, when I open the app it lives in the **menu bar without cluttering the Dock** (`.accessory` + `LSUIElement`). | code |
| S1.2 | On first launch I'm told **once** that the global shortcut needs **Accessibility permission**, with a button that opens the right System Settings pane (deduped via `AccessibilityPromptShown`). | code / manual |
| S1.3 | **Launch at Login is auto-enabled on first run** so I don't have to start it manually (`LaunchAtLoginDefaulted`). | code |

## Epic 2 — Force-Quit a Single App (core value)

Journey: click menu icon → "RUNNING APPS" list → that row's **✕** button.

| ID | Story | Verify |
|----|-------|--------|
| S2.1 | I see running apps as an **icon + name list, sorted alphabetically**. | code |
| S2.2 | I force-quit a frozen app by clicking the **✕ button** on its row. | manual |
| S2.3 | The **row body is inert** — only the ✕ acts — so a stray click can't fat-finger a quit (✕ turns red on hover). | manual |
| S2.4 | The frontmost app is highlighted with a **"(Frontmost)" tag** and bold name. | code / manual |

## Epic 3 — Bulk Force-Quit

Journey: menu "Force Quit All" / "Except Frontmost" **or** global **⌘⌥Q** from anywhere.

| ID | Story | Verify |
|----|-------|--------|
| S3.1 | I close **all user apps in one action** ("Force Quit All", with a count). | code |
| S3.2 | I close **everything except the frontmost** so I keep my current app. | code |
| S3.3 | I trigger force-quit-all from **any app via the global hotkey (⌘⌥Q)** without opening the menu. | manual |
| S3.4 | I see a **warning dialog** before a bulk quit, but can silence it with **"Don't ask again"** (default button is Cancel — safe side). | manual |
| S3.5 | **Finder and ForceQuitX itself are never quit.** | code |

## Epic 4 — Manage Background Processes

Journey: Settings → "Show Background Processes" → new "BACKGROUND PROCESSES" menu section.

| ID | Story | Verify |
|----|-------|--------|
| S4.1 | As a power user I can see and quit normally-hidden **background/agent processes** (`.accessory`/`.prohibited`). | unit |
| S4.2 | **Critical `com.apple.*` agents stay hidden** so I can't break the system. | unit |
| S4.3 | A long list shows the **first 25**, with **"Show All (N)"** to expand. | code |

## Epic 5 — Auto-Quit Idle Apps

Journey: Settings → enable Auto Quit → pick timeout → (optional) build an exclusion list.

| ID | Story | Verify |
|----|-------|--------|
| S5.1 | Apps **unused beyond a threshold are auto force-quit** (saves RAM/battery). | unit |
| S5.2 | I pick the idle threshold from **15m / 30m / 1h / 2h / 4h**. | unit / code |
| S5.3 | I keep apps safe via an **exclusion list** — add from running, add frontmost, remove one, or clear all. | code |
| S5.4 | Auto-quit **never touches Finder or ForceQuitX**. | code |

## Epic 6 — Customisation

| ID | Story | Verify |
|----|-------|--------|
| S6.1 | I set **my own global shortcut** via a recorder panel. | unit / manual |
| S6.2 | If my chosen combo is taken, the **previously working shortcut is not lost** and I get a warning (fixed in 1.0.1 — persist on success, rollback on failure). | code |
| S6.3 | I choose the appearance: **System / Light / Dark**. | code / manual |
| S6.4 | I toggle Launch at Login; if the system rejects it I get a **clear error and the toggle reflects reality** (fixed in 1.0.1). | code |

## Epic 7 — Stay Updated

Journey: Sparkle reads the appcast in the background → notifies on a new version → one-click update.

| ID | Story | Verify |
|----|-------|--------|
| S7.1 | New versions are **checked automatically and offered** (Sparkle, daily). | code |
| S7.2 | I can **check manually** via "Check for Updates...". | manual |
| S7.3 | I can **turn automatic checks on/off**. | code / manual |

## Epic 8 — Support & Attribution

| ID | Story | Verify |
|----|-------|--------|
| S8.1 | I can **support the developer (tip/sponsor)**. | manual |
| S8.2 | I can reach the **creator's website**. | manual |

## Epic 9 — Quit

| ID | Story | Verify |
|----|-------|--------|
| S9.1 | I fully quit via **"Quit ForceQuitX"** (hotkey + timer torn down cleanly on exit). | code |

---

## Failure / edge-case stories

| ID | Story | Verify |
|----|-------|--------|
| F1 | Without Accessibility permission the **global shortcut won't work**; every registration failure shows an alert routing me to the pane. | code / manual |
| F2 | If the shortcut is **claimed by another app**, I'm warned and pointed to Settings to change it. | code / manual |
| F3 | With **no running apps**, the menu shows "NO RUNNING APPS" and bulk actions are **disabled**. | code |

---

## Known UX risk (backlog candidate)

Auto-Quit (Epic 5) **always force-terminates** — it does not attempt a graceful quit first,
so unsaved work in an idle app can be lost. A "try a polite quit before forcing" option is a
candidate for a future release.
