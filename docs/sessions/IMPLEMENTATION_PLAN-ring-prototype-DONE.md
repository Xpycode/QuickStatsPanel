# Native Ring Prototype — Implementation Plan

**Created:** 2026-11-12 · **Status:** Complete 2026-11-13 — E1 closed by owner: interaction accepted, visual structure redirected (D-035)
**Progress:** 3/3 implementation tasks complete (1.1 owner-verified, 1.2 B/T + independent review, 1.3 R/T-all/B + inspection); **E1 closed** (interaction accepted, redirect to gauge design) — results in [ring-prototype evidence](../evidence/ring-prototype.md#e1-owner-review-checklist).
Unchecked tasks are pending unless explicitly marked implemented-unverified or blocked. This file
owns task status and evidence; `docs/TASKS.md` links here without duplicating completion boxes.
Execute with `/Users/sim/ProgrammingProjects/0-DIRECTIONS/__DIRECTIONS/commands/execute.md`.

## Goal and bounded scope

Build a small native, non-activating wedge ring to decide whether text, interaction and expansion
are comfortable before implementing the remaining layouts and appearance controls.

Source → action → destination → outcome: existing ordered enabled stat identities and readings
(or deterministic stress fixtures) → summon, hover/click a wedge or More, enter a detail, Escape →
native ring and existing detail content → readable values and stable, predictable navigation.

The agreed limit is one prototype presentation: favourite wedges, one More ring/list, one rich
detail surface, and finite screen-fit fallbacks. Use a Debug-only launch argument
`--ring-prototype`, with named fixture arguments for review. No persisted layout/favourite settings,
Grid/Rail, colour modes, preference controls, new samplers, new permissions, release work or
publication. Ordinary launch continues to show Strip. Reuse existing data and detail views; do not
build a parallel monitoring engine. Do not alter the prepared 1.2.1 app/DMG/feed.

Terminology: **owner** always means the human reviewer. The wedge or More control that a child
surface belongs to is its **parent target**; the spec's "owner click" means a parent-target click.

Stop and replan if comfortable text requires shrinking/rotating it, the parent target moves on
expansion, the pointer route cannot survive native input, or success requires recursive rings/new
permissions.
Use the spec's list/card fallback first. Capture failed cases and reconsider geometry; do not
silently proceed to the broader feature. This plan ends at E1; later work needs a follow-up plan.

## Requirements and evidence consulted

- [Layout/appearance spec](../../specs/panel-layouts-and-appearance.md), especially ring AC-04/05/06,
  AC-08–13 and AC-20–23; the complete feature's other criteria remain deferred.
- [D-034](../decisions.md): wedge direction accepted; exact geometry/timing still provisional.
- [Review sheets](02_Design/ring-review/): visual references, not native acceptance evidence.
- Existing `StatsStripView` consumes availability-filtered `visibleStats`; Ring needs ordered
  enabled identities independently of transient readings. Preserve Strip's existing projection.
- `PanelWindowController` sizes once per summon and accepts first mouse; its placement is strip
  oriented. `DetailPanelController` currently clamps below/above Strip and can overlap an owner.
- `AppDelegate` owns the single store, detail lifecycle, visibility-scoped Carbon Escape and
  whole-HUD dismissal. Ring needs a scoped Escape hierarchy and unified descendant teardown.
- Existing `QuickStatsPanelTests` is hostless, compiling model dependencies directly. App startup
  starts sampling/updater/hotkeys and shows the HUD: never treat app launch as a headless test.
- Plan review, 2026-11-12 (code-verified): `AppDelegate` builds `StatsStore()` with the real
  transfer-history root and `onPanelMoved` persists every drag as `customPosition`;
  `StatDetailView` resolves its stat through availability-filtered `visibleStats`, so an
  unavailable stat yields an empty card; Escape/Command-Comma/pin hotkeys, `store.setPanelVisible`
  (top-process sampler gate), pin reset and detail teardown all hang on the Strip controller's
  `onVisibilityChanged`, and click-away checks that controller's `isVisible`. `Views/` is outside
  the hostless bundle. The amendments below marked **(review)** address these.

## Prototype isolation and window model (review)

- **Isolation:** on the `--ring-prototype` path a ring drag never writes `customPosition` or any
  other persistent setting. In fixture mode the store is built with a disposable
  `transferHistoryRoot` (the initializer already accepts one), samplers and retained transfer
  history are not started, and readings come from fixture seeding. Real-data mode uses the
  ordinary store and its normal lifecycle, still without ring-specific persistence.
- **Window model (planned default, proven in 1.1):** separate non-activating panels sized to
  visible content — base ring, More ring/list, and the existing detail panel — never one large
  transparent window. Pointer position between panels comes from one visibility-scoped,
  permission-free mouse-moved observation (global plus local monitor, or a bounded
  `NSEvent.mouseLocation` poll) evaluated against the frozen geometry; it is removed on hide and
  intercepts nothing. If neither delivers reliable hover while another app is frontmost, stop and
  replan before Wave 2 rather than building interaction state on it.
- **Visibility parity:** whichever controller shows the HUD drives the same visibility effects as
  Strip: scoped Escape/Command-Comma/pin hotkeys, `store.setPanelVisible`, click-away, pin reset,
  hint/detail teardown and transfer-detail dismissal. The summon hotkey toggles the active
  presentation only.

## Acceptance criteria for this prototype

- Horizontal labels and paired/long readings fit actual wedge interiors with comfortable padding;
  use 13/16/12-point baseline text, no clipping, overlap, rotation or shrink-to-fit. Measure
  against each stat's worst-case `widestValue`/`widestSecondaryValue`, not the current reading.
  Native owner review decides comfort, beyond automated containment checks.
- 0/1/6/8 favourites, no enabled stats and up to twelve enabled stats remain reachable; unavailable
  entries retain identity and position. Wedges, gaps and hub use the same draw/hit geometry.
- Hover previews; click holds immediately; held detail resists hover replacement. Detail interaction
  promotes preview to held before controls act. More and its child remain reachable together.
- Escape closes detail → More → HUD; parent-target click/Close/Escape cannot immediately reopen a target
  under a stationary pointer. Hide, drag, Settings and display removal cancel stale callbacks.
- Pointer travel into More/detail does not accidentally select crossed wedges or collapse the
  branch; bounded travel grace never becomes an invisible clickable overlay.
- Full branch geometry is selected before input; the parent target stays fixed across expansion and sample
  updates. Visible-frame edge/corner cases select outer ring, side list/detail or whole-list
  fallback without clipping. Saved presentation is not changed by a fallback.
- Non-activating first click, existing pin/drag/hotkey/click-away meanings, accessibility Press
  and Strip behavior survive. No duplicate sampling/history lifecycle or live preference migration.

## Execution schedule and ownership

Three serial waves, one task each: geometry, tracking and native panel integration share the same
small presentation/controller surface. Parallel ownership would create overlapping edits; no
independent implementation task is needed. Use the execution procedure's runtime delegation rules.
No source execution is authorized by this planning request.

Coordinator owns `AppDelegate.swift`, `project.yml`, generated Xcode project, build/test output,
tracking documents and evidence. Serialize project generation and builds. Paths below under
`Sources` and `Tests` are relative to `01_Project`; new filenames are proposed locations.

Accepted interfaces: a summon snapshot of ordered stat IDs plus availability/readings; immutable
geometry (wedge paths, target IDs, child frames, fallback mode and travel region); explicit state
inputs with injectable clock and generation tokens; commands to show/hide More/detail and HUD.
Do not resolve geometry again on sample ticks. Existing detail content still receives the same store.

### Wave 1 — thin native end-to-end result

- [x] **1.1 — Summon a readable native ring and open one real detail** — *owner-verified
  2026-11-13: hover with another app frontmost, wedge → detail (process lists filled), Escape/
  click-away and hub drag all pass. Fixture-mode Disk/Network cards stuck on "Loading…" carried
  to 1.2 (see execution log). Hover mechanism not captured (log not persisted).*
  - Depends on: none. External gates: none; execute request starts this task. Precondition
    (review): commit and push the plan, spec, `02_Design/ring-review/` and pending doc edits
    first, with the user's confirmation, so wave diffs are clean and visible to the other Mac.
  - Owns: new `Sources/QuickStatsPanel/Model/RingGeometry.swift`, `RingPresentation.swift`,
    `Sources/QuickStatsPanel/Views/RingView.swift`, `Views/AppKit/RingInputView.swift`,
    `Sources/QuickStatsPanel/Panel/RingPanelController.swift`; focused `RingGeometryTests.swift`.
    Coordinator wiring: `AppDelegate.swift`, `Model/StatDescriptor.swift`, `Model/StatsStore.swift`
    (fixture seeding and the ordered enabled-identity projection), `Views/StatDetailView.swift`
    (resolve a stat by enabled identity and show an explicit unavailable state instead of an
    empty card; Strip behaviour unchanged), `Panel/DetailPanelController.swift`, `project.yml`
    and generated project as needed.
  - Placement: wedges replace Strip only in the Debug prototype path; centre has separate drag,
    More and Settings targets as specified. Use AppKit input/accessibility and native wrapped
    controls, SwiftUI drawing/text as useful; no new Settings pane or raw SwiftUI controls.
  - Interface: frozen summon snapshot and measured geometry shared by rendering and hit testing;
    reserved detail frame API supplements, rather than replaces, Strip positioning.
  - Success: running prototype can summon six/eight wedges, click a stat and display existing
    `StatDetailView` with correct data; baseline text bounds fit sectors. First mouse is delivered.
    Production launch path stays Strip. Add deterministic long/paired/unavailable fixtures without
    writing production defaults or transfer history; real-data mode reuses the existing store.
  - Success (review): isolation, window model and visibility parity hold as specified above —
    process lists appear in CPU/Memory/Disk details (proving `setPanelVisible`), Escape and
    click-away work in Ring, and a hub drag leaves `customPosition` untouched. Each wedge, More
    and Settings exposes an accessibility element with Press, name, value and availability.
    A minimal hover highlight tracks the wedge under the pointer while another app is frontmost,
    and pointer position remains known in the gap between ring and detail panels; record which
    tracking mechanism worked. Failure here is the stop condition, not a Wave 2 problem.
  - Backpressure: build B below; hostless `RingGeometryTests` via T below for wedge boundaries,
    holes/gaps, measured text bounds and identity stability. Native observations remain E1.

### Wave 2 — complete the bounded interaction and edge experiment

- [x] **1.2 — Make hover, held branches and edge travel predictable** — *complete 2026-11-13:
  B pass, T 110/110, independent review fixed; native feel/size/scroll observations go to 1.3/E1.
  See execution log.*
  - Depends on: 1.1 geometry/snapshot and reserved detail-frame interface. External gates: none.
  - Owns: the same ring files exclusively after 1.1, new `Model/RingInteractionState.swift`,
    `RingInteractionTests.swift`, `RingPlacementTests.swift`; coordinator serializes changes to
    `AppDelegate.swift`, `DetailPanelController.swift`, `StatDetailView.swift` if needed for
    first-click promotion/Close, and project wiring.
  - Interface: collapsed/preview/held branch state independent of `isPinned`; inputs include
    movement, enter/leave, click, detail interaction, Escape, hide, drag and display changes.
    Clock and generation tokens make timers deterministic and cancellable.
  - Success: implement the spec table, starting at 350 ms dwell, 450 ms leave and maximum 700 ms
    transit grace with 12-point route tolerance. More supports every non-favourite, not only four.
    Suppress hover until movement after summon and after drag; suppress reopening of a closed
    parent target until exit/re-entry. Accessibility elements report expanded state and Press
    follows the click rows of the spec table. Explicit click wins; held child retains More. No input interception in
    empty travel regions. Escape is hierarchical only in Ring, including while pinned.
  - Success: before summon choose full outer-ring branch if it fits, otherwise side More list
    above detail, otherwise compact whole-list fallback. Independently scroll list/detail.
    Measure full configured detail content, not mockup rows. Exercise 0/1/6/8 favourites, twelve
    stats, empty/unavailable, long paired values and graph display modes. Sample updates cannot
    move slots or resize the visible branch. Settings/hide/drag/display loss close descendants.
  - Backpressure: B and T; deterministic tests at/below/above timing boundaries, stale generation
    callbacks, held precedence, Escape sequence, transit/sibling switching, all edges/corners,
    negative display origins, 1024 × 640 and 1440 × 900 visible points and 1×/2× conversion.
    Also include a sufficiently large synthetic frame proving the outer-ring path is exercised.
    Placement tests take injected detail sizes because `Views/` is outside the hostless bundle;
    measurement of real `StatDetailView` content is therefore native evidence for 1.3/E1, not T.

### Wave 3 — integration evidence and reviewable fresh artifact

- [x] **1.3 — Validate integration and prepare the native review** — *complete 2026-11-13: R 0
  occurrences, T-all 212/212, B no-op rebuild of the running artifact, inspection no defects;
  [evidence + E1 checklist](../evidence/ring-prototype.md). See execution log.*
  - Depends on: 1.1, 1.2. External gates: none for build/headless evidence; native claims await E1.
  - Owns: `docs/evidence/ring-prototype.md`, prototype fixture definitions and targeted test fixes;
    coordinator owns any integration fixes, project/build resources and task-state updates.
  - Success: B and T pass; inspect ordinary Strip routing, Carbon registration/teardown, detail
    history selection, sample lifetime and launch-argument exclusion from Release: the prototype
    path sits entirely inside `#if DEBUG`, confirmed by build-only R below and by finding no
    `--ring-prototype` string in the Release executable (no archive, notarization or change to
    the prepared 1.2.1 artifacts). Retain exact
    build path/version/hash, fixture invocation, tested cases, failures and untested device cases.
    Prepare a concise review checklist with screenshots where available; no speculative passes.
  - Backpressure: run the focused hostless suites plus existing `PanelMetricOptionsTests`,
    `CPUBatteryPairTests` and `TransferDetailStateTests` for changed integration dependencies;
    then, because shared `Model/` files changed, the full hostless suite once (T-all below),
    comparing the executed count with the 113-test baseline plus the new ring tests and
    explaining any difference, including hardware-probe skips; `git diff --check`. Build the actual runnable Debug artifact after final fixes, verify signature.
    Follow applicable app-handoff authorization and current keep-running/no-control limits;
    intermediate test runners are not a fresh-app handoff. Do not automate clicks/keys without
    their own authorization. Provide full absolute paths for user-operated steps.

## Validation commands (B/T run in 1.1–1.2; R and T-all run in 1.3)

Inspect target effects/setup before running. B is build-only; T uses the existing hostless bundle
with injected disposable defaults/data and no sampler startup, updater or hotkey registration.
Extend source inclusion only as needed for pure ring models; do not add an application test host.

**B**, from `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`:

```bash
xcodegen generate
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/RingPrototype -clonedSourcePackagesDirPath build/SparklePackages build
```

All commands reuse the existing `build/SparklePackages` checkout, as the 1.2.1 runs did, so new
derived-data paths do not fetch Sparkle again.

**R** (task 1.3 only; build-only Release exclusion check, separate derived data):

```bash
xcodebuild -scheme QuickStatsPanel -configuration Release -destination 'platform=macOS' -derivedDataPath build/RingPrototypeReleaseCheck -clonedSourcePackagesDirPath build/SparklePackages build
strings build/RingPrototypeReleaseCheck/Build/Products/Release/QuickStatsPanel.app/Contents/MacOS/QuickStatsPanel | grep -c -- '--ring-prototype'
```

Expected count is 0 (`grep` then exits 1, which is the pass). If Release signing is unavailable
on this Mac, record that and fall back to source inspection, stated as such.

**T-all** (task 1.3 only): the T command without any `-only-testing` arguments, with its own
`build/RingPrototypeAllTests.xcresult`.

**T**, from the same directory (add suites when introduced; absent suites are not passing tests):

```bash
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/RingPrototypeTests -clonedSourcePackagesDirPath build/SparklePackages -resultBundlePath build/RingPrototypeTests.xcresult -only-testing:QuickStatsPanelTests/RingGeometryTests -only-testing:QuickStatsPanelTests/RingInteractionTests -only-testing:QuickStatsPanelTests/RingPlacementTests -only-testing:QuickStatsPanelTests/PanelMetricOptionsTests -only-testing:QuickStatsPanelTests/CPUBatteryPairTests -only-testing:QuickStatsPanelTests/TransferDetailStateTests test
```

For subsequent runs choose fresh result-bundle names, preserving evidence. Verify executed test
counts, not just exit status. Expected runnable artifact:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/RingPrototype/Build/Products/Debug/QuickStatsPanel.app`.

## External review gate

- [x] **E1 — Owner reviews the working native prototype** — closed 2026-11-13: H1–H6, M1, E1a, D2, P1, R4 pass; C1 card Close clipped (carried); others not run or superseded by D-035. See [owner results](../evidence/ring-prototype.md#owner-results).
  - Depends on: 1.3 fresh artifact and retained validation evidence.
  - Requires: owner hands-on review; available displays for native scale/edge cases. Missing
    hardware remains explicitly untested. Simulated frames do not prove mixed-display input.
  - Owns: owner observations and exact artifact/fixture matrix in `docs/evidence/ring-prototype.md`;
    coordinator records decisions and any bounded corrections.
  - Gates: prototype acceptance and **all remaining layout/appearance implementation**. No Grid,
    Rail, persistent Ring preferences or appearance controls may start while E1 is open.
  - Verify: text comfort on 1/6/8 wedges and long/paired/unavailable cases; hover → detail travel;
    More → child travel across sibling wedges; preview → click hold; second parent-target click; repeated
    Escape; deliberate sibling click while held; rapid leave/re-entry; stationary dismissal;
    hub drag, pin, hotkey and click-away; native first click/focus; real detail controls and
    accessibility Press; edges/corners at target workspaces and available scale configurations.
    Include both fallback modes, not only favourable centred geometry, and a full outer-ring case
    where an available display fits it (about 820 visible points each way plus the detail). If
    none does, record the outer ring as natively untested; synthetic-frame tests do not replace it.
    Confirm real detail content matches the size reserved at summon for each reviewed stat.
  - Success: owner records accept or requested corrections for readability, interaction and
    expansion. Resolve relevant failures and rerun affected checks; explicit review is required,
    not inferred from a clean build. Review proposed future Settings placement at this gate too;
    unresolved placement separately blocks the corresponding later controls.
  - While waiting: finish relevant diagnostics/documentation or bounded prototype corrections;
    no broader feature work. Separate 1.2.1 acceptance/Strongbox/publication gates remain unchanged.

## After E1 — deferred follow-up, not executable tasks

Use accepted geometry/interaction findings to plan production Ring selection and persistence,
Grid/Rail, shared Off/Value colour/Subtle tint modes and their native Settings controls. Preserve
Strip default, existing theme migration, per-sample hysteresis and retained history. Record the
D-006/D-008 extension at production approval. The vertical-strip backlog maps to Rail; general
hover-to-expand remains separate because this spec requires hover only in Ring.

## Operational learnings

- Static mockups cannot establish native feel or text comfort.
- 1.1: ring panel is a 520 × 520 window; whether clicks on its transparent corners/gaps pass
  through to apps beneath (and so count as click-away) is a native question for the owner check.
- 1.2: hit resolution lives in pure `Model/RingHitResolver.swift`; clicks inside the ring's outer
  radius that hit no target are inert (gaps, hub band, inactive annulus), only beyond it is outside.
- 1.2: every Ring detail card is wrapped in a vertical `ScrollView` at its summon-reserved frame,
  because sizes are measured before transfer history/process rows populate. Native look is 1.3/E1.
- 1.2: transit grace delays a stopped-on-sibling dwell until grace end (≤ 700 ms) rather than 350 ms
  after stopping — deliberate provisional choice, commented in `RingInteractionState.evaluate`.
- 1.2: the first T run's result bundle (run01, 7 test-authoring failures) was deleted by the agent
  before rerun, contrary to the keep-every-bundle rule; run02/run03/run04 retained.
- 1.3: `log stream` hides info-level messages unless given `--level info`; the 1.1 hover-mechanism
  instruction omitted it. Corrected command is in the evidence doc.
- 1.3: the `twelve` fixture enables all **eleven** `StatKind`s (the app has eleven); More then holds three.
- 1.3: Release still links the pure ring Model types (unguarded so hostless tests compile them);
  no entry point, view, controller, fixture or launch literal. Production plan decides on guarding.
- 1.1: slot 0 is centred on twelve o'clock (one constant to flip if the owner prefers sector 0
  starting at twelve). Ring text uses the spec's explicit 13/16/12 pt, not Theme font tokens.

## Blocked tasks

None. Plan complete. Next: plan the gauge ring prototype step per D-035 (open questions listed there).

## Execution log

| Wave / IDs | Assignment or serial reason | Validation / evidence | Commit / exception | Next / stop reason |
|---|---|---|---|---|
| Wave 1 / 1.1 | One fresh developer agent (single-task wave; serial by plan). Coordinator reviewed diff, ran `git diff --check`, verified artifact signature. Precondition met: plan/spec/review sheets already in 682dbb1 on origin. | B pass, no new warnings. T pass: 34/34 (`RingGeometryTests` 16, `PanelMetricOptionsTests` 7, `CPUBatteryPairTests` 6, `TransferDetailStateTests` 5), `01_Project/build/RingPrototypeTests-1.1-run01.xcresult`. Artifact `01_Project/build/RingPrototype/Build/Products/Debug/QuickStatsPanel.app`, 1.2.1 (1201), exec SHA-256 `cf0dc81a…a941c3`, team FDMSRXXN73, `codesign --verify --deep --strict` OK. Not launched (see next column). | Committed locally on `main` (see git log, "Ring prototype 1.1"); not pushed. | **Stop — user scope was Wave 1.** 1.1 stays unchecked until the owner's native check: launch with `--ring-prototype [--ring-fixture=none\|one\|six\|eight\|twelve\|long\|paired\|unavailable]`, observe via `log stream --predicate 'category == "RingPrototype"'` which hover mechanism (global/local/poll) fires. Then Wave 2 / 1.2. |
| Wave 1 / 1.1 owner look | Owner-operated launch (`--ring-fixture=eight`); screenshot reviewed by coordinator. No agent launch/control. | Owner: concept looks okay; size/visual refinement deferred to E1. Unreported: hover with another app frontmost (+ mechanism), wedge → detail/process lists, Escape/click-away incl. corners, hub drag vs `customPosition`. Possible inner-quadrilateral shading in amber wedges (TASKS Inbox). | Documentation only. | 1.1 stays unchecked; 1.2 blocked until those checks are reported. Slot-0 orientation still open. |
| Wave 1 / 1.1 owner checks (2026-11-13) | Owner-operated (`--ring-fixture=eight`, one instance); six screenshots reviewed by coordinator. No agent launch/control. | Owner: (1) hover with another app frontmost **pass** (Network wedge highlight shown); (2) wedge → detail **pass**: CPU/Memory cards show fixture data and process lists; (3) Escape/click-away **pass**; (4) hub drag **pass**. Findings: **Disk/Network transfer sections stay "Loading…"** — fixture store builds `TransferHistoryController` with `automaticallySchedules: false` and never starts it (`AppDelegate` skips `store.start()` in fixture mode), so the first load never runs; fixture-only, real-data path unaffected but unverified in Ring. CPU/Memory cards' empty lower area is the 10 reserved process rows (4 fixture rows) and the half-filled graph is 30 fixture samples vs. capacity — both identical to Strip, not Ring defects. Inner-quadrilateral shading visible natively in amber wedges (Temperature, Memory). Slot 0 (CPU) at twelve o'clock, no objection raised. Hover mechanism not captured (no persisted `RingPrototype` log). | Documentation only. | **1.1 ticked.** Carry to 1.2: start fixture transfer history on its temp root (or render an explicit empty state) so Disk/Network cards resolve; optionally confirm real-data Disk/Network cards with `--ring-prototype` alone. Wave 2 ready. |
| Wave 2 / 1.2 | One fresh developer agent (single-task wave; serial by plan), then the same agent for review fixes. Independent quality-reviewer agent (read-only) reviewed the diff: PASS_WITH_CONCERNS, no critical; findings 1–4 fixed (inert ring clicks dismissed HUD; drag replanned against summon display; whole-list replan shifted away from real panel; detail clipping → scroll on overflow), 5 commented, 6–7 accepted as low. Coordinator reran T and B, reviewed resolver/scroll fixes, `git diff --check` clean. | T (coordinator rerun before fixes) `build/RingPrototypeTests-1.2-run03.xcresult` 104/104; T after fixes `build/RingPrototypeTests-1.2-run04.xcresult` **110/110, 0 skipped** (RingGeometry 16, RingInteraction 48, RingPlacement 23, RingHitResolver 4, RingFixtureTransferHistory 1, PanelMetricOptions 7, CPUBatteryPair 6, TransferDetailState 5). B exit 0, no new warnings (`01_Project/build/RingPrototype-1.2-B.log`). Artifact `01_Project/build/RingPrototype/Build/Products/Debug/QuickStatsPanel.app`, 1.2.1 (1201), exec SHA-256 `21f04750…c7a828`, team FDMSRXXN73, `codesign --verify --deep --strict` OK. Handoff (standing Oct 27 authorization): old instance PID 36801 quit gracefully (Apple Event, exited ~2 s); fresh artifact launched with `--ring-prototype --ring-fixture=eight`, PID 19436 started 02:24:23 after the 02:23:08 build, executable path verified, sole instance. | `cf6da8f` "Ring prototype 1.2…" (local). | **1.2 ticked; selected scope (Wave 2) complete.** Next: `/execute` Wave 3 (1.3: R Release-exclusion check, T-all vs 113 baseline, evidence doc, review checklist). Native observations (hover/dwell feel, More ring/list, scroll, drag-to-other-display, accessibility) belong to 1.3/E1. |
| Wave 3 / 1.3 | Coordinator ran R, T-all and B serially (coordinator owns build/test output; one writer per derived-data dir) and wrote the evidence doc/checklist. In parallel, one fresh read-only quality-reviewer agent inspected Strip routing, Carbon hotkeys, detail resolution, sample lifetime, Release guards and stale callbacks: **no defects**, 3 minor concerns (fixture temp root not removed → TASKS Backlog; summon-time card measurement → native E1 C1; sleep flush to temp root, accepted). No source changes, so no test fixes were needed. | R: Release build exit 0 (`01_Project/build/RingPrototype-1.3-R.log`), `--ring-prototype` count **0** in the Release executable (controls: Debug dylib 1, planted line 1); no ring controller/view/fixture symbols, but pure Model types are present (noted). T-all `01_Project/build/RingPrototypeAllTests-1.3-run01.xcresult` **212 passed / 0 failed / 0 skipped** = 113 baseline + 7 (1.2.1: CPUBatteryPair 6, PanelMetricOptions +1) + 92 ring. Focused T reused from 1.2 run04 (no source change). B exit 0, no-op: exec SHA-256 `21f04750…c7a828` unchanged, `codesign --verify --deep --strict` OK, 1.2.1 (1201). `git diff --check` clean. Running PID 19436 already this exact artifact, so no quit or relaunch was needed. Hover-mechanism log read (`log show`): no entries. | Documentation/evidence commit (see git log, "Ring prototype 1.3"); not pushed. | **1.3 ticked; plan implementation complete.** Next: **E1** owner review using the checklist in `docs/evidence/ring-prototype.md` (start the log stream with `--level info` first). |

Planning performed no execution, build, app launch or product acceptance. 1.1 interfaces:
`RingGeometry` (`target(at:)`, `outline(of:)`, `frame(of:)`, `textFits`), `RingSnapshot` (generation
UUID, enabled kinds, ≤8 favourites, `moreKinds`), `RingPresentationState` (hover/pointer), and
`DetailPanelController.reservedFrame(forSize:parentFrame:footprint:visible:gap:)` (pure, static).
1.1 gaps carried to 1.2: More click is a no-op; no dwell/held state; reserved-frame fallback may
clip when no side fits; an unavailable-at-summon stat is sized for its fallback text only.
