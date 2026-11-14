# Gauge Ring Prototype — Implementation Plan

**Created:** 2026-11-14 · **Status:** Waves 1–2 complete (2.1 replanned under D-037); Wave 3 needs a new request
**Progress:** 4/7 tasks complete; external acceptance: **E1** open.
**Task states:** unchecked = pending / implemented-unverified / blocked (name the gate); checked =
complete with required evidence. This file owns task status and evidence; `docs/TASKS.md` links
here without duplicating completion boxes. Task identity is this plan path plus ID.
Execute with `/Users/sim/ProgrammingProjects/0-DIRECTIONS/__DIRECTIONS/commands/execute.md`.

## Goal and bounded scope

Rebuild the Debug-only native ring as the gauge ring of D-035/D-036, so the owner can judge gauge
legibility, the three size presets, the small hub, the More wedge and the sub-ring arcs natively
before any production layout, settings or sampler work is planned.

Source → action → destination → outcome: existing ordered enabled stat identities and live samples
(or deterministic fixtures, including per-part fixtures) → summon in a chosen preset, read the
gauges, dwell or click a wedge, travel outward into its sub-ring or sideways into its card, open
More, Escape → native gauge ring, one outer arc and one detail card → each wedge's fill agrees with
its stat, text never shrinks, and the accepted hover/hold behaviour survives the new structure.

Agreed limit: one prototype presentation behind `--ring-prototype`, Debug only and absent from
Release. Options are Debug launch arguments, not Settings controls. No persisted layout, favourite,
size or colour-mode setting; no Grid or Rail; no new sampler or sampler change; no new permission;
no release work. Ordinary launch still shows Strip. The prepared 1.2.1 app, DMG and feed are not
touched.

**Planning decision — fixtures first.** Sub-ring parts come from fixtures only. Gauge wedges use
real data, because every fill in the spec's table can be derived from sample fields that exist
today. In real-data mode no stat has parts, so it takes the spec's "fewer than two parts" path:
the detail card opens and no arc appears. Real per-part sampling (per-core CPU, volume enumeration,
per-interface deltas, un-averaged sensors) is a follow-up plan after E1, one sampler change at a
time behind hostless tests. AC-37, and AC-34 on real data, wait for that plan.

Terminology: **owner** is the human reviewer. The wedge that a child arc or card belongs to is its
**parent target**.

Stop and replan, instead of pressing on, when: any wedge in any preset cannot fit at least the
icon-only rung (D-037 accepts icon-only, including Medium with eight favourites and a More wedge,
with the full reading in the card and to accessibility; the earlier icon + value floor is retired);
any preset needs text
smaller than 13/16/12 points, rotated or truncated; the outward route from a wedge into its
sub-ring or card cannot be preserved with the accepted timings; or success would need a second
outer band, recursive rings, a new permission or a sampler change. Use the spec's list/card
fallback first and record the failed case. This plan ends at E1.

## Requirements and evidence consulted

- [Layout/appearance spec](specs/panel-layouts-and-appearance.md): "Ring contract — revised
  November 13", "Colour behaviour" (gauge fills), AC-04/05/06, AC-08–13, AC-20–36, AC-38–41,
  "Gauge ring: code and platform review", "Design gate and finite validation" and the Open
  Questions table. AC-01–03, AC-07, AC-14–19 and AC-37 are deferred with their features.
- [D-034, D-035, D-036](docs/decisions.md).
- [Ring prototype evidence and owner results](docs/evidence/ring-prototype.md): interaction rows
  H1–H6, M1, E1a, D2, P1 passed and are not repeated unless this plan changes their mechanism;
  rows not run or superseded are repeated at E1 (list under E1).
- [Archived ring prototype plan](docs/sessions/IMPLEMENTATION_PLAN-ring-prototype-DONE.md): window
  model, isolation rules, visibility parity and operational learnings still apply.
- Mockup, visual target only: `output/ring-gauges/ring-gauges.html`.
- Code confirmed at planning (2026-11-14, `main` at `5351e44`):
  - `Model/RingGeometry.swift`: radii and footprint are static constants (100 / 260 / 520); the
    hub owns the More and Settings frames; `outline(of:)` hard-codes both radii.
    `RingMoreGeometry` in `Model/RingPlacement.swift` repeats the same sector code at 274 / 410 / 820.
  - `RingReading` (`Model/RingPresentation.swift`) carries text and a band only.
    `RingSnapshot.make` takes the first eight enabled kinds as favourites.
  - `RingNode` is `.wedge`, `.more`, `.moreItem`; `RingExpansion` is one optional `more` hold plus
    one `Detail` with a `viaMore` flag; `RingPlan.Mode` is `.outerRing`, `.sideList`, `.wholeList`.
  - `CPUSample` exposes user, system and total (nice is inside total), `MemorySample` app, wired,
    compressed and used, `DiskSample` capacity and read/write rates, `NetworkSample` down/up,
    `BatterySample` percent, charging and on-power, `GPUSample` utilisation, `PowerSample` four
    components plus optional system watts, `FanSample` current/minimum/maximum per fan,
    `LoadSample` three averages, `TemperatureSample` thermal state and sensors.
  - C1: `AppDelegate.toggleRing` measures every card with `NSHostingView.fittingSize` before
    `setPanelVisible` starts the top-process sampler; `StatDescriptor`'s process `section` returns
    nil for empty rows, so nothing is reserved; `showRingDetail` wraps the whole card, Close row
    included, in a `ScrollView`.
  - The hostless test bundle compiles `Model/`, `Sampling/`, `Theme.swift` and `HotKeyService.swift`.
    `Views/` and `Panel/` are outside it. The generated Xcode project is not tracked.
  - Baseline: 212 hostless tests pass (92 of them ring tests).

## Open Questions rows: how this plan treats them

No row is marked confirmed by this plan. Proposed rows are built as provisional prototype
baselines and decided by the owner at E1. Open rows get a provisional prototype answer only where
the prototype cannot run without one.

| Spec row | Prototype treatment | Built in | Decided at |
|---|---|---|---|
| Child level shape (Proposed) | Arc centred on the parent in one outer band | 1.1, 3.1, 4.1 | E1 |
| Preset dimensions and content ladder (Proposed) | 260 / 360 / 460 points; richest rung that fits per wedge; mixed rungs allowed | 1.1, 2.1 | E1 |
| Gauges for Fans, Load, Uptime (Proposed) | Fan speed within its range; load ÷ cores; Uptime without fill | 1.2, 2.1 | E1 |
| Fill basis differing from text reading (Review) | Fixed basis; the Ring detail card names it where they differ | 1.2, 2.1 | E1 |
| Gauge fill colour versus colour mode (Open) | Mockup per-stat hues, Mono neutral; colour modes are not built | 1.2, 2.1 | E1 collects the owner's view; stays open |
| Status-band input for Network and Power (Open) | Bands untouched; they still set only value weight and colour. Gauge fills never read a band | — | Stays open |
| Power gauge ceiling (Open) | Provisional 30 W (the mockup's value), overridable with `--ring-power-ceiling=<watts>` for review | 1.2, 2.1 | E1 |
| Which gauge options become settings (Proposed) | Size, Wedge text and Fill scale exist as launch arguments only | 2.1 | E1 (with S1) |
| Volumes shown / Interfaces shown (Proposed) | Fixture parts follow the proposed rules; the real policy is exercised by the sampling plan | 1.2 | Sampling plan |
| Sensor labels and the 32-part cap (Proposed) | Role groups, raw names in captions, largest group collapses first | 1.2, 4.1 | E1 on fixtures |
| Real per-part sampling (Planning decision) | **Decided here: fixtures first** | — | — |
| Settings placement (Draft) | Not built; reviewed as checklist row S1 | — | E1 |
| Minimum workspace and text-size matrix (Proposed) | 1024 × 640 and 1440 × 900 visible points, 1×/2×, each preset, in placement tests; native part at E1 | 3.1, 5.1 | E1 |
| D-006 / D-008 evolution | Out of scope; decided at production approval | — | — |

## Prototype launch arguments (Debug only)

`--ring-prototype` and `--ring-fixture=<name>` keep their meaning. New arguments, all optional;
an unknown value logs and falls back to the default:

| Argument | Values (default first) | Stands in for |
|---|---|---|
| `--ring-size=` | `medium`, `small`, `large` | Size preset |
| `--ring-text=` | `label`, `icon-value`, `icon` | Wedge text upper rung |
| `--ring-fill=` | `area`, `linear` | Fill scale |
| `--ring-favourites=` | `8`, or `0`…`8` | How many of the first enabled stats are favourites; the rest go to More |
| `--ring-parts=` | `typical`, `dense`, `minimal` | Per-part fixture set; fixture mode only |
| `--ring-power-ceiling=` | `30`, or watts | Power gauge ceiling |

Part fixture sets: `typical` — 10 cores in two classes, four volumes, three interfaces, 29
sensors. `dense` — 32 cores in three classes, four volumes, three interfaces, more than 32 sensors
(exercises the collapse rule). `minimal` — 10 cores, one volume, one interface, no valid sensor
(exercises "fewer than two parts": three stats open a card and no arc). In fixture mode the CPU,
Disk, Network and Temperature parent readings are derived from the chosen part set, so parts and
parent agree by construction.

## Acceptance criteria for this prototype

- [ ] Gauge math: equal-area and linear fills satisfy AC-24; stacked stats satisfy AC-25; Disk and
      Network satisfy AC-26/27; unavailable stats satisfy AC-28. Hostless tests.
- [ ] Presets: in Small, Medium and Large with 1, 6 and 8 favourites, with and without a More
      wedge, text is 13/16/12 points, horizontal and contained; each wedge takes the richest rung
      that fits; rung and slot are frozen for the summon (AC-29, AC-04). Hostless containment
      tests plus native owner judgement of comfort.
- [ ] Hub and More wedge: the hub offers only the gear and drag, gear target at least 28 × 28
      points (AC-30); the More wedge sits at six o'clock with its count and is absent when nothing
      remains (AC-31); 0/1/6/8 favourites with up to eleven enabled stats keep every stat
      reachable (AC-06, AC-22, AC-05).
- [ ] Branch behaviour: a sub-ring and its card open, hold and close together (AC-32); at most one
      arc and one card are open and nothing in the ring moves when an arc opens (AC-33, AC-10); a
      stat in the More arc opens a card only (AC-09); Escape order, held precedence, stale-timer
      and stationary-reopen rules are unchanged (AC-08, AC-13, AC-20, AC-21, AC-23).
- [ ] Sub-rings on fixtures: parts agree with the parent (AC-34 on fixtures); 32 cores and 29
      sensors give segments at least 8 points wide, grouped, with captions; above 32 parts groups
      collapse and no part leaves the total (AC-35); fewer than two parts or no room for the band
      gives a card and no arc (AC-36); a part that disappears mid-summon keeps its position and
      shows unavailable (AC-38, model level).
- [ ] Edges: the whole branch (ring, band, largest card) is placed before input, or the declared
      fallback is chosen; the parent target never moves (AC-12, AC-23).
- [ ] Cards: Close stays visible and clickable outside the scrolling region with real data
      (AC-39).
- [ ] Accessibility and motion: explicit elements for wedges, More, gear and sub-ring segments
      (AC-40); fills step under Reduce Motion; the fill edge is an explicit line under Increase
      Contrast or Differentiate Without Colour, and reads at 3:1 or better otherwise (AC-41).
- [ ] Non-activating first click, pin, drag, hotkey and click-away keep their meanings; Strip is
      unchanged; no second sampler or history lifecycle; nothing ring-specific is persisted.
- [ ] Release contains no `--ring-` launch literal and no ring controller, view or fixture symbol.

## Execution schedule and ownership

- **Execution scope/limits:** 2026-11-14 owner requested "execute wave 1" only; Wave 1 done.
  2026-11-14 (later): owner chose fit option (a) (D-037), asked to replan 2.1 and execute **Wave 2
  only**. Wave 3 needs a new request. No push authorized.
- **Precondition for Wave 1:** commit and push this plan, the revised spec and the pending
  documentation edits (with the owner's confirmation), so wave diffs are clean and the other Mac
  can see them.
- **Coordinator-owned:** `01_Project/project.yml`, `xcodegen generate` and the generated project,
  every `xcodebuild` run and everything under `01_Project/build/`, this plan,
  `docs/PROJECT_STATE.md`, `docs/TASKS.md`, evidence documents and Git. Task agents write source
  and tests in their owned files and return; the coordinator generates the project once per wave
  and runs B/T serially, routing failures back to the owning agent. One writer per derived-data
  directory.
- **Paths:** `Sources/…` and `Tests/…` below are relative to
  `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`; `Sources/…` means
  `Sources/QuickStatsPanel/…` and `Tests/…` means `Tests/QuickStatsPanelTests/…`. New filenames are
  proposed; an agent may rename a new file but records the final name in its report.
- **Why this shape:** Wave 1 holds three tasks with no shared file and no mutual prerequisite
  (two additive pure-model kits and the card fix), so they can run in parallel. Waves 2–4 are
  single-task and serial: each rewrites the same ring model/controller/view surface and consumes
  the previous wave's result. Wave 5 is validation.

Dependency check: 1.1, 1.2, 1.3 → none. 2.1 → 1.1, 1.2, 1.3. 3.1 → 2.1. 4.1 → 3.1. 5.1 → 4.1.
E1 → 5.1. No cycle; every prerequisite is a task in this plan.

**Interfaces to establish before dispatch** (names proposed; shapes binding):

- 1.1 → 2.1/3.1/4.1: `RingSizePreset` (radii, separator, band gap and depths, footprints);
  `RingSector` (centre, inner and outer radius, centre angle, half span) with `contains`,
  `outline`, `boundingFrame`, a rectangle-containment check and sub-sector/half-sector
  constructors; `RingFillScale` with `radius(fraction:inner:outer:)`, cumulative radii for a stack
  and reference-arc radii; `RingLayout` (frozen favourites, More wedge, hub and per-wedge rung and
  text frame for one summon, plus `target(at:)`); `RingArcLayout` (one outer-band arc: span, entry
  sectors, label-or-sliver per entry, `entry(at:)`). All take measured text sizes as inputs and
  import nothing from views.
- 1.2 → 2.1/4.1: `RingGauge` (ordered fill components with fractions, optional left/right halves,
  rim brightness, peak, marks, badge, heat flag, availability, basis note); pure per-stat mapping
  functions from the existing sample structs; `RingRateScale`; `RingPeakWindow`; `RingPalette`;
  `RingPart` / `RingPartList` with grouping and the 32-part collapse; Debug part fixture sets.
- 3.1 → 4.1: a branch state in which any parent target (`.more` or a stat wedge) can own one
  outer arc, plus at most one detail card; `RingPlan` frames for the arc surface per owner and a
  `.outerBand` mode beside `.sideList` and `.wholeList`.

## Tasks

### Wave 1 (parallel — no dependencies, disjoint files)

- [x] **1.1 — Preset geometry kit (pure, additive)** — done 2026-11-14. Files as planned; API:
  `RingSizePreset` (in `RingSector.swift`), `RingSector`, `RingFillScale`, `RingLayout` (hit target
  `RingLayoutTarget`, since `RingTarget` exists), `RingArcLayout`. Angle convention as `RingGeometry`
  (radians clockwise from twelve, y down). 48 tests. Rung matrix and arc fit:
  [evidence](docs/evidence/gauge-ring-w1-rung-matrix.md). **Raised the plan's stop condition**:
  Medium + 8 favourites + More reaches only icon-only for Memory, Disk, Network, Fans, Power,
  Uptime. Also: a More arc with label + value entries fits only 1–2 entries (Small: 1).
  - Depends on / external gates: none.
  - Owns: new `Sources/Model/RingSector.swift`, `Sources/Model/RingLayout.swift`,
    `Sources/Model/RingArcLayout.swift`; new `Tests/RingSectorTests.swift`,
    `Tests/RingLayoutTests.swift`, `Tests/RingArcLayoutTests.swift`. Edits no existing file; the
    current `RingGeometry` keeps working until 2.1 retires it.
  - Build: the three presets from the spec table (inner radius 36 % of outer, 4-point separators,
    band 6 points out, 44-point sub-ring depth, 64-point More-arc depth). One annular-sector
    primitive used for wedges, partial fills, the Disk rim, halves and band segments. Fill radius
    for equal-area and linear scales with clamping and cumulative stacks; reference arcs at
    25/50/75 % with the 8-point rule. Favourite tiling: with a More wedge (24 degrees centred on
    six o'clock) favourites share the rest in equal sectors clockwise from More's trailing edge,
    favourite 1 being the first sector whose centre lies clockwise from twelve o'clock; without
    More, the full circle with the first centred on twelve; one favourite is a 60-degree wedge at
    twelve; no favourites leaves the More wedge alone. Hub: disc radius = inner radius − 6, gear
    target at least 28 × 28, "Settings" word only when the disc radius is at least 58. Content
    ladder: label + value + secondary → label + value → icon + value → icon only, richest rung
    that fits each wedge with 6-point padding, capped by an upper rung. Outer-band arc: span = sum
    of entries' angular needs, at least the parent's span, at most a full circle, centred on the
    parent mid-angle; wider gaps between groups; an entry is labelled only when its measured text
    fits, otherwise a sliver at least 8 points wide; report "cannot fit" instead of shrinking.
  - Interface: as listed above. Hit testing and drawing read the same sectors.
  - Success: AC-24 fill ratios hold to within 0.5 % for both scales, including 0, 1 and
    out-of-range; favourite and More sectors never overlap for 0–8 favourites with and without
    More; hub, separators and inactive annulus select nothing; every chosen rung's text frame is
    contained in its sector; a rung matrix (preset × favourite count × More present × stat, using
    each stat's widest strings) is produced by a test and attached to the task report; arc spans
    and sliver widths hold for 1–11 More entries and for 2, 10, 29 and 32 parts in each preset.
  - Backpressure: T-focus with the three new suites. No build of the app is required beyond the
    test bundle compiling.

- [x] **1.2 — Gauge content, palette and parts (pure, additive)** — done 2026-11-14. Files:
  `RingGauge.swift` (`RingGauge`, `RingGaugeMapper`, `RingRateScale`, `RingPeakWindow`),
  `RingPalette.swift`, `RingParts.swift`, `RingPartFixtures.swift` (`#if DEBUG`). 51 tests. Every
  `ThemePreset` passes 3:1 edge contrast (worst neon 3.12), so no explicit-edge fallback is needed;
  four mockup hues were lightened to achieve this, and Fans/Load hues were chosen (provisional,
  for E1). Over-32 backstop merges trailing single parts into "Other" (beyond the spec).
  - Depends on / external gates: none.
  - Owns: new `Sources/Model/RingGauge.swift`, `Sources/Model/RingParts.swift`; new
    `Tests/RingGaugeTests.swift`, `Tests/RingPartsTests.swift`. Edits no existing file.
  - Build: the `RingGauge` value type and one pure mapping per stat following the spec's table,
    using existing sample fields only: CPU user/system/nice (nice = total − user − system);
    Memory app/wired/compressed/other used against installed memory; Disk used ÷ total with a rim
    from read + write on the log scale; Network download left, upload right on the log scale with
    marks at 100 KB/s and 10 MB/s; Battery charge with the four power marks; GPU utilisation;
    Power CPU/GPU/Neural Engine/DRAM/rest of system against a ceiling parameter; Temperature
    hottest valid sensor on 30–100 °C with thermal state; Fans fastest fan within its range; Load
    selected average ÷ active cores, clamped; Uptime without fill. Absent hardware or an empty
    sample maps to unavailable, never to a zero fill. The log rate fraction
    `(log10(bytes per second) − 3) ÷ 6`, clamped. A 60-second rolling peak window with injected
    timestamps. A palette: one hue per stat, lighter steps for stacked components, a heat ramp
    whose lightness rises with heat, a single neutral fill for Mono, and a contrast function.
    Parts: a frozen part list per stat with group, name, value text and fraction(s); the rules for
    fewer than two parts, group order, never sorting by value, merging same-named sensors, dropping
    readings outside 0–110 °C, pairing hyperthreads then grouping above 32 cores, and collapsing
    the largest group to its hottest or highest member until 32 or fewer remain; aggregation
    helpers (mean, sum, hottest) that state how parts agree with the parent. Debug-only part
    fixture sets `typical`, `dense` and `minimal`, each returning parent values derived from its
    parts.
  - Interface: as listed above. Nothing here reads `StatsStore`; mappings take sample values.
  - Success: AC-25, AC-26, AC-27 and AC-28 hold at the content level; the rate scale is fixed at
    below 1 KB/s, 1 KB/s, 1 MB/s, 1 GB/s and above; fill edge against track is 3:1 or better for
    every shipped `ThemePreset` (or the failing presets are listed for 2.1 to draw an explicit
    edge); AC-34 holds for all three fixture sets; AC-35's collapse keeps the parent total
    unchanged and ends at 32 or fewer; a part missing from a later reading keeps its index and
    reports unavailable (AC-38).
  - Backpressure: T-focus with the two new suites.

- [x] **1.3 — Detail card keeps Close visible (C1)** — done 2026-11-14. Close sits outside the
  body `ScrollView` (`StatDetailView` `scrollsBody`); Ring measures with 10 process rows reserved
  (`descriptor(for:settings:reservingProcessRows:)`); Strip path unchanged. **Criterion amended:**
  Disk has no per-process data source in code, so it reserves no section (tested as nil in both
  modes); CPU and Memory reserve. Native check stays E1 row C1.
  - Depends on / external gates: none. Native confirmation is E1 row C1; it does not gate 2.1.
  - Owns: `Sources/Views/StatDetailView.swift`, `Sources/Model/StatDescriptor.swift` (process
    section reservation only), the ring detail functions in `Sources/AppDelegate.swift`
    (`ringDetailCard`, `showRingDetail` and the card measurement inside `toggleRing`),
    `Sources/Panel/DetailPanelController.swift` if needed; new
    `Tests/RingDetailMeasurementTests.swift`.
  - Build: in Ring only, the Close row sits outside the scrolling region and the card is measured
    with its process rows reserved whether or not process samples have arrived. Strip's card —
    content, size and behaviour — is unchanged (`onClose` nil path).
  - Interface: 2.1 and 4.1 keep calling the same card constructor and reserved-frame path.
  - Success: for CPU, Memory and Disk, the descriptor used for Ring measurement reports a process
    section with its reserved row count when the process list is empty, and Strip's descriptor is
    unchanged (hostless); the code path shows Close outside the `ScrollView`; B passes. The
    existing prototype still runs with `--ring-prototype`.
  - Backpressure: B; T-focus with `RingDetailMeasurementTests`, `PanelMetricOptionsTests`,
    `CPUBatteryPairTests` and `TransferDetailStateTests`.

### Wave 2 (serial — one coupled migration; consumes 1.1, 1.2, 1.3)

- [x] **2.1 — Gauge ring end to end: presets, gauges on real data, small hub, More wedge** —
  done 2026-11-14 (`ad22329`). New `Model/RingPrototypeOptions.swift` (pure argument parser),
  `Views/RingGaugeWedgeView.swift`, `Tests/RingPrototypeOptionsTests.swift`. `RingGeometry.swift`
  reduced to the `RingTarget` enum; `RingMoreGeometry`, `RingMoreRingView`, `.outerRing` and the
  100/260/520/820 constants removed. Rungs for `eight`/`long` agree with the 1.1 matrix (Small all
  icon-only; Medium Memory/Network icon-only; Large L/S); no unfit wedge. Hostless: layout,
  containment, More wedge at 180° for 0/1/6/8 favourites in each preset, fixtures, real-data gauge
  construction, options parsing. Code path only, for E1: drawing, motion/contrast variants,
  accessibility with VoiceOver, controller wiring. **Deviations for E1:** every card now sits in
  the fixed 380-point side column (More list above it), vertically centred on the ring, not beside
  the parent wedge (3.1 restores parent-relative placement with the band); base panel is the
  ring-only footprint (band footprint comes with 3.1); Small's More icon/count is contained but
  inside the 6-point padding; Battery mark glyph may touch tall text; peak ticks start empty at
  launch; the Temperature fixture gauge uses its own three-sensor sample while the card keeps
  none. Interaction suite passed unmodified apart from `.outerRing` → `.sideList`.
  - Depends on: 1.1, 1.2, 1.3. External gates: none.
  - **Replanned 2026-11-14 (D-037):** the fit stop is relaxed to "at least icon only". The 1.1
    rung matrix is the expected outcome, not a failure: at Medium/8 with More, Memory, Disk,
    Network, Fans, Power and Uptime draw icon only; Small with 7–8 favourites is icon only
    throughout. Consume the 1.1 API as built (`RingSizePreset` lives in `RingSector.swift`; the
    layout hit type is `RingLayoutTarget`, because `RingTarget` already exists) and the 1.2 API as
    built (`RingGaugeMapper`, `RingPalette`, `RingRateScale`, `RingPeakWindow`). An icon-only
    wedge draws its gauge at full strength with the stat icon centred in its text frame; its
    accessibility value and the card always carry the full reading, whatever the rung. The ladder
    choice stays inside `RingLayout`; views never re-measure or pick a rung themselves.
  - Owns: `Sources/Model/RingGeometry.swift` (retired or reduced to shared helpers),
    `RingPresentation.swift`, `RingPlacement.swift`, `RingHitResolver.swift`,
    `RingInteractionState.swift` (only where frames or targets change), `StatDescriptor.swift`
    (`ringReading`), `StatsStore.swift` (fixture seeding, Power peak window),
    `Sources/Panel/RingPanelController.swift`, `Sources/Views/RingView.swift`, `RingMoreView.swift`,
    `Views/AppKit/RingInputView.swift`, `StatDetailView.swift` (gauge-basis line, Ring only), the
    ring section of `AppDelegate.swift`; `Tests/RingGeometryTests.swift`,
    `RingPlacementTests.swift`, `RingHitResolverTests.swift`, `RingInteractionTests.swift` (More
    target only), new `Tests/RingPrototypeOptionsTests.swift`. May add a new drawing file under
    `Sources/Views/`.
  - Build: the summon snapshot takes a preset, an explicit favourites list, the upper rung and the
    fill scale, and freezes a `RingLayout`. `RingReading` carries a `RingGauge`; real-data readings
    build it from the live samples through the 1.2 mappings, fixtures supply their own. Wedges draw
    track, fill (stacked, split or heat), reference arcs, peak tick, Disk rim, marks and badges,
    then horizontal text or icon at the frozen rung, with a separate selection outline. The fill
    eases for at most 0.2 seconds and steps under Reduce Motion; the fill edge is an explicit line
    under Increase Contrast or Differentiate Without Colour. The hub shrinks to gear + drag with
    the pin glyph; empty-state messages move out of the hub. The More wedge replaces the hub's More
    control; in this task it opens the existing side More list above the card (the spec's declared
    fallback), because the outer band arrives in 3.1/4.1. Placement uses the preset footprint. The
    full 820-point outer ring (`RingMoreGeometry`, `RingMoreRingView`, `.outerRing` mode) and the
    static 520-point constants are removed once nothing references them. The Ring detail card
    names the gauge basis where it differs from the configured text reading. The launch arguments
    in the table above are parsed in one pure, tested place; `--ring-parts` is accepted but has no
    visible effect until 4.1.
  - Interface: `RingNode`, `RingExpansion` and `RingPlan` keep their current shape (minus
    `.outerRing`) so that 3.1 generalises one known form.
  - Success: with `--ring-prototype` alone the ring shows real gauges for every enabled stat in
    each preset; `--ring-fixture=` sets still work, including `none`, `one`, `unavailable`, `long`
    and `paired`; `--ring-favourites=0`, `1`, `6` and `8` with eleven enabled stats place the More
    wedge at six o'clock with the right count and reach every remaining stat; hover, hold, Escape,
    drag, pin, click-away and first click behave as accepted in the earlier review; no ring
    argument or drag writes a persistent setting; accessibility elements exist for each wedge
    (name, value, availability, expanded), the More wedge (count) and the gear, with Press equal
    to click. Report the rung actually chosen per preset for the `eight` and `long` fixtures and
    confirm it agrees with the 1.1 matrix; icon-only wedges draw icon and gauge with nothing
    clipped.
  - Stop condition: the relaxed fit rule in "Goal and bounded scope" (a wedge that cannot fit even
    icon only), or any other stop listed there.
  - Backpressure: B; T-ring. Surviving interaction suites (hover, dwell, hold, leave, transit,
    Escape, stale token, drag, accessibility) pass unmodified apart from where the More target
    moved; replaced hub-target, fixed-radius and outer-ring tests are listed with their
    replacements. `git diff --check`. Then a fresh-build handoff of the B artifact under the
    standing authorization, so the owner can look early; no reply is needed to continue.

### Wave 3 (serial — pure branch model; consumes 2.1)

- [ ] **3.1 — Generalise branch state and placement to an outer band owned by any wedge**
  - Depends on: 2.1. External gates: none.
  - Owns: `Sources/Model/RingInteractionState.swift`, `RingPlacement.swift`,
    `RingHitResolver.swift`, `RingPresentation.swift` (snapshot parts and state mirroring only);
    `Tests/RingInteractionTests.swift`, `RingPlacementTests.swift`, `RingHitResolverTests.swift`.
    Views and the panel controller are not edited here; thin compatibility accessors keep them
    compiling until 4.1 migrates and removes them.
  - Build: the expansion becomes "at most one outer arc, owned by More or by a stat wedge, plus at
    most one detail card", replacing the single hub-owned More slot and the `viaMore` flag. A stat
    wedge with two or more parts opens its arc and card together as one branch: dwell previews
    both, click holds both, Close or Escape closes both, mouse-down in the arc promotes a preview
    to held. A stat in the More arc opens a card only and keeps the More arc; a held child holds
    the arc. Segments are caption-only hits: no dwell target and no further level. The inside
    region for the leave delay is the union of parent wedge, arc, the gap between them, the card
    and the travel region; timings, arming, closed-parent suppression, tokens and generations are
    unchanged. Placement adds `.outerBand`: reserve the preset footprint with band plus the
    largest card before placing the base; arcs are laid out once per summon from the 1.1 layout
    and never move a favourite or the hub; if the band cannot fit, sub-rings are omitted and More
    uses the side list; if the ring plus a 380-point side area cannot fit, the whole-list fallback
    is used.
  - Interface: as listed under "Interfaces to establish before dispatch"; commands gain show/hide
    for an arc with its owner.
  - Success: the spec's interaction table holds row by row for both kinds of arc owner, including
    AC-20, AC-21 (one Escape closes a favourite's arc and card together; card → More → HUD for
    More), AC-32, AC-33 and AC-36; stale callbacks cannot reopen anything after hide, drag,
    Settings, display change or a newer selection; placement covers all four edges and corners,
    negative display origins, 1024 × 640 and 1440 × 900 visible points, 1× and 2×, each preset,
    plus a frame large enough to prove the `.outerBand` path. B still passes through the
    compatibility accessors.
  - Backpressure: T-ring; B. Deterministic tests at, below and above each timing boundary. An
    independent read-only review of the state-machine diff; findings fixed and affected suites
    rerun.

### Wave 4 (serial — native arcs; consumes 3.1)

- [ ] **4.1 — Native sub-ring and More arcs, captions and segment accessibility**
  - Depends on: 3.1. External gates: none.
  - Owns: `Sources/Panel/RingPanelController.swift`, `Sources/Views/RingView.swift`,
    `RingMoreView.swift`, `Views/AppKit/RingInputView.swift`, the ring section of
    `AppDelegate.swift`, `Sources/Model/StatsStore.swift` (fixture seeding from part sets),
    `RingPresentation.swift` (fixtures), plus removal of the 3.1 compatibility accessors in the
    model files; targeted fixes to the ring test suites.
  - D-037 carry-over: More-arc entries use the same content ladder including icon only, which
    the 1.1 arc fit shows is the usual case; an arc that cannot fit icon-only entries uses the side
    list chosen at summon.
  - Build: one non-activating arc panel sized to the arc's frame, following the existing window
    model (no large transparent window, no click interception in travel regions). The More arc
    draws each non-favourite as a full gauge wedge with text; sub-ring arcs draw each part as a
    gauge segment on the parent's scale and colour basis, grouped with wider gaps, labelled only
    where the text fits. Hovering a segment shows a caption with its name and value inside space
    reserved at summon, so nothing resizes on hover. `--ring-parts=` selects the fixture set and
    the four parent readings come from it. The side More list remains as the fallback chosen at
    summon. Sub-ring segments are read-only accessibility children of the expanded wedge with name,
    value and range; a More-arc entry is pressable. The detail card sits beside the footprint with
    band and never over its parent target or the open arc.
  - Success: in fixture mode, CPU, Disk, Network and Temperature each open an arc centred outside
    their wedge together with the card, in every preset where the band fits; `dense` shows 32
    cores and a collapsed sensor group with captions; `minimal` opens cards and no arcs for Disk,
    Network and Temperature; real-data mode opens cards and no arcs; with `--ring-favourites=6`
    and eleven enabled stats the More arc shows five gauge wedges and each opens its card while
    the arc stays; near a screen edge the fallback is chosen before input and the parent target
    does not move. No compatibility accessor remains.
  - Backpressure: B; T-ring; `git diff --check`. An independent read-only review of the controller
    diff for stale callbacks, panel teardown on hide/drag/Settings/display change and Release
    guards; findings fixed and affected checks rerun.

### Wave 5 (verification)

- [ ] **5.1 — Integration evidence, fresh artifact and the owner checklist**
  - Depends on: 4.1. External gates: none for build and headless evidence; native claims wait for
    E1.
  - Owns: new `docs/evidence/gauge-ring-prototype.md`; targeted test fixes. The coordinator runs
    the builds serially while one fresh read-only reviewer inspects Strip routing, Carbon hotkey
    registration and teardown, sample lifetime, fixture isolation and Release guards.
  - Success: R shows no `--ring-` literal and no ring controller, view or fixture symbol in the
    Release executable (pure model types may still be linked; record which). T-all passes, and its
    executed count is reconciled against the 212 baseline: tests added, tests removed with their
    replacements, any skip explained. B produces the final artifact after the last fix; record its
    path, version, executable hash and signature check. The evidence document holds the rung
    matrix, the fixture and argument matrix, what was and was not covered by automation, and one
    finite E1 checklist with case IDs, exact launch line, action, expected result and completion
    condition. Then the fresh-build handoff under the standing authorization.
  - Backpressure: R, T-all, B, `git diff --check`. No app-hosted tests, no automated clicks or
    keys, no screenshots of the desktop without their own authorization.

## Validation commands

Inspected at planning: the scheme's test target is the hostless bundle (no `TEST_HOST`); it
compiles models and samplers directly, injects disposable defaults and never launches the app,
starts samplers, the updater or hotkeys. Effects class: headless. B and R are build-only. Run all
from `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`, serially, after
`xcodegen generate`. Redirect output to a log file instead of piping through a formatter, and read
the command's own exit status; a missing or stale result bundle is not a pass. Use a fresh
result-bundle name for every run and keep every bundle, including failed ones. All commands reuse
the existing `build/SparklePackages` checkout.

**B** (Debug build):

```bash
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/GaugePrototype -clonedSourcePackagesDirPath build/SparklePackages build
```

Runnable artifact:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/GaugePrototype/Build/Products/Debug/QuickStatsPanel.app`

**T-focus** (Wave 1; list only the suites the task names):

```bash
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/GaugePrototypeTests -clonedSourcePackagesDirPath build/SparklePackages -resultBundlePath build/GaugePrototypeTests-<task>-run01.xcresult -only-testing:QuickStatsPanelTests/<Suite> test
```

**T-ring** (Waves 2–4): T-focus with every ring suite that exists at that point (`RingSectorTests`,
`RingLayoutTests`, `RingArcLayoutTests`, `RingGaugeTests`, `RingPartsTests`,
`RingDetailMeasurementTests`, `RingPrototypeOptionsTests`, `RingGeometryTests`,
`RingInteractionTests`, `RingPlacementTests`, `RingHitResolverTests`,
`RingFixtureTransferHistoryTests`) plus `PanelMetricOptionsTests`, `CPUBatteryPairTests` and
`TransferDetailStateTests`. A suite that no longer exists is named in the task report with its
replacement; an absent suite is not a passing test.

**T-all** (5.1): the same command without `-only-testing`, result bundle
`build/GaugePrototypeAllTests-run01.xcresult`.

**R** (5.1; build-only Release exclusion check, separate derived data):

```bash
xcodebuild -scheme QuickStatsPanel -configuration Release -destination 'platform=macOS' -derivedDataPath build/GaugePrototypeReleaseCheck -clonedSourcePackagesDirPath build/SparklePackages build
strings build/GaugePrototypeReleaseCheck/Build/Products/Release/QuickStatsPanel.app/Contents/MacOS/QuickStatsPanel | grep -c -- '--ring-'
```

Expected count is 0 (`grep` then exits 1, which is the pass). Run the same `grep` on the Debug
`.debug.dylib` as a control; it must be greater than 0.

## External checks

- [ ] **E1 — Owner reviews the gauge ring natively**
  - Depends on: 5.1 (fresh artifact, evidence document and checklist).
  - Requires: owner hands-on review; a second display if available. Missing hardware is recorded
    as not run, never as passed.
  - Owns: owner results in `docs/evidence/gauge-ring-prototype.md`; the coordinator records
    decisions and bounded corrections.
  - Gates: prototype acceptance; the Proposed and Open rows listed above; the per-part sampling
    plan; and all production layout and appearance work (persisted Ring settings, Grid, Rail,
    colour modes, Settings controls). It gates no task inside this plan.
  - Verify, as one finite batch written in 5.1:
    - Repeated from the earlier review because not run or superseded: text comfort on `one`, `six`
      and `eight` (R1) and on `long` and `paired` (R2); `unavailable` slots and card (R3); `none`
      (R4); Strip position unchanged after a ring drag (D1); real-data cards with Close visible
      (C1) and a card control on a previewed card (C2); the old inner-shape artifact is gone (C3);
      second display, drag across displays, display removal (P2); outer band on a display that
      fits it (P3); VoiceOver navigation and Press (A1); settings placement read-through (S1).
      Geometry-dependent rows are run in each preset.
    - New gauge rows: fill legibility at a glance in both fill scales; fill basis differing from
      the text reading (for example Disk showing Free); mixed rungs in one ring; hub size and
      gear reach; More wedge reach at six o'clock; outward travel into a sub-ring and sideways
      into its card; segment captions on `dense`; Fans, Load and Uptime wedges; Power at 30 W and
      at one other ceiling; Reduce Motion and Increase Contrast.
    - Interaction rows already passed (H1–H6, M1, E1a, D2, P1) get one confirming pass on the new
      structure, since the More target and the arcs changed their geometry.
  - Success: the owner records accept or requested corrections per row and a decision or "stays
    open" for each Open Questions row in the table above. Relevant failures are fixed and the
    affected checks rerun. A clean build is not acceptance.
  - While unavailable: bounded prototype corrections and documentation only. The 1.2.1 Strongbox,
    updater and upgrade gates are separate and unchanged.

## After E1 — deferred follow-up, not executable tasks

- Per-part sampling plan: per-core CPU with core class from `cluster-type`, volume enumeration by
  container off the main thread, per-interface deltas with display names, un-averaged sensors;
  each behind hostless tests, sampling only while the panel is visible. Carries AC-37 and AC-34 on
  real data.
- Production plan: persisted layout, favourites, size, wedge text and fill scale; Grid and Rail;
  the shared colour mode and its mapping onto gauge fills; status-band inputs for Network and
  Power; Settings controls; the D-006/D-008 decision; whether pure ring model types are guarded
  out of Release.

## Operational learnings

Carried from the ring prototype plan; add new ones during execution.

- `log stream` needs `--level info` for the hover-mechanism line, and agent shells must call
  `/usr/bin/log` because zsh's `log` builtin shadows it.
- Hit resolution lives in the pure resolver: clicks inside the ring's outer radius that hit no
  target are inert, only beyond it is outside.
- Keep every result bundle, including failed runs.
- The `twelve` fixture enables all eleven stat kinds.
- Agent worktrees are created from `origin/main`, not local `HEAD`: push (or tell agents to read the
  plan/spec from the main checkout) before dispatch. Worktree builds need `Config/Debug.local.xcconfig`
  copied and an APFS clone (`cp -cR`) of `build/SparklePackages`.
- The Bash tool runs zsh: build `-only-testing` lists as an array (`O+=(...)`, `"${O[@]}"`); a
  space-joined string is passed as one argument and xcodebuild rejects it.

## Blocked tasks

None. *Resolved 2026-11-14:* 2.1 had stopped on the Medium/eight-favourite fit rule (1.1
[matrix](docs/evidence/gauge-ring-w1-rung-matrix.md): six stats icon-only). The owner chose option
(a) — accept icon-only and rely on the card ([D-037](docs/decisions.md)); options (b) Large default
or six-favourite cap, (c) narrower value font and (d) stacked icon/value were declined. 2.1 replanned
in place.

## Execution log

| Wave / IDs | Assignment or serial reason | Validation / evidence | Commit / exception | Remaining gates / next action or stop reason |
|---|---|---|---|---|
| W1 / 1.1, 1.2, 1.3 | Parallel, three fresh developer agents (Sonnet), each in its own git worktree with its own generated project and derived data (adaptation: lets agents compile; coordinator re-validated on `main`) | Agents: 1.1 139/139 (incl. existing ring suites), 1.2 51/51, 1.3 B ok + 20/20. Integrated on `main`: B `build/GaugePrototype-W1-B-run01.log` exit 0; T-focus 14 suites `build/GaugePrototypeTests-W1-run02.xcresult` 211 tests, 0 failures (run01 was a shell argument error, no tests ran); `git diff --check` clean | `87dfaf7` (1.1), `f171627` (1.2), `baaa4e7` (1.3), `5d5a70f` (records); plan precondition `6558f59`; not pushed | Stop condition raised by 1.1 → 2.1 blocked on owner decision (Blocked tasks) |
| W2 / 2.1 (replanned under D-037) | Serial (single coupled migration): one fresh developer agent in the main checkout, own derived data `build/GaugePrototype-2.1-agent*`; coordinator re-validated (adaptation: no worktree since nothing ran in parallel) | Agent: B exit 0, T-ring 229/229 (`build/GaugePrototypeTests-2.1-agent-run02.xcresult`; run01 had 2 own-test failures, fixed), compile-only Release `--ring-` count 0. Coordinator on `main`: B `build/GaugePrototype-W2-B-run01.log` exit 0; T-ring 15 suites `build/GaugePrototypeTests-W2-run01.xcresult` **229 tests, 0 failures** (+18 vs 211; replacements listed in 2.1); `git diff --check` clean | `ad22329` (2.1); replan/D-037 `64c9436`; not pushed | Fresh-build handoff done: old prototype PID 92303 quit normally, `GaugePrototype` Debug launched with `--ring-prototype` as PID 56912, path and SHA-256 `18544d9a…` verified. Wave 3 (3.1) ready, needs a new request |

Planning performed no source change, build, test run, app launch or product acceptance.

---
*Keep active while required work or acceptance is incomplete. On completion, archive with its
evidence and update incoming links before retiring the active copy.*
