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
- **Focus:** **D-014 top-process lists now sourced from `/usr/bin/top`** (replaces D-013's in-process rusage engine — proven this session that XNU same-user-gates *all* per-proc CPU/mem APIs, so in-process can never see WindowServer/kernel_task). CPU + Memory popover lists now look like Activity Monitor (system processes included, grouped by app, 1-decimal locale %, fixed-height popover). Disk-I/O per-process list dropped (top can't provide it). `top` gated to panel-visible; our own probe PID filtered. ✅ Verified on screen vs Activity Monitor. **App icon ✅ done** (parallel track): "Abstract bars" `AppIcon.appiconset` generated from the design handoff (native CG generator, build-verified). Next: **first-run hint / signing.**
- **Status:** ✅ `** BUILD SUCCEEDED **` (clean, no warnings), launches & runs. All 5 stats live; gear tile → standard Settings window (D-009); Esc / toggle-hotkey / click-away all dismiss. Settings persist via `UserDefaults`. ✅ **Esc + click-away dismissal verified** (2026-06-05, CGEvent-tap test): Esc captured only while visible, dismisses panel, released after hide; click-away exercised literally. ✅ **Top-process lists (D-014) verified on screen**: CPU list shows WindowServer/kernel_task with sane per-core % matching Activity Monitor; app-grouping correct; spawned-`top` probe filtered out. ⚠️ Settings UI **not yet visually clicked-through** by user.
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
| Top process (CPU/mem) | `TopProcessSampler` parses `/usr/bin/top` → lists in CPU/Mem popovers (D-014; system-inclusive, app-grouped, panel-visible-gated). Disk-I/O per-proc dropped (top has no column). | **✅ built + verified** |
| GPU / temps / fans | new, SMC (⚠ private-ish APIs, risky) | v2 |

## Done — history digest (full detail in `sessions/`)
- **v0 scaffold (06-04):** xcodegen `project.yml`, `QuickStatsPanelApp`+`AppDelegate` (agent app), `PanelWindowController` (NSPanel thin strip), `HotKeyService` (Carbon ⌃⌥⌘Q toggle), CPU+Mem samplers + `StatsStore`, `StatsStripView`/`StatTileView` (click→popover), mouse-monitor click-away.
- **Content-driven strip + Disk (06-04):** width hugs tiles via `fittingSize` (killed 620pt dead space); fixed-width monospaced tiles (Penumbra pattern, no jitter); `DiskSampler` (`statfs` + IOKit `IOBlockStorageDriver`, permission-free).
- **v1.1 stats (06-04):** `NetworkSampler` (`getifaddrs`/`AF_LINK`, cumulative→delta) + `BatterySampler` (IOKit Power Sources, hidden on desktops, inverted color band).
- **Data-driven strip refactor (06-04):** `StatKind` enum + `StatDescriptor` + `StatsStore.visibleStats` (single `descriptor(for:)` chokepoint); `StatsStripView` 75→12-line `ForEach`; fixed type-checker strain.
- **In-panel settings (06-04):** `AppSettings` (`@Observable` UserDefaults singleton) + `PanelAnchor` enum; gear→self-managed Settings `NSWindow` (D-009); `SettingsView` form (reorder/toggle stats, interval/height sliders, anchor, hotkey recorder, Reset/Quit); `HotKeyRecorderView` (rejects Shift-only).
- **Esc-to-dismiss (06-05, D-010):** bare Esc as a 2nd scoped Carbon hotkey; `PanelWindowController.onVisibilityChanged` covers every hide path; `HotKeyService` made ID-filtered (latent multi-handler bug fixed).
- **Phase A stats (06-05, D-011/D-012):** `LoadAverageSampler` (`getloadavg`), `UptimeSampler` (`kern.boottime`, not `systemUptime`), first `TopProcessSampler` (libproc, "top user proc by memory"); `AppSettings.knownStats` migration defaults new stats ON safely.
- **Top-process lists in popovers (06-05, D-013 — data source later superseded by D-014):** folded CPU/mem/disk rankings into the tile popovers, retired the standalone tile, app-grouping introduced. The popover/grouping design stands; the in-process `rusage` engine was replaced — see D-014.

## Done (D-014 top-process via `top`, 2026-06-05)
- [x] **Proved the limit with two throwaway probes**: `proc_pid_rusage` *and* `proc_pidinfo(PROC_PIDTASKINFO)` both fail for foreign-UID procs (kernel_task pid 0, WindowServer) — XNU same-user-gates all per-proc CPU/mem. So D-013's in-process engine could never show system processes. `top`/Activity Monitor see them only via Apple's private `com.apple.private.proc_info-list` entitlement.
- [x] **Rewrote `TopProcessSampler` to parse `/usr/bin/top`** (`-l 2 -s 1 -o cpu -stats pid,cpu,mem,command`, command last). Parses the **2nd** sample (top's instantaneous %CPU — no rate math, mach-unit conversion retired). CPU + Memory rank from one parse; `TopProcessesSample` lost `byDiskIO`.
- [x] **App-grouping kept** (`proc_pidpath` is permission-free for any PID — verified on WindowServer), fallback to top's COMMAND for pathless procs (kernel_task). **Disk-I/O per-proc list removed** (top has no column) — Disk popover shows aggregate Read/Write only.
- [x] **Gated to panel-visible**: `StatsStore.setPanelVisible()` ↔ `PanelWindowController.onVisibilityChanged` starts/stops the costly `top` sampler + clears the stale list on hide. Cadence `max(2s, interval)`.
- [x] **Observer-effect fix**: our spawned `top` reported itself (~8%) — filtered by the exact spawned PID (`Process.processIdentifier`), so a user's terminal `top` still shows.
- [x] **Earlier same-session polish** (carried in): thresholds dropped (no more 2-3-item lists), rows 5→10, fixed-height popover (no tick-to-tick resize), 1-decimal locale CPU%.
- [x] Builds clean, verified on screen vs Activity Monitor (WindowServer/kernel_task present, per-core % sane, grouping correct). See D-014.

## Next (in order)
1. **First-run hint UI + signing** (`Debug.local.xcconfig`). App icon ✅ done.
2. Live click-through verify: Settings UI (reorder/sliders/recorder persistence across relaunch).
3. ⚠ **MAS caveat (from D-014):** `top` can't be spawned under the App Sandbox — if Mac App Store distribution is ever pursued, the top-process lists must fall back to D-013's user-only `rusage` engine (or be dropped). Fine for direct/notarized distribution.
4. Optional: per-app CPU smoothing if grouped readings flicker; revisit grouping edge cases (apps outside an `.app` bundle).
5. Hover-to-expand tile detail (later enhancement; needs tracking-area work).

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
