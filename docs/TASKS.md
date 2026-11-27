# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Active plan

[Floating-tile prototype](IMPLEMENTATION_PLAN-floating-tiles.md) — 4/4 tasks complete 2026-11-27; awaiting owner review
(tile E1, [packet](evidence/floating-tiles-prototype.md#e1-owner-review-packet)). Provisional defaults are evaluated at E1; no production rollout.

## Parked plan

[Gauge ring prototype](../IMPLEMENTATION_PLAN.md) — 12/12 implementation tasks complete (8 original tasks plus F5–F8 fix pass 2,
2026-11-15). Separator/CPU-width follow-ups implemented; scoped native passes recorded, E1 remains open.
Review parked while tile exploration takes priority (D-040); all remaining E1 gates stay open.
See [current handoff](sessions/2026-11-22.md#resume--pre-clear-floating-tile-implementation-next) and [fix pass 2 evidence](evidence/gauge-ring-fix-pass-2.md).
Original implementation tasks completed 2026-11-14 (3.2 added from
the owner's look at the 2.1 build; fit rule resolved by D-037). External gate E1 (owner review,
[checklist](evidence/gauge-ring-prototype.md#e1-owner-review-checklist)) closes the plan. Status and
evidence live in the plan.

Previous: [Native ring prototype](sessions/IMPLEMENTATION_PLAN-ring-prototype-DONE.md) complete
2026-11-13; E1 closed with interaction accepted and look redirected (D-035).

Transfer history shipped as **v1.2.0 (1200)** on 2026-10-28: 8/8 implementation tasks complete;
remaining E1 checks explicitly deferred by the owner to everyday use, not marked as tested.
[Archived plan](sessions/IMPLEMENTATION_PLAN-transfer-history-DONE.md) ·
[Release evidence](evidence/release-1.2.0.md). No further acceptance batch is required before ordinary use.

## Current standalone work

- Power input/system, CPU usage/temperature and Battery charge/time pairs implemented for 1.2.1 (1201); 19 focused tests and Debug build passed. User accepted the latest paired-display build (“works. pass.”); no claim of exhaustive live hardware-state testing. See [handoff](sessions/2026-11-11.md#resume).
- Sparkle 2.10.0 integrated; initial signed empty feed published and verified. Live manual no-update check passed by user screenshot on 2026-11-12; remaining updater controls, real upgrade, Strongbox backup and release packaging remain open.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

The whole stats roadmap has shipped (D-017/D-018/D-019 + D-024), and configurable tiles + activity
graphs shipped 2026-07-27 (D-025). Retained transfers shipped in v1.2.0 on 2026-10-28. Remaining work is the follow-up backlog below.
**This file is the backlog** — `PROJECT_STATE.md` is a digest and points here.

### Ring
- [ ] **Fixture history period queries stall (Debug only)** — confirmed November 16: automatic scheduling is disabled in fixture mode, so changing period queues a query without publishing it. Real-data Network retest passed. See owner evidence; deferred from C7 drawing correction.
- [ ] **Configurable ring gap width, including zero (no gaps)** — owner, 2026-11-15, after accepting the constant-width main-ring separators. Deferred to production appearance/settings planning; no control added now. Decide how ordinary and sensor-group spacing relate when specifying it.
- [ ] **CPU wedge secondary value low contrast** — owner, 2026-11-15: "74°C" under "42%" sits on the
      lighter inner temperature ring. Deferred by owner ("later").
- [ ] **Disk/Network detail card: blank gap mid-card (Strip and Ring)** — owner screenshots 2026-11-14;
      cause found by 3.2: `transferContent` always reserves a 32-point empty warning slot between
      "Unsaved · Last saved …" and Used/Free. Shared with the Strip card, so left unchanged. Fix
      candidate: reserve the slot only while a warning is shown (check D-008 jitter discipline first).
- [ ] **Wedge inner-shape artifact — superseded by D-035 gauge drawing; verify gone in gauge step (plan E1 row C3).** Owner's native screenshot (`eight`
      fixture) shows a darker inner quadrilateral inside the amber Temperature/Memory wedges
      (fainter in others). Not fixed in 1.2 (out of its scope); bounded prototype correction
      candidate for 1.3/E1. E1 checklist case C3 re-checks it.
- [ ] **Fixture-mode Settings saves to real defaults (Debug only, minor)** — 5.1 review F1, 2026-11-14.
      A `--ring-fixture` launch opens the real Settings on the fixture store, so edits persist; unticking
      a fixture sensor/fan under "Detail card rows" stores a made-up label in `hiddenDetailRows`
      (orphan, no visible effect). Kept for E1 (rows B9/G4 use Settings in fixture mode); doc comment
      corrected. Fix candidate: a volatile `UserDefaults` suite for `AppSettings` in fixture mode.
- [ ] **Fixture temp roots never removed (Debug only, minor)** — found by 1.3 inspection, 2026-11-13.
      Each `--ring-fixture` launch leaves `QuickStatsPanel-ring-fixture-<UUID>` in the temp folder
      (`StatsStore.makeRingFixtureStore`; nothing removes it after the termination flush). Fix: keep the
      root URL and remove it after the flush when in fixture mode. Real root unaffected.
- [ ] **Ring wedge radial gauges** — owner idea, 2026-11-13. Each wedge fills from inner edge (0) to
      outer edge (ceiling), stacked components, toggleable text/icon overlay, colour mode, fill
      strength and size presets. Explored in [mockup](https://claude.ai/artifact/WNNwTzTsSQDTR63E8YUj9g)
      (`output/ring-gauges/`); proposals and open questions in `sessions/2026-11-13.md`. Needs
      `RingReading` fraction/segment fields and a sub-radius wedge path. Fix gauge-misleading scales
      first: `PowerSample.loadPercent` (session peak only rises), `NetworkSample.activityPercent`
      (12.5 MB/s cap) — the revised spec gives gauges their own scales, so these now matter only for
      status bands (open item). Spec revised 2026-11-13 (D-035, D-036); adds per-part needs: per-core CPU
      read, volume enumeration, per-interface deltas, un-averaged sensors. Not authorized for
      implementation until an execute request. **Mapped to the
      [gauge ring prototype plan](../IMPLEMENTATION_PLAN.md)** (tasks 1.1–5.1, E1); per-part sampler
      work is deferred there to a follow-up plan. Status lives in the plan.

### Distribution
- [ ] **Sparkle release acceptance** — requested 2026-11-11. Integration, dedicated signing key, signed empty feed and packaging validation implemented for 1.2.1. Initial signed empty feed published and verified; validate manual check and opt-in checkbox, back up key to Strongbox, package/notarize release, and test a real upgrade with retained preferences/history. 1.2.0 must upgrade manually. See `sparkle-updates.md`.

### Layouts and appearance
- [ ] **Specify floating tiles, then plan the native prototype** — owner, 2026-11-22 (D-040/D-041). Clickable mockup explored; carry forward separate surfaces, content-sized detail, hidden overview, stationary independent switcher and usage colours. Next session writes a short spec covering sizing/order, edge placement and keyboard/dismiss behaviour, reusing existing stat/detail groundwork. Native implementation has not started. See [handoff](sessions/2026-11-22.md#resume--spec-next-session).
- **Alternate layouts and bounded appearance** — the first ring prototype is
  [archived](sessions/IMPLEMENTATION_PLAN-ring-prototype-DONE.md); the gauge ring prototype is the
  [active plan](../IMPLEMENTATION_PLAN.md). Remaining production Ring, Grid/Rail and appearance
  controls stay deferred pending follow-up planning; tile exploration may proceed before ring E1 closes (D-040); [spec](../specs/panel-layouts-and-appearance.md). No duplicate completion status here.

### D-025 tails
- [ ] **Detail-card headline pair** (optional) — the big `61 KB/s / Upload` block from the iStat
      reference. Omitted deliberately: the strip and the card's own rows already show those values.
- [ ] **Text-template tile values** (power-user escape hatch) — Stats' `$capacity.free/$capacity.total`
      syntax (`Kit/Widgets/Text.swift:83`) is the only mechanism in either reference product that
      lets a user say "free, not used" in arbitrary form. Best power-to-complexity ratio if the
      per-stat enums ever feel limiting. Not for v1.

### Accuracy
- [ ] **Actual memory pressure and swap** — current `MemorySampler.pressurePercent` is used RAM
      divided by total RAM and is labeled "Pressure" in the detail card. Keep utilization distinct
      from system memory-pressure state; consider swap detail (confirmed source review 2026-10-03).
- [ ] **Disk free-space accuracy** — `DiskSampler.swift:108` (`statfs f_bavail`) reads **600.62 GB**
      where Finder shows **617.24 GB**: a **16.62 GB** purgeable gap, twice-measured. exelban/stats
      matches Finder via `CSDiskSpaceGetRecoveryEstimate` (CoreServices, cached 30 s,
      `Modules/Disk/readers.swift:144`) — **undocumented SPI**, consistent with QSP's IOReport/IOHID
      posture but another one. Alternative `volumeAvailableCapacityForImportantUsageKey` is a
      **required-reason API** (matters only if a `PrivacyInfo.xcprivacy` is ever added). Never
      display `…ForOpportunisticUsage` — it is *smaller* than plain available. ⚠️ The existing
      `used = total − free` derivation (line 109) is **correct**; don't "fix" it.

### Features not started
- [ ] **Right-click Restart QuickStatsPanel** — user request, 2026-10-26; saved for later.
      Add Restart to the strip's context menu. Relaunch the same app bundle through normal
      termination/startup so saved preferences, retained history and cumulative totals survive.
      Current menu lives in `01_Project/Sources/QuickStatsPanel/AppDelegate.swift` (`makePanelMenu`)
      and has Quit but no Restart. Implementation has not started; separate from the shipped transfer-history work.
- [ ] **Vertical strip orientation** — a portrait variant (tiles stacked, anchored to a screen edge).
      Touches D-006/D-008 (thin-strip + content-driven-width assumptions), `PanelWindowController`
      sizing/anchors, and the tile layout — needs a small spec before building.
- [ ] **Per-volume disk rows** — middle ground from the exelban/stats review; adds card height.
      Available on request. (Also reviewed and **rejected** then: usage donuts — user since said
      "donuts later perhaps"; **public IP** — needs an external HTTP call, and QSP making *zero*
      network requests is a privacy property worth keeping; **MAC address** — not glanceable.)
- [ ] **Hover-to-expand tile detail** — later enhancement; needs tracking-area work.
- [ ] **Per-app CPU smoothing** — only if grouped readings flicker; revisit grouping edge cases
      (apps outside an `.app` bundle).

### Release tooling
- [x] **Fail packaging on rejected Gatekeeper assessment** — implemented 2026-11-11 with required app/DMG checks and nested Sparkle signature validation; fixtures passed, real release packaging pending.

### Polish / nice-to-haves (from visual verify)
- [ ] **⏳ USER:** tune `Theme.loadColor(forPercent:)` thresholds — at-a-glance color bands.
      Open questions: same bands for CPU vs memory? gradient vs steps? hysteresis to stop flicker?
- [ ] Memory readout shows 2 decimals ("16,85 GB") — consider 1 decimal for faster glancing.
- [ ] `cornerRadius` 12pt reads fine at the snug width — revisit if it ever feels too round.

## Inbox
- 2026-11-27 — 5.3 look notes (D-046 open items): small tiles Fans/Temperature/Power/Load/Uptime show a blank middle between value and caption; Fan detail row isn't label-left/value-right like other cards; boot date mixes locales ("24. Nov 2026 at 15:30"); fixture Battery temp 31 °C vs 72 °C in Temperatures, Temperature tile "Nominal" under all-hot.
- 2026-11-27 — Flaky: `TransferPersistenceTests.testActualWorstDayDiskMemoryAndIncrementalCheckpointSize` memory budget (75.7/77.8 MB vs 64 MB) fails on some runs, passes on others; unrelated to tiles.
- 2026-11-27 — Shared Atlas helper: other sessions' clicks dismiss the non-activating tile panel within seconds; consider a Debug `--floating-tiles-pinned` launch flag for helper checks.
- [ ] **Primary/secondary tile model (owner, 2026-11-27).** Clicking a primary keeps it, hides the other primaries, opens the secondary inward (CPU → right). Discuss next session; see `sessions/2026-11-27.md` and D-043 update.
- [ ] **Graph inside the CPU primary panel (owner idea, 2026-11-27).** Fill the large tile's empty space.
- [ ] **Double outline on the open tile (2026-11-27, 5.1).** Clicked tile shows the blue focus ring and the white open outline together.
- [ ] **First tile hotkey press after launch sometimes ignored (2026-11-27).** In the Atlas helper the first press after launch did nothing; a second press 1–2 s later worked (seen twice in tile Wave 2). Cause unknown; may be helper-specific.
- [ ] **Ring fixture test leaves TMPDIR folders (2026-11-27).** A hostless Ring test leaves `QuickStatsPanel-ring-fixture-*` folders in `$TMPDIR` (seen during tile Wave 1). Not changed.
- [ ] **Tile transfer controls outside Tab loop (2026-11-27, tile 3.1).** Period/reset controls in tile detail cards work by mouse and VoiceOver but `refusesFirstResponder` keeps them out of Tab traversal (existing behaviour). Decide at tile E1.
- [ ] **Overlay scroller overlaps card values while scrolling (2026-11-27, tile 3.1).** In scrolling tile detail cards the overlay scroller briefly covers right-hand values; legacy scroll bars are fine.
- [ ] **CPU tile detail card taller than content (2026-11-27, tile 3.1).** Reserved process rows inflate the measured height.
- [ ] **Forced-kill leaves isolated defaults plist in helper TMPDIR (2026-11-27, tile 3.1).** `atlas close`/cleanup kills skip graceful teardown, leaving the prototype's temp `-defaults.plist`; graceful Quit leaves nothing.
- [ ] **Fixture transfer-card labels disappear during period changes** — November 16 screenshots; did not recur after verified real-data launch. Cause unconfirmed; distinct from the diagnosed fixture history-query stall.
- [ ] **Text orientation setting (owner request, 2026-11-14).** As in MousePlus (`LabelOrientation`:
      upright / radial / tangential, auto-flipped). Conflicts with the spec's horizontal-text rule
      (D-035); decide at Ring E1 close.
- [ ] **Sub-ring caption/label toggle (owner idea, 2026-11-14).** Possible Settings toggle for hover
      captions versus in-segment labels. Not requested yet.
- [ ] **Power sampler stop/restart race — awaiting reproduction (2026-10-03).** Review found
      timer cancellation followed by main-thread reader/SMC teardown while a queued tick may still
      run. No crash reproduced. Validate queue-confined teardown before changing sampler lifecycle.

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

_Active prototype tasks and evidence live in the plan linked above. Completed transfer-history
evidence remains separate; preferences redesign remains accepted and unreleased._

---

## Progress Calculation

```
Sprint Progress = checked in Current Sprint / total in Current Sprint
Overall Progress = (archived count + checked) / (backlog + current + archived)
```

Archived task count is read from `tasks-archive.md` header.

## Workflow Integration

| Command | Action |
|---------|--------|
| `/interview` | Adds tasks to Backlog |
| `/plan` | Moves Backlog → Current Sprint |
| `/execute` | Checks off tasks as waves complete |
| `/log` | Archives checked tasks, updates PROJECT_STATE.md progress bar |
| `/status` | Reports progress from checkbox counts |

---
*Location: `docs/TASKS.md`. Parsed by Directions app.*
