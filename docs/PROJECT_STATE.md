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
- **Focus:** **Move + "Keep on Screen" pin — ✅ SHIPPED 2026-06-15 (D-016).** The strip is now repositionable and stickable: drag it by its background (persists as a custom position that wins over the anchor), a right-click menu (Keep on Screen / Reset Position / Settings / Quit), a per-summon pin that survives click-away (Esc/toggle still dismiss) with a rebindable ⌃⌥⌘P hotkey, a fix so Settings no longer opens behind the floating strip, and a theme-tinted `pin.fill` indicator in a reserved leading slot. All five user-verified on screen. Prior: **Themes (named presets) — ✅ SHIPPED 2026-06-13** (all 5 waves / 12 tasks / 11 ACs). Full theming system: 4 presets (Default/Mono/Vitals/Neon) + Custom, follow-system light+dark, a unified `usageColor`/hysteresis status function (retired `loadColor` *and* the battery `100-percent` hack), Settings "Appearance" `Picker` + "Customize…" editor (`ColorPicker`/`Slider`/density via a generic `customBinding`). Theme rides the existing `AppSettings.shared` `@Observable` singleton (views read `theme` in `body`; the 3 NSHostingView panels re-render live on a switch). Full record archived: `docs/sessions/IMPLEMENTATION_PLAN-themes-DONE.md`. **Next focus: GPU + Fan stats (D-017) — spec + plan ready, awaiting `/execute`.** Spec `specs/gpu-fan-stats.md`, plan `IMPLEMENTATION_PLAN.md` (4 waves; SMC reader + GPU read grounded in live exelban/stats source). Increment 1 of the GPU/temps/fans roadmap item: two permission-free tiles (GPU via IOAccelerator `PerformanceStatistics`, Fans via a new minimal AppleSMC reader decoding the Apple-Silicon `flt` type), both hide-when-absent like Battery. Temps split off to D-018 (tile = public `ProcessInfo.thermalState`, detail = best-effort IOHID per-sensor °C). Research-grounded (M4 Pro target = arm64 + fans, all testable on-screen). Other roadmap leftovers: per-app CPU smoothing; hover-to-expand tile. Prior queue items also done: first-run hint, code signing, ⌘,-opens-Settings, flat detail card (D-015), top-process via `top` (D-014).
- **Status:** ✅ `** BUILD SUCCEEDED **` (clean-from-scratch, **0 Swift warnings**), code-signed (team `FDMSRXXN73`, full Apple chain). All stats live; **theme switching live across strip + detail card + hint, user-confirmed on screen ("works and works")**. `NSObservationTrackingEnabled=YES` in the bundle (macOS-15 AppKit observation opt-in). Settings persist via `UserDefaults` (preset id + custom `ThemeData` JSON; round-trip data-layer-verified). gear / ⌘, → Settings (D-009/D-010); Esc / toggle-hotkey / click-away dismiss the strip + detail card + hint. Adversarial `code-reviewer` pass on the Themes diff found **no correctness bugs**. **`origin/main` in sync** (pushed through `2268787` on 2026-06-13).
- **Last updated:** 2026-06-15

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
- D-016: **Drag-to-move + "Keep on Screen" pin.** Drag persists as `AppSettings.customPosition` (beats the anchor); right-click `NSMenu`; per-summon pin gates only click-away (Esc/toggle still dismiss), rebindable ⌃⌥⌘P (4th scoped hotkey); `openSettings` hides the strip first; pinned `pin.fill` in a reserved leading slot.

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
3. ✅ ~~**Themes (named presets)**~~ — **SHIPPED 2026-06-13** (5 waves, 12 tasks, 11 ACs, commits `3fe3bb4`→`befa6d8`). Spec `specs/themes.md`; full wave-by-wave record + Operational Learnings archived to `docs/sessions/IMPLEMENTATION_PLAN-themes-DONE.md`. Summary in Focus/Status above.
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
