# Network and Disk History Specification

**Status:** Executing — user-facing requirements confirmed; feasibility gate in progress
**Created:** 2026-10-20
**Last updated:** 2026-10-20

## Problem Statement

The user wants to inspect network download/upload and disk read/write activity over longer
periods and see cumulative transferred amounts. Existing one-minute graphs show recent rates
only, live in memory, and clear when the app or sampling interval restarts. Rate peaks alone
cannot answer how much data moved during a period.

## Proposed Solution

### One-Liner
Add retained network/disk transfer history and clearly labeled byte totals to the existing
detail cards while keeping the HUD strip compact.

### Confirmed Capabilities
1. Retain the last 24 hours locally across restarts, with user-confirmed graph ranges of
   1 minute, 1 hour and 24 hours.
2. Show paired download/upload or read/write totals for the selected graph period (user confirmed).
3. Maintain a separate cumulative pair labeled “Since reset,” with its start timestamp.
   It survives restarts. Reset is scoped independently to Network or Disk and affects only
   that stat’s cumulative pair, leaving its retained history intact (user confirmed).
4. Preserve collected data across sampling-interval changes. Show sleep and app-closed time
   as gaps, not zero activity; only measured coverage contributes to totals (user confirmed).
5. Reuse the existing Network and Disk detail cards (user confirmed): period selector above
   the graph, selected-period and “Since reset” totals below. Keep the strip compact by default.

### User Journey
- **Input:** Locally observed byte-counter deltas from counted physical network interfaces
  and block-storage devices, with elapsed times and timestamps.
- **Action:** Summon the HUD, open Network or Disk, select a history period.
- **Output:** The card shows that period's rate graph and paired byte totals, plus coverage
  and separately labeled cumulative totals since reset.
- **Observable success:** A known fixture adding 100 MB received and 20 MB sent displays
  those totals for its covered period; reopening the app retains the recorded data.

## Acceptance Criteria

### Core
- Given 100 MB down and 20 MB up in the selected period, when Network opens, then the totals
  show 100 MB downloaded and 20 MB uploaded separately from rates in bytes/second.
- Given 80 MB read and 40 MB written, when Disk opens, then its transfer totals show those
  amounts and remain distinct from boot-volume used/free capacity.
- Given retained data, when the sampling interval changes, then prior history and totals survive.
- Given collected data, when the app closes and reopens, then persisted observations survive
  according to the chosen retention policy; collection resumes from fresh counter baselines.
- Given an accepted graph period, when it changes, then graph and period totals refer to the
  same interval; the compact strip retains its existing default appearance.

### Timing, Devices and Coverage
- Given 20 MB transferred across a delayed two-second sample, when the rate is derived, then
  it is 10 MB/s and the byte total increases by 20 MB exactly once.
- Given an interface reconnect or storage hot-plug, when a new counter appears, then it seeds
  a baseline; its lifetime counter is not added as newly transferred data.
- Given two counted interfaces/devices, when one disappears or its counter resets, then the
  other source continues correctly without negative totals or an artificial catch-up spike.
- Given a VPN over a counted physical link, when collecting network totals, then tunnel
  counters are excluded consistently with the current physical-link policy.
- Given sleep or an interval without observations, when history is rendered, then missing
  coverage is distinguishable from observed zero activity. No invented samples fill the gap.
- Given a period longer than available coverage, when totals are shown, then the UI identifies
  the partial coverage instead of implying a complete 24-hour measurement.
- Given a system-clock change, when elapsed rates are computed, then monotonic timing avoids
  negative or inflated rates; stored period placement follows an explicitly defined clock policy.

### Reset and Storage Errors
- Given cumulative values, when an explicitly scoped reset is confirmed, then only the chosen
  stat’s cumulative counters reset and their new start timestamp is visible; history and the
  other stat’s cumulative totals remain intact.
- Given cumulative values and their start time, when the app restarts, then both persist
  independently of the rolling 24-hour history retention.
- Given corrupt or unwritable history storage, when collection continues, then live stats
  remain usable, loss of persistence is visible, and unrelated preferences are preserved.

## Technical Considerations

### Current Evidence
- `StatsStore.historyDuration` is 60 seconds. Buffers are rebuilt and cleared in `start()`;
  graph peaks advance with sample revisions. The existing short graph behavior is established.
- NetworkSampler sums active physical `en*` counters before calculating deltas, then divides
  by the configured interval. Device membership changes can therefore distort aggregate deltas.
- DiskSampler similarly differences aggregate IOBlockStorageDriver counters and divides by
  the configured interval. Disk I/O scope is whole-machine block storage, unlike capacity's `/`.
- Current sample structs expose rates, not exact byte deltas or observation timestamps.
- StatDetailView uses a fixed graph size and its controller measures the card once when opened.
  Period controls must not introduce live content resizing or clipped card content.

### Required Architecture Properties
- Derive totals from integer counter deltas, not rounded displayed rates.
- Track baselines by source identity and actual monotonic elapsed time. Define reset, read
  failure, sleep/wake, device removal and counter-width handling before relying on totals.
- Keep sampling and storage work off the main thread, with serialized ownership and bounded
  memory/disk usage. Choose aggregation resolution, write cadence and storage format in planning.
- Retention is time based. Old data expires; graph rendering reduces retained data to a bounded
  number of plotted points while preserving transferred byte sums and recorded coverage.
- Storage remains local and requires no external service or new permissions. Do not retain
  IP addresses or process names in transfer history; they are unnecessary for aggregate totals.
- Collection is limited to observed coverage while the app runs. Full accounting while the
  app is stopped would need a separate design; do not infer or promise it from lifetime counters.

### Feasibility Before Broad Implementation
Use deterministic counter/timestamp fixtures to prove per-source accounting under hot-plug,
resets, delayed ticks and gaps. Inspect real counter types and source identities before selecting
the implementation. If reliable identities or required accuracy cannot be established with the
current APIs, stop and revise scope before building persistence or UI around incorrect totals.
No background helper, new database dependency or expanded hardware permissions are approved.

## Out of Scope
- Per-app, per-volume or per-interface history browsing; Internet-only or billing-grade accounting.
- Public-IP lookup, cloud sync, telemetry, CSV export, or collection while the app is stopped.
- Changes to CPU/GPU/Memory history, strip orientation, or the newly accepted preferences layout.

## Confirmed Decisions and Planning Questions

1. **Resolved:** retain the last 24 hours across app restarts, confirmed by user.
2. **Resolved:** show both selected-period totals and cumulative “Since reset” totals, confirmed by user.
3. **Resolved:** existing Network/Disk detail cards; 1 min / 1 hour / 24 hours selector above
   the graph and both kinds of totals below, confirmed by user.
4. **Resolved:** sleep/unobserved time appears as gaps; totals cover measured activity only.
5. **Resolved:** “Since reset” survives restarts, shows a start time and resets per stat without
   clearing retained history, confirmed by user.
6. **Planned technical policies:** retain measured intervals rather than lossy storage buckets;
   prorate query-edge intervals with a visible estimate marker; use continuous elapsed time with
   explicit clock/reboot fallback; compact five-minute segments and atomic checkpoints every
   30 seconds plus reset/normal quit; 64 MiB disk and incremental-memory budgets; inline per-stat
   reset confirmation and queue-ordered boundary read. See the plan for exact contracts and limits.
7. **Internal feasibility gate remains open:** prove 64-bit network counters, per-driver disk
   identity, deterministic accounting and the fastest-cadence resource budget before dependent work.

## Implementation Plan

`../IMPLEMENTATION_PLAN.md` owns eight implementation tasks in three phases within one continuous
execution run, plus separate manual acceptance E1. Task dependencies remain explicit; phases do not
require separate user approvals. Planning does not pass the feasibility gate or authorize execution.
The installed SDK confirms the existing `getifaddrs`/`if_data` network byte counters are UInt32;
casting to UInt64 does not widen the underlying counter. The plan first proves the 64-bit route
snapshot API, then per-source accounting, retention/storage and detail-card integration.

## Related
- Backlog: `../docs/TASKS.md` — History and transfer totals; Transfer-rate continuity.
- Existing graph decisions: `../docs/decisions.md` — D-025 and D-026.

## Execution clarification — storage scope (2026-10-20)

The bounded read-only probe found both physical block devices and file-backed virtual drivers.
Distinct registry IDs alone cannot exclude duplicate I/O through an image and its backing disk.
The reader will use the immediate storage provider's public Protocol Characteristics to include
positively classified physical providers and exclude Virtual Interface or File/RAM layers.
Unknown classification is incomplete coverage; stacked retained physical-driver ancestors are
rejected rather than summed twice. Boot-volume capacity remains independent. This implements
whole-machine physical block-storage accounting; unobserved multipath/RAID behavior remains a
real-hardware limitation, not a validated claim. Task 1.1 evidence and tests remain pending.
