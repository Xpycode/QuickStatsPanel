# QuickStatsPanel

A macOS 15+ utility that summons a **wide, glanceable HUD panel** of live Mac
stats with a **global keyboard shortcut**. Think "iStat at a glance" — quick,
shallow, dismissible — not a deep monitoring suite.

> Current state: `docs/PROJECT_STATE.md` · Decisions: `docs/decisions.md` · Directions system: read on-demand from your `~/.claude/CLAUDE.md` Directions Index (master, not copied here)

---

## What it is

- Press a global hotkey → a horizontally-wide, vertically-short rounded rectangle
  appears (small corner radius — **not** the heavy macOS "Tahoe" rounding).
- Shows live stats (CPU, Memory, Disk, Network, Battery, eventually GPU/temps).
- Press the hotkey again (or Esc / click-away) → it dismisses.
- **No Dock icon. No menu-bar item.** Settings & Quit live *inside* the panel.

## Tech stack

- **Language:** Swift 5.10+, SwiftUI for the panel content, AppKit for the window.
- **Build:** `xcodegen` → `project.yml` generates `QuickStatsPanel.xcodeproj`
  (lives in `01_Project/`). See cookbook `47-xcodegen-swiftterm-setup.md`.
- **Window:** `NSPanel` (`.nonactivating`, floating level), summoned without
  stealing focus — adapted from MousePlus `RingWindowController`.
- **Hotkey:** Carbon `RegisterEventHotKey` (toggle, **no Accessibility
  permission** required) — see `docs/decisions.md` D-002.
- **Sampling:** `DispatchSourceTimer`-based samplers with `Sendable` value-type
  samples and a callback — ported from StatsWindow.
- **Presence:** `LSUIElement = YES` (agent app, no Dock, no status item).

## Architecture at a glance

```
QuickStatsPanelApp (@main, NSApplicationDelegateAdaptor)
 └─ AppDelegate
     ├─ HotKeyService          (RegisterEventHotKey → toggle panel)
     ├─ PanelWindowController  (NSPanel show/hide, screen clamp)  ← from MousePlus
     ├─ DismissMonitor         (Esc / click-outside → hide)        ← from MousePlus
     └─ StatsStore (@MainActor, ObservableObject)
         ├─ CPUSampler         ← from StatsWindow
         ├─ MemorySampler      ← from StatsWindow
         ├─ DiskSampler        ← from StatsWindow (FSUsageSampler)
         ├─ NetworkSampler     (new)
         └─ BatterySampler     (new, IOKit)
```

## ⚠️ App Shell Standard does NOT apply here

The global App Shell Standard (HSplitView + sidebar + FCPToolbarButtonStyle) is
for **document/editor apps**. QuickStatsPanel is a **HUD panel app**. Do not run
`/shell-check` against it expecting HSplitView — the correct shell is an
`NSPanel`. The `Theme` struct (colors, spacing, fonts) still applies to the panel
content.

## Reuse sources (same machine, study before reinventing)

| Need | Borrow from |
|------|-------------|
| Stat samplers (CPU/Mem/Disk) | `../StatsWindow/Sources/StatsWindow/Sampling/` |
| xcodegen `project.yml` | `../StatsWindow/project.yml` |
| Non-activating panel | `../MousePlus/01_Project/MousePlus/Controllers/RingWindowController.swift` |
| Click-away dismiss | `../MousePlus/01_Project/MousePlus/Services/DismissMonitor.swift` |
| Settings-in-app bridge pattern | `../MousePlus/01_Project/MousePlus/MousePlusApp.swift` |

## Build & run

```bash
cd 01_Project
xcodegen generate
xcodebuild -scheme QuickStatsPanel -destination 'platform=macOS' build
```
(Project not yet scaffolded — see PROJECT_STATE.md "Next".)


<!-- DIRECTIONS-PROJECT:START -->
## Shared Directions workflow

- **Local master:** `/Users/sim/ProgrammingProjects/0-DIRECTIONS/__DIRECTIONS`.
- For Directions commands, use the installed Directions skill in Codex or read the master's
  `commands/<name>.md` completely. Slashless forms work too. Approved-plan continuation uses
  `commands/execute.md`; status alone does not authorize execution.
- Resolve shared `reference/...` from that master. Read universal guidance there on demand;
  use the relevant host global template's routing section if global guidance is unavailable.
  Report a missing master instead of using copied universal guides.
- This section supersedes older generic Directions workflow, copied-guide loading, automatic
  app-control and PR-ceremony instructions in this file. Preserve project-specific architecture,
  build commands, security constraints and product requirements above.
- Retained numbered guides in `docs/` are legacy references, not workflow authority. Preserve
  their project-specific additions; consult them only for relevant historical/project evidence.
- Preserve existing state, selected plans, open gates and session history. Legacy task/state
  reconciliation is separate work; never mark a manual gate complete from an old checkbox.
- Before builds/tests, read the master's `34_testing.md` and inspect startup effects. Desktop/app
  control requires explicit user permission; older automatic quit/launch instructions do not grant it.
  Give full absolute paths for user-operated file/app steps. Preserve dirty work and user limits.
<!-- DIRECTIONS-PROJECT:END -->
