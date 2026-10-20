# Implementation Plan — 24-hour transfer history and totals

**Created:** 2026-10-20 · **State:** executing; tasks 2.1/2.2 in progress
**Progress:** 1/8 implementation tasks complete; external acceptance **E1 open**.
**Execution:** one continuous run, organized into three phases; no per-phase approval stops.
Unchecked tasks are pending unless explicitly annotated implemented-unverified or blocked.
This file owns task status/evidence; `docs/TASKS.md` retains backlog mappings.

## Goal and accepted scope

Retain 24 hours of locally observed Network download/upload and Disk read/write activity across
restarts, with 1 min / 1 hour / 24 hours detail-card graphs, selected-period byte totals, and
independent persistent “Since reset” totals with start timestamps.

Source → action → destination → observable outcome: integer deltas from physical-link/block-device
counters → summon HUD, open Network/Disk and choose a period → existing detail card and local
history files → a fixture of 100,000,000 bytes down and 20,000,000 up produces those separate
byte totals, the corresponding rate graph and measured coverage; reopening retains saved data.
The complete journey and accepted requirements are in [the spec](specs/transfer-history.md).

Sleep/app-closed/read-failure time is unobserved, never fabricated zero traffic. Reset affects only
the chosen stat's cumulative pair, preserving both histories and the other stat's cumulative pair.
Disk I/O remains whole-machine block storage; its capacity rows remain boot-volume capacity.
No helper, third-party dependency, new permissions, external requests, per-source browsing or release.
Accepted preferences redesign and existing dirty edits must be preserved.

## Gap analysis and inspected evidence

- `Sampling/NetworkSampler.swift`: differences aggregate `getifaddrs` counters and divides by the
  configured interval. The installed SDK's `net/if_var.h` declares `if_data.ifi_ibytes/ifi_obytes`
  **UInt32**; casting them to UInt64 does not prevent rollover. `net/if.h` supplies `if_msghdr2`
  with `if_data64`. A 64-bit source is a prerequisite, not an optional later optimization.
- `Sampling/DiskSampler.swift`: sums IOBlockStorageDriver counters before differencing; it has
  neither device identity nor observation timestamps. Missing individual directions currently
  become implicit zero. Capacity sampling is independent and should remain so.
- `Model/StatsStore.swift`: five 60-second sample-count buffers, all cleared on `start()` and
  interval restart. Background callbacks hop independently onto MainActor. There is no durable
  transfer owner, checkpoint loading, generation rejection, or sleep discontinuity handling.
- `Model/StatDescriptor.swift` / `StatHistory.swift` / `Views/ActivityGraphView.swift`: existing
  compact graph data assumes equally spaced values and has no missing-coverage representation.
  Preserve that renderer for other stats; transfer detail graphs need an actual time axis.
- `Views/StatDetailView.swift`: 220×44 graph, legend and configurable detail rows.
  `Panel/DetailPanelController.swift` measures once per opening; new controls/status rows need
  reserved geometry. The controller's existing nonactivating-panel behavior must survive.
- `Views/AppKit/MetricOptionControls.swift`: native target/action wrappers refresh coordinator
  bindings on updates. Reuse this wiring pattern for period and reset controls.
- `Views/SettingsView.swift`: supported refresh range is **0.25–5 seconds**. Capacity budgets must
  cover 4 samples/sec/stat, not assume a one-second minimum.
- `AppDelegate.swift`: starts samplers and registers hotkeys at launch; termination calls `stop()`.
  `project.yml` defines hostless tests compiling Model/Sampling without running app startup.

Source paths above are under `01_Project/Sources/QuickStatsPanel/`, except `project.yml` under
`01_Project/`. SDK inspected at
`/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`.
`IOKitLib.h` documents registry-entry IDs as valid until reboot; `mach_time.h` documents
`mach_continuous_time` as advancing through sleep. Header evidence is not a successful runtime probe.

## Planned design and explicit policies

These are concrete implementation choices for this plan, subject to the bounded feasibility gate
1.1. They do not change the user-confirmed scope or claim implementation approval.

### Accounting contract

- A reader returns an immutable snapshot: stat, run/generation ID, sequence, monotonic capture
  time, wall timestamp, source IDs and **paired UInt64 counters**, plus enumeration/read validity.
  An observation contains accepted paired byte deltas, start/end times, and complete/partial/missing
  coverage. Source identity stays transient; persist aggregate bytes and coverage only, with no
  IP addresses, interface identifiers, hardware identifiers or process names.
- Network: prove `sysctl` route `NET_RT_IFLIST2` / `RTM_IFINFO2` 64-bit counters with validated message
  bounds. Key baselines by interface index/name plus observed incarnation changes, scoped to the
  sampler generation. Keep `shouldCount`'s active physical `en*` policy and tunnel exclusions.
  Existing display-only interface/IP discovery may continue separately.
- Disk: pair each driver's complete read/write counters with `IORegistryEntryGetRegistryEntryID`;
  deduplicate IDs and release IOKit objects. Never use aggregate counters as a baseline. A missing
  direction makes that source unreadable rather than zero. Keep `statfs("/")` capacity unchanged.
- First sightings seed baselines. Removed/reappearing sources and decreasing counters rebaseline;
  discard their uncertain deltas, not healthy peers' deltas. A failed read invalidates the affected
  baseline so recovery cannot count the missed interval. Unknown/reused identities require reseeding.
  Successful empty physical-network enumeration is known offline zero; an unavailable disk reader
  is missing coverage. Source-set transitions are partial coverage for their affected interval.
- Compute rates from exact integer deltas / actual positive monotonic elapsed seconds; never sum
  rounded rates. Reject nonfinite/nonpositive times. Use checked additions and visible unavailable
  accounting on overflow rather than wrapping. Enforce the supported transfer cadence defensively
  at the sampler boundary; do not change other samplers' cadence or the Settings layout.
- Confine each sampler's timer, baselines, reads and lifecycle to its own serial queue. Serial
  ingestion owns history and persistence; run IDs and sequences reject duplicate/late callbacks.
  Views receive immutable summaries on MainActor, not per-source state or disk work.

### Time, gaps, boundaries and graphs

- Use continuous monotonic elapsed time for rates and the rolling window within a boot, with a
  validated boot identity. Sleep/wake, stop/start and interval replacement invalidate baselines.
  Will-sleep may take a final observation; wake starts fresh. Also reject unsignaled intervals
  longer than `max(10 seconds, 3 × effective interval)` as gaps. Thus a delayed 2-second tick with
  20 MB still counts once at 10 MB/s; a long suspension never becomes a catch-up spike.
- Retain measured intervals, **not lossy storage buckets**. At most 345,600 ordinary intervals per
  stat per day at 0.25 seconds; keep at most one intersecting boundary interval. Cumulative totals
  are independent of expiry. Bound record size/count and include reset-triggered observations in
  the resource tests. Retention prunes during ingestion, loading and idle maintenance.
- Queries are half-open `[now − duration, now)`, ending at one shared query timestamp for the
  graph, totals and coverage. Full intervals contribute their exact integer bytes. For an interval
  intersecting a query edge, assume uniform transfer within that measured interval and allocate
  bytes by elapsed overlap with deterministic integer remainder handling. This is a sampling
  boundary estimate: indicate “≈” for affected period totals and explain it in help/accessibility.
  Adjacent partitions must conserve every byte; cumulative totals never use boundary interpolation.
- Reduce query intervals to at most 120 time-aligned display slots. Integrate overlapping bytes
  before deriving slot rates; changing plot resolution must not change query totals. Distinguish
  observed idle from missing time and mark partial-source intervals without claiming full coverage.
  Missing portions get a muted patterned background; partial portions get a separate marker.
  Coverage text reports fully measured duration and identifies partial-source data; never sums
  per-source durations into a value greater than the selected period.
- Same-boot wall-clock changes do not move records on the elapsed-time axis, alter byte totals,
  or manufacture coverage. Relative x-axis labels avoid implying an unchanged civil clock.
  Date/timezone formatting uses current locale; reset's original wall timestamp is preserved.
  After reboot, age persisted intervals by wall time and re-anchor them once to the new continuous
  axis. If that mapping is invalid (backward clock, future records, impossible durations), exclude
  ambiguous rolling history, preserve trustworthy cumulative state, and show a history warning.
  A forward wall jump while offline may expire old history; do not invent missing clock evidence.
- Keep CPU/Memory/GPU histories and compact strip geometry/rendering intact. Network/Disk strip
  values use corrected rates; existing short strip buffers may retain their existing restart
  behavior. The retained detail timeline is independent and survives interval changes.

### Local storage and durability

- Foundation-only, versioned compact interval records in immutable **five-minute segments** with
  checksums; one atomic checkpoint contains cumulative pairs/start times, generation/sequence
  watermarks, clock anchors, segment references and the current active segment. No database/helper.
  Runtime location resolves via Application Support and the bundle identifier; on this Mac the
  intended containing folder is
  `/Users/sim/Library/Application Support/com.sim.QuickStatsPanel/TransferHistory/v1`.
  Tests inject a unique disposable directory through every storage layer.
- Checkpoint at most every 30 seconds while dirty, plus reset and graceful quit. Seal segment
  files first, then atomically replace the checkpoint that references them; recover only its
  committed watermarks. Keep one prior valid checkpoint; GC only segments unreferenced by both.
  This ordering must be proven under crash injection before live integration.
- Normal quit drains samplers and awaits a final checkpoint through a bounded termination path
  (maximum two seconds; report failures). Abrupt exit/power loss can lose up to 30 seconds plus
  any in-flight checkpoint latency. Expose last-saved time and an unsaved/error state; never
  promise durable data while writes fail. Sleep flush is best effort and never delays wake sampling.
- Target **≤64 MiB on disk including active/previous checkpoints, temporary/quarantine files**, and
  **≤64 MiB incremental history memory** at the fastest supported cadence. Fixed-width packed
  records target ≤48 bytes each (~32 MiB/day for both stats before metadata); active five-minute
  payload target ≤128 KiB. No full-day snapshot rewrite every 30 seconds and no full-day scan on
  MainActor/body evaluation. Cache summaries off-main, coalesce superseded UI queries, and test
  the worst supported day. A failed budget proof stops/replans rather than silently truncating.
- Load asynchronously before reconciling buffered observations; never add a checkpoint's totals
  twice. Reopening always seeds fresh hardware baselines; saved counters never backfill downtime.
  Check format version, lengths, checksums, sequence ranges and resource bounds before allocation.
- Corrupt segments become visible gaps; a valid cumulative checkpoint remains authoritative.
  A prior-checkpoint fallback shows its saved time and possible loss. If cumulative state cannot
  be recovered, say so and start a visibly new epoch; never silently relabel lost totals as reset.
  Unsupported versions are preserved without overwrite. Unwritable storage keeps live collection
  and bounded in-memory history usable, with a persistent card warning. Cleanup never targets
  preferences and quarantines at most one bounded corrupt artifact within the storage budget.

### Reset and detail-card interaction

- Existing confirmed placement: a native `NSSegmentedControl` with 1 min / 1 hour / 24 hours above
  the graph; paired “Selected period” bytes and separate “Since reset” bytes/start time below.
  Default to 1 min, retain selection per stat within the process, and keep it independent of tile
  value direction and customizable legacy detail rows. New transfer totals remain discoverable
  even if every optional legacy row is hidden.
- Use a native `NSButton` beside “Since reset.” First click enters a reserved, inline confirmation
  row: “Reset Network totals?” / “Reset Disk totals?” with Reset and Cancel. It explicitly says
  history is kept. No new activating alert or separate window. Pending/error/coverage slots have
  reserved heights and bounded text so period changes, saves and confirmations cannot resize or
  clip the card. Preserve the 220×44 plot unless measured native controls require a modest fixed
  transfer-card width; prove the final size in 5.1/E1 rather than redesigning preferences.
- Confirmation asks the target sampler queue for a boundary read, then emits an ordered reset
  marker after that observation. The history owner accounts pre-reset bytes, zeros only the
  selected cumulative pair and records that boundary start time; subsequent deltas belong to the
  new epoch. Failed boundary reads rebaseline honestly and leave a gap. Duplicate actions are
  disabled while pending. Do not apportion a straddling tick into exact cumulative totals.
- Immediately checkpoint reset state. Show saved success only after commit; failure is an explicit
  unsaved reset, with in-memory state and preserved history, not a false durability claim.
  Escape/dismiss cancels an unconfirmed reset; cancelling changes no counters.
- New controls follow the existing AppKit coordinator/binding pattern with accessible labels and
  MainActor actions. No new raw SwiftUI controls or app-shell/sidebar changes. D-031 already confirms
  primary placement; reset confirmation uses that same cumulative section.

## Acceptance criteria

- Exact paired fixture totals and actual-elapsed rates; membership changes, 64-bit values beyond
  4 GiB, failures and resets cannot inflate another source or double-count bytes.
- 1 min / 1 hour / 24 hours share graph/total boundaries, distinguish gaps from zero, disclose
  partial coverage and boundary estimates, and expire history by time independent of cadence.
- Checkpoint/reopen and interval changes preserve measured history/cumulative epochs; downtime
  never backfills. Clock changes do not corrupt rates, and reboot ambiguity is disclosed.
- Per-stat confirmed reset preserves history/other stat, is ordered against sampling, and has a
  visible new start time and truthful save status.
- Failure recovery is bounded, keeps live stats usable and preserves unrelated preferences.
- Existing strip, configurable detail rows, other histories, themes, hotkeys and preferences remain
  usable; fixed transfer-card controls work without focus theft or geometry changes while open.
- All required automated checks and the separate finite E1 user acceptance batch pass. A fixture
  suite is not evidence of real-device behavior or user acceptance.

## Execution schedule and ownership

User authorized **execute the plan** on 2026-10-20. Continue all dependency-ready tasks;
publication and interactive desktop control remain outside this request.
At execution, read the canonical
`/Users/sim/ProgrammingProjects/0-DIRECTIONS/__DIRECTIONS/commands/execute.md` and follow its fresh-context
delegation/validation rules. No agents were used to prepare this plan.

Coordinator exclusively owns `01_Project/project.yml`, generated project files, this plan, tracking
documents, integration wiring and all XcodeGen/build/test resources. Task owners request project
registration through the coordinator. Run shared builds/tests serially, using one unique build
directory per execution attempt and never overwriting a potentially running Debug artifact.
Task source/test ownership below is exclusive while a task runs; subsequent owners inherit only
after named prerequisite integration and validation. All source/test paths below are relative to
`01_Project/`. Accepted interfaces from 1.1 are required before starting 2.1/2.2.

The original six-wave presentation overstated scheduling detail. Use three phases below in one
continuous execution run, following each task's prerequisites and checks. Phases include sequential
work and are not independent parallel waves or user approval gates. Preserve original task IDs so
existing links remain valid. Continue all ready in-scope work automatically; stop only for a real
blocker/scope decision or the final user acceptance, not to ask permission for the next phase.

### Phase 1 — prove and implement accurate accounting (1.1, 2.1, 2.2)

- [x] **1.1 — Prove counter identity/width, timing and resource feasibility.**
  - Depends on / external gates: none. This is an internal feasibility gate for every later task.
  - Owns: `Sources/QuickStatsPanel/Model/TransferObservation.swift`,
    `Tests/QuickStatsPanelTests/TransferAccountingTests.swift`,
    `Tests/QuickStatsPanelTests/TransferReaderProbeTests.swift`; evidence in the spec/plan by coordinator.
  - Interface: freeze Sendable snapshot/observation/coverage/reset-marker types, injectable clock
    and counter-reader protocols, generation/sequence semantics and the compact record budget.
  - Scope: current permission-free Darwin/IOKit APIs only; one bounded headless read-only probe
    of current counters, deterministic fixtures and a packed-day size calculation. No endurance
    wait, disk workload, device unplug, helper, new dependency or live-profile write.
  - Success: validate a current 64-bit route snapshot and distinct block-driver IDs/counter pairs;
    fixture two-second delay, >4 GiB counters, source loss/reset/read failure and duplicate events.
    Prove the 0.25-second day fits proposed bounds. Retain observed probe limitations honestly;
    hardware-dependent test is an explicit failure/skip gate, never an unconditional suite pass.
  - Stop/replan: identity/width unavailable, duplicate storage accounting unresolved, actual API
    privileges exceed scope, or record budget fails. Dependents remain pending; do not build
    persistence/UI on an unproven API or broaden scope silently.
  - Backpressure: T below selecting `TransferAccountingTests` and `TransferReaderProbeTests`,
    plus retained SDK/probe evidence and capacity calculation. Real sleep/hot-plug is deferred to E1.

- [ ] **2.1 — Replace aggregate baselines with queue-confined per-source accounting.**
  - Depends on: 1.1. External gates: none.
  - Owns: `Sources/QuickStatsPanel/Sampling/NetworkSampler.swift`, `Sampling/DiskSampler.swift`,
    new `Sampling/TransferCounterReader.swift`,
    `Tests/QuickStatsPanelTests/NetworkSamplerTests.swift`, new `TransferSamplerTests.swift`.
    Sampling paths share the `Sources/QuickStatsPanel/` prefix; test paths share the Tests prefix.
  - Interface: accepted snapshots/observations, existing live sample callbacks plus ordered transfer
    events, queue-ordered boundary-reset and lifecycle invalidation APIs; compatible default initializers.
  - Success: real adapters use proven 64-bit/source-ID APIs; healthy peers survive partial failures;
    delayed ticks, first samples, wrap/reset, duplicate source records, stop/start and queued old
    callbacks obey policy. Live rate/disk-capacity and display metadata behavior remain compatible.
  - Backpressure: T selecting `NetworkSamplerTests`, `TransferSamplerTests`, `TransferAccountingTests`;
    no timers/hardware in deterministic tests. Read-only hardware probe stays separately identifiable.

- [ ] **2.2 — Implement retained intervals and period/cumulative queries.**
  - Depends on: 1.1. External gates: none.
  - Owns: `Sources/QuickStatsPanel/Model/TransferTimeline.swift`,
    `Tests/QuickStatsPanelTests/TransferTimelineTests.swift`.
  - Interface: serial-owner-friendly pure timeline accepting observations/reset markers; bounded
    snapshot/restore value types; immutable period result with paired UInt64 bytes, coverage,
    boundary-estimate flag and ≤120 slots; independent cumulative epochs.
  - Success: retain/expire 24 hours at mixed cadences; prove integer conservation, half-open edges,
    empty/zero/partial gaps, no double-counted coverage, separate resets and clock/reboot policies.
    Long gaps and expiry cannot erase cumulative bytes. Full-day fixtures stay within record bounds.
  - Backpressure: T selecting `TransferTimelineTests`; deterministic virtual clock and multi-day
    fixtures, no actual 24-hour wait or dependency on 2.1's files.

### Phase 2 — add retained storage and graph presentation (3.1, 3.2)

- [ ] **3.1 — Implement bounded checkpoint persistence and failure recovery.**
  - Depends on: 1.1, 2.2. External gates: none.
  - Owns: `Sources/QuickStatsPanel/Model/TransferHistoryRepository.swift`,
    `Tests/QuickStatsPanelTests/TransferPersistenceTests.swift`.
  - Interface: injected-root async load/commit/prune operations, saved watermark/time, versioned
    restore result, recoverable diagnostics and durability status. No singleton production I/O.
  - Success: prove segment/checkpoint transaction ordering, duplicate-free recovery, reset durability,
    stale checkpoint fallback, corrupt segment/manifest, unsupported version, permission/write failure,
    bounded quarantine and pruning. Check file/record/size limits before allocation. Measure worst-day
    disk/memory and checkpoint write size against the explicit budgets.
  - Backpressure: T selecting `TransferPersistenceTests`; crash injection at each commit step,
    temp-directory restart round trips and fast virtual-day resource measurements.

- [ ] **3.2 — Build gap-aware transfer graph and presentation model.**
  - Depends on: 1.1, 2.2. External gates: none.
  - Owns: `Sources/QuickStatsPanel/Model/TransferHistoryPresentation.swift`,
    `Sources/QuickStatsPanel/Views/TransferHistoryGraphView.swift`,
    `Tests/QuickStatsPanelTests/TransferPresentationTests.swift`.
  - Interface: pure immutable display model for period/coverage/totals/start/save/error state and a
    fixed-size Canvas graph/legend consuming timeline slots, independent of StatsStore and storage.
  - Success: byte vs byte/second formatting is distinct and safe for UInt64; down/up and read/write
    labels/mono-safe markers are unambiguous. Plot gaps/partial coverage visibly; query time and
    scale are coherent and stable across rerenders. No sampled array suffix masquerading as 24 hours.
    Keep peak memory scoped per stat/period, advance on new observation/query revision, not body reads.
  - Backpressure: T selecting `TransferPresentationTests`, then B compilation by coordinator.
    Pixel geometry/control appearance remains E1, not asserted by logic tests.

### Phase 3 — integrate the feature and validate the fresh app (4.1, 5.1, 6.1)

- [ ] **4.1 — Connect sampling, recovery, save cadence, clock/sleep and reset ordering.**
  - Depends on: 2.1, 2.2, 3.1. External gates: none.
  - Owns: new `Sources/QuickStatsPanel/Model/TransferHistoryController.swift`,
    `Sources/QuickStatsPanel/Model/StatsStore.swift`, `Sources/QuickStatsPanel/AppDelegate.swift`,
    `Tests/QuickStatsPanelTests/TransferLifecycleTests.swift`; shared project wiring by coordinator.
  - Interface: MainActor immutable Network/Disk summaries, async range request and scoped confirmed
    reset action; bounded controller flush/start/stop/discontinuity hooks. Inject clocks/readers/root
    and scheduling into headless tests; keep real hotkey and panel startup out of test construction.
  - Success: one long-lived history owner survives sampler restarts; load/tick/reset races cannot
    overwrite or duplicate totals. Old-generation callbacks are rejected before live/history mutation.
    Suspend/wake and excessive delay rebaseline correctly; quit drains in order with bounded wait.
    Coalesce range queries; publish summaries without full-day main-thread processing.
    Storage failure propagates to UI data while live rates continue; no unrelated preferences change.
  - Backpressure: T selecting `TransferLifecycleTests` plus accounting/timeline/persistence suites;
    B. Include tick-during-load, interval restart, reset-vs-tick, queued-stop, two-stat reset isolation,
    sleep/wake and failed quit-flush fixture cases.

- [ ] **5.1 — Add period, totals, coverage/save status and confirmed scoped reset controls.**
  - Depends on: 3.2, 4.1. External gates: none for implementation; E1 gates live UI acceptance.
  - Owns: `Sources/QuickStatsPanel/Views/StatDetailView.swift`, new
    `Sources/QuickStatsPanel/Views/AppKit/TransferHistoryControls.swift`,
    `Sources/QuickStatsPanel/Panel/DetailPanelController.swift` if measured geometry requires it,
    `Tests/QuickStatsPanelTests/TransferDetailStateTests.swift` for reset/selection state only.
  - Interface: native controls → latest bindings/controller → immutable selected-period summary.
    Keep period/reset state separate per stat. Cancel unconfirmed reset on dismissal.
  - Success: approved placement, reserved status/confirmation geometry, accessible native actions,
    localized timestamps and truthful unsaved state. Legacy rows still filter correctly; all-hidden
    rows do not hide transfer controls. Period changes do not resize the panel, steal focus or
    accidentally trigger click-away dismissal. Existing other-stat detail cards stay unchanged.
  - Backpressure: T selecting `TransferDetailStateTests`; B; source review against UI constraints.
    Actual click/binding/geometry/keyboard behavior is explicitly not validated until E1.

- [ ] **6.1 — Verify complete journey and prepare one finite user acceptance handoff.**
  - Depends on: 1.1, 2.1, 2.2, 3.1, 3.2, 4.1, 5.1. External gates: none for automated work;
    E1 separately gates overall product completion.
  - Owns: `Tests/QuickStatsPanelTests/TransferHistoryIntegrationTests.swift`; coordinator owns
    final project/build/docs changes, evidence and fixes routed back to the appropriate task owner.
  - Success: deterministic Network 100 MB/20 MB and Disk 80 MB/40 MB journey survives checkpoint,
    reopen, cadence change and stat-specific reset. Simulated >24-hour runs expire history but keep
    cumulative totals. Full existing/new hostless suite passes, source/ownership/concurrency review
    finds no unresolved in-scope issue, and a final standalone ad-hoc Debug build succeeds after
    the last source fix. Record failure/recovery/resource evidence and final artifact identity.
  - Backpressure: full T, final standalone B, `git diff --check`. Record actual commands, logs and
    unique `.xcresult` location; no success evidence until executed. Any fixes invalidate affected
    checks and require appropriate reruns, not endless speculative broad testing.
  - Launch: standing fresh-build authorization applies only to the final runnable artifact. Inspect
    exact existing process/artifact read-only; if it prevents launch, leave it untouched and provide
    full containing-folder/app steps. Report full artifact path and actual result. Do not launch a
    failed/intermediate test-runner build, quit/relaunch an existing instance or replace live profiles.

Tasks 2.1/2.2 can run independently after 1.1, and 3.1/3.2 after 2.2: their write sets are disjoint.
Other work follows the explicit prerequisites, with lifecycle, UI and final validation integrated
in order. The DAG is acyclic; all prerequisite IDs exist. Ready tasks need not wait for unrelated
earlier work: 3.1/3.2 need 2.2, not 2.1; 4.1 needs 3.1, not 3.2. Shared builds remain serialized.

## Backpressure commands (for execution, not run during planning)

Working directory: `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/01_Project`.
Before any build/test, recheck the master `34_testing.md`, current scheme/setup and startup effects.
Coordinator generates with `xcodegen generate` after source registration. Select a new unused run
suffix for every build/result path; commands below illustrate one such run, not evidence it occurred.

**T — hostless tests**, optionally add `-only-testing:QuickStatsPanelTests/<named suite>` for task checks:

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun01 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -resultBundlePath build/TransferHistoryRun01Tests.xcresult test
```

**B — standalone runnable build** (final B must follow the final relevant tests/source fixes):

```sh
xcodebuild -scheme QuickStatsPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/TransferHistoryRun01 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

Existing hostless tests compile model/sampler code without the application host. New tests inject
clocks/readers/files/defaults and do not start hardware samplers, app entrypoints, hotkeys or login
items, except the separately named read-only 1.1 probe. Inspect this property again at execution.
Normal local Developer ID signing is unavailable; command-line ad-hoc Debug overrides are established
local practice and do not change Release settings. Escalate sandbox-denied compilation only through
the normal tool approval path, keeping command/log/exit status and real `.xcresult` evidence.

## External acceptance

- [ ] **E1 — Finite acceptance of integrated fresh artifact on the user's Mac.**
  - Depends on: 6.1 and the exact fresh app artifact. Requires user-operated foreground actions
    or new explicit scope for desktop interaction. No requirement for a 24-hour real-time wait.
  - Owns: acceptance evidence in the session log. Gates live UI, real sleep/reconnect continuity,
    cross-launch observed retention and overall feature acceptance; does not block earlier ready work.
  - Cases (final instructions must be checked against the implemented controls):
    1. Open both cards; select each period; confirm rates vs byte totals, graph legends, coverage,
       timestamps and gap/idle distinction. Use Mono and one other existing theme; inspect near
       screen edges for clipping. Check Network/Disk strip and one unrelated detail card.
    2. While collecting ordinary activity, change refresh interval and re-open: prior detail history
       remains. Quit/reopen the exact app normally: persisted history/start times/totals remain;
       app-closed time is a gap and restart introduces no counter-lifetime spike.
    3. Cancel a Network reset, then confirm it: only Network “Since reset” clears and its timestamp
       changes; Network history and Disk totals persist. Quit/reopen to verify saved reset. Repeat
       scoped Disk reset. No activating confirmation window or unexpected dismissal/focus change.
    4. User performs one sleep/wake and one available physical-link reconnect; verify gaps/partial
       coverage and no catch-up spike. Storage hot-plug is conditional on suitable hardware; if
       unavailable, keep that real-device claim explicitly unverified while retaining fixture evidence.
    5. Inspect saved/partial/empty states reached through the cases above. Storage failure/recovery
       is verified by injected repository/lifecycle and presentation fixtures plus source review;
       record that live error-state rendering has not been exercised if no natural failure occurs.
       Do not corrupt/chmod live history to manufacture an error UI. An observed error-display
       defect still blocks acceptance; an artificial live corruption exercise is not required.
  - Completion: user returns pass/failure with case and exact artifact, plus screenshots for layout
    issues. Conditional hardware coverage is recorded as pass, failed or explicitly deferred by user;
    not silently waived. Source fixes trigger only affected repeated cases on the new artifact.
  - While unavailable: complete all independent automated checks and handoff; leave E1 unchecked.

## Blocked tasks and open decisions

Task 1.1 feasibility gate passed on this Mac; see the execution evidence. Its physical-provider
classification excludes virtual image layers and reports unknown metadata as incomplete coverage.
Integrated persistence resource measurement and final real-device acceptance remain required. No user-facing requirements remain unspecified. E1 is open and will need
the integrated build and user availability. Protocol/encoding details must be frozen by 1.1 and
validated in 3.1 without expanding the accepted source/storage scope.

## Execution log

| Phase / task IDs | Assignment or serial reason | Validation / evidence | Commits / exceptions | Next action / stop reason |
|---|---|---|---|---|

| Phase 1 / 1.1 | Fresh agent `counter_contract`; independent read-only `contract_review`; coordinator runs shared checks | **15/15 accounting + 3/3 probe tests passed**, no skips. [Feasibility evidence](docs/evidence/transfer-history-feasibility.md). Corrected unknown-provider classification and combined active payload budget. | Scoped local checkpoint pending; prior dirty preferences/entrypoint/docs preserved. | Gate passed; 2.1 and 2.2 assigned to independent fresh agents. |
| Phase 1 / 2.1, 2.2 | Fresh agents `transfer_samplers` and `transfer_timeline`; disjoint owned files, shared builds serialized by coordinator | In progress; no completion claimed | Pending validation | Sampler adapters/accounting lifecycle and retained queries. |

Keep this plan active until required implementation and acceptance are complete. Archive with its
evidence and update incoming links only after acceptance or explicit scoped deferral.
