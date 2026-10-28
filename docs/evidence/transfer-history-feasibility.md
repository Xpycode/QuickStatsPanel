# Transfer history feasibility — 2026-10-20

Task 1.1 passed. Source contract: `01_Project/Sources/QuickStatsPanel/Model/TransferObservation.swift`.
Host: current M1-Max workspace, macOS/Xcode local SDK; this is current-Mac evidence only.

The bounded headless read-only route probe validated 25 RTM_IFINFO2 records and seven active
physical links, with paired eight-byte counters. The SDK/probe uses NET_RT_IFLIST2 and validates
message bounds/version before unaligned loads. A standalone read showed an existing counter
beyond 4 GiB; exact hardware IDs, IPs and lifetime values are not retained in history.

IOKit probe validated two distinct physical drivers with complete eight-byte read/write counters
and no driver ancestor stacking. Ten Virtual Interface layers were excluded; nine were explicitly
file-backed images. Distinct registry IDs alone would have double-counted backing I/O. The reader
contract uses public provider Protocol Characteristics, an explicit physical-type whitelist and
recognized physical locations; virtual/File/RAM layers are excluded, unknown metadata is partial.
No unobserved multipath/RAID topology, real sleep/reconnect or hot-plug claim is made.

Packed aggregate records are 40 bytes, without persisted source IDs. At four ordinary samples
plus at most one admitted reset boundary per second per stat, the maximum is 432,001 intervals
per stat including one retention edge. Day payload is 34,560,080 bytes. Proposed disk allowance
is 38,620,592 bytes including segment headers, current/prior metadata, active/temp/quarantine
allowances. Combined five-minute active payload plus two 4 KiB headers is 128,352 bytes, below
128 KiB. The fixture allocated the full retained array and checked actual stride/headroom.
This is a representation proof; actual integrated repository memory/disk measurement remains 3.1/6.1.
Avoid full-day copies and copy-on-write snapshots during mutation.

Independent fresh-context reviewer found two issues, both fixed: the original reset allowance
exceeded combined active size, and arbitrary nonempty provider types were accepted as physical.
No further paired-accounting fault was found. Review is not runtime lifecycle/storage validation.

## Executed checks

Working directory: `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`.
Hostless unit-test bundle compiles model/sampler dependencies without AppDelegate/@main/TEST_HOST.
Fixtures use virtual timestamps and in-memory counters; probe reads current counters only.
No app launch, traffic workload, device changes, standard preferences or live history writes.

`xcodegen generate` succeeded. Initial sandbox accounting run failed (exit 133): Swift macros and
Xcode distributed-notification/test services were blocked by sandbox restrictions. Log retained at
`/tmp/qsp-transfer-run01-accounting.log`; no product change was made for this environment failure.
Retry outside sandbox succeeded, exit 0, **15 tests, zero failures**:

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun01 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -resultBundlePath build/TransferHistoryRun01AccountingRetryTests.xcresult -only-testing:QuickStatsPanelTests/TransferAccountingTests test
```

Log: `/tmp/qsp-transfer-run01-accounting-retry.log`. Structured result:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun01AccountingRetryTests.xcresult`.

After registering the probe file with XcodeGen, read-only hardware/parser tests succeeded outside
sandbox, exit 0, **3 tests, zero failures/skips**:

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun01 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -resultBundlePath build/TransferHistoryRun01ProbeTests.xcresult -only-testing:QuickStatsPanelTests/TransferReaderProbeTests test
```

Log: `/tmp/qsp-transfer-run01-probe.log`. Structured result:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun01ProbeTests.xcresult`.
`git diff --check` passed at this checkpoint. These were intermediate test builds; no launch.

## Phase 1 sampler and timeline validation

Task 2.1: per-source readers use snapshot-consistent RTAX_IFP network identity and positive physical
provider classification; serial driver owns timer/read/accounting/start/stop/reset. Reset boundary
read precedes its marker; rejected/duplicate/same-time actions do not change counters. Generation
identity is attached to live callbacks. Actual adapter smoke confirmed a valid boot UUID/continuous
clock and seven network/two disk paired sources outside the Codex shell sandbox. Shell-only clock
probe was blocked by sandbox; product code was not changed for that environment restriction.

Task 2.2: pure timeline keeps bounded immutable five-minute chunks and independent cumulative epochs.
Snapshot slices share storage; a persisted per-segment offset places older-boot history without
copying a day. Independent review/harness found and fixed restore fragmentation/cumulative loss,
slot boundary byte loss at UInt64.max, impossible reboot aging, immediate fresh-generation reset,
full-day temporary allocations and extreme finite clock-anchor overflow. Fixtures reproduce these
cases. Reviewer also checked 20,000 random maximum-byte queries and 50,000 targeted boundary queries.

Working directory and signing/effects class remain as above. Regenerated project and executed:

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun02 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -resultBundlePath build/TransferHistoryRun02Tests.xcresult -only-testing:QuickStatsPanelTests/NetworkSamplerTests -only-testing:QuickStatsPanelTests/TransferSamplerTests -only-testing:QuickStatsPanelTests/TransferAccountingTests -only-testing:QuickStatsPanelTests/TransferReaderProbeTests -only-testing:QuickStatsPanelTests/TransferTimelineTests test
```

Exit 0, **51 tests passed**: Network 7, Sampler 10, Accounting 15, Probe 4 (no skips), Timeline 15.
Log `/tmp/qsp-transfer-run02-tests.log`; structured result:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun02Tests.xcresult`.
The final network reader fix removed the separate name lookup race. Affected checks reran:

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun02 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -resultBundlePath build/TransferHistoryRun02RouteTests.xcresult -only-testing:QuickStatsPanelTests/NetworkSamplerTests -only-testing:QuickStatsPanelTests/TransferSamplerTests -only-testing:QuickStatsPanelTests/TransferReaderProbeTests test
```

Exit 0, **22 tests passed**: Network 8, Sampler 10, Probe 4 (no skips).
Log `/tmp/qsp-transfer-run02-route-tests.log`; structured result:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun02RouteTests.xcresult`.
No app launch or UI interaction; these remain intermediate test builds. Broader real-device/UI
claims remain E1. Long-lived controller must retain reset admission across sampler replacements.

## Phase 2 presentation validation

Task 3.2 passed eight hostless tests: unsigned max/units/nonfinite handling, distinct direction
markers, partial/missing coverage, boundary estimate disclosure, locale/date and save/recovery
states, overflow, revision-gated independent peak memory and reset confirmation/pending/cancel.
Coordinator review corrected an invented 1 B/s idle peak; idle now displays a true zero. Graph
compilation used the real Theme and app wiring. Tests do not establish pixels, focus or native
control behavior; those remain E1.

From `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`, after `xcodegen generate`:

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun03 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -resultBundlePath build/TransferHistoryRun03PresentationTests.xcresult -only-testing:QuickStatsPanelTests/TransferPresentationTests test
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun03 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

Both exit 0; eight tests passed. Logs `/tmp/qsp-transfer-run03-presentation-tests.log` and
`/tmp/qsp-transfer-run03-build.log`. Structured result:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun03PresentationTests.xcresult`.
Intermediate compilation artifact:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun03/Build/Products/Debug/QuickStatsPanel.app`.
This is not the integrated user-testing artifact and was not launched. Final runnable build and
launch preflight remain task 6.1. Repository source/tests were frozen for compilation; persistence
tests were not executed by this selected check. No app startup or live-profile/storage writes.

## Phase 2 repository validation

Task 3.1: versioned bounded packed segments/checkpoints, current/prior atomic recovery, per-chunk
checksums, protected-reference GC, bounded quarantine, immutable-file reuse and injected storage
roots. Payload/rename/directory ordering uses macOS full-sync barriers. Actual physical power loss
was not exercised; deterministic crash injection establishes app-crash transaction ordering.
Independent reviewer reproduced and confirmed fixes for post-commit cleanup status, oversized
future-version preservation, unreadable-current fallback, invalid sealed watermark bounds and
excess inventory preserving recoverable cumulative state. Decoder/filename/resource bounds and
parent-directory synchronization reviewed. No unresolved named finding remained.

From `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`:

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun03 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -resultBundlePath build/TransferHistoryRun03PersistenceTests.xcresult -only-testing:QuickStatsPanelTests/TransferPersistenceTests test
```

Exit 0, **17 tests passed** in 15.3 s. All storage paths were unique disposable test directories;
no app startup, live history/preferences or hardware manipulation. Raw log:
`/tmp/qsp-transfer-run03-persistence-tests.log`. Structured result:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun03PersistenceTests.xcresult`.

Official worst-day fixture, 864,000 records (both stats, periodic plus reset boundaries):

| Measurement | Bytes |
|---|---:|
| Packed day | 34,560,000 |
| Final logical files | 34,734,336 |
| Final allocated files | 35,545,088 |
| Peak allocated, including prior and pending | 35,737,600 |
| Maximum active checkpoint (payload plus references/metadata) | 191,984 |
| Normal 30-second checkpoint | 83,984 |
| Saving resident increment | 47,857,664 |
| Loading resident increment | 5,832,704 |
| Combined history resident increment | 53,690,368 |

Disk and incremental memory are below 64 MiB. Combined active *interval payload* plus planned
headers remains below 128 KiB; whole checkpoint includes bounded references/metadata and is below
256 KiB. Sealed-file mtime remains unchanged across another checkpoint, proving no full-day rewrite.
Per-segment autorelease pools prevent decoded temporary data accumulating across a day. Isolated
owner/reviewer logs/harnesses under `/tmp` are supplemental; official values above are canonical.

## Phase 3 lifecycle validation

Task 4.1: dedicated serial history owner loads before FIFO buffered events, admits fresh runs,
rejects stale callbacks, coalesces immutable range summaries, checkpoints 30 seconds from the first
dirty observation and confirms resets only after matching durable watermarks. Recovery warnings
remain visible while current data is dirty. StatsStore keeps one owner across interval restarts,
checks live run/sequence on MainActor and stops only transfer timers across sleep. Wake seeds new
generations; a three-second fixture proves explicit lifecycle gaps below automatic delay rejection.
AppDelegate drains transfer readers/flushes off-main and schedules an idempotent two-second quit
reply deadline. This NSApplication deadline is source-reviewed, not automatically executed.

Independent reviewer found/fixed 1-second maintenance quantization could delay the dirty save to
31 seconds; a dedicated deadline now schedules from first-dirty/last-save-attempt. No unresolved
blocking source finding. Eleven lifecycle fixtures include blocked-load events, duplicate recovery,
old run rejection, ordered/two-stat/immediate reset, cross-replacement throttling, unsaved reset,
30-second failure/retry cadence, async slow flush, sticky warning and coalesced period selection.

From `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`, after XcodeGen:

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun04 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -resultBundlePath build/TransferHistoryRun04LifecycleTests.xcresult -only-testing:QuickStatsPanelTests/TransferLifecycleTests -only-testing:QuickStatsPanelTests/TransferAccountingTests -only-testing:QuickStatsPanelTests/TransferTimelineTests -only-testing:QuickStatsPanelTests/TransferPersistenceTests -only-testing:QuickStatsPanelTests/TransferPresentationTests test
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun04 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

Both exit 0. **66 tests passed** (11 lifecycle, 15 accounting, 15 timeline, 17 persistence,
8 presentation). Logs `/tmp/qsp-transfer-run04-lifecycle-tests.log`, `/tmp/qsp-transfer-run04-build.log`.
Structured result:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun04LifecycleTests.xcresult`.
Intermediate artifact:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun04/Build/Products/Debug/QuickStatsPanel.app`.
No launch, NSApplication startup, hotkeys, live storage/preferences or desktop interaction.
Root presentation follow-up for 5.1 adds seconds to displayed timestamps so reset within one minute
changes visibly; its new fixture is pending the affected 5.1/presentation check.

## Phase 3 detail-card validation

Task 5.1 adds native segmented period selection and scoped inline reset actions following the
existing refreshed AppKit coordinator bindings. Fixed transfer content width is 260 pt (284 pt
including padding), with the existing 220×44 plot. Loading, coverage, save/error and confirmation
slots reserve height. Period mismatch displays loading for graph/period totals, preserving current
cumulative state. Network legacy rows reserve configured slots through disconnect/reconnect and
truncate long metadata with full help; all-hidden legacy rows still expose the transfer controls.
Other-stat detail rendering and the panel controller remain unchanged. Coordinator source review
confirmed no activation/alert or app-shell changes. Native pixels, focus and click/keyboard actions
are E1, not proven by compilation or pure state tests.

Root added seconds to localized timestamps and a regression for visibly distinct resets within
one minute. Store injection supports disposable history roots/clocks/manual scheduling and a
manual boundary action so the final journey can enter the same selection/confirmation facade
without starting unrelated hardware samplers or standard preferences. Defaults preserve runtime.

From `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`, after XcodeGen:

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun05 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -resultBundlePath build/TransferHistoryRun05DetailTests.xcresult -only-testing:QuickStatsPanelTests/TransferDetailStateTests -only-testing:QuickStatsPanelTests/TransferPresentationTests -only-testing:QuickStatsPanelTests/PanelMetricOptionsTests -only-testing:QuickStatsPanelTests/ExtendedMetricOptionsTests -only-testing:QuickStatsPanelTests/StatHistoryTests -only-testing:QuickStatsPanelTests/NetworkSamplerTests test
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun05 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

Both exit 0; **37 tests passed** (5 detail state, 9 presentation, 6 panel options, 6 extended
options, 3 existing history, 8 network). Logs `/tmp/qsp-transfer-run05-detail-tests.log` and
`/tmp/qsp-transfer-run05-build.log`. Structured result:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun05DetailTests.xcresult`.
Intermediate artifact:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun05/Build/Products/Debug/QuickStatsPanel.app`.
No launch/app control/live storage writes. The final task will create a separate integrated artifact
for user testing; no intermediate build is handed off as the final accepted feature.

## Final integration validation — 2026-10-21

Task 6.1's three journeys enter the actual StatsStore selection/confirmation facade, manual real
sampler accounting and the disposable on-disk repository. The main fixture proves separate
100,000,000/20,000,000 Network and 80,000,000/40,000,000 Disk bytes and elapsed rates; 0.25/5 s
cadence replacement; fresh-store reopen without lifetime-counter backfill; cancelled/confirmed
scoped Network/Disk resets with distinct persisted start times; and >24-hour expiry preserving
cumulative epochs. Additional journeys prove continued collection through save failure/retry and
truthful older-checkpoint recovery warnings. Fixtures do not operate native controls or launch apps.

A bounded optimized synthetic benchmark at 864,000 intervals measured both-stat queries at
0.05 ms (minute), 2.23 ms (hour), 40.09 ms (day), mean of ten iterations. Coordinator fixed a
confirmed performance issue: continuous selected-day queries would keep running after dismissal.
Only open transfer cards now receive continuous expensive summaries; collection/checkpoints remain
active while hidden, and opening immediately refreshes the selected range. A lifecycle fixture
proves hidden query suppression plus continued durable collection. Independent visibility review
found no blocking issue; AppDelegate visibility wiring is source-reviewed, while the journey's
forced barriers intentionally bypass visibility gating. Actual native facade behavior remains E1.
Benchmark source/binary: `/tmp/qsp-query-bench-20261020` (no hardware or live storage).

From `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`, after XcodeGen:

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun06 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -resultBundlePath build/TransferHistoryRun06AllTests.xcresult test
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun06 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

Both producer exits **0**; **113 tests passed, zero failures**, no hardware skips. Full test
execution/teardown completed. Final source edits preceded the test/build; later changes are docs.
Raw logs `/tmp/qsp-transfer-run06-all-tests.log`, `/tmp/qsp-transfer-run06-final-build.log`.
Structured result:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun06AllTests.xcresult`.

Final resource remeasurement: logical 34,734,336 B, allocated 35,545,088 B, peak allocated
35,737,600 B; saving resident increment 39,141,376 B, loading increment 7,553,024 B, combined
history increment **46,694,400 B**. Normal checkpoint 83,984 B; max active checkpoint 191,984 B.
All remain below their budgets. Real adapters again validated clock/boot identity, seven network
and two physical disk sources, with ten virtual layers excluded. Broader hardware remains E1.
`git diff --check` passed. Existing preferences source and AGENTS/CLAUDE baseline hashes unchanged.

### Exact final artifact and launch result

Folder: `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun06/Build/Products/Debug`.
App: `QuickStatsPanel.app`; bundle `com.sim.QuickStatsPanel`, version 1.1.0/build 1100, LSUIElement true.
Executable SHA-256: `0271bcd38e82224d65e557c1d8b481937ac7b99592eb83a78209913e45b0a6e5`.

Initial handoff deferred launch while older PreferencesRedesign PID **52821** was running.
User subsequently explicitly requested “quit and launch please”. Verified the old executable path,
requested graceful termination through NSRunningApplication, and confirmed PID 52821 exited.
`open -n` of the exact final artifact returned exit 0; NSRunningApplication then reported exactly
one matching bundle process, PID **55982**, with executable:
`/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project/build/TransferHistoryRun06/Build/Products/Debug/QuickStatsPanel.app/Contents/MacOS/QuickStatsPanel`.
Executable SHA-256 was rechecked before launch and matches above. No clicks, keystrokes, window
manipulation, clipboard changes or profile/history replacement occurred. Normal startup may
collect/persist live samples. Launch succeeded; E1 manual acceptance remains open. No new temporary
profile/restoration obligation was introduced. This is unreleased; no push/publication occurred.

## E1 screenshot correction — 2026-10-21

Run06 user screenshots exposed native-control contrast on Neon/light appearance and excessive
reserved confirmation space. View-only fixes are validated by the final Run07 standalone Debug
build (`/tmp/qsp-transfer-run07-build-final3.log`), successful strict ad-hoc signature verification,
whitespace check and actual-object offscreen renders across Neon/light, Default/light/dark and
Mono/light, including stable 284×561-point reset confirmation geometry. Warning text wraps within
its retained slot. No accounting/storage/model changes or new full-suite run; 113/113 remains
prior model evidence. Live E1 recheck remains open. Exact artifact/hash, probe effects/isolation,
retained screenshot/render evidence and launch deferral are recorded in the
[session follow-up](../sessions/2026-10-21.md#e1-screenshot-follow-up).

## Run08 gap display — 2026-10-21

User-directed replacement of diagonal gap hatching with quiet dashed baseline runs and “No data”
labels; measured idle baselines are solid, partial-source markers unchanged. Standalone ad-hoc
Debug build passed (`/tmp/qsp-transfer-run08-build.log`), as did signature verification and
whitespace check. Six actual-object offscreen graph fixtures inspected across Default light/dark,
Neon and Mono, including completely missing and measured-zero history. No model/storage changes
or new model-suite run. Exact Run08 launch verified at PID 77708; user accepted the live Network
gap display with screenshot and “well done”. Remaining E1 is still open. Full artifact/hash,
probe isolation and retained evidence: [current session handoff](../sessions/2026-10-21.md#run08-gap-display-and-visual-acceptance).
