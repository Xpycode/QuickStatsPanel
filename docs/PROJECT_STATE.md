# Project State — QuickStatsPanel

> **Size limit: <100 lines.** Digest, not archive. Details go in session logs.

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD panel of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04
- **Target:** macOS 15+

## Current Position
- **Funnel:** build
- **Phase:** Implementation — v0 shell running
- **Focus:** **D-013 top-process lists built** (iStat-style: top-5 by CPU / memory / disk-I/O folded into the CPU/Mem/Disk popovers from one rusage pass; standalone Top Process tile retired; mach-unit CPU% math). Builds clean, launches & runs. ⚠ Awaiting visual click-through (open the 3 popovers via ⌃⌥⌘Q) + Activity-Monitor cross-check of CPU%/disk rates. Then: app icon / first-run hint / signing.
- **Status:** ✅ `** BUILD SUCCEEDED **` (clean, no warnings), launches & runs. All 5 stats live; gear tile → standard Settings window (D-009); Esc / toggle-hotkey / click-away all dismiss. Settings persist via `UserDefaults`. ✅ **Esc + click-away dismissal verified** (2026-06-05, CGEvent-tap test): Esc captured only while visible, dismisses panel, released after hide; click-away exercised literally (empty-desktop click → dismiss + Esc released). ⚠️ Settings UI **not yet visually clicked-through** by user.
- **Last updated:** 2026-06-05

## What we're building
Press a global hotkey → a **thin** horizontally-wide strip appears near the cursor
showing live stats as compact tiles (CPU, Mem, Disk, …). Click a tile → detail
breakdown. Press again / Esc / click-away → dismiss. **No Dock icon, no menu-bar
item** — settings & quit live in the panel. Small corner radius (NOT "Tahoe").

## Decisions locked (see decisions.md)
- D-001: HUD `NSPanel`, **not** the App Shell Standard HSplitView.
- D-002: Global hotkey via Carbon `RegisterEventHotKey` (no perm). Default **⌃⌥⌘Q**, rebindable. User triggers via BetterMouse (mouse button → key combo).
- D-003: `LSUIElement = YES` — no Dock icon, no status item.
- D-004: Build with xcodegen (`project.yml`).
- D-005: Port StatsWindow samplers rather than rewrite.
- D-006: **Thin strip (~36pt, configurable) + click-to-expand detail**, not a tall dashboard.
- D-007: Panel position configurable; default **near cursor** (clamped on-screen).
- D-008: Strip width is **content-driven** (hugs its tiles via `NSHostingView.fittingSize`), grows as stats are added — not a fixed 620. Content uses `.fixedSize(horizontal:)` so values never wrap.
- D-009: In-panel gear → self-managed Settings `NSWindow` (not the SwiftUI `Settings` scene; works under `LSUIElement` so the hotkey recorder can become key).
- D-010: **Esc-to-dismiss** = bare Escape as a Carbon hotkey, registered **only while the panel is visible** (permission-free; never steals focus). `HotKeyService` is now ID-filtered for multiple instances.

## Stats roadmap (user wants all eventually)
| Stat | Source | Phase |
|------|--------|-------|
| CPU | StatsWindow `CPUSampler` (reuse) | **v1 ✅** |
| Memory | StatsWindow `MemorySampler` (reuse) | **v1 ✅** |
| Disk capacity + I/O | `DiskSampler` (new: `statfs` + IOKit, permission-free) | **v1 ✅** |
| Network up/down | `NetworkSampler` (new: `getifaddrs`, permission-free) | **v1.1 ✅** |
| Battery / power | `BatterySampler` (new: IOKit Power Sources) | **v1.1 ✅** |
| Load average | `LoadAverageSampler` (new: `getloadavg`, permission-free) | **Phase A ✅** |
| Uptime | `UptimeSampler` (new: `kern.boottime`, permission-free) | **Phase A ✅** |
| Top process (mem/CPU/disk) | `TopProcessSampler` → lists in CPU/Mem/Disk popovers (D-013, iStat-style); standalone tile retired | **✅ built** |
| GPU / temps / fans | new, SMC (⚠ private-ish APIs, risky) | v2 |

## Done (v0 scaffold, 2026-06-04)
- [x] `01_Project/project.yml` (macOS 15, `LSUIElement` via Info.plist, id `com.sim.QuickStatsPanel`).
- [x] `QuickStatsPanelApp` + `AppDelegate` (agent app, no menu bar; first-run shows panel once).
- [x] `PanelWindowController` (NSPanel, thin strip, small radius, `anchor: .cursor | .fixed`, screen-clamped).
- [x] `HotKeyService` (Carbon RegisterEventHotKey, default ⌃⌥⌘Q) → toggles panel.
- [x] `CPUSampler` + `MemorySampler` ported + `StatsStore` (`@Observable @MainActor`).
- [x] `StatsStripView` + `StatTileView` (HStack of tiles; **click tile → detail popover**).
- [x] Click-away dismissal via permission-free global *mouse* monitor.
- Builds clean (Swift-6-ready), smoke-launched OK.

## Done (afternoon, 2026-06-04)
- [x] **Visually verified** the panel on screen (⌃⌥⌘Q) — all v1 stats + popovers + toggle.
- [x] Strip width **content-driven** (`fittingSize`) — killed the 620pt dead space; `.fixedSize` fixes the wrap.
- [x] **Fixed-width tiles + monospaced digits** (Penumbra TimecodeView pattern) → no per-summon jitter.
- [x] **`DiskSampler`** (new): capacity via `statfs`, live I/O via IOKit `IOBlockStorageDriver`; permission-free. Disk tile + popover (Used/Free/Total + Read/Write). "Zero KB/s" → "0 KB/s".

## Done (v1.1 stats, 2026-06-04)
- [x] **`NetworkSampler`** (new): up/down throughput via `getifaddrs` (`AF_LINK` → `if_data`), cumulative→per-tick delta like Disk. Permission-free. Interface filter = pluggable `shouldCount` (currently count-everything; loopback inflates idle reading slightly).
- [x] **`BatterySampler`** (new): IOKit Power Sources (`IOKit.ps`), absolute snapshot (not delta). Tile **hidden on desktop Macs** (`isPresent`). Color band **inverted** (`100 - percent`). Dynamic charge/charging SF Symbol.
- [x] Both wired into `StatsStore`; **verified on screen** (all 5 tiles ticking).

## Done (in-panel settings, 2026-06-04)
- [x] **`AppSettings`** (new): `@Observable` singleton, `UserDefaults`-backed; single source of truth for both `AppDelegate` and the `Settings` scene. Passive reads (anchor/height/stats) + active `didSet` hooks (`onIntervalChanged`→`store.restart()`, `onHotKeyChanged`→re-register).
- [x] **`PanelAnchor`** (new) enum: cursor / screenCenter / topCenter / bottomCenter; origin math in `PanelWindowController`.
- [x] **Gear tile** in strip → `NSApp.activate` + `showSettingsWindow:` (D-009; window can become key so the hotkey recorder works).
- [x] **`SettingsView`** real form: drag-reorder + toggle stats, interval slider (0.25–5s), anchor picker, height slider (22–44pt), hotkey recorder, Reset, Quit.
- [x] **`HotKeyRecorderView`** + **`HotKeyBinding+Display.swift`** (new): local `keyDown` monitor records a combo; `displayString` (⌃⌥⌘Q); **validation = reject Shift-only, require ≥1 of ⌘/⌥/⌃**.
- [x] `visibleStats` now composes order → enabled → availability. Builds clean.

## Done (Esc-to-dismiss, 2026-06-05)
- [x] **D-010**: bare Escape via a **second `HotKeyService`** (`id: 2`), registered only while the panel is visible, unregistered on hide. Permission-free, never steals focus; toggle-hotkey stays the primary dismiss.
- [x] **`PanelWindowController.onVisibilityChanged`** (new): fired in `show`/`hide` (guarded against redundant hides) so Esc teardown covers **every** dismiss path (toggle / click-away / Esc) — not just `togglePanel()`.
- [x] **`HotKeyService` made ID-filtered**: callback now reads the fired `EventHotKeyID` and matches per-instance `id` (Carbon dispatches every press to all handlers). Fixes a latent bug + unblocks multiple scoped hotkeys. Builds clean.

## Done (Phase A stats, 2026-06-05)
- [x] **D-011 `LoadAverageSampler`** (new): `getloadavg(3)`, absolute snapshot. Headline = 1-min load; color band = load÷activeCores; popover = 1/5/15 + cores.
- [x] **D-011 `UptimeSampler`** (new): `kern.boottime` (NOT `systemUptime` — that drops sleep time). Headline = compact "3d 4h"; always-calm tint; popover = uptime + boot date.
- [x] **D-012 `TopProcessSampler`** (new): memory-first via `libproc` (`proc_listallpids` + `proc_pid_rusage` `ri_phys_footprint`, EPERM-skip). Honestly "top *user* process" — no privileged helper (keeps zero-permission). Value headline, process name in popover (preserves D-008 fixed-width). Hidden until first readable proc.
- [x] **`AppSettings.knownStats`** migration: new `StatKind`s default ON for existing users without re-enabling deliberately-disabled stats.
- [x] **`SettingsView`** stat-list height now scales with stat count (was hardcoded 170). All wired via the data-driven `StatKind`/`descriptor(for:)` chokepoint — zero view changes. Builds clean, launches & runs.

## Done (D-013 top-process lists, 2026-06-05)
- [x] **Rewrote `TopProcessSampler`** → top-5 by **CPU% / memory / disk-I/O** from one `rusage_info_v4` pass per tick. `TopProcessSample`→`TopProcessesSample` (`byCPU`/`byMemory`/`byDiskIO`). CPU%/disk are two-tick rates (per-PID `prevCPU`/`prevDisk` + `prevWall`); memory stays a snapshot. Names resolved only for the top-8 winners/list (no per-PID `proc_pidpath` storm).
- [x] **mach-unit CPU% fix** (researched vs XNU + osquery#7459): `ri_user_time`/`ri_system_time` are mach ticks, not ns → convert via `mach_timebase_info`, wall via `mach_absolute_time()`.
- [x] **Lists fold into CPU/Mem/Disk popovers** (iStat-style); **standalone `.topProcess` tile retired** (auto-migrates — `compactMap` drops the stale rawValue). `StatDescriptor.ProcessSection` (optional, auto-hidden empty) rendered by `StatTileView`.
- [x] **Grouped by app**: helper PIDs roll up to the outermost `.app` bundle in their path (Activity-Monitor-style), summed then ranked — so N Chrome helpers show as one "Google Chrome" row. Per-PID `nameCache` (pruned each tick) keeps `proc_pidpath` to once-per-process. `ProcStat` now keyed by app name (no `pid`).
- [x] **Network excluded by platform limit**: no permission-free per-process bandwidth API (private `NetworkStatistics.framework` / root only). Net tile stays Down/Up.
- [x] Builds clean (no warnings), launches & runs. See D-013.

## Next (in order)
1. **Visual click-through of D-013** (⌃⌥⌘Q): open CPU / Memory / Disk popovers — each shows a "Top by …" list of 5 procs; names readable, values sane. CPU/disk lists appear from the **2nd** tick (rates need two samples), memory list immediately. Cross-check a couple of CPU% / disk-rate numbers against Activity Monitor (validates the mach-unit math).
2. App icon, first-run hint UI, signing (`Debug.local.xcconfig`).
3. Live click-through verify: Settings UI (reorder/sliders/recorder persistence across relaunch); confirm no stray "Top Process" row remains.
4. Optional: per-app CPU/disk smoothing if grouped readings flicker tick-to-tick; revisit grouping edge cases (e.g. apps outside an `.app` bundle).
5. Hover-to-expand tile detail (later enhancement; needs tracking-area work).

## Done (data-driven strip refactor, 2026-06-04)
- [x] **`StatDescriptor.swift`** (new): `StatKind` enum (stable identity + display order) + `StatDescriptor` struct + `StatsStore.visibleStats` builder (`descriptor(for:)` — single mapping chokepoint; battery filtered by `isPresent`).
- [x] `StatsStripView` collapsed from 5 hardcoded tiles (~75 lines) to a ~12-line `ForEach` with `if index > 0 { divider }`. No behavior change; fixed SwiftUI type-checker strain. Builds clean.

### Design
- **Claude Designer prompts:** `02_Design/design-prompts.md` — 6 paste-ready briefs (strip, tile+popover, color language, settings, icon, first-run hint) + locked design-values table.

### Backlog / nice-to-haves (from visual verify)
- **⏳ USER:** tune `Theme.loadColor(forPercent:)` thresholds — at-a-glance color bands (open Q: same bands for CPU vs memory? gradient vs steps? hysteresis to stop flicker?).
- Memory readout shows 2 decimals ("16,85 GB"); consider 1 decimal for faster glancing.
- `cornerRadius` 12pt reads fine at the snug width — revisit if it feels too round.

## Resolved design (see D-006, D-007)
- **Hotkey:** default ⌃⌥⌘Q, rebindable. User routes a mouse button → that combo via BetterMouse.
- **Anchor:** near cursor by default; user-settable to a fixed position.
- **Size:** width **content-driven** (hugs tiles; ~210pt with CPU+Mem, grows with more stats), height ~22–44pt (configurable; ~36 default). Detail on click.

## Blockers
None.

---
*Updated by Claude. Source of truth for project position.*
