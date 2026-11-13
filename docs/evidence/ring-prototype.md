# Ring Prototype — Integration Evidence and Native Review (1.3 / E1)

Plan: [IMPLEMENTATION_PLAN.md](../../IMPLEMENTATION_PLAN.md) · Spec: [panel layouts](../../specs/panel-layouts-and-appearance.md) · Decision: D-034.
Recorded 2026-11-13 on this Mac (MacBook Pro, arm64, macOS 27.2 build 26B5091g). Source `306f2cf`
(ring code last changed in `cf6da8f`). Nothing here is native acceptance; E1 owns that.

## Review artifact

| Field | Value |
|---|---|
| Folder (Finder Go to Folder) | `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/RingPrototype/Build/Products/Debug` |
| App | `QuickStatsPanel.app` (Debug), 1.2.1 (1201) |
| Executable SHA-256 | `21f04750c1e89647a0e1a04d4706b2bdafbbded8284babb05813be6052c7a828` (`.debug.dylib` `c3775ad34caa0ae7…`) |
| Signing | team FDMSRXXN73; `codesign --verify --deep --strict` OK (02:41) |
| Built | 2026-11-13 02:23:08 (1.2); 1.3 rebuild at 02:41 was a no-op (no source change), identical hash |
| Running | PID 19436, started 02:24:23, executable path matches; launched with `--ring-prototype --ring-fixture=eight` |

Local, Git-ignored artifact: another Mac must rebuild with B. The prepared 1.2.1 app/DMG/feed were not touched.

### Launching other fixtures (owner-operated)

Quit the running copy normally (its in-panel Quit), then in Terminal:

```bash
/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/RingPrototype/Build/Products/Debug/QuickStatsPanel.app/Contents/MacOS/QuickStatsPanel --ring-prototype --ring-fixture=eight
```

Fixtures (`RingPresentation.swift`, Debug only): `none` (no enabled stats), `one` (CPU), `six`,
`eight`, `twelve` (all **eleven** stat kinds — the app has eleven, so "twelve stats" means all of them),
`long` (eight stats, every paired value at its worst-case string), `paired` (six, two-line values),
`unavailable` (eight, Battery/GPU/Power unseeded). An unknown name logs and falls back to `six`.
`--ring-prototype` alone uses real data and the ordinary store. Fixture mode skips samplers, the
updater and real transfer history; it uses a disposable temp root.

To capture the hover mechanism, run this in a second Terminal window **before** hovering. `--level info` is
required; it was missing from the 1.1 instruction, which is likely why that check captured nothing:

```bash
log stream --level info --predicate 'category == "RingPrototype"'
```

Expect `first hover event delivered by global|local|poll`. On hide, it also logs the delivery counts for that summon.

## Automated and build evidence (1.3)

All commands run from `01_Project`, after `xcodegen generate` (no project diff).

| Check | Command / result bundle | Result |
|---|---|---|
| **R** Release exclusion (build-only) | Plan R; log `build/RingPrototype-1.3-R.log` | BUILD SUCCEEDED 02:39–02:39:50, exit 0, only the AppIntents metadata notice. `strings … \| grep -c -- '--ring-prototype'` = **0**; `ring-fixture`/`RingPrototype` = 0. Controls: same grep on Debug `.debug.dylib` = 1; on a planted line = 1. Release exec SHA-256 `f01ee93d…4545c3`, signed without a team (build-only; not an archive, not notarized). |
| R symbol check | `nm \| swift demangle` | Release contains **no** `RingPanelController`, `RingView`, `RingInputView`, `RingFixture` or `RingPlacement` view/controller symbols. It does contain the pure, unreachable Model types (`RingInteractionState`, `RingPlan`, `RingTarget`, `RingNode`, `RingSide`, `RingHit`, `RingHold`, `RingExpansion`, `RingClock`, `RingPresentationState`), which are compiled unguarded because the hostless tests compile `Model/`. No entry point or launch literal reaches them. A production plan decides whether to guard them. |
| **T-all** full hostless suite | `build/RingPrototypeAllTests-1.3-run01.xcresult`, log `…-run01.log` | **212 passed, 0 failed, 0 skipped**, exit 0, 20 s. |
| Focused T | reused `build/RingPrototypeTests-1.2-run04.xcresult` (110/110) | Not rerun: no source change since; T-all re-executes every focused suite. |
| **B** Debug build | log `build/RingPrototype-1.3-B.log` | Succeeded, exit 0, no new warnings, no-op rebuild. |
| `git diff --check` | repository | Clean. |

**Count reconciliation:** 113 (v1.2.0 baseline) + 7 added in 1.2.1 (`CPUBatteryPairTests` 6;
`PanelMetricOptionsTests` 6→7) + 92 ring tests (`RingInteraction` 48, `RingPlacement` 23,
`RingGeometry` 16, `RingHitResolver` 4, `RingFixtureTransferHistory` 1) = **212**. Hardware probes
(`TransferReaderProbeTests` 4) ran and passed on this Mac; no tests were skipped.

T-all effects: hostless bundle (no `TEST_HOST`; compiles `Model`, `Sampling`, `Theme`, `HotKeyService`),
injected disposable defaults/data, no app launch, no samplers, updater or hotkeys started.

## Integration inspection (read-only code review, fresh agent)

| Area | Verdict | Evidence |
|---|---|---|
| Release exclusion | OK | `RingPanelController`, `RingView`, `RingMoreView` and `RingInputView` are wrapped whole in `#if DEBUG`. Launch literals appear only in `RingPanelController.swift:23-24`. Fixtures are in `RingPresentation.swift:230-313` and `StatsStore.swift:421-492`, all DEBUG. All `AppDelegate` ring wiring is DEBUG-guarded. The unguarded pure models are noted above. |
| Ordinary Strip routing | OK | The ring path is taken only when `ringLaunch != nil`. `toggleDetail`, `DetailPanelController.show(kind:stripFrame:…)` and `StatsStripView` are unchanged. `StatDetailView` defaults keep the Strip behaviour. The only Strip-side edit is `acceptsMouseMovedEvents = false`, which is the default value. |
| Carbon hotkeys | OK | The scoped Escape, Command-Comma and pin hotkeys register on `visibilityChanged(true)` and unregister on `false`. `register` unregisters first. `RingPanelController.hide()` is the single exit, guarded so it emits once, and every hide path reaches it. The Strip is unreachable in Ring mode. |
| Detail history selection | OK | Ring cards resolve through `store.resolvedDescriptor(for:)`, the same descriptor and tint as the Strip without the availability filter, on the shared store. A missing reading shows "X unavailable", never a blank card. |
| Sample lifetime | OK | `setPanelVisible` runs through the shared handler. Fixture mode skips `store.start()`, the updater and interval restarts. Ring code never writes `customPosition`. The fixture transfer root is a UUID temp directory and the real root is never touched. |
| Stale callbacks | OK | `hide()` cancels the timer and poll, removes all monitors and the screen observer, and bumps the token and generation. `fire(token:)` ignores stale tokens. Drag, Settings and display changes go through `closeEverything`. |

Concerns (no defects): (1) every fixture launch leaves an empty or small
`QuickStatsPanel-ring-fixture-<UUID>` directory in the temp folder, because it is never removed
(Debug only). This is captured in TASKS. (2) Cards are measured at summon, before process rows or
transfer history load, so a real-data card may scroll where the Strip's would fit; this is the 1.2
`ScrollView` design and is native/E1. (3) Sleep flushes the fixture controller to its temp root only.

## Not covered by automation

The following need the owner and native hardware: native hover delivery (global, local or poll),
dwell and leave feel, travel across sibling wedges, text comfort, measured real `StatDetailView`
sizes against the reserved frames, scrolling, accessibility Press with VoiceOver, edges and corners
on real displays, mixed scale, drag to a second display, display removal, and Escape or hide during
the modal drag loop. Placement tests use injected detail sizes and synthetic frames only. No
screenshots were taken in 1.3, because desktop capture or control was not in scope. The earlier
owner screenshots from 1.1 were reviewed in conversation and not stored.

## E1 owner review checklist

One finite batch. For each case, return **pass**, **fail (with what you saw)** or **skipped**.
Screenshots help for fails and for any text-comfort doubt. The batch is complete when every row
has a result; hardware you don't have is marked skipped, never passed.

| ID | Setup (fixture) | Do | Expect |
|---|---|---|---|
| R1 | `one`, `six`, `eight` | Summon; read every wedge | Labels and values horizontal, comfortable padding, no clipping, overlap or shrinking |
| R2 | `long`, `paired` | Summon; read every wedge | Worst-case and two-line values fit their wedges comfortably |
| R3 | `unavailable` | Summon; open Battery | Wedges keep their positions; card says "Battery unavailable" (no blank card) |
| R4 | `none`, `twelve` | Summon; open More (`twelve`) | `none` shows "No stats enabled" (no More target), hub drag and Settings still work; `twelve` lists all three non-favourites in More |
| H1 | `eight` + log stream | With another app frontmost, hover a wedge, pause, move on | Detail previews after a short dwell; log names the mechanism (record it) |
| H2 | `eight` | Hover wedge A, travel diagonally into its detail across wedge B | B does not take over; A's detail stays |
| H3 | `eight` | Click a wedge (held), then hover siblings | Held detail stays; sibling hover does not replace it |
| H4 | `eight` | Held: click a sibling deliberately | Detail switches to the sibling |
| H5 | `eight` | Click the same wedge again / Close / Escape, without moving | Detail closes and does not reopen until you leave and re-enter |
| H6 | `eight` | Leave the ring quickly and come back | Preview collapses after leave; re-entry behaves normally, no flicker or stuck card |
| M1 | `twelve` | Open More, move to a More item, then into its detail | More and child stay open together; crossed wedges are not selected |
| E1a | `eight` | Escape repeatedly (detail open, More open, then plain) | Closes detail, then More, then the HUD; works while pinned too |
| D1 | `eight` | Drag the hub, then reopen | Ring moves; children close; ordinary Strip position (launch without flags afterwards) is unchanged |
| D2 | `eight` | Pin; hotkey toggle; click-away; first click from another app | Pin/hotkey/click-away keep their meanings; the first click acts without a focus click |
| C1 | `--ring-prototype` alone (real data) | Open CPU, Memory, Disk, Network cards | Real process lists and transfer history; content fits or scrolls cleanly; size matches what you'd expect |
| C2 | real data | Interact with a card control (period/graph mode) on a previewed card | Card becomes held before the control acts |
| C3 | `eight` | Look at amber wedges (Memory, Temperature) | Note whether the inner-quadrilateral shading is still visible (Backlog item) |
| P1 | `eight` | Summon near each screen edge and corner | Branch picks outer ring / side list / whole list without clipping; wedge under pointer does not move |
| P2 | second display, if any | Summon on it; drag ring across displays; unplug if feasible | No clipping; children close on drag; display removal hides cleanly |
| P3 | display ≥ ~820 pt visible each way plus detail | Summon centred, open More | Full outer-ring More branch; otherwise mark the outer ring **natively untested** |
| A1 | VoiceOver on | Navigate wedges, More, Settings; Press | Each has name, value, availability, expanded state; Press matches click |
| S1 | — | Read spec "Proposed settings placement and wiring" (`specs/panel-layouts-and-appearance.md`) | Accept or redirect (separately gates later controls) |

Also record any sizing or visual corrections you want (size was deferred to here at 1.1).

## Owner results

*(pending — E1)*
