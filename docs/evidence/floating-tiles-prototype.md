# Floating Tiles Prototype: Integrated Evidence and E1 Review Packet

**Task:** 4.1 in [the floating-tile plan](../IMPLEMENTATION_PLAN-floating-tiles.md) · **Date:** 2026-11-27 · **Mac:** M4 Pro
**Source:** `main` at `eeed0ca` (code identical to the 3.1 commit `0925d1d`; later commits are docs only).
**Spec:** [floating-tiles.md](../../specs/floating-tiles.md) (FT-1 to FT-10, defaults provisional).
**Status:** 4.1 complete. **E1 is open** and waits for owner review.

## Artifacts

| Build | Full folder path | App | Identity |
|---|---|---|---|
| Debug (prototype, for E1) | `/Users/simpro/ProgrammingProjects/1-macOS/QuickStatsPanel/build/FloatingTiles-Debug/Build/Products/Debug` | `QuickStatsPanel.app` 1.2.1 (1201) | ad-hoc signed; stub executable SHA-256 prefix `2fdd812740be3acb`, `QuickStatsPanel.debug.dylib` `953fcd7a03cc4b0e` (same as 3.1) |
| Release, ad-hoc | `/Users/simpro/ProgrammingProjects/1-macOS/QuickStatsPanel/build/FloatingTiles-Release/Build/Products/Release` | `QuickStatsPanel.app` | executable `a0c730f0d67e65a1`; **does not launch** (see Findings) |
| Release, Developer ID (local only) | `/Users/simpro/ProgrammingProjects/1-macOS/QuickStatsPanel/build/FloatingTiles-Release-DevID/Build/Products/Release` | `QuickStatsPanel.app` | team FDMSRXXN73, hardened runtime, not notarized or published; executable `ffe6100319448ea5` |

None of these was launched on the owner's desktop. Helper runs used copies.

## Regression and exclusion (4.1)

Logs and results under `/Users/simpro/ProgrammingProjects/1-macOS/QuickStatsPanel/build/`.

| Check | Command / source | Result |
|---|---|---|
| Project generation | `xcodegen generate` (`w4-xcodegen.log`) | exit 0 |
| B: Debug build | ad-hoc flags `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` (`w4-debug.log`) | exit 0 |
| R: Release build | same flags (`w4-release.log`); Developer ID variant (`w4-release-devid.log`) | both exit 0 |
| T: full hostless suite | `FloatingTiles-tests-w4-full01.xcresult` (`w4-test.log`) | **462 passed, 0 failed, 0 skipped** (`xcresulttool` summary). The target is hostless (no `TEST_HOST`); `TransferReaderProbeTests` only reads route/IOKit counters. |
| Signatures | `codesign --verify --deep --strict` on all three bundles | all pass |
| Release exclusion | `strings -a` and `nm -a` on both Release executables (debug-map paths that contain the derived-data folder name filtered out) | 0 `floating-tiles` strings, 0 `FloatingTile` strings, 0 `FloatingTile` symbols |
| Debug control | same on `QuickStatsPanel.debug.dylib` | 8 flag strings, 1832 symbols |

**Diff review (startup/isolation, shared detail, routing).** Reviewed `AppDelegate`, `AppSettings`,
`StatsStore` and `StatDetailView` from `48b9548` to `HEAD`. All tile routing, fixture store,
isolated defaults and termination cleanup are inside `#if DEBUG`; Release `AppSettings.launchDefaults()`
returns `.standard`. Both prototype flags together: tiles are ignored and Ring runs (options parser
and `AppDelegate` agree). `StatDetailView`'s standard path is unchanged (`usesReservedFrame` equals
the old `onClose != nil` test, and the outer width frame only differs for floating-tile scrolling).
`publishesTransferQueriesOnSelection` defaults to false. No concrete findings, so no source changes.

**Helper smoke (Atlas, isolated helper account).**

| Case | Evidence (`~/Library/Application Support/Atlas/runs/`) | Result |
|---|---|---|
| Release Strip launch (Developer ID copy): live samplers, twelve tiles, first-run hint | `1795797678928534000-capture.png`, `1795797695677880000-capture.png` | pass |
| Release Strip detail card | — | **not run**: Atlas treats the first-run hint card as a dialog and refuses clicks behind it |
| Ring compatibility: Debug `--ring-prototype --ring-fixture=six` launches and renders six wedges with Settings | `1795797708115535000-capture.png` | pass |
| Ring wedge interaction | — | **not run**: Atlas could not identify the front app in the shared helper (another session active) and refused clicks; the Ring code paths are unchanged by the diff review |
| Cleanup | `atlas cleanup --apply`; no `QuickStatsPanel-*` temp roots in the helper | pass; the helper's own pre-existing QuickStatsPanel preferences kept |

Tile behaviour was not re-run in 4.1: the Debug artifact is byte-identical to the one checked in
Waves 1–3, so their evidence stands (see the plan's execution log for screenshot IDs).

### Findings

- **Ad-hoc Release cannot launch on this Mac.** Release enables hardened runtime; with ad-hoc
  signing, library validation rejects the embedded Sparkle framework (`Library not loaded:
  @rpath/Sparkle.framework … not valid for use in process`). A Developer ID-signed local build
  launches. This is a signing-environment limit on the M4 Pro (no Apple Development identity), not
  a code regression; recorded in `MACHINES.md`.

## FT coverage

| FT | Integrated evidence | Remaining for E1 |
|---|---|---|
| FT-1 | W2 eleven-stat hierarchy, live values without movement | owner: readability of order/sizes (A) |
| FT-2 | W1/W3 detail + switcher, Settings/Quit | owner fit (B) |
| FT-3 | W1–W3 stationary switcher across short/long cards (identical coordinates) | owner fit (B) |
| FT-4 | W1/W3 return, focus restore, Escape/hotkey/click-away | owner fit (B, D) |
| FT-5 | W3 edge clamp, simulated narrow frame, oversized-card scroll | native multi-display (F) |
| FT-6 | W2 unavailable / empty; W3 unavailable GPU | owner readability (E) |
| FT-7 | W2 band unit tests (0/49.9/50/79.9/80/100, reversed battery, neutral); Atlas light/dark/Mono | owner readability (E) |
| FT-8 | W1/W3 keyboard matrix, no focus theft, AX tree | live VoiceOver speech (F) |
| FT-9 | W1/W3 gap click-through, group drag, coordinated dismiss/quit, temp-root removal | owner fit (D) |
| FT-10 | 4.1: 462/0 suite, Release exclusion, Release Strip launch, Ring render | — |

## E1 owner review packet

**Setup (owner-operated).** The artifact is on the M4 Pro. On another Mac, build Debug there first.

1. Quit your installed QuickStatsPanel first. The prototype has the same bundle identifier and
   hotkey (Control-Option-Command-Q); with both running, the hotkey goes to whichever registered first.
2. In Terminal:
   `/Users/simpro/ProgrammingProjects/1-macOS/QuickStatsPanel/build/FloatingTiles-Debug/Build/Products/Debug/QuickStatsPanel.app/Contents/MacOS/QuickStatsPanel --floating-tiles-prototype --floating-tiles-fixture=all-hot`
3. The prototype uses a temporary preferences file and history folder and deletes both when you
   quit it (Quit in the group bar or Command-Q). Your saved settings and history are not used.
   Fixture data is made up; nothing is sampled.
4. Relaunch with another fixture by changing the last argument: `all`, `all-reversed`, `all-hot`,
   `all-live`, `subset`, `one`, `empty`, `unavailable`, `cpu-network`, `network-cpu`. Optional:
   `--floating-tiles-edge=top-left|top-right|bottom-left|bottom-right`.
5. The first hotkey press after launch can be ignored; press it again.

| Case | Fixture | Do | Judge | Result |
|---|---|---|---|---|
| A | `all-hot`, then `all-live` | Summon; look for about five seconds | Are eleven stats, their order and the large/wide/small sizes quick to read? Do values change without anything moving? | |
| B | `all` | Click CPU, then Network in the switcher, then a short card such as Uptime, then return | Does the switcher stay still, and does the detail size feel right? | **Fail (2026-11-27, owner):** detail replaced the overview; owner wants the overview to stay and the card to open beside the clicked tile. Revised per D-043; re-run B and C on the new build. |
| C | `all` with `--floating-tiles-edge=bottom-right` | Open Network (long card), scroll it, change its period | Is scrolling only where needed, and are controls reachable? | |
| D | `all` | Tab, Shift-Tab, arrows, Return, Space, Escape; click a gap pinned (Control-Option-Command-P) and unpinned; drag the group bar | Is the keyboard and dismissal behaviour what you expect? | |
| E | `all-hot`, `unavailable`, `empty`; then the Mono theme in Settings, in Light and Dark | Look at colours, words and unavailable tiles | Readable without relying on colour? No false zeros? | |
| F | any | Only if you have them: a second display (move or unplug while shown); VoiceOver | Pending: the helper cannot test these | |

Record pass / fail / not run per row, with a note. Already established by helper evidence (no need
to repeat): no focus theft on summon, gap click-through, temp data removed on quit, Release excludes
the prototype. A failed critical benefit check (A or B) means simplify, replan or park; it does not
extend into dashboard customisation.
