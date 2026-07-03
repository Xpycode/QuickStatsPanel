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
- **Focus:** **Settings window redesign — ✅ SHIPPED 2026-06-16 (D-020).** The whole stats roadmap is done, so this session was pure UX polish: rewrote the Settings window from one tall scrolling `Form` into a **`NavigationSplitView` sidebar** (ClipSmart pattern) with 5 panes — **Stats / Appearance / Panel / Hotkeys / About**. All binding logic moved verbatim into per-pane structs (each its own `@Bindable AppSettings.shared`); new **About** pane (app icon + version + `confirmationDialog` on Reset + Quit); `SettingsWindowController` made `.resizable` (600×460, min 560×420) since a split view fills rather than hugs. Two on-screen bugs fixed: dead sidebar selection (needed `List(…, id: \.self)` so the tag is the element, not its String id) + spurious Stats scrollbar (bare List fills the pane vs fixed-height List in a Form). Then gave **⌘, a real home**: `AppDelegate.installMainMenu()` (App/Edit/Window) so ⌘,/⌘W/⌘Q/edit shortcuts fire when the app is active — complementing the existing strip-scoped Carbon ⌘,; a **global** ⌘, was rejected (would hijack every app's Preferences shortcut). Menu bar stays hidden during glances (strip is `.nonactivating`). 0 warnings, user-verified "better." Decision D-020. **Prior: D-018 Temperatures — ✅ SHIPPED 2026-06-15. The roadmap is complete — every planned stat ships.** The last roadmap stat. A **two-layer** tile: headline = public `ProcessInfo.thermalState` badge (`Nominal`/`Fair`/`Serious`/`Critical`) → the project's **first always-visible *optional* tile** (never hides; works on Intel/VM); detail = best-effort **IOHID** per-sensor °C (`IOHIDEventSystemClient` + `kIOHIDEventTypeTemperature`, private/un-entitled, 2nd bridging-header consumer, `-framework IOKit`) — chosen over SMC (Apple-Silicon temp keys are undocumented/per-machine/identity-less). **Wave 1 ✅** (the IOHID risk, de-risked in isolation first): standalone `swiftc` spike links+runs un-elevated, then `Sampling/TemperatureReader.swift` (`IOHIDTemperatureReader`) + bridging-header block + `project.yml` build clean in-app, **0 warnings**. **Empirical finding:** this M4 Pro exposes `PMU tdie*` SoC dies / `gas gauge battery` / `NAND CH*` — NOT role-named CPU/GPU sensors — plus `PMU tdev*` −9200 °C sentinels, so honest detail = **SoC/SSD/Battery**; `role(for:)` auto-upgrades to CPU/GPU on chips that name them, clamp `0<c<130` drops sentinels. Decision D-018 + plan `docs/sessions/IMPLEMENTATION_PLAN-temperatures.md` (4 waves/10 ACs). **✅ SHIPPED (all 4 waves):** `TemperatureSampler`/`TemperatureSample` (state→loadPercent 0/40/75/100, role grouping, `Pressure:` fallback) → `.temps` wired into `StatKind`+`StatsStore`+`descriptor` (no `guard`, always shows). On screen (M4 Pro): tile after Power = `Nominal`, detail card **SoC 36 °C / SSD 33 °C / Battery 31 °C**, fixed-width no jitter. **Launch-crash found & fixed in verification** (`a73dea8`): IOHID event-system client was a local in `init` → ARC freed it at init's end while its cached service handles lived on → use-after-free heap corruption on the first tick; now a stored `let`. Migration AC-7 verified (`knownStats` gained `temps`, defaults ON, deliberately-off stat preserved). Plan archived → `IMPLEMENTATION_PLAN-temperatures-DONE.md`. Prior: **Power tile (watts) — ✅ SHIPPED 2026-06-15 (D-019).** A permission-free **⚡ CPU·GPU split-watts** tile (`8·4 W`) via Apple's private but **un-entitled** `IOReport` "Energy Model" channels — no root, no entitlement, notarizable (unlike `powermetrics`). Project's **first bridging header** (`-lIOReport`, no `dlopen`). Watts = ΔJoules÷Δseconds with a **runtime unit-label divisor** (mJ/uJ/nJ), **prefix/suffix channel routing** (multi-die safe), **delta-per-tick** like Network (first tick → `0·0 W` seed), **session-peak tint** (stored `loadPercent`), **hide-when-unavailable** like Battery/GPU/Fan, **un-gated**. 4 waves / 11 ACs. Verified un-elevated (M4 Pro): 0 warnings, `-lIOReport` links, `isAvailable=true`, idle ≈1.2 W total, **CPU → ~6–7 W under a 12-core load while GPU/ANE stay flat** (correct routing/math), `peakTotal` ratchets & `loadPercent` normalizes; on screen (user) tile present + fixed-width + 5-row detail card (CPU/GPU/ANE/DRAM/Total); migration AC-9 data-layer-verified (`knownStats` gained `power`, ON, in-memory `statOrder` append). **Honest limits:** AC-6 hide-on-Intel by mechanism only (no Intel/VM); exact `sudo powermetrics` ballpark cross-check **left to user**; **notarytool + `-lIOReport` unproven — release gate, not dev-blocking** (notarization not wired; fallback `dlopen`). Decision D-019 in `decisions.md`; archived plan `docs/sessions/IMPLEMENTATION_PLAN-power-DONE.md`. **Next: D-018 Temperatures** (tile = public `ProcessInfo.thermalState`, detail = best-effort IOHID per-sensor °C). Polish: Power glyph `bolt.fill` + GPU glyph `cpu.fill` (design pass), prettier GPU device name (`IOClass` "AGXAcceleratorG16X"). Prior: **GPU + Fan stats — ✅ SHIPPED 2026-06-15 (D-017)** (GPU = `IOAccelerator` utilization; Fans = read-only `AppleSMC` `flt` decode; both hide-when-absent, free migration; fans hit 2483 rpm under stress on screen). Prior: **Move + "Keep on Screen" pin — ✅ SHIPPED 2026-06-15 (D-016).** The strip is now repositionable and stickable: drag it by its background (persists as a custom position that wins over the anchor), a right-click menu (Keep on Screen / Reset Position / Settings / Quit), a per-summon pin that survives click-away (Esc/toggle still dismiss) with a rebindable ⌃⌥⌘P hotkey, a fix so Settings no longer opens behind the floating strip, and a theme-tinted `pin.fill` indicator in a reserved leading slot. All five user-verified on screen. **Prior shipped:** Themes (named presets, D — 2026-06-13: 4 presets + Custom, follow-system, unified `usageColor`/hysteresis, archived `docs/sessions/IMPLEMENTATION_PLAN-themes-DONE.md`); first-run hint + code signing; ⌘,-opens-Settings; flat detail card (D-015); top-process via `top` (D-014). Roadmap leftovers: D-018 Temperatures (tile = public `ProcessInfo.thermalState`, detail = best-effort IOHID per-sensor °C); per-app CPU smoothing; hover-to-expand tile.
- **Status:** ✅ `** BUILD SUCCEEDED **` (clean-from-scratch, **0 Swift warnings**), code-signed (team `FDMSRXXN73`, full Apple chain). All stats live; **theme switching live across strip + detail card + hint, user-confirmed on screen ("works and works")**. `NSObservationTrackingEnabled=YES` in the bundle (macOS-15 AppKit observation opt-in). Settings persist via `UserDefaults` (preset id + custom `ThemeData` JSON; round-trip data-layer-verified). gear / ⌘, → Settings (D-009/D-010); Esc / toggle-hotkey / click-away dismiss the strip + detail card + hint. Adversarial `code-reviewer` pass on the Themes diff found **no correctness bugs**. ✅ **Pushed** the D-016/D-017/D-019 backlog (`812251c..afe51da`). ✅ **D-018 Temperatures committed** locally (Waves 1–3 + crash fix: `2e3d315`, `9d18595`, `c5e9349`, `a73dea8`) — **not yet pushed**; push before the next Mac handoff.
- **Last updated:** 2026-07-03

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
- D-017: **GPU + Fan tiles** (permission-free). GPU = IOKit `IOAccelerator` utilization (Disk-style walk); Fans = read-only `AppleSMC` reader with native-LE `flt` decode. Both hide-when-absent like Battery; not visibility-gated; free `knownStats` migration. `powermetrics`-for-power deferred to D-019 (needs root → IOReport instead).
- D-020: **Settings window redesign.** `NavigationSplitView` sidebar (Stats/Appearance/Panel/Hotkeys/About) replacing the single scrolling Form; `.resizable` window. ⌘, gets an application main menu (`installMainMenu()`) so it/⌘W/⌘Q work when the app is active — global ⌘, rejected (hijacks every app); strip-scoped Carbon ⌘, kept. Menu bar hidden during glances (`.nonactivating` strip); doesn't add an `NSStatusItem` (D-003 intact).
- D-019: **Power tile (watts)** (permission-free). Private but un-entitled `IOReport` "Energy Model" channels; first bridging header + `-lIOReport` (no `dlopen`). ΔJoules÷Δseconds, runtime unit-label divisor (mJ/uJ/nJ), prefix/suffix routing (multi-die safe), delta-per-tick (first tick `0·0 W`), session-peak tint (stored `loadPercent`), hide-when-unavailable, un-gated. CPU·GPU split headline; ANE/DRAM/Total in detail. Notarizable but not App-Sandbox-safe (D-014/D-017 class). Flagged release gate: `notarytool` + `-lIOReport` unproven.

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
| GPU utilization | `GPUSampler` (new: IOKit `IOAccelerator` `PerformanceStatistics`, permission-free) | **v2 ✅ (D-017)** |
| Fan speed (rpm) | `FanSampler` + read-only `SMC` (new: `AppleSMC` `flt` decode, permission-free) | **v2 ✅ (D-017)** |
| Power (watts) | `IOReport` "Energy Model" (permission-free; `powermetrics` needs root) | **v2 ✅ (D-019)** |
| Temperatures | `ProcessInfo.thermalState` badge tile + best-effort IOHID per-sensor °C | **v2 ✅ (D-018)** |

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
0. **Cross-pollination backlog (from D-021, 2026-07-03)** — the stat roadmap is done; this is the natural "what next":
   - **Launch-at-login** via `SMAppService` (pattern: ClipSmart `Views/SettingsView.swift:340-379`). Highest value ÷ effort — an always-on HUD should start at login.
   - **Update path:** adopt `SilentUpdateKit` (`zPackages`) + ClipSmart's `scripts/package-dmg.sh`. QSP has no updater; the DMG script also closes the D-019 notarization gate.
   - **Adopt `ShortcutKit`** incl. the new `GlobalHotKeyMonitor` (just added to `zPackages`) → delete hand-rolled `HotKeyService`/`HotKeyRecorderView`.
   - **Port LaunchAway's `ResolvedTheme` + `@Environment(\.theme)`** *before* enabling follow-system light/dark (QSP forces `.dark` today, `Theme.swift:39`, so the repaint bug is dormant not fixed).
   - **Settings search** derived from `StatKind` (pattern: ClipSmart `Models/SettingsSearchIndex.swift`).
   - Full detail: `docs/decisions.md` D-021; sibling `docs/CROSS-POLLINATION.md`; `zPackages/docs/plans/CROSS-POLLINATION-hotkey-panel-family.md`.
   - **Syncthing fix:** add `Config/Debug.local.xcconfig` to `.stignore` (per-machine signing cert leaks across Macs).
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
