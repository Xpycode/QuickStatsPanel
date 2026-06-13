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
- **Focus:** **First-run hint + code signing** (queue #1) ✅ built. A one-time hint card teaches the summon hotkey on first launch (this Dock-less agent app has no other cue): `HintPanelController` (sibling of `DetailPanelController`) shows a flat `Theme` card centered beneath the strip; `FirstRunHintView` renders the live bound hotkey in a keycap chip; `AppSettings.hasSeenHint` gates it (mark-seen-on-first-display; dismisses *with* the strip via `onVisibilityChanged`). Fixed a centering bug (hint anchored at t=0 before async samples landed → strip grew ~1 tile wider; now deferred 0.2s so the strip settles first). Signing: per-machine `Config/Debug.local.xcconfig` (gitignored, Manual, team **FDMSRXXN73** — the cert's `OU`, *not* the name's paren) included by tracked `Config/Debug.xcconfig`, wired via `configFiles` in `project.yml`. Prior: D-015 flat detail card; D-014 top-process via `top`. Hint copy now finalized to a **"warm welcome"** voice; slider/recorder persistence confirmed by inspection. Next: **Themes (named presets).**
- **Status:** ✅ `** BUILD SUCCEEDED **` (clean, no warnings), launches & runs, **now code-signed** with the Apple Development cert (`codesign -dvv`: team `FDMSRXXN73`, full Apple chain). All stats live; gear → standard Settings window (D-009); Esc / toggle-hotkey / click-away all dismiss (and now also hide the detail card **and the first-run hint**). Settings persist via `UserDefaults`. ✅ **Esc + click-away dismissal verified** (CGEvent-tap test). ✅ **Top-process lists (D-014) verified** vs Activity Monitor. ✅ **Flat detail card (D-015) verified on screen** by user. ✅ **Settings UI click-through verified by user (2026-06-13)**. ✅ **First-run hint verified via `CGWindowList` probe** — 2 windows, hint centered under strip (midX 994 vs 993.5), 6pt gap; on-screen visual by user pending.
- **Last updated:** 2026-06-13

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
- **Flat detail card (06-13, D-015):** replaced the native `.popover` with a self-drawn card (`StatDetailView`) in its own borderless non-activating `NSPanel` (`DetailPanelController`); flat Theme fill + 12pt radius + no arrow, anchored below the strip, live-reading `store.visibleStats`, sized once per open. Tile drops its popover state → reports taps via `onTap`; card hides whenever the strip hides via the existing `onVisibilityChanged`. Verified on screen. Also confirmed Settings stat on/off toggles already existed & work.

## Done (D-014 top-process via `top`, 2026-06-05)
- [x] **Proved the limit with two throwaway probes**: `proc_pid_rusage` *and* `proc_pidinfo(PROC_PIDTASKINFO)` both fail for foreign-UID procs (kernel_task pid 0, WindowServer) — XNU same-user-gates all per-proc CPU/mem. So D-013's in-process engine could never show system processes. `top`/Activity Monitor see them only via Apple's private `com.apple.private.proc_info-list` entitlement.
- [x] **Rewrote `TopProcessSampler` to parse `/usr/bin/top`** (`-l 2 -s 1 -o cpu -stats pid,cpu,mem,command`, command last). Parses the **2nd** sample (top's instantaneous %CPU — no rate math, mach-unit conversion retired). CPU + Memory rank from one parse; `TopProcessesSample` lost `byDiskIO`.
- [x] **App-grouping kept** (`proc_pidpath` is permission-free for any PID — verified on WindowServer), fallback to top's COMMAND for pathless procs (kernel_task). **Disk-I/O per-proc list removed** (top has no column) — Disk popover shows aggregate Read/Write only.
- [x] **Gated to panel-visible**: `StatsStore.setPanelVisible()` ↔ `PanelWindowController.onVisibilityChanged` starts/stops the costly `top` sampler + clears the stale list on hide. Cadence `max(2s, interval)`.
- [x] **Observer-effect fix**: our spawned `top` reported itself (~8%) — filtered by the exact spawned PID (`Process.processIdentifier`), so a user's terminal `top` still shows.
- [x] **Earlier same-session polish** (carried in): thresholds dropped (no more 2-3-item lists), rows 5→10, fixed-height popover (no tick-to-tick resize), 1-decimal locale CPU%.
- [x] Builds clean, verified on screen vs Activity Monitor (WindowServer/kernel_task present, per-core % sane, grouping correct). See D-014.

## Next (in order)
1. ✅ ~~First-run hint UI + signing~~ — done 2026-06-13. Hint card + `Debug.local.xcconfig` signing built & probe-verified. Copy finalized to a **"warm welcome"** voice ("You're all set 👋 / Press ⌃⌥⌘Q anytime to pop up your stats."). App icon ✅ done. **Remaining:** user on-screen visual (needs `defaults delete com.sim.QuickStatsPanel hasSeenHint` to re-trigger the one-time card).
2. ✅ ~~Settings UI click-through verify~~ — done 2026-06-13 (toggles + reorder confirmed by user). **Slider/recorder persistence confirmed by inspection:** `hasSeenHint` (same `didSet→defaults.set` pattern) survives in the on-disk domain, so the structurally-identical `interval`/`stripHeight`/`hotKey` writes persist too; those keys are merely absent until first changed (write-on-change semantics). User visual round-trip still nice-to-have.
3. **Themes (named presets)** — see TASKS.md backlog. Refactor `Theme` from a static enum into a persisted, selectable value (colors + bg/opacity + radius/density) the strip and detail card both read. User wants pickable named themes, not loose knobs.
4. ⚠ **MAS caveat (from D-014):** `top` can't be spawned under the App Sandbox — if Mac App Store distribution is ever pursued, the top-process lists must fall back to D-013's user-only `rusage` engine (or be dropped). Fine for direct/notarized distribution.
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
