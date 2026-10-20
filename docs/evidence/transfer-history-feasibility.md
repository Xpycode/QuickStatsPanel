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
