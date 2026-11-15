# Gauge ring — fix pass 2

2026-11-15, M1 Max. Owner requested execution of F5–F8 after E1 Step 3.

## Changes and ownership

- F5: fresh `arc_spacing` agent owns RingArcLayout and its regression test. Every entry receives
  equal extra angle; intrinsic needs, separator/group gaps and overflow fallback are preserved.
- F8: fresh `heat_fill` agent owns the shared RingGaugeFill renderer. One radial gradient replaces
  ten slices in wedges, More entries and sub-ring segments. Gradient anchors follow the selected
  fill scale; the ring centre can lie outside the arc panel. Smooth interpolation between anchors
  replaces the old stepped approximation.
- F6/F7: coordinator owns both panel controllers and PanelDragTracker. No window-server drag;
  Strip returns consumed mouse-up to SwiftUI, preserving repeated gestures and final-position
  persistence. Hub and whole-list header retain drag begin/end/replanning. The arc window shadow
  is disabled; the 2% hit fill stays in place. Its faintness needs visual review.
- Fresh read-only `review_drag` agent found no concrete regression. It specifically checked
  native movability, mouse-up delivery, position persistence, ring replanning and hit interception.
  Reentrant SwiftUI mouse-up delivery still requires hands-on validation.

## Automated evidence

Working directory: `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`.
Generated project with `xcodegen generate`. Inspected test scheme: hostless, no app entry point,
no TEST_HOST; fixture readers/clocks/manual schedules and disposable storage/defaults. No app,
updater, global hotkey or live profile is started by these tests. Builds and tests ran serially.

- Debug build: `build/GaugePrototype-Fix2-B-run02.log`, exit 0. Derived data `build/GaugePrototypeFix2`.
  Run01 failed before compilation because sandbox blocked external Swift caches; escalated run02
  succeeded. Existing Sparkle checkout `build/SparklePackages` reused.
- Regression red: `build/GaugePrototypeFix2-red-run01.xcresult`, xcodebuild exit 65; one test,
  18 expected failed assertions against old RingArcLayout. Fixed source restored in `finally`.
- Full suite: `build/GaugePrototypeFix2-all-run01.xcresult`, exit 0, **391 tests, 0 failures**.
  Raw log `build/GaugePrototype-Fix2-all-run01.log`; derived data `build/GaugePrototypeTests`.
- Absolute-path deep strict signature verification passed. Relative-path codesign attempts
  returned “host has no guest”; the absolute-path verification is the valid result.
- Release build-only check: `build/GaugePrototype-Fix2-R-run01.log`, exit 0. Release binary
  has 0 `--ring-` lines; Debug control has 4. Prepared distribution artifacts were not touched.
- `git diff --check` passed.

Reproduction commands (run from the working directory above):

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/GaugePrototypeFix2 -clonedSourcePackagesDirPath build/SparklePackages build
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/GaugePrototypeTests -clonedSourcePackagesDirPath build/SparklePackages -resultBundlePath build/GaugePrototypeFix2-all-NEW.xcresult test
```

## Preserved acceptance artifact

Folder: `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/GaugePrototypeFix2/Build/Products/Debug`

App: `QuickStatsPanel.app`, Debug arm64, 1.2.1 (1201). Built with Developer ID Application:
GREGOR MÜLLER (FDMSRXXN73). Verified 2026-11-15 around 17:37 UTC.
Executable SHA-256: `a71f4be494ce8c82869aa5265ef95fdd2a073a9a0e395a8e322b755caa12471f`.
Debug dylib SHA-256: `f56189960968653ca2164593193407db8761c8f5daf80bdeb093b2e711732c25`.
Durable local Git-ignored build, not synced by Git. The older GaugePrototype artifact remains intact.

## Finite affected-row recheck — not run

After gracefully quitting the old prototype, launch this exact artifact for Ring review:

```sh
open -n -a /Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/GaugePrototypeFix2/Build/Products/Debug/QuickStatsPanel.app --args --ring-prototype --ring-fixture=eight --ring-parts=typical
```

| Case | Action | Expected |
|---|---|---|
| F5 / B3 | Open Disk and Temperature arcs; repeat in Small and Large using `--ring-size=small` or `--ring-size=large` | Less exaggerated span differences; labels/captions readable, group gaps intact. Total segment widths need not be identical |
| F7 / B3 | Open Disk arc, leave segments unhovered, then hover each; click the empty caption slot | No shadow box; captions appear correctly; empty-slot click does not reach the app below or dismiss HUD |
| F8 | Inspect Temperature wedge and arc in default area fill, then relaunch with `--ring-fill=linear` | Smooth continuous heat ramp, no slice seams, sensible fill edge and hue progression |
| F6 / G4, D1, B11, P1 | With arc/card open, drag hub repeatedly and hold at screen edges; repeat Small/Large and another display if available | No Space switch; children close; ring remains usable and inside available screen bounds |
| F6 / Strip | Quit prototype and launch the same app without arguments; perform several drags from padding and tiles, hold at edges, then click a tile and gear | No Space switch or stuck gesture; clicks still work; At cursor still re-homes on summon, fixed-position behavior unchanged |
| F6 / list | If a small display naturally triggers whole-list fallback, drag its header repeatedly and at edges | No Space switch; list stays usable and details reopen. If unavailable, record not run; no force-list launch option exists |

Return pass/fail per case and screenshots of any visual defect. Complete only when affected
cases pass or receive explicit scoped deferral; automated tests do not close E1. Remaining E1 rows,
S1/Q1–Q9, corrected CPU screenshots, Disk rim verdict and saved-settings confirmation stay open.
Release Strongbox/updater/upgrade gates are separate and unchanged.
