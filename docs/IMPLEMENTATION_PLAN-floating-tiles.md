# Floating Tiles — Native Prototype Plan

**Created:** 2026-11-22 · **Status:** implementation complete 2026-11-27; awaiting owner review (E1)
**Progress:** 5/6 implementation tasks complete (5.2 implemented-unverified) (5.1 added after E1 case B failed; 5.2 added for D-044); external acceptance **E1 open** — B and C to re-run on the 5.1 build ([review packet](evidence/floating-tiles-prototype.md#e1-owner-review-packet)).
Unchecked tasks are pending unless explicitly marked blocked or implemented-unverified.
This file owns task status/evidence. The [ring plan](../IMPLEMENTATION_PLAN.md) remains parked,
12/12 implemented with its own E1 open; it is not archived or superseded as evidence.

Execute using `/Users/sim/ProgrammingProjects/0-DIRECTIONS/__DIRECTIONS/commands/execute.md`.

## Goal and scope

One Debug-only, fixture-backed native HUD demonstrating overview → select CPU → switch to
Network/history → return → dismiss, using independent tile surfaces and stationary navigation.
The [spec](../specs/floating-tiles.md) owns FT-1–FT-10. All are pending; this plan maps them to
implementation and acceptance rather than copying completion boxes.

The user's “next” advances preparation to planning. Proposed sizing/order, gap-click and
keyboard defaults remain provisional, to be evaluated at E1, not recorded as accepted design.
An execute request authorizes this bounded experiment, not production rollout.

No new sampling, production preferences, ring fixes, updater/release work or public publication.
Leave the owner's review app and saved preferences alone. UI checks run in the Atlas helper
with isolated data. Read the Atlas skill and testing guide before execution; do not launch
on the owner's desktop under a generic fresh-build handoff.

## Gap analysis and interfaces

- `StatDescriptor.swift` already offers ordered enabled identities and unavailable-aware
  descriptors. `AppSettings` already accepts injected defaults, but `shared` currently uses
  standard defaults: isolation must begin before first singleton access, including Settings.
- `StatsStore` already accepts a transfer-history root and scheduling policy. Ring fixtures
  seed useful samples but disable automatic history scheduling and do not clean their root;
  tile fixtures need their own lifecycle and working period-query publication.
- `StatDetailView` contains reusable details, fixed transfer width and height limiting.
  Its `onClose` option also gates Ring presentation. Add an explicit presentation option with
  unchanged existing defaults; do not emulate Ring to get scrolling.
- `AppDelegate` already routes hotkey, Escape, pin, click-away, shutdown and updater startup.
  Tile launch must be mutually exclusive with Ring launch. Ordinary Debug/Release remain Strip.
- Existing panels intentionally never become key. Arrow/Tab navigation needs a native focus
  check; Ring's passthrough host cannot simply replace controls in an interactive detail card.
- Hostless tests compile Model/Sampling, Theme and HotKeyService, not Views/Panel/AppDelegate.
  Native focus, transparency and accessibility require separate observed helper checks.

New interfaces: `FloatingTilePlan` (frozen frames, identities, neighbour map, scroll limits),
`FloatingTileState` (overview/detail/hidden and focused identity), `FloatingTileReading`
(existing display text plus explicitly based optional usage), and a controller reporting
visibility and consuming select/return/dismiss/drag actions. Names may change without changing
the contract. No sample update may rebuild the plan or move switcher targets.

### Geometry decision for the experiment

Preserve the confirmed switcher anchor at the overview's right edge. Measure required detail
widths first; if needed, enlarge the overview footprint once at summon to accommodate the
widest detail plus 106-point switcher and 12-point gap. Freeze that footprint for the session.
This is a provisional native adaptation of the 480-point HTML baseline, not permission to
shift the switcher when a different card opens. On narrow displays, establish a readable
minimum in 1.1 and use bounded scrolling/column reduction. If the anchored layout cannot fit
without clipping, reduced type or inaccessible controls, stop and revise the spec.

## Execution schedule and ownership

Four serial waves: each extends and validates the same native interaction loop and consumes
the prior task's interface. Parallel edits to app routing, controller and singleton setup
would overlap; no safe independent implementation task is proposed. Follow execute.md's
fresh-context rules at execution time; planning itself starts no agents.

The coordinator exclusively owns AppDelegate wiring integration, `01_Project/project.yml`,
project generation, all documentation, Git operations and `build/FloatingTiles-*` resources.
Task owners own the source/test files listed below only during their wave. Never overwrite
existing dirty Ring changes. New paths below are relative to
`01_Project/Sources/QuickStatsPanel/`; test paths to `01_Project/Tests/QuickStatsPanelTests/`.

## Tasks

### Wave 1 — prove one native interaction loop

- [x] **1.1: CPU/Network overview, detail switch and return with isolated startup**
  - Depends on: none. External gates: none; starts only after execution is requested.
  - Owns: new `Model/FloatingTilePrototypeOptions.swift`, `Model/FloatingTileFixtures.swift`,
    `Model/FloatingTileLayout.swift`, `Model/FloatingTileState.swift`,
    `Panel/FloatingTilePanelController.swift`, `Views/FloatingTilesView.swift`,
    `Views/AppKit/FloatingTileControls.swift`; bounded changes to `Model/AppSettings.swift`,
    `Model/StatsStore.swift`, `Views/StatDetailView.swift`; coordinator integrates AppDelegate.
    Tests: new FloatingTileOptionsTests, FloatingTileLayoutTests, FloatingTileStateTests,
    FloatingTileIsolationTests.
  - Interface: frozen plan/state and controller callbacks above; proposed Debug argument
    `--floating-tiles-prototype` with fixture selection (not an existing command yet).
  - Success: CPU and Network can open, switch, return and dismiss in the helper with stationary
    switcher, no focus theft on summon, usable keyboard entry and explicit AppKit navigation
    controls. Settings/Quit stay reachable. Prove transparent gaps and coordinated dismissal;
    choose the smallest working panel arrangement and record why. Start with one transparent
    host and separate detail/switcher surfaces as needed, not one window per stat by default.
  - Isolation: defaults selected before any singleton read; temporary history root retained
    until flush completes and then removed. Disable samplers, updater and first-run hint in
    fixture mode; wire existing history queries so period changes settle. Fixture Settings
    writes must remain isolated. Preserve default initialization for normal launches/tests.
  - Backpressure: B and focused T below for the four new suites, plus Atlas observations of
    the named journey/focus/gap cases. Keep screenshots and actual artifact identity in evidence.
  - Stop/replan: new permission, focus theft, unreadable minimum size, broken click-through or
    leaked defaults/history. Do not build the remaining tiles until this proof passes.
  - Covers: initial FT-2–5, FT-8–10; full breadth belongs to 2.1–4.1 and E1.

### Wave 2 — complete the eleven-stat overview

- [x] **2.1: Stable hierarchy, real descriptor meanings and usage colours on fixtures**
  - **Status (2026-11-27):** complete, commit `6fa2952`. Dark appearance observed natively after
    switching the helper's System Settings → Appearance to Dark (helper restored to Light after).
    See execution log.
  - Depends on: 1.1 and its accepted plan/state interfaces. External gates: none.
  - Owns: FloatingTileLayout/Fixtures/View/Controls from 1.1; new
    `Model/FloatingTileReading.swift`; corresponding layout/reading/state tests.
  - Success: saved order drives first-large/next-two-wide hierarchy and switcher; all eleven
    stat identities, empty/one/subset cases and unavailable states work. Render configured
    primary/paired readings with width reservation. Usage basis is explicit; only meaningful
    percentages receive the spec's bands. Selection/focus remain distinct without colour.
  - Backpressure: B; focused T for layout/reading/state, including colour boundaries, reverse
    battery and neutral scales. Atlas checks eleven-stat overview, Mono/light/dark and value
    changes without movement. Freeze gap/size prototype constants; no production settings UI.
  - Covers: FT-1, FT-6, FT-7 and full-stat reachability portion of FT-2/FT-3.

### Wave 3 — complete detail, edges and accessible interaction

- [x] **3.1: All details, constrained displays, keyboard and group lifecycle**
  - **Status (2026-11-27):** complete; see execution log. Native multi-display re-clamp and live VoiceOver speech remain for E1 (F).
  - Depends on: 2.1. External gates: none.
  - Owns: FloatingTileLayout/State/Controller/View/Controls, `Views/StatDetailView.swift` explicit
    presentation adaptation, isolated fixture query plumbing; coordinator integrates AppDelegate
    visibility, Escape, pinning and display-change routing. Tests: layout/state/isolation suites.
  - Success: all existing detail content and transfer controls remain usable, including period
    switching and scoped reset confirmation on disposable data. Short/long cards share stationary
    navigation; only oversized content scrolls. Arrow navigation follows actual neighbours;
    return restores focus; VoiceOver names/value/selection/actions are exposed. Group drag and
    display re-clamp move surfaces together; hide/quit removes all panels and owned monitors.
  - Backpressure: B and focused T for affected suites; Atlas finite matrix: edge/corner and
    narrow frames, longest labels, unavailable stat, Always-show scroll bars, Reduce Motion,
    Tab/Shift-Tab/arrows/Return/Space/Escape, pinned/unpinned gap-click, drag and resummon.
    Simulated model frames do not count as native multi-display verification; record unavailable
    hardware checks separately for E1. Restore only helper settings changed by these checks.
  - Covers: FT-2–6, FT-8, FT-9. Existing Strip/Ring callers retain their defaults and behaviour.

### Wave 4 — integrated verification and review handoff

- [x] **4.1: Regression, Release exclusion and finite owner review packet**
  - **Status (2026-11-27):** complete; evidence and E1 packet in [floating-tiles-prototype.md](evidence/floating-tiles-prototype.md).
  - Depends on: 3.1. External gates: none for compilation/tests/helper inspection.
  - Owns: coordinator documentation/build results and necessary corrections returned to their
    owning source; no unrelated cleanup. Evidence: `docs/evidence/floating-tiles-prototype.md`.
  - Success: full inspected hostless suite passes; Debug and Release compile; signatures verify;
    Release has no floating prototype flag/controller symbol, with Debug as positive control.
    Review startup/isolation and shared detail/routing diffs; correct concrete scoped findings
    and rerun affected checks. Normal Strip smoke and Ring compatibility checks use only isolated
    helper instances. Record real test counts, skipped/blocked checks and exact final artifact.
  - Backpressure: B, full T, R, `codesign --verify --deep --strict` against each built bundle,
    `strings` and `nm` Release inspection with Debug control; Atlas screenshots/interaction
    evidence. Do not infer regression success from earlier 394/0 results.
  - Handoff: prepare E1 cases below against implemented controls and fixtures, with full artifact
    paths. Keep owner's existing app running. No desktop replacement or publication.
  - Covers: FT-10 and integrated evidence for FT-1–9. E1 remains open after this task.

### Wave 5 — E1 revision

- [x] **5.1: Detail beside a stationary overview (D-043)**
  - Depends on: 4.1 and the owner's E1 case B result (fail, 2026-11-27).
  - Files: `FloatingTileLayout.swift`, `FloatingTileState.swift`, `FloatingTilePanelController.swift`,
    `FloatingTilesView.swift`, `FloatingTileLayoutTests.swift`, `FloatingTileStateTests.swift`.
  - Success: overview never hides or moves; card opens on the nearest side with fallback, lined
    up with its tile, never over the core; open tile outlined; same tile again closes; switcher
    kept as a reserved column; geometry frozen at summon.
  - Backpressure: focused + full hostless T, B, R, codesign, Release exclusion.

- [ ] **5.2: Primary stays, others hide, detail opens inward (D-044)** — implemented-unverified (native look not done; see log)
  - Depends on: 5.1 and the owner interview (2026-11-27).
  - Files: `FloatingTileLayout.swift`, `FloatingTileState.swift`, `FloatingTilePanelController.swift`,
    `FloatingTilesView.swift`, `FloatingTileLayoutTests.swift`, `FloatingTileStateTests.swift`.
  - Success: clicking a primary hides the others and leaves it unmoved; detail opens toward the
    larger part of the old footprint (top/bottom edge aligned by row), flips if it does not fit,
    scrolls only if neither side fits; switcher and open outline removed; height fits content;
    same primary or Escape returns, second Escape dismisses; ~0.15 s fade honouring Reduce Motion.
  - Backpressure: focused + full hostless T, B, R, codesign, Release exclusion; Atlas look at
    CPU (left), a middle tile and a right/bottom tile.

## Backpressure commands and execution prerequisites

Before running, read master `34_testing.md`, inspect current scheme/test setup and startup
effects, and use the Atlas skill for any native UI check. No commands below ran during planning.
From `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`:

```bash
xcodegen generate
# B — compile only; never launch implicitly
xcodebuild -scheme QuickStatsPanel -destination 'platform=macOS' -configuration Debug -derivedDataPath ../build/FloatingTiles-Debug build
# T — hostless tests; use a fresh result path for every invocation
xcodebuild -scheme QuickStatsPanel -destination 'platform=macOS' -configuration Debug -derivedDataPath ../build/FloatingTiles-Tests -resultBundlePath ../build/FloatingTiles-tests-run01.xcresult test
# R — compile only
xcodebuild -scheme QuickStatsPanel -destination 'platform=macOS' -configuration Release -derivedDataPath ../build/FloatingTiles-Release build
```

Focused T adds one `-only-testing:QuickStatsPanelTests/<SuiteName>` argument per implemented
suite. Confirm actual suite names before invocation. Inspect hardware-probe tests before full T;
separate any unsafe/unsupported cases and report them rather than silently skipping them.
Preserve raw logs, producer exit status and failed result bundles; serialize shared build caches.
Native commands depend on the implemented argument parser and verified Atlas backend, not a
guessed invocation. Verify startup isolation before the first helper launch.

## External acceptance

- [ ] **E1: Owner judges floating-tile usefulness and provisional defaults**
  - Depends on: 4.1. Requires owner feedback on the exact final native artifact.
  - Owns: result rows in the evidence document. Gates final product acceptance and subsequent
    production planning; does not block implementation on the provisional defaults above.
  - Finite cases: (A) glance at eleven stats/order/size hierarchy; (B) CPU → Network → short
    detail → return with no moving switcher; (C) long detail/edge/scroll behaviour; (D) keyboard,
    dismiss/pin and gap clicks; (E) colour/Mono/unavailable readability; (F) any native display
    or accessibility cases unavailable in the helper, clearly listed as pending.
  - Record pass/fail/blocked/not run separately, with screenshots/artifact and changed-scope
    reasons for any repeat. Do not ask the owner to rerun unchanged checks already established
    by reliable helper evidence; owner review primarily decides readability and interaction fit.
  - Completion: FT-1–10 supported by integrated evidence, provisional choices accepted or scoped
    changes implemented/rechecked, and no unresolved required case. A failed critical benefit
    check triggers simplify/replan/park; do not extend into dashboard customization.

## Schedule validation and current boundary

Dependency graph: 1.1 → 2.1 → 3.1 → 4.1 → E1, no cycles or same-wave shared writers.
All FT criteria have implementation and integrated/owner evidence owners. First ready task: 1.1,
awaiting an execution request. No technical blocker is yet established; feasibility is 1.1's
explicit stop boundary. Ring E1 and 1.2.1 release gates are independent and remain open.

## Execution log

| Wave / task | Assignment | Validation / evidence | Commit / exception | Next / stop reason |
|---|---|---|---|---|
| W1 / 1.1 (2026-11-27, M4 Pro) | One fresh-context agent (single task, serial plan). Coordinator reassigned AppDelegate integration and `xcodegen generate` to it for this wave; no parallel writers. Coordinator reviewed diffs and re-ran checks in the repo. | B Debug/Release exit 0 (ad-hoc: `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`); focused hostless T `build/FloatingTiles-tests-coord02.xcresult` 88/0 (four new suites, 33 tests, + RingLayout, TransferTimeline, TransferPresentation, TransferDetailState, RingFixtureTransferHistory, RingPrototypeOptions); `codesign --verify --deep --strict` both; Release `strings`/`nm` 0 floating hits, Debug control 4. Atlas helper (agent run): summon without focus theft, open CPU, switch to Network with stationary switcher, period change settles, return, keyboard (arrows/Tab/Space/Return/Escape), pinned/unpinned gap click-through, Settings/Quit, coordinated dismissal — all pass; screenshots in `~/Library/Application Support/Atlas/runs/` (e.g. `1795792545968261000-capture.png`). Isolation: owner plist/history untouched; fixture writes only in a `$TMPDIR` file-backed suite, removed on quit. Not run: group drag (Atlas refuses a desktop drag end), VoiceOver, light/Mono (Waves 2–3). No independent review beyond coordinator diff review. | `48b9548` (Xcode 26.3 type-check annotations — prerequisite blocker found in W1, separate commit); task commit follows | Arrangement: one transparent non-activating NSPanel; tiles/detail/switcher/group bar are surfaces inside it (native click-through works, so no multi-window sync). Known gap → 3.1: when the app is already active at summon, keyboard entry needs a first click. Next: 2.1 ready. |
| W2 / 2.1 (2026-11-27, M4 Pro) | One fresh-context Sonnet agent (serial plan; no AppDelegate/project.yml edits needed). Coordinator reviewed diff, re-ran R and focused T in the repo, re-checked exclusion. | B Debug exit 0 (agent); R Release exit 0 (coordinator rebuild after final tweak, `build/w2-coord-release.log`); focused T `build/FloatingTiles-tests-w2-coord02.xcresult` 55/0 (Reading 13, Layout 18, State 9, Options 8, Isolation 7) — bands 0/49.9/50/79.9/80/100, reversed battery 100…0, neutral and unavailable. Release: 0 `FloatingTile` symbols, 0 `floating-tiles` flag strings (only the W1 `floatingTile` presentation-enum name, non-gated in `StatDetailView`); Debug positive control is in `QuickStatsPanel.debug.dylib` (4 flag strings, 1541 symbols) — the main Debug executable is a stub. `codesign --verify --deep --strict` pass. Atlas (agent, screenshots in `~/Library/Application Support/Atlas/runs/`): eleven-stat `all-hot` hierarchy CPU large / Memory+Disk wide / 8 small with bands + words (`1795794978184872000`); Mono (`1795795020602837000`); CPU→Network→return with switcher at identical coords (`1795795028160534000`, `1795795038858195000`); `all-live` value changes with identical frames (`1795795123919732000`, `1795795127592592000`); unavailable no false zero (`1795795053920110000`); empty with Move/Settings/Quit (`1795795091606325000`); subset order (`1795795108409096000`). **Not run:** dark appearance (helper light-only; per-process `-AppleInterfaceStyle Dark` had no effect, `1795795279754478000`); keyboard/click-through/drag/VoiceOver not repeated (W1 evidence stands). No independent review beyond coordinator. Debug artifact exec SHA-256 prefix `5a4714477cb2d228`. | `6fa2952` | Spec bands use fixed 50/80 thresholds, no hysteresis (spec allows reuse only where basis matches). Next: dark check (needs owner choice of method), then 3.1. |
| W2 / 2.1 dark check (2026-11-27, M4 Pro) | Coordinator, Atlas helper. | Same Debug artifact (exec SHA-256 prefix `5a4714477cb2d228`), `--floating-tiles-prototype --floating-tiles-fixture=all-hot`. `defaults write -g AppleInterfaceStyle Dark` in the helper did **not** affect the app; System Settings → Appearance → Dark did, and the open panel switched live: dark tile backgrounds, light primary/secondary text, red/yellow bands and words legible, hierarchy unchanged (`1795795901785814000`). Helper restored via Appearance → Light (global key absent again); helper cleaned up (`atlas cleanup --apply`). Stale helper System Settings (modal Open dialog from an earlier session) was quit to reach the pane. Not run: Mono in dark. | — | 2.1 complete. Next: 3.1 ready. |
| W3 / 3.1 (2026-11-27, M4 Pro) | One fresh-context agent (deep model; serial plan). Agent made two minimal AppDelegate edits (tile accessibility value; Debug-only `tilePanel.hide()` in `applicationShouldTerminate`). Coordinator reviewed diff (Strip/Ring branches unchanged; `hide()` guarded) and re-ran T, R, exclusion, codesign. | Focused hostless T `build/FloatingTiles-tests-w3-coord01.xcresult` 86/0 (FloatingTile Layout/State/Options/Isolation/Reading + TransferDetailState, TransferPresentation, TransferHistoryIntegration, RingFixtureTransferHistory); agent run w3-03 also 86/0. B Debug exit 0; R Release exit 0 (`build/w3-coord-release.log`): 0 `floating-tiles`/`FloatingTile` strings, 0 real `FloatingTile` symbols (filter OSO/SO debug-map paths containing the derived-data folder name); Debug control 8 flag strings in `QuickStatsPanel.debug.dylib`. `codesign --verify --deep --strict` both. Atlas (agent; screenshots in `~/Library/Application Support/Atlas/runs/`): summon w/o focus theft `1795796888846682000`; detail + abbreviated switcher `1795796889539535000`; keyboard/AX current `1795796911137343000`; Network detail, stationary switcher `1795796929482764000`; period switch `1795796939786898000`; reset confirm/complete on temp-root fixture `1795796944953945000`/`1795796965852068000`; Escape/Tab/Shift-Tab/Space/focus-restore via AX dumps; W1 gap closed (app active → keyboard at once) `1795796994171027000`; bottom-right clamp `1795797024481770000`; pinned gap click `1795797039637092000`, unpinned dismisses (windows check); group drag `1795797060165623000`; simulated 420×560 frame scrolling overview `1795797071838482000`; oversized card scroll vs short card `1795797089787171000`/`1795797101003258000`; arrow scroll-into-view `1795797110772383000`; Always-show scroll bars (per-process arg) `1795797122060132000`; unavailable GPU `1795797138099108000`; Settings `1795797164937274000`; Quit removes panel/process/temp root. **Not run natively:** Reduce Motion — tile/detail code has no animations (grep: no `withAnimation`/`.animation`/`animator`/`NSAnimationContext`/`.transition`), so accepted by inspection; helper System Settings was in use by another session. Live VoiceOver speech (AX tree verified). Display-change re-clamp unit-tested only (native multi-display → E1 F). No helper settings changed. **Incident:** two untargeted keys (Down, Return) landed in another session's Waveform Cue window in the shared helper; agent then gated untargeted keys on QuickStatsPanel being active (Atlas `key --app` refuses non-activating panels). | task commit (this wave) | Provisional: switcher abbreviations Temp/Load; display change re-clamps or dismisses if footprint no longer fits; overview scrolls only on constrained displays, below ~402 pt `fits` false. Next: 4.1 ready. |
| W4 / 4.1 (2026-11-27, M4 Pro) | Coordinator, serial (coordinator-owned task; no agent). | xcodegen, B Debug, R Release exit 0; full hostless T `build/FloatingTiles-tests-w4-full01.xcresult` **462/0, 0 skipped**; codesign strict pass on Debug, ad-hoc Release and Developer ID Release; Release 0 prototype strings/symbols, Debug control 8/1832. Diff review of AppDelegate/AppSettings/StatsStore/StatDetailView: no findings. Atlas: Release (Developer ID copy) Strip live launch `1795797678928534000`; Ring `--ring-fixture=six` render `1795797708115535000`. **Not run:** Release Strip detail (Atlas treats first-run hint as a dialog), Ring wedge click (Atlas could not identify the front app in the shared helper). **Finding:** ad-hoc Release cannot launch (hardened runtime library validation rejects Sparkle) — signing-environment limit, recorded in MACHINES.md. Debug artifact byte-identical to 3.1. | 4.1 commit | Plan implementation complete. Next: owner E1 using the packet. |
| W5 / 5.1 (2026-11-27, M4 Pro) | Coordinator, serial (small coupled change across four files; no agent). No Atlas (owner instruction for this session). | Focused T `build/FloatingTiles-tests-sides-run01.xcresult` 43/0 (Layout 33, State 10; new: nearest side, tile alignment, fallback, clamped tall card, core unchanged by card placement, screen↔core conversion, same-tile close). Full hostless T `build/FloatingTiles-tests-sides-run02.xcresult` **469/0**. B Debug, R Release exit 0; codesign strict Debug pass; Release 0 `floating-tiles-prototype` strings, 0 `FloatingTile` symbols; Debug control 1. **Not run:** any native/visual check (no Atlas) — owner re-runs E1 B and C. | 5.1 commit | Next: owner E1 B/C on the rebuilt Debug artifact (quit the running prototype first). |
| E1 feedback (2026-11-27) | Owner, after 5.1 | Owner clarified the intended model (other primaries hide; detail opens inward). 5.1 does not match; design discussion before a new task. | — | Next: owner discussion, then revise D-043/spec and add a task. |
| W5 / 5.2 (2026-11-27, M4 Pro) | One fresh-context agent (single coupled task); coordinator reviewed diff and re-ran checks. | Agent focused T `build/FloatingTiles-tests-inward-run01.xcresult` 47/0. Coordinator full hostless T `build/FloatingTiles-tests-inward-full02.xcresult` **473/0/0**; B Debug, R Release exit 0; codesign strict both pass; Release 0 prototype strings, 0 `FloatingTile` symbols; Debug control 1. Atlas: overview renders with no switcher (`~/Library/Application Support/Atlas/runs/1795802729214439000-capture.png`); **detail open/side/fade not verified** — another session was active in the shared helper and its clicks dismissed the non-activating panel within seconds; one right-click of ours landed in that session's Waveform Cue window, then testing stopped and the helper was cleaned up. Agent-noted trade-offs: neither-side-fits keeps width and may overlap the primary by a few points; details that would hit the group bar start below it (bottom alignment lost); primaries fading out are still clickable for 0.15 s (ignored by state). | `7386ec9` | Next: native look (helper when quiet, or owner E1 B/C on the Debug artifact). |
