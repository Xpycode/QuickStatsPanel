# Decisions Log — QuickStatsPanel

This file tracks the WHY behind technical and design decisions.

---

## Template

### [Date] - [Decision Title]
**Context:** [What situation prompted this decision?]
**Options Considered:**
1. [Option A] - [pros/cons]
2. [Option B] - [pros/cons]

**Decision:** [What we chose]
**Rationale:** [Why we chose it]
**Consequences:** [What this means going forward]

---

## Decisions

### 2026-06-04 - D-001: HUD `NSPanel`, not the App Shell Standard
**Context:** The global App Shell Standard mandates HSplitView + sidebar + FCPToolbarButtonStyle for macOS apps. QuickStatsPanel is a transient, hotkey-summoned overlay — not a window with chrome.
**Options Considered:**
1. App Shell Standard (HSplitView window) — wrong interaction model; a sidebar/toolbar makes no sense for a glance HUD.
2. `NSPanel` (`.nonactivating`, floating level), summoned over whatever app is focused — matches the MousePlus ring overlay.
**Decision:** `NSPanel`, adapting MousePlus `RingWindowController`.
**Rationale:** A quick-glance overlay must appear *without stealing focus* from the current app and vanish on dismiss. That is precisely what a non-activating panel provides; an HSplitView window cannot.
**Consequences:** `/shell-check` must NOT be run against this app expecting HSplitView. The `Theme` struct still governs panel *content* styling. Documented in CLAUDE.md.

### 2026-06-04 - D-002: Global hotkey via Carbon `RegisterEventHotKey`
**Context:** The app is summoned only by a global hotkey (no menu bar, no Dock). The hotkey must work while any app is focused.
**Options Considered:**
1. `NSEvent.addGlobalMonitorForEvents` (MousePlus's approach) — requires Accessibility/Input Monitoring permission; can only *observe*, and adds first-launch friction.
2. Carbon `RegisterEventHotKey` — system-level hotkey registration, **no special permission**, fires reliably regardless of focused app. API is old (Carbon) but fully supported on macOS 15.
**Decision:** Carbon `RegisterEventHotKey` for a toggle (press → show, press → hide).
**Rationale:** The user explicitly wants minimal friction and to "get away from" system clutter. Requiring an Accessibility grant on first launch contradicts that. MousePlus needed press+release (hold-to-show ring) so it had to use NSEvent; QuickStatsPanel only needs a toggle, so the permission-free path is available.
**Consequences:** Need a tiny Carbon bridge (`HotKeyService`). Hotkey rebinding UI must re-register. If the hotkey conflicts with another app, the panel silently won't appear — mitigate with a sensible default + in-panel rebind.
**Addendum (2026-06-04):** User drives the trigger via **BetterMouse** (mouse button → synthesized key combo, e.g. ⌃⌥⌘Q or ⌃⌥⌘S). `RegisterEventHotKey` catches system-posted *synthetic* key events, so the BetterMouse → hotkey chain works with no Accessibility permission. **Default hotkey: ⌃⌥⌘Q, user-rebindable** in the in-panel settings. ⚠ Verify during implementation that BetterMouse's synthetic keystroke is seen by the hotkey registration (post via CGEvent → should be).

### 2026-06-04 - D-003: `LSUIElement = YES` — no Dock icon, no menu-bar item
**Context:** User wants to avoid the menu bar entirely ("sorting through too many items is cumbersome; menu-bar managers are hampered now") and has no need for a Dock icon.
**Options Considered:**
1. Menu-bar status item (typical utility-app pattern) — rejected by user.
2. Dock + menu bar — heavier, more clutter.
3. Pure agent app (`LSUIElement=YES`), no status item; settings & quit reached from inside the panel.
**Decision:** Option 3.
**Rationale:** Directly serves the user's stated preference. The panel itself becomes the only UI surface.
**Consequences:** The global hotkey is the *only* entry point — a single point of failure (see D-002 mitigations). Settings (incl. hotkey rebind) and Quit MUST be reachable from within the panel (a gear button). First-launch needs a one-time discoverability moment (e.g. show the panel once on first run with a hint).

### 2026-06-04 - D-004: Build with xcodegen (`project.yml`)
**Context:** Need a real `.app` bundle (Info.plist with `LSUIElement`, entitlements, signing). Two local templates exist: StatsWindow (SPM) and MousePlus (xcodegen).
**Options Considered:**
1. Swift Package (StatsWindow's approach) — app-bundle config (LSUIElement, icon, signing) is awkward via SPM.
2. xcodegen `project.yml` — declarative, regenerable, clean app-target config; documented in cookbook `47`.
**Decision:** xcodegen.
**Rationale:** App-bundle metadata is first-class in xcodegen; matches the cookbook and MousePlus.
**Consequences:** `project.yml` lives in `01_Project/`. Re-run `xcodegen generate` after adding files. `.xcodeproj` can be gitignored (regenerable) per cookbook guidance.

### 2026-06-04 - D-005: Port StatsWindow samplers rather than rewrite
**Context:** StatsWindow (same machine) already has working `CPUSampler`, `MemorySampler`, `FSUsageSampler`.
**Decision:** Copy these samplers into QuickStatsPanel, adapt naming, keep the `DispatchSourceTimer` + `Sendable`-sample + callback shape.
**Rationale:** They're clean, concurrency-correct (`SWIFT_STRICT_CONCURRENCY: complete`), and battle-tested. Rewriting Mach host-statistics code is error-prone and pointless.
**Consequences:** Network/Battery/GPU samplers (not in StatsWindow) follow the same shape when added. Attribute the source in a header comment.

### 2026-06-04 - D-006: Thin strip + detail-on-demand, not a tall dashboard
**Context:** Initial proposal was a ~620×120 panel. User: 120 height is too much — wants ~22–44pt, with detail revealed on hover/click of a stat element.
**Options Considered:**
1. Tall dashboard (~120pt) — shows everything at once; intrudes on screen; covers content when anchored near cursor.
2. **Thin strip (~36pt, configurable)** — single row of compact stat tiles (SF Symbol + primary value, e.g. `􀫥 34%`); detail breakdown revealed per-tile on demand.
**Decision:** Option 2. Panel is a thin horizontal strip; each stat tile expands to a detail view (breakdown + sparkline) on interaction.
**Rationale:** User wants a *quick glance*, not a monitoring dashboard. A thin readout intrudes minimally and pairs well with "near cursor" anchoring. Depth stays available without permanent clutter — matches the iStat Menus menu-bar-dropdown feel.
**Detail trigger:** **Click-to-expand for v1** (reliable in a non-activating panel), **hover as a later enhancement** (needs `acceptsMouseMovedEvents` + tracking; user said "click would also be fine if easier"). Implemented via `NSPopover` or inline expansion below the tile.
**Consequences:** Layout is a horizontal `HStack` of fixed-height tiles. Width ~620 default but content-driven/variable. Each sampler must expose both a compact value and a richer breakdown. Strip height configurable (~22 single-line ↔ ~44 icon+label+sparkline).

### 2026-06-04 - D-007: Panel position configurable; default near cursor
**Context:** Where should the strip appear when summoned?
**Decision:** Default **near the cursor** (clamped fully on-screen, like MousePlus); user can set a **fixed anchor** instead (e.g. top-center, a corner, or a remembered point).
**Rationale:** Near-cursor means the readout shows up where the user is already looking — least eye travel. But some users prefer a stable, predictable location; making it a setting serves both.
**Consequences:** `PanelWindowController` takes an `anchor` mode: `.cursor` (default) vs `.fixed(position)`. Settings exposes the choice; the cursor-clamp logic from MousePlus `RingWindowController` covers the `.cursor` case.

### 2026-06-04 - D-008: Strip width is content-driven, not fixed
**Context:** The first cut used a fixed ~620pt-wide panel. With only CPU + Memory tiles that left a large band of empty strip, and a fixed width would either waste space or clip once more stats were added.
**Options Considered:**
1. Fixed width (~620) — predictable, but dead space at few tiles and risks clipping as stats grow.
2. **Content-driven width** — ask the SwiftUI tree for its ideal size (`NSHostingView.fittingSize`) at summon; the strip hugs its tiles and grows as stats are added.
**Decision:** Option 2. `PanelWindowController.show()` measures `hosting.fittingSize` once per summon and sizes the panel to it.
**Rationale:** A glance HUD should be as small as its content allows — least screen intrusion, and it scales automatically as the stat set changes (ties into D-006's "grows with more stats").
**Implementation notes:**
- Tile content uses `.fixedSize(horizontal:)` so values never wrap as the width is computed.
- **Per-summon jitter fix:** tiles are fixed-width with monospaced digits (Penumbra `TimecodeView` pattern, cookbook `67`) so a changing readout (e.g. `9%` → `100%`) doesn't reflow the strip. Width is measured **once per summon**, not per tick — the strip never resizes while visible.
**Consequences:** Width is variable (~210pt with CPU + Mem, larger as tiles are added); anchor/clamp math already works off the measured size. Because size is fixed at summon, settings that change content (stat set, height) apply on the *next* summon, not live (see D-009 consequences).

### 2026-06-04 - D-009: In-panel gear opens the standard Settings *window* (not a popover)
**Context:** "Settings live inside the panel" (D-003), but the panel is a non-activating `NSPanel` and the app is `LSUIElement`. The hotkey-rebind setting needs to *capture* keystrokes, which requires a window that can become key — exactly what the panel refuses to do.
**Options Considered:**
1. Gear → SwiftUI **popover** inside the panel — most on-brand, but recording a hotkey needs a focus workaround since the panel never becomes key.
2. **Gear → the standard `Settings` window** — more room, standard form, and it can become key so the hotkey recorder "just works"; costs a focus switch and a separate window.
**Decision:** Option 2. A trailing gear tile opens a settings window. **Mechanism:** a *self-managed* `NSWindow` hosting `SettingsView` (`SettingsWindowController`), **not** the SwiftUI `Settings` scene — `showSettingsWindow:` silently no-ops under `LSUIElement` (focus shifts, no window appears, as observed in testing). The controller does `NSApp.activate(ignoringOtherApps:)` + `makeKeyAndOrderFront`; the SwiftUI `Settings` scene is now an empty placeholder.
**Rationale:** The hotkey recorder relies on a local `keyDown` monitor, which only fires while a window is key. A self-managed window becomes key reliably; the `Settings` scene's action does not in an accessory app, and a popover in the non-activating panel never becomes key at all.
**Architecture:** `AppSettings.shared` (`@Observable`, `UserDefaults`-backed) is the single source of truth shared by `AppDelegate`'s imperative objects and the `Settings` scene. Passive settings (anchor, height, stat order/enabled) are read lazily at summon / in `body`; active settings (interval, hotkey) push via `onIntervalChanged` / `onHotKeyChanged` `didSet` hooks (`store.restart()` / hotkey re-register). Hotkey validation: reject Shift-only — require ≥1 of ⌘/⌥/⌃.
**Consequences:** Supersedes the "fixed anchor = arbitrary point" hint in D-007 — anchor is now an enum (`cursor`/`screenCenter`/`topCenter`/`bottomCenter`). Anchor/height changes apply on next summon (panel size is measured once per summon via `fittingSize`).

### 2026-06-05 - D-010: Esc-to-dismiss via a scoped Carbon hotkey
**Context:** Esc should dismiss the panel. But the panel is a `.nonactivatingPanel` summoned with `orderFrontRegardless()` — it deliberately never becomes key (D-001), so `keyDown` / SwiftUI `.onKeyPress` never reach it; Esc goes to whatever app actually has focus.
**Options Considered:**
1. Global `NSEvent` keyboard monitor — catches Esc regardless of focus, but a *keyboard* global monitor requires Input-Monitoring permission, breaking the permission-free principle (D-002, D-003).
2. Make the panel key on show + local monitor — no system-wide capture, but steals keyboard focus from the user's app, contradicting the non-activating glance design.
3. **Carbon `RegisterEventHotKey` for bare Escape, registered only while the panel is visible** — permission-free, fires regardless of focus, no focus theft.
**Decision:** Option 3. A second `HotKeyService` instance (`id: 2`) registers bare-Escape on panel show and unregisters on hide.
**Rationale:** Same permission-free, focus-independent mechanism already proven for the toggle hotkey (D-002) — the only such option for a panel that never becomes key. The toggle hotkey remains the primary dismiss; Esc and click-away are conveniences.
**Architecture:** Registration is driven by a new `PanelWindowController.onVisibilityChanged` signal (fired in `show`/`hide`), **not** by `AppDelegate.togglePanel()` — so teardown covers *every* hide path (toggle, click-away, Esc itself). Wiring Esc to the toggle call site alone would leave Escape captured after a click-away dismissal. Required a latent fix in `HotKeyService`: the Carbon callback now reads the fired `EventHotKeyID` (`kEventParamDirectObject` → `typeEventHotKeyID`) and filters by per-instance `id`, since Carbon dispatches every press to *all* installed app-level handlers — without filtering, the toggle hotkey would also fire the dismiss action.
**Consequences:** While the panel is visible, bare Escape is captured **system-wide** (every other app loses Esc until the panel hides). Acceptable because the panel is transient and the capture window is exactly its on-screen lifetime. `HotKeyService` is now multi-instance-safe (ID-filtered), so further scoped hotkeys can be added the same way.

### 2026-06-05 - D-011: Add Load Average + Uptime tiles (Phase A quick-wins)
**Context:** Roadmap calls for more stats. Load average and uptime are permission-free single-call reads that fit the existing sampler pattern with zero view changes.
**Decision:** Two new absolute-snapshot samplers (no delta), wired through `StatKind`/`descriptor(for:)`/`StatsStore` like the others.
- **Load Average** — `getloadavg(3)` (libc, no entitlement). Headline = 1-min load (`"1.24"`); color band = `load1 ÷ activeProcessorCount` (saturation, clamped 100); popover = 1/5/15-min + core count.
- **Uptime** — `sysctlbyname("kern.boottime")`, **not** `ProcessInfo.systemUptime`. Headline = compact two-unit `"3d 4h"`; `loadPercent: 0` (no "load" → always-calm tint); popover = uptime + approx boot date.
**Rationale:** `systemUptime` only counts *awake* time, so on any Mac that sleeps it reads low; `kern.boottime` matches `uptime(1)` / Activity Monitor. Both are snapshots → correct on the very first summon (preserves the summon-glance-dismiss feel — no delta-seeding blank frame).
**Consequences:** Files `Sampling/LoadAverageSampler.swift`, `Sampling/UptimeSampler.swift`. Load can exceed the reserved `"88.88"` width on a >99 load (implausible on a desktop) — acceptable.

### 2026-06-05 - D-012: Top-Process tile is "top *user* process by memory" (no privileged helper)
**Context:** A "what's eating my Mac" tile. macOS gates `proc_info` with a same-user check (verified in XNU `proc_security_policy`): enumerating PIDs and reading a process *name/path* works for any process, but reading *memory/CPU* works only for processes owned by the current user — foreign ones (kernel_task, WindowServer, root daemons) return EPERM.
**Options Considered:**
1. Privileged root helper (how Activity Monitor's `sysmond` does it) — true system-wide top, but installs a setuid helper and breaks the zero-permission stance (D-002/D-003).
2. **Unprivileged libproc, report the heaviest *readable* process** — permission-free; honestly "top user process," missing system daemons. Same model as `top`/htop without `sudo`.
**Decision:** Option 2. **Memory first** (`ri_phys_footprint`, matches Activity Monitor's Memory column), via `proc_listallpids` → `proc_pid_rusage(RUSAGE_INFO_V4)` (skip EPERM) → name via `proc_pidpath().lastPathComponent`. Tile shows the memory value as headline; process name lives in the popover (keeps the fixed-width numeric tile design, D-008, intact). Hidden until the first readable process is found.
**Rationale:** Memory is a snapshot (correct on first summon, no two-tick delta), cheaper than CPU%, and identical permission profile. Top-by-CPU (delta-based, reads blank on the first frame unless sampled continuously) is the documented fast-follow.
**Consequences:** File `Sampling/TopProcessSampler.swift`. Enumerates ~600 PIDs/tick on a background queue (~1–3 ms) even while the panel is hidden — consistent with the other always-on samplers; could be gated to panel-visibility later if power matters. `import Darwin` for libproc. The `proc_pid_rusage` buffer needs a `withMemoryRebound(to: rusage_info_t?.self)` because the C param is an opaque `void *`.
**Also (this change):** `AppSettings` gained a `knownStats` UserDefaults record — new `StatKind`s default ON for existing users without re-enabling stats they deliberately disabled (a disabled stat and a brand-new stat are otherwise indistinguishable, since only enabled stats are persisted). `SettingsView` stat-list height now scales with stat count instead of a hardcoded 170.

### 2026-06-05 - D-013: Top-process lists live in the CPU/Mem/Disk popovers (iStat-Menus style); retire the standalone tile
> **⚠️ Partially superseded by D-014 (2026-06-05):** the popover-folding, app-grouping, and standalone-tile retirement all stand. The **data source** does not — the in-process `rusage` engine (and with it the mach-unit CPU math and the per-process disk-I/O list) was replaced by parsing `/usr/bin/top`, because `rusage` structurally can't see system processes. Read D-014 for the current implementation.

**Context:** Fast-follow to D-012 (top-process CPU mode). Rather than add a second standalone tile or a memory/CPU toggle, fold the rankings into the relevant tile dropdowns — the way iStat Menus does it (CPU dropdown → top by CPU, etc.).
**Options Considered:**
1. Two standalone tiles (top-by-CPU + top-by-memory) — more strip clutter, redundant glyphs.
2. One tile with a memory/CPU toggle — can't see both leaders at once.
3. **Top-N lists inside each tile's existing popover** (CPU/Memory/Disk), retire the `.topProcess` tile — most iStat-like, no extra strip width, each metric's culprits sit under that metric's breakdown.
**Decision:** Option 3. One `TopProcessSampler` enumeration pass per tick reads each PID's `rusage_info_v4` **once** and ranks three ways from that single struct: CPU% (Δ user+system), memory (`ri_phys_footprint` snapshot), disk I/O (Δ `ri_diskio_bytes{read,written}`). Top 5 of each render as a "Top by …" section in the CPU / Memory / Disk popovers. The standalone `.topProcess` `StatKind` is removed.
**Rationale:** All three metrics come free from the rusage struct already read for the old memory tile — one pass, three rankings, same permission profile (still "top *user* processes", D-012's same-user gate). Folding into popovers keeps the thin strip thin (D-006/D-008).
**⚠️ Units gotcha (verified against XNU + osquery#7459):** `ri_user_time`/`ri_system_time` are in **mach absolute time units, not nanoseconds** — the kernel writes `rm_time_mach` straight through (`osfmk/kern/bsd_kern.c` `fill_task_rusage`). On Apple Silicon a tick ≈ 41.67 ns, so treating them as ns under-reports CPU ~24×. Fix: convert via `mach_timebase_info` and measure wall time with `mach_absolute_time()` (for CPU% the timebase cancels mach÷mach; disk bytes/sec needs the real-seconds conversion).
**Network is deliberately excluded:** per-process network bandwidth has **no permission-free public API** on macOS (`nettop` uses the private `NetworkStatistics.framework`; alternatives need root). The Network tile stays system-wide Down/Up only — a hard platform limit, consistent with D-002/D-003.
**Architecture:** `TopProcessSample` → `TopProcessesSample` (`byCPU`/`byMemory`/`byDiskIO: [ProcStat]` + formatting helpers). Sampler keeps per-PID `prevCPU`/`prevDisk` maps + `prevWall` for the rate deltas. `StatDescriptor` gained an optional `ProcessSection` rendered by `StatTileView` beneath the detail rows (auto-hidden while empty, so two-tick CPU/disk rates don't flash an empty header on first summon). `.topProcess` removal needs **no migration** — `AppSettings.init`'s `compactMap(StatKind.init(rawValue:))` silently drops the stale persisted rawValue.
**Grouping (same change):** processes are grouped **by app** — a browser/editor spawns N helper PIDs and a flat list would just repeat the helper name. Each PID is attributed via `appGroupName(forPath:)`, in priority order: (1) **outermost `.app` bundle** in its `proc_pidpath` (first `.app` from the root; how Activity Monitor groups — helpers nested in deeper `.app`s roll up to the top-level app); (2) **`.xpc`/`.appex` service bundle** with no `.app` ancestor, name *prettified* (reverse-DNS → last component → camelCase-split, e.g. `com.apple.WebKit.WebContent` → "Web Content"); (3) plain executable name, but **climbing past version-like tokens and generic launcher dirs** (`versions`/`bin`/`MacOS`/…) so a version-named binary like `…/claude/versions/2.1.165` groups as "claude", not "2.1.165". Values are summed per app, *then* ranked — so 20 small Chrome helpers correctly roll up above a single mid-size process. Grouping defeats the earlier "resolve names for top-8 only" optimization (a PID's group must be known *before* ranking), so names are resolved for every readable PID via a **per-PID `nameCache`** (`proc_pidpath` once per process; pruned to live PIDs each tick so it can't grow unbounded and a recycled PID can't carry a stale name). `ProcStat` is now identified by app `name` (the `pid` field is gone — a row is an app, not a process).
**Rejected — responsible-app attribution for XPC services:** WebKit content/networking procs are XPC services with no `.app` in their path and parent = `launchd`, so they can't be tied to the host app (Safari vs Chrome) from public, permission-free APIs (`ppid` is useless here; ES `responsible_audit_token` needs an Apple entitlement + FDA). The only working route is the **private** `responsibility_get_pid_responsible_for_pid` (libquarantine — permission-free for same-user but unexported, App-Store-rejecting, OS-fragile). Chose to **prettify the name instead** (public-only), consistent with D-012's "stay clean even if data is partial". Consequence: all browsers' content processes group into one summed "Web Content" row, not split per host app (exelban/Stats has the same limitation — closed both grouping requests as not-planned).
**Consequences:** Files: `Sampling/TopProcessSampler.swift` (rewritten), `Model/StatDescriptor.swift`, `Model/StatsStore.swift`, `Views/StatTileView.swift`, `Views/StatsStripView.swift`. `flame`/`Top Process` no longer appear in Settings. Builds clean, no warnings. CPU%/disk-rate accuracy pending on-screen cross-check vs Activity Monitor.

### 2026-06-05 - D-014: Source top-process lists from `/usr/bin/top`, not in-process `rusage`
**Context:** On an idle Mac the D-013 CPU list was near-useless — it showed only QuickStatsPanel + a couple of tiny user procs, never the actual heavy hitters (WindowServer, kernel_task). Root cause, **proven this session with two throwaway probes**: XNU same-user-gates *all* per-process CPU/memory APIs, not just `rusage`. `proc_pid_rusage` **and** `proc_pidinfo(PROC_PIDTASKINFO)` both returned failure/EPERM for kernel_task (pid 0) and WindowServer (`_windowserver`-owned), while succeeding for our own PID. So **no in-process libproc call can ever see foreign processes' CPU** — D-013's "top *user* apps" was hiding a hard wall, and on a quiet machine the genuinely-busy processes are almost always the system ones we couldn't read.
**Key finding:** `top`/Activity Monitor see everything because they are **Apple-signed binaries carrying the private `com.apple.private.proc_info-list` entitlement** that third-party apps cannot obtain. But the entitlement rides with the *binary*, so **shelling out to `/usr/bin/top` works** — the subprocess runs with top's credentials, prints all processes, and we parse it. Still no permission prompt to the user.
**Options Considered:**
1. Keep in-process `rusage`, relabel "Top user apps" — pure/instant/grouped, but structurally blind to system processes (the actual complaint). Rejected.
2. Privileged helper / request the entitlement — true system-wide, but breaks zero-permission (D-002/D-003) and the entitlement is Apple-private/unobtainable. Rejected.
3. **Parse `/usr/bin/top`** — borrows Apple's pre-entitled binary; system-inclusive; no user permission. Chosen.
**Decision:** Option 3, **all lists via `top`** (user-chosen over a CPU-only hybrid). Per tick: `top -l 2 -s 1 -o cpu -stats pid,cpu,mem,command`, read stdout to EOF (~1s), parse the **2nd** sample (whose %CPU is the instantaneous delta top computed — so we do **no rate math**, retiring D-013's mach-unit conversion). `command` is placed **last** so process names with spaces survive whitespace-splitting. CPU% and memory both rank from that one parse.
**Rationale:** Gets the list the user actually wants (looks like Activity Monitor) with no permission, no privileged helper, no private API linkage — just a subprocess of a guaranteed-present system binary. Sandbox is OFF (verified), so spawning is allowed.
**Lifecycle — gated to panel-visibility:** `top` is costly (it showed ~8% CPU itself), so unlike the always-on in-process samplers this one runs **only while the panel is on screen**. `StatsStore.setPanelVisible(_:)` starts/stops it, driven from `PanelWindowController.onVisibilityChanged` (the same hook that scopes the Esc hotkey, D-010). On hide it also clears `topProcesses` so a stale list doesn't flash on the next summon. Cadence is `max(2s, interval)` to leave a gap between the ~1s top runs. List populates ~1s after each summon (headline tiles stay instant).
**Grouping kept; disk-I/O dropped:** app-grouping survives — `proc_pidpath` is permission-free for *any* PID (verified: resolved WindowServer's real path), so we still roll helper soup into one app row, falling back to top's COMMAND for pathless procs (kernel_task). The per-process **disk-I/O list is removed**: `top` has no per-process disk column and the only source is the entitled API behind Activity Monitor's Disk tab. The Disk popover now shows aggregate Read/Write only.
**Observer effect:** our own spawned `top` reports itself in its output (~8%). Filtered out by the **exact PID we spawned** (`Process.processIdentifier`), not by name — so a user's own terminal `top` still appears.
**Consequences:** `Sampling/TopProcessSampler.swift` rewritten (now `import Darwin` only for `proc_pidpath`; spawns `Process`, no `DispatchSourceTimer`-vs-stream change — still timer-driven, but each tick is a self-contained `top` run). `TopProcessesSample` lost `byDiskIO`/`diskRows`. `StatsStore` gained `panelVisible` + `setPanelVisible`. `StatDescriptor` disk case lost its `processSection`. `AppDelegate` visibility hook now also calls `store.setPanelVisible`. **Requires sandbox OFF** (already true; revisit for Mac App Store — `top` can't be spawned under the sandbox, which would force a fallback to D-013's user-only `rusage` engine). Builds clean. Verified on screen: CPU list shows WindowServer/kernel_task with sane per-core % matching Activity Monitor; grouping correct; probe filtered.

---
*Add decisions as they are made. Future-you will thank present-you.*
