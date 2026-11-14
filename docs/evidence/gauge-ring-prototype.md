# Gauge Ring Prototype — Integration Evidence and Owner Checklist (5.1 / E1)

Plan: [IMPLEMENTATION_PLAN.md](../../IMPLEMENTATION_PLAN.md) · Spec: [panel layouts](../../specs/panel-layouts-and-appearance.md) ·
Decisions: D-035, D-036, D-037 · Earlier prototype: [ring-prototype.md](ring-prototype.md) · Rung matrix
source: [gauge-ring-w1-rung-matrix.md](gauge-ring-w1-rung-matrix.md).
Recorded 2026-11-14 on this Mac (MacBook Pro, arm64, macOS 27.2). Source `6b16a33` plus the 5.1 doc-comment
correction in `RingPanelController.swift` (ring behaviour last changed in `3a6338c`). **Nothing here is native acceptance; E1 owns that.**

## Review artifact

| Field | Value |
|---|---|
| Folder (Finder Go to Folder) | `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/GaugePrototype/Build/Products/Debug` |
| App | `QuickStatsPanel.app` (Debug), 1.2.1 (1201) |
| Executable SHA-256 | `250643856d0d50a1e7bb0a5f50952e121618f5f715b2ebd937e9c35325dc2731` (`.debug.dylib` `ec6591a170793d2b5115060e1346c39ea5b0aa8d52a8e8798336f6a8e95b84a9`) |
| Signing | team FDMSRXXN73; `codesign --verify --deep --strict` OK (2026-11-14 15:35) |
| Built | B run02, 2026-11-14 05:14 (log `build/GaugePrototype-W5-B-run02.log`), after the review's doc-comment fix. B run01 (05:00) had been a no-op identical to Wave 4 (`c138f26f…`) |
| Running | PID 92319, started 15:36:07. The Wave 4 PID 48142 quit normally first (~1 s, PID-specific quit request). Executable path and loaded `.debug.dylib` hash match. Launched with `--ring-prototype --ring-fixture=twelve --ring-favourites=6 --ring-parts=typical` |

This is a local, Git-ignored artifact; another Mac must rebuild it with B. The prepared 1.2.1 app,
DMG and feed were not touched.

### Launching a case (owner-operated)

Quit the running copy with its in-panel Quit first. Then run this in Terminal, adding the case's arguments:

```bash
/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/GaugePrototype/Build/Products/Debug/QuickStatsPanel.app/Contents/MacOS/QuickStatsPanel --ring-prototype <arguments>
```

Below, **`L(…)`** stands for that line with the listed arguments. For example, `L(--ring-fixture=eight
--ring-size=small)`. Summon with the usual hotkey. Optional hover log, started in a second window
**before** hovering: `/usr/bin/log stream --level info --predicate 'category == "RingPrototype"'`.

## Fixture and argument matrix

| Argument | Values (default first) | Effect |
|---|---|---|
| `--ring-prototype` | required | Without it, the app shows the Strip and none of the arguments below apply |
| `--ring-fixture=` | `none`, `one`, `six`, `eight`, `twelve`, `long`, `paired`, `unavailable` | Deterministic stats and disposable store. Unknown name → `six`. Omitted → real data on the ordinary store |
| `--ring-size=` | `medium`, `small`, `large` | Preset 360 / 260 / 460 points; text stays 13/16/12 points |
| `--ring-text=` | `label`, `icon-value`, `icon` | Highest wedge-text rung allowed |
| `--ring-fill=` | `area`, `linear` | Equal-area or linear fill |
| `--ring-favourites=` | `8`, `0`…`8` | First N enabled stats are wedges; the rest go to the More wedge |
| `--ring-parts=` | `typical`, `dense`, `minimal` | Per-part fixtures; **fixture mode only** (otherwise logged as ignored) |
| `--ring-power-ceiling=` | `30`, positive watts | Power gauge ceiling |

The first occurrence of an argument wins. An unknown value logs a warning and uses the default
(`RingPrototypeOptionsTests`).

| Fixture | Enabled stats (order = favourite order) |
|---|---|
| `none` | none |
| `one` | CPU |
| `six` | CPU, Memory, Disk, Network, GPU, Temperature |
| `eight` | CPU, Memory, Disk, Network, Battery, GPU, Power, Temperature |
| `twelve` | all **eleven** kinds: CPU, Memory, Disk, Network, Battery, GPU, Fans, Power, Temperature, Load, Uptime |
| `long` | as `eight`, every paired value at its worst-case string |
| `paired` | as `six`, two-line values |
| `unavailable` | as `eight`, with Battery, GPU and Power unseeded |

| Part set | CPU | Disk | Network | Temperature |
|---|---|---|---|---|
| `typical` | 10 cores, 2 classes | 4 volumes | 3 interfaces | 29 sensors |
| `dense` | 32 cores, 3 classes | 4 volumes | 3 interfaces | > 32 sensors (collapse rule) |
| `minimal` | 10 cores | 1 volume | 1 interface | no valid sensor |

In fixture mode, the CPU, Disk, Network and Temperature parent readings are derived from the
chosen part set. Fixture wedge text follows the app's real per-stat **Panel value** settings,
which are read only. In real-data mode no stat has parts, so every wedge opens a card and no arc.

## Rung matrix

The integrated T-all run (`build/GaugePrototypeAllTests-run01.log`, `RingLayoutTests.testRungMatrix`)
re-emitted the 102-row matrix (run02 identical). Ignoring trailing spaces, it is **identical** to the Wave 1 record in
[gauge-ring-w1-rung-matrix.md](gauge-ring-w1-rung-matrix.md), which holds the full table. In short:

- **Small:** 7 or 8 favourites are icon-only throughout. With 1 to 6 favourites, CPU, Battery,
  GPU and Load keep text, and Memory, Disk, Network and Fans are icon-only.
- **Medium:** text in most slots. With 8 favourites and a More wedge, Memory, Disk, Network, Fans,
  Power and Uptime are icon-only at worst case. D-037 accepts this; the full reading goes to the
  card and to accessibility.
- **Large:** label + value or richer everywhere, except Memory icon-only at 8 + More with paired
  worst-case strings.
- **More arc:** the arc cannot fit text for 3 or more entries at Medium or Large, or for 2 or more
  at Small. Then the entries use the content ladder (icon only), or the side list chosen at summon.

No wedge falls below icon-only in any preset or favourite count
(`RingGeometryTests.testEveryWedgeFitsAtLeastIconOnlyInEveryPresetAndFavouriteCount`).

## Automated and build evidence (5.1)

All commands were run from `01_Project` on 2026-11-14, serially, after `xcodegen generate` (exit 0,
log `build/GaugePrototype-W5-xcodegen.log`; generated project is untracked).

| Check | Command / result bundle | Result |
|---|---|---|
| **R** Release exclusion (build-only) | Plan R; derived data `build/GaugePrototypeReleaseCheck`, logs `build/GaugePrototype-W5-R-run01.log`, `…-run02.log` | Both BUILD SUCCEEDED, exit 0. Final run02 (after the fix): Release exec SHA-256 `19b3b8e8…` (build-only, not archived or notarized). `strings … \| grep -c -- '--ring-'` = **0** (grep exit 1 = pass). `RingPrototype`, `ring-fixture`, `RingFixture` = 0. Controls: Debug `.debug.dylib` = **4**; a planted line = 1 |
| R symbol check | `nm Release-exec \| swift demangle` | **No** `RingPanelController`, `RingView`, `RingMoreView`, `RingArcView`, `RingGaugeWedgeView`, `RingInputView`, `RingFixture`, `RingPartFixtures` or `RingPrototypeOptions` symbol. Pure model types linked in Release (unguarded, unreachable; listed under Integration inspection) |
| **T-all** full hostless suite | `build/GaugePrototypeAllTests-run01.xcresult` and `…-run02.xcresult` (after the fix), with logs | Both **390 passed, 0 failed, 0 skipped**, exit 0 (24 s, 41 s). Same per-suite counts. Hardware probes (`TransferReaderProbeTests` 4) ran and passed |
| **B** Debug build | derived data `build/GaugePrototype`, logs `build/GaugePrototype-W5-B-run01.log`, `…-run02.log` | Both BUILD SUCCEEDED, exit 0. run01 was a no-op; run02 is the final artifact above |
| `git diff --check` | repository | Clean |

T-all effects: a hostless bundle with no `TEST_HOST`. It compiles `Model`, `Sampling`, `Theme` and
`HotKeyService`, and injects disposable defaults and data. It does not launch the app or start
samplers, the updater or hotkeys. The probes are read-only `sysctl`/IOKit queries.

### Count reconciliation against the 212 baseline

Baseline: `build/RingPrototypeAllTests-1.3-run01.xcresult` (212; 92 ring tests). Now: 390 = 212 − 21 + 199.

| Suite | Baseline | Now | Δ |
|---|---|---|---|
| RingInteractionTests | 48 | 75 | +27 |
| RingPlacementTests | 23 | 34 | +11 (7 retired, 18 added) |
| RingGeometryTests | 16 | 26 | +10 (12 retired, 22 added) |
| RingHitResolverTests | 4 | 8 | +4 (2 retired, 6 added) |
| RingFixtureTransferHistoryTests | 1 | 1 | 0 |
| RingGaugeTests | — | 31 | +31 (1.2) |
| RingPartsTests | — | 20 | +20 (1.2) |
| RingLayoutTests | — | 18 | +18 (1.1) |
| RingSectorTests | — | 16 | +16 (1.1) |
| RingArcLayoutTests | — | 14 | +14 (1.1) |
| RingArcSurfaceTests | — | 13 | +13 (4.1) |
| RingPrototypeOptionsTests | — | 7 | +7 (2.1) |
| RingWedgeValueTests | — | 5 | +5 (3.2, 4.1) |
| RingDetailMeasurementTests | — | 2 | +2 (1.3) |
| 14 non-ring suites | 120 | 120 | 0 |
| **Total** | **212** | **390** | **+178** |

Ring tests: 92 → 270. No suite lost count, and no test was skipped. The 21 retired baseline tests
covered geometry that 2.1 deliberately removed: the 100/260/520 constants, the hub's More and
Settings targets, `RingMoreGeometry` and the 820-point outer More ring. Their replacements:

| Retired (baseline) | Replacement (now) |
|---|---|
| Geometry `testEqualSectorsClockwiseFromTwelveInOrder` | `…InOrderWithoutMore`; Layout `testFavouriteOneIsFirstClockwiseFromTwelveWithMore`, `testTilingMatchesRuleForEveryPresetAndCount` |
| Geometry `testFootprintAndRadiiMatchReviewBaseline` | Geometry `testPresetFootprintsAndRadiiComeFromThePreset`; Sector `testPresetTable` |
| Geometry `testGapBetweenWedgesAndOutsideSelectNothing` | Geometry `testGapsBetweenWedgesAndOutsideSelectNothing`; Layout `testHubSeparatorsAndInactiveAnnulusSelectNothing` |
| Geometry `testGeometryDoesNotDependOnLiveValuesOnlyWorstCase` | Geometry `testLayoutDoesNotDependOnLiveValuesOnlyWorstCase`; Layout `testLayoutIsFrozenAndDeterministic` |
| Geometry `testHoverIsSuppressed…TracksFrozenGeometry` | Geometry `testHoverIsSuppressed…TracksTheFrozenLayout` |
| Geometry `testHubTargetsAreDisjointTallEnoughAndInsideTheHub`; HitResolver `testHubSpecialsAreInertWithTheirSpecialSet` | Geometry `testHubOffersTheGearAndDragOnlyAndTheGearIsAtLeast28Square`; HitResolver `testHubOffersOnlyTheGearAndTheDragArea`; Layout `testHubGeometry` |
| Geometry `testMeasuredWorstCaseTextFitsSixAndEightWedges`, `testTextFitsWithTypicalAndWorstCaseHeadlinesWithoutFixtures`, `testTextFitDetectsAnOversizedBlock` | Geometry `testEveryWedgeFitsAtLeastIconOnly…`, `testRungsOfTheEightAndLongFixturesAgreeWithTheOneOneMatrix`, `testTheOtherFixturesFitInEveryPreset`; Layout `testRungMatrix`, `testUnfittableWedgeIsReportedNotShrunk`; Sector `testTextFrameFindsFittingPositionOrNil` |
| Geometry `testMoreThanEightEnabledKeepsEightFavouritesAndCountsTheRest` | Geometry `testMoreWedgeSitsAtSixOClockWithTheRightCountAndReachesEveryRemainingStat`; Layout `testOnlyFirstEightFavouritesAreUsed` |
| Geometry `testNoEnabledStatsKeepsSettingsAndExplains` | Geometry `testNoEnabledStatsKeepsTheGearAndExplains` |
| Geometry `testOutlineVerticesAndFramesAgreeWithHitTesting` | Geometry `testSectorOutlinesAndFramesAgreeWithHitTesting`; Sector `testBoundingFrameIsExactAndContainsOutline`, `testOutlineStepAndPath` |
| HitResolver `testMoreRingGapsAndTheBandBeforeItAreInsideTheOpenBranch`; Placement `testMoreRingHitsEntriesAndNeverTheGaps` | HitResolver `testMoreArcEntriesResolveToMoreItems`, `testOpenSubRingResolvesItsSegmentsAndTheGap…`; ArcLayout `testEntryHitTestingAndGaps`; ArcSurface suite |
| Placement `testLargeSyntheticFrameExercisesTheOuterRingPath`, `testOuterRingNeedsAboutEightHundredTwentyPointsPlusTheDetail`, `testOuterRingFallsBackWhenMoreTextCannotFitItsSectors` | Placement `testLargeFrameKeepsTheSideColumnAndNeverTheRemovedOuterRing`, `testOuterBandReservesTheBandFootprintAroundTheUnmovedRing`, `testBandThatCannotFitOmitsSubRingsAndUsesTheSideList`, `testMoreArcThatCannotFitKeepsTheListAboveTheCardBesideTheBand` |
| Placement `testMoreRingHoldsTwelveEntriesAndDetectsOversizedText` | ArcLayout `testMoreArcOneToElevenEntries` (+ compact and sliver variants), `testCannotFitIsReportedNotShrunk`; Placement `testMoreArcTakesTheRichestRungThatFitsAndIsAbsentWhenNoneFits` |
| Placement `testNothingInMoreUsesTheBaseAloneAndNeedsNoSurface` | Placement `testNothingInMoreHasNoListAndNoMoreNode`, `testNoStatsAndNoDetailsReserveNothingBesideTheRing` |
| Placement `testZeroOneSixEightFavouritesAndTwelveEnabledAllPlace` | Placement `testZeroOneSixEightFavouritesAndElevenEnabledPlaceInEveryPreset` |

## Integration inspection (read-only code review, fresh agent)

This was a fresh Opus reviewer with read-only access to five areas. It found no blockers.

| Area | Verdict | Evidence |
|---|---|---|
| Strip routing | PASS | The ring branch needs `RingPrototypeLaunch.current != nil`, which is set only when `--ring-prototype` is present. It is a `static let`, read once at launch. No scheme, `project.yml` or xcconfig carries a `ring-` argument. In Debug without the flag, the idle `RingPanelController` starts nothing, and `hideHUD`, `hudIsVisible` and `handleEscape` fall through to the Strip |
| Carbon hotkeys | PASS | One toggle hotkey (id 1), and the ring adds no `HotKeyService`. The scoped Escape, Command-Comma and pin hotkeys (ids 2–4) register and unregister through the one visibility closure both presentations share. `hide()` is guarded and emits once. The handler is installed once, and everything is unregistered in `applicationWillTerminate` |
| Sample lifetime | PASS | No sampler or history lifecycle is added. Fixture mode skips `store.start()`, the updater and interval restarts. Hide nils every panel, the reading provider, snapshot, plan and interaction. Dwell and grace items check generation and token; the global monitor checks generation. Local monitors, the poll and the screen observer are removed on hide. Drag disarms hover; the Settings and display-change paths hide through `apply`. Card Close is weak and guarded |
| Fixture isolation | PASS_WITH_CONCERNS | Fixture data is Debug-only and built only with `--ring-fixture`; transfer history uses a per-launch temp root; pin, first-run hint and Reset Position are skipped. **F1 (should-fix, confirmed):** fixture mode opens the real Settings on the fixture store, so any edit there saves to real defaults. In particular, unticking a fixture sensor or fan row under "Detail card rows" stores that fixture label in `hiddenDetailRows`. **Disposition:** behaviour kept, because E1 rows B9 and G4 need Settings in fixture mode. A fixture label matches no real row, so it is an orphan entry with no visible effect. The false "no production defaults written" doc comment in `RingPanelController.swift` was corrected. A volatile Settings store for fixture mode was captured in the TASKS Backlog. **F2 (note):** `recordRingPeak` runs in every Debug launch, including a plain Strip launch. It is bounded bookkeeping with no sampler, and Release is unaffected. This is a Debug-only difference from the Strip baseline |
| Release guards | PASS | Controller, `RingPrototypeLaunch`, `RingInputView` types, `RingView`, `RingGaugeWedgeView`, `RingMoreView`, `RingArcView`, `RingPrototypeOptions`, `RingPartFixtures`, the fixture section of `RingPresentation.swift` and the `StatsStore` fixture and peak code are all wholly inside `#if DEBUG`. Every `--ring-` literal is guarded. `project.yml` has no per-configuration exclusion |

**Ring types linked into Release.** They are compiled unguarded because the hostless bundle
compiles `Model/`. They are unreachable, since no entry point or launch literal leads to them. A
production plan decides whether to guard them.

- `RingGauge.swift`: gauge, components, marks, badge, halves, math, `RingRateScale`, `RingPeakWindow`, `RingGaugeMapper`
- `RingPalette.swift`
- `RingParts.swift`: parts, lists, aggregation, builders and inputs
- `RingSector.swift`: `RingSizePreset`, `RingSector`, `RingFillScale`
- `RingLayout.swift`
- `RingArcLayout.swift`
- `RingGeometry.swift`: `RingTarget`
- `RingArcSurface.swift`
- `RingPlacement.swift`
- `RingHitResolver.swift`
- `RingInteractionState.swift`: including `SystemRingClock` and `RingBranchState`
- `RingPresentation.swift` lines 1–442: `RingReading`, `RingTypography` (AppKit), `RingSnapshot`, and `RingPresentationState`, an `@Observable @MainActor` class
- `StatsStore` ring peak and ceiling accessors, which in Release return the default or nil
- `StatDescriptor` ring reading and wedge-value extensions
- The ring-only parameters of `StatDetailView`, and `DetailPanelController.show(kind:frame:content:)`, whose defaults keep Strip behaviour

`nm` on the Release executable agrees: only model types appear.

## What automation covers, and what it does not

**Covered by hostless tests (model level):**

| Area | Spec criteria | Suites |
|---|---|---|
| Gauge math: equal-area or linear fill, clamping, stacks, Disk rim, Network halves on a fixed log scale, unavailable stats | AC-24…28 | RingSector, RingGauge |
| Preset radii, rung choice, containment, frozen rung and slot, text 13/16/12 points | AC-29, AC-04 | RingLayout, RingGeometry, RingWedgeValue |
| Hub (gear and drag only, gear ≥ 28 × 28), More wedge at six o'clock with its count, every stat reachable with 0/1/6/8 favourites | AC-30, AC-31, AC-05/06/22 | RingLayout, RingGeometry, RingHitResolver, RingPlacement |
| Branch state: one arc and one card, a More stat opens a card only, Escape order, held precedence, stale timers, stationary reopen | AC-32/33, AC-09/10, AC-08/13/20/21/23 | RingInteraction |
| Sub-rings on fixtures: parts agree with the parent; ≥ 8-point segments; grouping; collapse above 32; fewer than two parts gives a card; frozen positions when a part disappears | AC-34 (fixtures), AC-35, AC-36, AC-38 | RingParts, RingArcLayout, RingPlacement |
| Arc surface including the 6-point gap, caption slot reserved at summon, travel route from the rendered arc | — (4.1) | RingArcSurface |
| Edge placement before input, fallback choice, parent target unmoved, 1024 × 640 and 1440 × 900 at 1× and 2× | AC-12, AC-23 | RingPlacement |
| Card measurement and the Close row outside scrolling | AC-39 (model) | RingDetailMeasurement |
| Accessibility text carries the full reading at every rung | AC-40 (model) | RingGeometry, RingWedgeValue |
| Launch-argument grammar | — | RingPrototypeOptions |

**Native only (E1):**

- How the gauges look and read: fill legibility, peak ticks, rim, marks, and Battery glyph against tall text.
- Drawing of arcs, segment labels and captions, and where captions sit.
- Arc panel order and shadow.
- Clicks in the gap, the separators, the caption slot and the base-disc gaps at the lowest Custom opacity.
- The large, mostly transparent arc panel on `dense`.
- Teardown on drag, Settings and display change.
- The ring-crossing travel change: no 700 ms grace from a sub-ring; a sibling previews after 350 ms.
- Real `StatDetailView` sizes and scrolling.
- Hover delivery and feel.
- VoiceOver, including segment children and More-arc Press.
- Reduce Motion, Increase Contrast and Differentiate Without Colour rendering.
- Second display and display removal.

Two items are not covered at all: AC-37, and AC-34 on real data. Both wait for the per-part
sampling plan. No screenshots were taken, and no app-hosted tests or simulated input were run.

## E1 owner review checklist

This is one finite batch. For each row, return **pass**, **fail (what you saw)** or **skipped (why)**.
Screenshots help with fails and with any doubt about text comfort. The batch is complete when every
row and every Open Questions row has an answer. Hardware you don't have is marked skipped, never
passed. "Each preset" means running the row three times, with `--ring-size=small`, `medium` and
`large`.

Rows that change macOS or app settings (A2, A3, B9, C4, C5, C6, C7, G2) say so. Note the
original value first and put it back afterwards. Settings opened from a fixture launch is the
**real** Settings, so every edit saves. In fixture mode, don't untick "Detail card rows": the
fixture's made-up sensor and fan names would be stored (review F1).

### A — Text, presets, gauges

| ID | Launch | Do | Expect |
|---|---|---|---|
| R1 | `L(--ring-fixture=one)`, `=six`, `=eight`; each preset | Summon; read every wedge | Text is horizontal, comfortable and never shrinks. Each wedge shows the richest content that fits, and the rungs match the matrix above. Icon-only wedges (for example Medium `eight`: Memory, Disk, Network) are acceptable under D-037 only if the card or VoiceOver gives the reading |
| R2 | `L(--ring-fixture=long)`, `=paired`; each preset | Summon; read every wedge | Worst-case and two-line values fit their wedges, with no clipping or overlap |
| R3 | `L(--ring-fixture=unavailable)` | Summon; look at Battery, GPU and Power; open Battery | These wedges keep their slots and show an empty track with an unavailable mark, never a zero fill. The card says "Battery unavailable" |
| R4 | `L(--ring-fixture=none)`; `L(--ring-fixture=twelve --ring-favourites=0)` | Summon; use the gear and drag | `none`: "No stats enabled", no More wedge, gear and drag work. `0`: only the More wedge, with the explanation in the ring |
| G1 | `L(--ring-fixture=twelve --ring-fill=area)`, then `--ring-fill=linear` | Summon; glance for 2 s and read the fill levels | Fill levels can be read at a glance in both scales. Record which scale you prefer |
| G2 | `L()` real data. Settings → Disk → Panel value: **Capacity**, then **Read/write activity** | Look at the Disk wedge and card | Text shows Free (or read/write), while the fill follows used capacity. The card names the basis where they differ. Judge whether the difference reads clearly |
| G3 | `L(--ring-fixture=eight)` Medium | Look at the ring as a whole | Mixed rungs in one ring look intentional, not broken |
| G4 | `L(--ring-fixture=eight)`; each preset | Click the gear; drag the hub; click elsewhere on the hub | Gear opens Settings and is easy to hit. Drag moves the ring. No hub click opens More, a sub-ring or a card |
| G5 | `L(--ring-fixture=twelve --ring-favourites=6)`; each preset | Reach for the More wedge at six o'clock | It is narrow but easy to reach, and shows count 5 |
| G6 | `L(--ring-fixture=twelve)` | Look at the Fans wedge; open More and look at the Load and Uptime entries | Fans fills within its speed range; Load fills relative to cores; Uptime has no fill. All read sensibly |
| G7 | `L(--ring-fixture=eight --ring-power-ceiling=30)`, then `=60` | Look at the Power wedge | The fill changes with the ceiling, and 30 W looks like a sensible default |
| C3 | `L(--ring-fixture=eight)` | Look at amber wedges (Memory, Temperature) | The old inner-quadrilateral shading is gone |

### B — Branches, sub-rings and the More arc

| ID | Launch | Do | Expect |
|---|---|---|---|
| B1 | `L(--ring-fixture=eight --ring-parts=typical)`; each preset | Dwell on, then click, CPU, Disk, Network and Temperature in turn. Move outward into the arc, then sideways into the card | Arc and card appear together, centred outside the parent wedge. Nothing in the ring moves. The route outward and sideways never loses the branch. Close, Escape or a click on the wedge closes both |
| B2 | same | With one branch open, open another wedge and then More | At most one arc and one card at any time. The previous branch closes cleanly |
| B3 | `L(--ring-fixture=eight --ring-parts=typical)`, then `=dense` | Hover segments in the CPU and Temperature arcs | A caption with name and value appears in its reserved strip, and nothing resizes. `dense`: 32 cores in groups with visibly wider gaps, and a collapsed sensor group. Segment labels are legible where shown |
| B4 | `L(--ring-fixture=eight --ring-parts=minimal)` | Open CPU, Disk, Network and Temperature | CPU opens an arc and a card. Disk, Network and Temperature open a card only, with no empty arc |
| B5 | `L()` real data | Open several wedges | Cards only, no arcs |
| B6 | `L(--ring-fixture=twelve --ring-favourites=6 --ring-parts=typical)` | Open More; open each of the five entries | The More arc shows five gauge wedges. Each opens its card while the arc stays. No More entry opens a sub-ring |
| B7 | same | With a More entry's card open, go back to the More wedge | Both the arc and the card stay open (3.1 fix) |
| B8 | `L(--ring-fixture=eight --ring-parts=typical)` | Open CPU's arc, then move across the ring to a sibling | The sibling previews after about 350 ms (the 700 ms grace no longer covers crossing from a sub-ring). Judge whether this feels right |
| B9 | Settings → Theme **Custom**, Background opacity **30%**; `L(--ring-fixture=eight --ring-parts=typical)` | With an arc open, click in: the gap between ring and arc, the separators, the caption strip, and the gaps in the hub band | The HUD stays open and no click reaches the app below |
| B10 | `L(--ring-fixture=eight --ring-parts=dense)` | Open CPU (near-full arc); click on the desktop just outside the drawn arc, inside its square | Behaves as click-away, and nothing invisible blocks clicks. Note the arc panel order and shadow |
| B11 | `L(--ring-fixture=eight --ring-parts=typical)` | With an arc and card open: drag the hub; reopen and click the gear; change displays (P2) | Each closes the arc and card cleanly, with nothing left behind on screen |

### C — Cards (real data unless stated)

| ID | Launch | Do | Expect |
|---|---|---|---|
| C1 | `L()` | Open CPU, Memory, Disk and Network | Real process lists and transfer history. Content fits or scrolls cleanly; Close is visible and clickable |
| C2 | `L()` | On a previewed (not clicked) card, use a card control (period or graph mode) | The card becomes held before the control acts |
| C4 | System Settings → Appearance → Show scroll bars: **Always**; `L()` | Open Fans, Battery, Memory, CPU, Load and Power | No scroller, no wrapped value, no clipped footnote, and Close visible. If any card is genuinely too tall, it scrolls with Close outside the scrolling area (otherwise record "none too tall") |
| C5 | `L()`, on battery power | Settings → Power → Panel value: **Charger input + Whole system** | The wedge shows one figure; the card shows the pair |
| C6 | `L()` | Temperature → **Status + CPU temperature**; Load → **1-minute average / cores** | Each wedge shows one token |
| C7 | `L()` Medium | Settings → CPU → Panel value: **Usage + temperature**; look at the CPU wedge | The label, value and temperature block does not crowd the wedge's outer rim line (3.2 left this unchanged, as a layout question for E1) |

### D — Interaction confirmations (passed before; geometry changed)

| ID | Launch | Do | Expect |
|---|---|---|---|
| H1 | `L(--ring-fixture=eight)` + hover log | With another app frontmost, hover a wedge, pause, move on | Preview after a short dwell; record the logged mechanism |
| H2 | same | Hover wedge A, then travel diagonally into its card across wedge B | B does not take over |
| H3 | same | Click a wedge (held), then hover its siblings | The held card stays |
| H4 | same | While held, click a sibling | The card switches to the sibling |
| H5 | same | Same-wedge click / Close / Escape, without moving | The card closes and does not reopen until you leave and re-enter |
| H6 | same | Leave the ring quickly and come back | No flicker or stuck card |
| M1 | `L(--ring-fixture=twelve --ring-favourites=6)` | Open More, move to an entry, then into its card | More and the card stay together; crossed wedges are not selected |
| E1a | same | Press Escape repeatedly with a card and More open, then plain; repeat while pinned | Closes the card, then More, then the HUD |
| D1 | `L(--ring-fixture=eight)`, then quit and launch the app with **no** arguments | Drag the ring; reopen; then check the Strip | Ring moves and children close; the Strip position is unchanged |
| D2 | `L(--ring-fixture=eight)` | Pin; hotkey toggle; click-away; first click from another app | All keep their meanings, and the first click acts without a focus click |
| P1 | `L(--ring-fixture=eight --ring-parts=typical)`; each preset | Summon near each screen edge and corner; open CPU | The band or a fallback is chosen with no clipping, and the wedge under the pointer does not move |
| P2 | second display, if any | Summon on it; drag across displays; unplug if feasible | No clipping; children close on drag; display removal hides cleanly |
| P3 | a display with room for the band and a card | Summon centred; open CPU and More | Full outer-band branch; otherwise mark it **natively untested** |

### E — Accessibility and motion

| ID | Launch | Do | Expect |
|---|---|---|---|
| A1 | VoiceOver on (Command-F5); `L(--ring-fixture=twelve --ring-favourites=6 --ring-parts=typical)` | Navigate wedges, More, gear; open CPU and step into its segments; Press a More-arc entry | Each wedge speaks name, full reading (paired values as the pair), availability and expanded state. More speaks its count. Segments are children with name, value and range. Press matches click |
| A2 | System Settings → Accessibility → Display → **Reduce motion** on; `L()` | Watch fills as values change | Fills step without tweening |
| A3 | **Increase contrast** on, then **Differentiate without colour** on; `L(--ring-fixture=eight)` | Look at fill edges and states | The fill edge is an explicit line, and every state reads without relying on hue |

### F — Settings placement and Open Questions

| ID | Do | Return |
|---|---|---|
| S1 | Read the spec section "Proposed settings placement and wiring" | Accept or redirect |
| Q1 | Child level shape: arc centred on the parent in one outer band | Decide / stays open |
| Q2 | Preset dimensions 260 / 360 / 460 and the content ladder (richest rung, mixed rungs) | Decide / stays open |
| Q3 | Gauges for Fans (speed range), Load (÷ cores), Uptime (no fill) | Decide / stays open |
| Q4 | Fixed fill basis, with the card naming it where it differs from the text | Decide / stays open |
| Q5 | Gauge fill colour versus colour mode (per-stat hues, Mono neutral) | Your view; the row stays open |
| Q6 | Power gauge ceiling 30 W | Decide / stays open |
| Q7 | Which gauge options become settings (Size, Wedge text, Fill scale) | Decide (with S1) |
| Q8 | Sensor labels and the 32-part cap (role groups, raw names in captions, largest group collapses first) | Decide on fixtures / stays open |
| Q9 | Caption placement (top or bottom strip of the band footprint) and the large transparent arc panel | Accept or redirect |

Status-band input for Network and Power, and Volumes/Interfaces shown, stay open beyond E1:
they are decided by the sampling plan. Also record any sizing or visual corrections you want.

## Owner results

*Not yet run.* Record results here against the artifact hash above. If the artifact changes,
note the new hash and which rows were rerun.
