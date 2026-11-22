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

Record results here against the artifact hash above. If the artifact changes, note the new
hash and which rows were rerun.

### Batch 1 — 2026-11-14 (artifact `25064385…`, partial)

Screenshots only, sent without row IDs; the owner later named them as network and storage. Rows
are therefore inferred from what is shown. Rows the owner did not judge stay **open**, not
passed.

| Row | Observed | Owner verdict |
|---|---|---|
| B6 / G6 | More arc: five icon-only gauge wedges (Uptime, Load, Temperature, Power, Fans). Uptime has no fill; the others fill | Not judged (open) |
| C4 (Power card) | Scroll bar shown; footnote clipped at "Fill is measured against a fixed 30" (full: "…30 W ceiling."). **Defect F2**, see below | Fail (Claude's reading; confirm on rerun) |
| B3 CPU `typical` | Caption "P8 19%" in the top strip. In-segment labels only on P1 and P2; the others are caption-only | **Correction:** either label every segment, or tell P-cores from E-cores by a different shade |
| B1 / B3 Network | Hover moves the caption (Wi-Fi, Ethernet); each segment shows paired orange/teal (down/up) fills. The top of the arc looks narrower than the rest (unexplained, open) | Paired fills **don't read clearly**; numbers would be better |
| B1 / B3 Storage | Hover moves the caption (Archive 35%, Backup 81%); "Scratch 12%" labelled in-segment | Not judged beyond Q9 (open) |
| Q9 (caption placement) | CPU caption above the arc; Network and Storage below | **Accepted**: captions belong to their wedge |
| CPU card (C1, fixture) | Large empty area under four fixture processes, which is the 10 reserved process rows (D-008). "38,0%" next to "26%" is the existing Strip format | Not judged |

**New request (outside the prototype's settings):** text orientation should be a setting, as in
MousePlus (`LabelOrientation`: upright / radial / tangential, auto-flipped to stay readable). This
conflicts with the spec's horizontal-text rule (D-035), so it needs a decision before it's built.

**F2 — Power card footnote clipped.** The card is measured once at summon
(`AppDelegate.swift`, `NSHostingView(...).fittingSize`) with no width proposal, so the footnote
(`StatDetailView.swift`, `.frame(maxWidth: 240)` + vertical `fixedSize`) measures as one line but
wraps to two when shown. The card then overflows its frozen frame and falls through to the
scrolling layout. Affects every card with a fill-basis note (Power, and Disk under G2). Fix: give
the note a definite width so measurement and display agree; add a test. Deferred until the batch
returns, so the artifact doesn't change mid-review.

### Batch 2 — 2026-11-14 (artifact `25064385…`, launch `twelve --ring-favourites=6 --ring-parts=typical`)

| Row | Result |
|---|---|
| B6 | Pass |
| B7 | Pass |
| G5 | Pass at Medium. Small and Large still open |
| G6 | Pass |
| M1 | Pass |
| E1a | Pass |
| A1 | Skipped: VoiceOver not tested |

**F2 confirmed across cards.** Screenshots of the More cards show the same clipping on every card
with a fill-basis note: Load ("Fill shows load per active core,"), Temperature ("Fill shows the
hottest valid sensor; the"), Power ("…a fixed 30") and Fans ("Fill shows the fastest fan
between its"), each with a scroll bar. Uptime, which has no note, fits with no scroll bar. Memory and
Disk carry notes too and are expected to fail the same way. The fixture Temperature card (29
sensors) is tall but would fit without the note.

**Owner correction:** the card's Close button is redundant. Cards already close by clicking the
wedge again, Escape, or click-away. Removing it changes the spec (hover rules, "Held details …
close by owner click, Close, or Escape", and the interaction table's "Close button / Escape" row)
and rows B1, H5 and C1. VoiceOver can still close a card by pressing the wedge again.

### Batch 3 — 2026-11-14 (artifact `25064385…`, launch `eight --ring-parts=typical`, Medium)

Ten screenshots, no row verdicts yet (B1, B2, B3, B8, B11, P1 open). Claude's observations:

- **F2 also on Memory** ("Fill shows memory in use against", with a scroll bar). The Disk card,
  which has a fixed width, shows its two-line note in full, which supports the F2 root cause.
- **F3 (fixture only): CPU and Temperature wedges read "—°C".** The owner's real settings are
  CPU = Usage + temperature and Temperature = CPU temperature. That reading looks for a sensor
  labelled exactly "CPU". The `typical` fixture names its sensors "CPU sensor 1…", so there's no
  match. Real data is unaffected; the fixture should include a "CPU" (and "GPU") role sensor.
- **Caption repeats the in-segment label** when hovering a labelled segment (CPU "P3 76%" in both).
- **Disk arc caption floats far from a short arc**: the caption sits at the top of the band footprint,
  well above the four-segment arc.
- **Temperature arc segment widths vary widely**: each sensor group appears to get an equal share
  of the arc, so CPU's 12 sensors are thin slivers while SSD's and Battery's 3 are wide. Owner to judge.
- **Network arc**: segments differ in length and the paired fills are hard to read (already a correction).
- CPU and Memory cards keep empty reserved process rows below four fixture processes (D-008, by
  design). The Network transfer card fits with no scroll bar.

Owner answers on Batch 3:

- **Caption repeating the label:** pass, fine for now. Possible later Settings toggle (captions
  or in-segment labels).
- **Disk caption position:** acceptable, but the arc doesn't make clear what its segments are
  (volumes). Needs identification, e.g. a title or role in the caption.
- **Temperature arc density (Q8):** owner questions whether that many CPU sensors need to be
  visible, and suggests a further fan-out. Claude's recommendation: the arc shows one segment per
  sensor group (CPU, GPU, SoC, SSD, Battery, each at its hottest sensor), and individual sensors
  stay in the card. A third fan-out level would break the "one arc and one card" rule (Q1), so
  defer it unless the group arc proves too coarse.

Row verdicts (Medium): **B1, B2, B3, B8, B11 pass. P1 pass** for placement, with one defect:

**F4 — dragging the ring to a left or right screen edge switches Space.** The panel follows to the
next Space, then input is slow to respond for a while. Cause: the hub drag uses
`NSWindow.performDrag(with:)` (`RingPanelController.swift`), a window-server drag that gets
macOS's "hold a dragged window at the edge to switch Space" behaviour. The panel is
`.canJoinAllSpaces`, so it comes along. Fix direction: replace it with an AppKit event-tracking
loop that moves the panel with `setFrameOrigin` and clamps it to the screen. That loop isn't
paced by SwiftUI rendering, which was why `performDrag` was chosen. The Strip uses the same
`performDrag` (`PanelWindowController.swift`) and likely shares the defect.

Small and Large (`--ring-size=small`, `large`): **B1 and P1 pass**, text comfortable.

### Fix pass 1 — 2026-11-14 (new artifact)

| Field | Value |
|---|---|
| Executable SHA-256 | `d973794615e701f927b901a2f9c930057646b1218b245a96e711ce86f7d6ff5f` (`.debug.dylib` `07b4507de9fa1ccd8700c26a978bb2e34372cc5dc9af006f3fdb45054516b016`) |
| Build | B, log `01_Project/build/GaugePrototype-E1fix-B-run01.log`, exit 0; `codesign --verify --deep --strict` OK |
| Tests | T-all `01_Project/build/GaugePrototypeAllTests-E1fix-run01.xcresult`: **390 tests, 0 failures** (tests rewritten one-for-one for the new rules) |
| Running | PID 7984, started 21:52:51 with `--ring-prototype --ring-fixture=eight --ring-parts=typical`; executable and `.debug.dylib` paths verified. No earlier instance was running |

Changes:

- **F2:** the fill-basis note has a definite 220-point width (`StatDetailView.basisNoteWidth`), so the
  one-time measurement and the display agree. View-only; verified natively, not hostless.
- **Close removed** from ring cards. They close by clicking the wedge again, Escape or click-away.
- **F4:** the hub drag is an AppKit event-tracking loop (`RingPanelController.trackDrag`) that keeps
  the ring on the visible frame of the screen under the pointer, so macOS never sees a window drag
  and doesn't switch Space. The Strip still uses `performDrag` (not changed; owner to confirm whether
  it shows the same Space switch).
- **CPU arc:** Efficiency-core fills are drawn at half opacity, so E and P cores read apart.
- **Network arc:** one fill for download plus upload on the log scale, and the segment label shows
  that combined rate. The caption keeps the ↓/↑ pair.
- **Temperature arc (provisional Q8):** one segment per sensor role at its hottest sensor; the caption
  says "hottest of N". The real reader already reports one reading per role.
- **Disk arc:** the caption says "<volume> <n>% used".
- **F3 (fixture):** fixture temperature readings are role-labelled ("CPU", "GPU"…), as the real
  reader reports, so CPU and GPU temperature panel values resolve on fixtures and the card lists
  one row per role.

Rows invalidated by this pass and to be rerun on this artifact: B1 (Close), B3 (Temperature and
Network arcs), G4/D1/B11 (drag), H5 (Close), C1/C2/C4 (cards), P1 (drag clamping near edges).

### Recheck of fix pass 1 — 2026-11-15 (artifact `d9737946…`, `eight --ring-parts=typical`, Medium)

Eight screenshots. Arc items:

- **CPU arc E-core shade:** shown. The two Efficiency segments come first, after a wider group gap,
  with a dimmer fill. They read only faintly because both fixture E-cores are nearly empty.
- **Network arc:** one fill per segment. The caption reads "Wi-Fi ↓4,5 MB/s ↑600 KB/s". The segments
  are too short for the combined-rate label inside them.
- **Temperature arc:** 5 segments, one per role. The caption reads "SSD 66°C · hottest of 3".
- **Disk arc:** all four captions read "<volume> <n>% used" (Macintosh HD 62%, Archive 35%,
  Backup 81%, Scratch 12%). This answers the Batch 3 identification note.

Claude's observations (owner to judge):

- **F5 — arc segments in one arc have very different lengths** (Disk: Macintosh HD about twice
  Archive or Backup; Temperature: Battery and SSD much longer than the lower three). Likely cause (code reading, not yet verified), from
  `RingArcLayout`: each entry's angle is its label's projected width at its tilt, and spare span is
  shared *in proportion* to those needs. A label that then doesn't fit the band depth is dropped,
  but its segment keeps the width it was sized for. So length follows text width and position,
  not data. Fix candidates: equal shares of spare span, or size segments as unlabelled first and
  only widen ones that keep a label.
- **Temperature fill shows fine horizontal banding** in the screenshot. The CPU, Network and Disk
  fills don't.
- **The CPU wedge's "74°C" secondary value has low contrast** against the lighter inner temperature ring.
- **A thin teal line at the outer edge of the Disk wedge**, in the whole-ring screenshot.

Still open from the recheck: cards (clipped note, scroll bar, no Close) and drag at the screen edges.

Cards (Memory, Disk, Network, GPU; four screenshots): **no clipped note, no scroll bar, no Close.**
The Memory note shows all three lines; the Disk note shows both lines. GPU Temp reads 70°C (F3
fixed on fixtures). The Disk and Network transfer sections read "No data", which is expected in
fixture mode: the store is disposable, runs no samplers and keeps its own temporary transfer
history (`StatsStore.makeRingFixtureStore`). This needs a real-data check (`L()`, C1). The scroll
bar setting during capture wasn't stated, so C4 (Fans, Battery, CPU, Load, Power with scroll bars
on Always) is still open.

Drag at screen edges: owner reports **no Space switch — F4 fixed** for the ring. Whether the ring
stays fully on screen and closes open children is covered when G4, D1, B11 and P1 are rerun.
Whether the Strip's `performDrag` drag switches Space is still open.

**Recheck result:** fix pass 1 accepted (F2, F3, F4 and the arc and card corrections). New: F5
(arc segment lengths) plus three minor visual notes, all above.

**F6 — the Strip drag switches Space too** (owner, 2026-11-15, same artifact launched with no
arguments). Input keeps responding afterwards, unlike F4 on the ring. Same cause:
`PanelWindowController.drag` hands off to `performDrag(with:)`. The ring's list panel
(`RingPanelController`, header drag, `isMovable`) uses the same window-server drag and likely
does the same. This defect is in the released v1.2.0 Strip, not only in the prototype.

Owner answers on the recheck (2026-11-15):

- **F5:** share spare span **equally** (option a). Goes into fix pass 2.
- **"74°C" contrast on the CPU wedge:** later (backlog, not fix pass 2).
- **F8 — Temperature heat fill shows visible seams** on screen (owner screenshots, wedge and arc).
  Cause: `RingGaugeWedgeView.stackFill` draws the heat ramp as 10 separate radial slices, and the
  antialiased edges between neighbouring slices show as thin lines. Fix direction: one shape filled
  with a radial gradient centred on the ring. The arc segments use the same stepped drawing.
- **Disk outer teal line: by design.** It's the Disk I/O rim (`gauge.rim`, D-035 Disk mapping):
  a thin outer rim whose brightness follows read + write. It isn't a leftover arc. Owner to say
  whether it reads as intended.
- **F7 — an empty caption slot shows as a faint pale box** when the Disk arc is open and no segment
  is hovered (owner screenshot). Likely cause (not verified): the slot carries the 2% black hit fill
  (`RingArcView.hitFill`) so clicks don't fall through, and the panel's window shadow then outlines
  that almost-transparent rectangle.
- The "CPU" screenshots duplicated the Temperature ones; owner asked to resend.
- **D1, Strip half:** you can't observe this with the owner's setting. Position is **At cursor**, so
  the Strip re-homes to the pointer on every summon and never saves a drag (`AppDelegate`
  `onPanelMoved` guard; `PanelWindowController.origin` ignores the saved spot in cursor mode). By code
  inspection: the only writer of `AppSettings.customPosition` is the Strip's `onPanelMoved`, and the
  ring controller never writes it. **Pass by inspection**; the ring half of D1 is still to run.

### Step 3 — 2026-11-15 (artifact `d9737946…`, `eight`, Medium)

Owner returned **"all pass"** for the Step 3 batch presented in this session:

- **G3, C3:** mixed text/icon rungs look intentional; no darker inner quadrilateral.
- **G4:** gear, hub drag and inert hub clicks pass on the current Medium launch.
- **H1–H6:** preview, protected travel into the card, held precedence, sibling switching,
  stationary dismissal and quick exit/re-entry pass. Close is no longer part of the interaction.
- **D2:** pin, toggle hotkey, click-away and first click from another app pass.
- **D1, ring half:** dragging moves the ring and closes child panels. Strip position isolation
  remains passed by inspection as recorded above.

The running process was checked before the batch: PID 14881 with
`--ring-prototype --ring-fixture=eight`; the on-disk executable hash matched fix pass 1.
Small/Large G4 repeats were described as later work, so this response does not establish them.
No hover-mechanism log was captured; H1's owner-observed behaviour passes, but its logged
mechanism remains unrecorded. This does not revalidate arc-specific rows on a launch without
`--ring-parts`, or close the rest of E1. Corrected CPU screenshots and the Disk I/O rim verdict
remain separate follow-ups.

Next: request execution of queued fix pass 2 (F5–F8), then rebuild, test and rerun affected rows.

### Fix pass 2 implementation — 2026-11-15

F5–F8 implemented and committed as `6c70d18`; Debug/Release builds, 391 hostless tests and
deep signature verification passed. [Changes, exact artifact and finite affected-row recheck](gauge-ring-fix-pass-2.md).
No new native acceptance is claimed. E1 remains open.

### Constant-gap correction — 2026-11-15

Owner reviewed the verified Fix2 artifact (1.2.1/1201, PID 17600) with `eight`/`typical`
fixtures. [Eight supplied screenshots](gauge-gap-review-2026-11-15/) preserve the visual evidence.
Owner: “The wedges look strange as there is a tiny gap that grows bigger.” Requested parallel,
constant-width separators on main wedges and outer arcs. Owner also reports no visible difference
from two hours earlier; F5/F7/F8 visual acceptance remains open, and screenshots do not test F6 drag.
CPU screenshots are now supplied; this alone does not approve CPU contrast or the Disk rim.

Correction uses the shared sector geometry for drawing, fill slices, reference/peak lines,
selection outlines, text containment, hit testing and translated arc panels. Ordinary gaps remain
4 points and group gaps 12 points, now measured perpendicular to parallel edges at every radius.
Gauge radial scales retain their nominal annular basis. No sampler, Settings or release change.

Validation: full suite 392/0 (`GaugeGaps-all-run02.xcresult`); after adding the arc-layout
regression, focused sector/arc tests 33/0 (`GaugeGaps-focused-run01.xcresult`). Tests cover all
presets, ordinary/group separators, both outer-band depths, gap hit exclusion and partial fills.
Initial run01 failed compilation on extra arguments introduced during editing; fixed before run02.
Native visual acceptance remains open. Next: compare main wedge and outer-arc separators, then
continue the prior finite recheck; do not mark unrelated corrections accepted from this change.

### Main-ring separator acceptance — 2026-11-15

Owner: “fantastic” on the constant-gap build, with [main-ring screenshot](gauge-gap-review-2026-11-15/09-main-ring-accepted.png). Main-ring separator appearance accepted. Requested a later gap-width setting including zero/no gap; tracked in TASKS, deferred to production settings planning. This screenshot does not close outer-arc, drag, preset or other outstanding E1 checks.

### Outer-arc screenshots — 2026-11-15

Owner supplied Temperature, CPU, Disk and Network crops from the current review. Preserved as
images 10–13 in `gauge-gap-review-2026-11-15/`. Visual inspection: separator edges appear parallel
through the band depth; wider Temperature/CPU group gaps remain distinct. Segment lengths still
vary with label allocation. These images show hovered captions, not the unhovered empty caption
slot or click-through behavior. No explicit owner accept/reject accompanies this batch; do not
close other E1 rows from it. Next useful check: repeated Ring hub drags and screen-edge holds.

### Ring drag recheck — 2026-11-15 — PASS

On the constant-gap review build, owner replied “pass” to: open an arc, repeatedly drag the
centre hub and hold it at a screen edge; no Space switch, arc/card closes during dragging, normal
interaction afterward. Records the current Medium fixture Ring case of F6/G4/D1/B11/P1 only.
Strip, whole-list fallback, Small/Large and additional-display repetitions are not implied.
Next: F7 empty-caption visual and click-through check on the Disk arc.

### Disk empty-caption recheck — 2026-11-15 — PASS

Owner replied “pass” to the current Medium fixture Disk arc F7/B3 check: moving off segments
leaves no faint caption box/shadow; clicking the empty caption area neither dismisses the HUD
nor clicks the underlying app; hovering a segment restores its caption. This closes that scoped
F7 recheck, not other presets or unrelated E1 rows. Next: default-area Temperature heat ramp verdict.

### Temperature heat-ramp recheck — 2026-11-15 — PASS (default area)

Owner replied “pass” to inspecting the Temperature wedge and outer segments for smooth
purple-to-red transitions without thin bands or seams. Applies to current Medium, eight/typical
fixtures, default area fill. Linear fill and Small/Large repetitions remain open. Next: F6 Strip
repeated-drag/click check, requiring relaunch of the same artifact without prototype arguments.

### Strip drag recheck — 2026-11-15 — PASS

Owner replied “pass” after normal live-data launch of the GaugePrototypeGaps artifact: repeated
Strip drags from padding and tiles, holds at screen edges without Space switching or stuck
gestures, then functioning tile and Settings-gear clicks. F6 Strip repeated-gesture/click case
passes. This does not establish fixed-position persistence or cursor re-homing, which were not
part of this prompted batch. Whole-list fallback, other ring presets and linear-fill review
remain open.

### Saved display settings confirmed — 2026-11-15

Owner confirmed “saved choices”: CPU = Usage + temperature; Temperature = CPU temperature;
Power = DC in + system; Load = relative to cores. These are intended preferences, not temporary
test values. Saved-settings confirmation is closed; no preferences changed or restoration needed
for these four choices. This does not close other E1 checks.

### Small Ring screenshot review — 2026-11-15

Three owner screenshots preserved as images 14–16 in `docs/evidence/gauge-gap-review-2026-11-15/`
(project-relative path). Main ring uses the expected icon-only rung for eight favourites in Small.
Disk and Temperature captions are readable in the supplied crops; separator edges appear parallel
and Temperature fills smooth. Visual inspection only: no explicit owner verdict or evidence of
Small hub dragging/screen-edge holds supplied yet. Next: confirm that interaction check.

### Small Ring interaction recheck — 2026-11-15 — PASS

Owner confirmed “pass” for repeated hub drags and screen-edge holds in Small. No Space switch,
children close and normal interaction remains usable, as in the prompted check. Screenshot
inspection is recorded separately above; no other E1 row is implicitly closed.

### Large Ring recheck — 2026-11-15 — PASS

Owner replied “pass” to the Large eight/typical, default-area batch: Disk/Temperature readable
captions, clean gaps, smooth gradients, repeated hub drag and screen-edge hold. Only these
prompted cases are accepted; no empty-caption clicks, other displays or fallback implied.

### Linear-fill Temperature recheck — 2026-11-15 — PASS

Owner replied “pass” to the Large linear-fill Temperature wedge and outer segments: smooth
colour transitions without bands or seams. F8 linear-fill visual recheck passes for this
configuration. Large/eight/typical/linear fixture build remains running (last verified PID 56878).
This does not select a preferred fill scale or close all E1 acceptance. Next design decision:
Q2, whether to retain Small/Medium/Large with Medium as the default.

### Preset/default decision — 2026-11-15 — APPROVED

Owner confirmed keeping Small, Medium and Large with Medium as default (D-038). Resolves the
preset/default portion of Q2; no other acceptance or design question is inferred. The currently
running Large/linear review configuration is unchanged.

### Dense-data screenshots — 2026-11-15

Images 17–18 preserve the owner-supplied dense CPU arc and main ring. CPU caption “S3 24%”
is readable; segment widths vary strongly, with wide segments beside thin slivers. This matches
the label/sliver allocation but remains a visual review concern, not an accepted result. The
second image is the main ring, not the Temperature arc. Still need owner outcome for caption
stability during hover and outside-arc click-away (B3/B10); screenshots alone cannot establish
those interactions. No dense-data pass inferred.

### Dense-data interaction verdict — 2026-11-15 — PASS

Owner replied “pass” to stable captions while hovering and outside-arc click dismissal (B3
interaction/B10), supplying the missing Temperature screenshot, preserved as image 19 in
`docs/evidence/gauge-gap-review-2026-11-15/`. Temperature caption is readable and the role-group
arc is visible. The prior concern about unequal dense CPU segment widths remains separate;
this response does not explicitly approve or request a correction to that allocation.

### CPU equal-width correction — 2026-11-15

Owner explicitly approved equal-width CPU segments within each group, showing labels only when
they fit and retaining full hover captions. The CPU sub-ring now shares each group's allocated
span evenly among its cores, retaining total footprint and wider group gaps. Text fit runs after
redistribution; hidden inline text does not remove a part, its caption or accessibility information.
Other stat arcs and the More arc keep their existing allocation. Prior dense caption/click-away
passes remain historical evidence; CPU geometry requires a focused native recheck after rebuild.

CPU correction validation: regression fails old layout with 110 assertions; full suite **394/0**,
Debug/Release builds and signature pass. `GaugePrototypeCPUEqual` launched and identity verified;
see current session handoff. Dense CPU appearance/hover recheck awaits owner; no native pass claimed.

### Equal-width CPU appearance — 2026-11-16 — PASS

Owner explicitly accepted the rebuilt dense CPU arc appearance (“pass”), following screenshot
`gauge-gap-review-2026-11-15/20-equal-cpu-accepted.png`: even segments within each group, wider
group gaps retained, readable “S6 75%” hover caption. Closes the D-039 visual correction for the
Medium dense fixture on GaugePrototypeCPUEqual. Does not close all E1 or infer additional
interaction checks from the screenshot.

### Minimal-parts review — 2026-11-16 — B4 PASS

Owner supplied three screenshots, then explicitly confirmed CPU opens both an arc and a
card, while Disk, Network and Temperature open cards only, with no empty arc. B4 passes
for the requested Medium/eight/minimal configuration on GaugePrototypeCPUEqual. The
executable and debug dylib hashes matched the current handoff during preparation; process
inspection was sandbox-blocked, so launch arguments were not independently verified.
No build, test rerun or app control performed. E1 and unresolved design decisions remain open.
Next: real-data B5 and the outstanding Disk I/O rim clarity verdict; preserve saved display choices.

### Real-data review — 2026-11-16 — B5 PASS

Owner confirmed CPU, Disk, Network and Temperature open cards only, with no arcs,
after the requested real-data Medium launch. B5 passes for those wedges. Disk's rim
is visible at idle, but the owner observed no activity, so its response and clarity
under load remain unverified. No active-I/O pass inferred. Process/configuration not
independently verified; no agent app control, build or test run.
Next: C2, use a period or graph-mode control on a hover-previewed real-data card and
confirm it becomes held. E1 remains open.

### C2 report and configuration correction — 2026-11-16

Owner confirms the Network card stays held after using the period control and moving
over another wedge. History still did not load after waiting. C2 hold behavior passes
on the fixture; real-data C2 remains untested. Screenshots show changing period selection,
stuck hour/day loading and missing labels/rows; rendering completeness remains unresolved.

Read-only process inspection identified PID 65973 running GaugePrototypeCPUEqual with
`--ring-prototype --ring-fixture=eight --ring-parts=minimal --ring-size=medium`. This
supersedes the inferred real-data attribution above: **B5 real-data is not yet verified**.
B4 remains passed. No app was quit or launched by the agent.

Source diagnosis: makeRingFixtureStore disables automatic history scheduling and seeds
no retained transfer samples. Initial load publishes the empty minute view. selectPeriod
requests a presentation, but requestPresentation does not schedule it when automatic
scheduling is disabled. Thus hour/day remain loading in this fixture. This explains
missing history, not the disappearing static labels. No source correction made.
Next: verify a real-data launch before repeating B5 and real-data C2/history rendering.

### Real-data Network retest — 2026-11-16 — C2 PASS

Owner reports “works” after the real-data launch and repeat Network period-control
check (history loads, labels remain visible, card stays held). Read-only process
inspection verified PID 77497 at GaugePrototypeCPUEqual with only
`--ring-prototype --ring-size=medium`; no fixture arguments. C2 passes for Network
period controls and the reported rendering/loading problem does not recur in this
real-data check. Fixture scheduling limitation and fixture missing-label cause remain
unfixed. No app control, source change, build or test run.

Next: B5 real-data cards-only behavior for CPU, Disk and Temperature (Network checked),
and C1 content fit for CPU, Memory, Disk and Network. Do not repeat C2. E1 remains open;
Disk rim activity response remains unverified.

### Real-data card fit and cards-only review — 2026-11-16 — C1/B5 PASS

Owner replied “pass and pass”: CPU, Memory, Disk and Network card content fits or
scrolls without clipping (C1, superseded Close requirement excluded); CPU, Disk and
Temperature open cards only, with no outer arcs. Together with the preceding Network
check, B5 passes on real-data Medium. Same requested CPUEqual setup; no new process
inspection, app control, build or test run.
Next: C4 with macOS Show scroll bars set to Always, covering Fans, Battery, Memory,
CPU, Load and Power. This specific setting and remaining cards were not covered by C1.
E1 stays open; Disk rim activity response and fixture issues remain unresolved.

### Always-visible scrollbars — 2026-11-16 — C4 PASS

Owner reports “all pass” for Fans, Battery, Memory, CPU, Load and Power with macOS
Show scroll bars set to Always: no clipping, wrapped values or unnecessary scrollbars;
content reachable if scrolling is needed. C4 passes with the superseded Close-button
requirement excluded. Whether any card actually needed scrolling was not separately
reported; no too-tall fallback claim inferred. Restoration of the prior system setting
was requested but not independently verified. No app control, build or tests performed.
Next: C7 real-data Medium CPU text/rim spacing with saved Usage + temperature display.
The separately deferred secondary-temperature contrast issue stays deferred. E1 open.

### C7 correction — 2026-11-16 — implemented, visual recheck pending

Owner screenshot `gauge-gap-review-2026-11-15/21-cpu-peak-label-overlap.png` shows
the CPU peak line striking through its label. Owner authorized continuing the correction.
The line is a live peak marker, not the fixed outer rim; moving the text would not
prevent crossing at other peak values. RingGaugeWedgeView now passes its frozen text
frame plus 3 pt clearance into RingGaugeFill. An even-odd mask removes only reference,
peak and accessibility fill-edge lines inside that frame. Fill, Disk rim, selection
outline, text positioning, geometry and hit targets are unchanged. Main-wedge content
gets the same protection at every rung; arc callers retain their existing drawing.

Validation: Debug build `TextClearance-B-run02.log` and Release
`TextClearance-R-run01.log` pass; deep strict signature verification passes outside
the sandbox. Release has zero ring-flag strings (Debug control four). `git diff --check`
passes. Initial Debug run01 failed on sandbox cache access; generation initially ran
from the repository root, then succeeded from 01_Project. No hostless tests rerun:
this change is only SwiftUI drawing, outside the hostless model target; prior 394/0
remains historical evidence, not a new result. Native mask appearance is not yet verified.

Candidate: `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/GaugePrototypeTextClearance/Build/Products/Debug/QuickStatsPanel.app`,
version 1.2.1 (1201), arm64, team FDMSRXXN73; signature timestamp November 16 09:41:30.
Executable SHA-256 `31e6b10f2cf5a16e01bfb1a1abbdaa5503cca0554f436ca154a1cf8959d635dd`;
dylib `b0cf2b432540416a8ad51341351e6f934204000977d383421f7b50c0a03b28e4`.
Not launched; current keep-running handoff preserved. Next: owner quits prior review
app normally and launches this candidate with `--ring-prototype --ring-size=medium`.
C7 recheck: CPU label, percentage and temperature stay clear of the peak line as
readings change; line remains visible outside the content area. Inspect other visible
wedges for unintended blank fill patches. E1 remains open; no unrelated checks reopened.

### C7 text clearance — 2026-11-16 — ACCEPTED

Owner supplied `gauge-gap-review-2026-11-15/22-cpu-text-clearance-accepted.png` and
answered “acceptable” to the corrected clearance and line-gap appearance. C7 visual
correction accepted on the requested real-data Medium TextClearance candidate. Screenshot
shows CPU label/value clearance and continuous gauge fill, with corresponding gaps at
GPU text and Network icon. No broader dynamic, preset or accessibility pass inferred.
No new process inspection, app control, build or test run. Deferred temperature contrast
remains separate. Next: C5 Power wedge/card on battery power with the saved paired
display; E1 and other unperformed cases/design questions stay open.

### C5 Power on battery — 2026-11-16 — screenshot evidence PASS

Six owner screenshots preserved as images 23–28 in gauge-gap-review-2026-11-15.
Battery card explicitly says “On battery”. Power wedge shows one wattage; the Power
card shows System 32.4 W and DC In 0.0 W. Later plugged-in screenshots show the plug
mark and System 32.0 W / DC In 41.1 W. C5's visible one-value wedge / two-value card
behavior is satisfied by screenshot evidence; no separate owner verdict or timing/
accuracy claim inferred. Screenshots are separate moments, so wedge/card numbers
need not match. E1 remains open. Next: C6 Temperature Status + CPU temperature and
Load relative-to-cores wedge presentation; restore only temporary test preferences.
No source edits, build/tests, process inspection or app control.

### C6 compact Temperature/Load readings — 2026-11-16 — PASS

Owner replied “pass” to Temperature in Status + CPU temperature mode and Load in
1-minute average / cores mode each showing one compact reading without overlap.
C6 passes for the current real-data review. No new process inspection or app control;
restoration of temporary preferences not independently verified. E1 remains open.
Next: explicit Q1 decision on one outer arc centred on the selected parent wedge,
with its detail card open alongside. Prior acceptance is not inferred as Q1 approval.
