# Power Tile Specification (D-019)

**Status:** Draft
**Created:** 2026-06-15
**Last Updated:** 2026-06-15

---

## Problem Statement

### What problem does this solve?
The strip shows CPU/Mem/Disk/Network/Battery/Load/Uptime/GPU/Fan, but nothing about
how much **power** the Mac is actually drawing right now. Power draw (watts) is a
core "is my Mac working hard / running hot" signal that users of a stats HUD expect —
it's the natural companion to the GPU and Fan tiles shipped in D-017, and the obvious
next "core hardware" stat before temperatures (D-018).

### Who has this problem?
The same single user — someone glancing at a quick HUD to gauge load. Power is
especially meaningful on laptops (battery drain rate, thermal headroom) and when
comparing idle vs. heavy-workload states.

### How do they solve it today?
There is no in-app answer. The system tools that report SoC power either need root
(`sudo powermetrics`, `asitop`) or aren't a glance HUD (Activity Monitor's Energy tab
shows an "Energy Impact" score, not watts). QuickStatsPanel's whole premise is
**permission-free, no-prompt** stats — so `powermetrics` is disqualified.

---

## Proposed Solution

### One-Liner
Add a permission-free **Power tile** showing live CPU and GPU power draw in watts,
read from Apple's private-but-unentitled **IOReport** "Energy Model" channels — no
root, no entitlement, notarizable — wired through the existing data-driven strip.

### Key Capabilities
1. **Permission-free watts via IOReport** — subscribe to the "Energy Model" channel
   group and derive watts from the cumulative energy counters (W = ΔJoules ÷ Δseconds),
   exactly the no-sudo path the `macmon` tool proves. No `powermetrics`, no privileged
   helper, no permission prompt.
2. **CPU·GPU split headline** — the strip tile shows two numbers, CPU and GPU watts
   (e.g. `⚡ 8·4 W`), in a fixed-width slot that never reflows.
3. **Per-subsystem detail breakdown** — the detail card splits power into CPU, GPU,
   ANE, DRAM, and a Total row.
4. **Self-calibrating tint** — total SoC watts is normalized against the highest total
   seen since launch (session peak), so the calm→busy→hot band auto-scales to this
   specific Mac's power envelope (an Air and an M4 Max calibrate differently, no config).
5. **Hide-when-unavailable** — on hardware/OS where the Energy Model channels don't
   resolve (Intel Macs, an untested future chip whose channel names changed), the tile
   hides cleanly like Battery on a desktop, rather than showing wrong/zero numbers.

### User Flow
1. User presses the global hotkey → strip appears.
2. On a supported Apple-Silicon Mac, a Power tile shows `⚡ <cpu>·<gpu> W` live,
   updating each tick; its tint reflects how hard the SoC is working relative to the
   session's own peak.
3. User clicks the tile → detail card lists CPU / GPU / ANE / DRAM / Total watts.
4. On an unsupported Mac, no Power tile appears (and it's absent from Settings'
   reorder/toggle list) — no error, no empty tile.

---

## Acceptance Criteria

> Given/When/Then. See `56_acceptance-criteria.md`.

### Core Functionality
- [ ] **AC-1 (permission-free read):** Given the app running un-elevated (no sudo, no
  added entitlement, hardened runtime, notarized), when the Power sampler ticks, then
  it returns live watts and triggers **no** permission prompt — at the same trust level
  as the existing IOKit reads.
- [ ] **AC-2 (watts math):** Given two energy samples taken `interval` seconds apart,
  when the sampler computes a reading, then watts = (ΔenergyCounter ÷ unitDivisor) ÷
  interval, where the unit divisor is derived from each channel's **runtime unit label**
  (`mJ`→1e3, `uJ`→1e6, `nJ`→1e9), not a hardcoded assumption.
- [ ] **AC-3 (split headline, no jitter):** Given the Power tile is visible, when CPU
  and GPU watts change tick-to-tick (e.g. `2·1` → `41·38`), then the tile shows both
  values as `⚡ <cpu>·<gpu> W` and its width never changes (fixed-width worst-case slot,
  monospaced digits — D-008 Penumbra pattern).
- [ ] **AC-4 (detail breakdown):** Given the tile is tapped, when the detail card opens,
  then it shows CPU, GPU, ANE, DRAM, and Total watts rows, each reading plausibly versus
  the workload.
- [ ] **AC-5 (session-peak tint):** Given the Mac goes from idle to heavy load, when the
  total SoC watts rises, then the tile's `loadPercent` = currentTotal ÷ sessionPeakTotal
  × 100 drives the existing calm→busy→hot tint (no per-tile color code), and the peak
  ratchets up but never down within a session.

### Edge Cases
- [ ] **AC-6 (hide on unsupported hardware):** Given a Mac where the "Energy Model"
  group / CPU+GPU channels don't resolve (Intel, or a future chip with renamed channels
  → all-zero/empty), when the strip is built, then the Power tile is absent from both the
  strip and the Settings stat list (same `compactMap(descriptor(for:))` chokepoint that
  hides Battery/GPU/Fan), with no crash and no empty tile.
- [ ] **AC-7 (first-tick seeding):** Given the very first sample after launch (no prior
  sample to delta against), when the first tick fires, then the tile does **not** flash a
  spurious huge/blank number — it shows nothing/placeholder until the first valid delta
  is available (the Network/Disk cumulative-counter seeding behavior).
- [ ] **AC-8 (multi-cluster aggregation):** Given a Pro/Max/Ultra chip that exposes
  multiple CPU/ANE/DRAM channels (e.g. `DIE_0_CPU Energy`, `ANE0`, `ANE1`), when the
  sampler sums power, then it matches channels by **prefix/suffix** (not exact full
  strings) and aggregates all matching clusters, so multi-die chips aren't under-reported.
- [ ] **AC-9 (free migration):** Given an existing user who already has a saved stat
  order/selection, when they update to the build with `.power`, then the Power tile
  defaults **ON** and appends to the end (the existing `knownStats` migration), without
  disturbing stats they deliberately disabled.

### Error / Resource States
- [ ] **AC-10 (no leak):** Given the sampler runs continuously at ~1 Hz, when it takes
  samples each tick, then every `IOReportCreateSamples` / `IOReportCreateSamplesDelta`
  result is `CFRelease`d each tick and the subscription is released on `stop()` — memory
  is flat over time (no per-tick CF leak).
- [ ] **AC-11 (off-main-thread):** Given the panel UI thread, when the sampler runs,
  then all IOReport subscribe/sample work happens on the sampler's background
  `DispatchSourceTimer` queue (matching every other sampler) — the UI thread only reads
  the latest published `PowerSample`.

---

## Technical Considerations

### Dependencies
- **IOReport** (private framework, **directly linkable** — add `-lIOReport` to the
  target's linker flags; resolves against the dyld shared cache, **no `dlopen`**, no
  relocated-framework Library-Validation issue). No public header ships — declare the C
  prototypes in a bridging header (the `socpowerbud` pattern; `NeoAsitop` is the Swift
  precedent).
- IOKit (already linked).

### Architecture Notes
- **New file `Sampling/PowerSampler.swift`** + a small **`Sampling/IOReport.swift`**
  (bridging-header-style `extern "C"` decls + a thin Swift wrapper that owns the
  subscription), mirroring how `FanSampler` owns the long-lived `SMC` connection.
- **Sampler shape = cumulative-counter delta-per-tick** (like `NetworkSampler` /
  `DiskSampler`, **not** the GPU/Fan snapshot shape): subscribe **once** in `start()`;
  each `tick()` takes a fresh sample, deltas it against the **previous tick's** sample,
  divides by `interval` → watts; stash current as previous. First tick has no previous →
  emits a seeding/placeholder sample (AC-7). This avoids a blocking `sleep` inside the
  tick (macmon sleeps between two samples in one call; we instead delta across ticks,
  which is the established pattern in this codebase).
- **Channel routing:** group `"Energy Model"`; match `…CPU Energy` (suffix), `GPU Energy`
  (exact), `ANE` (prefix), `DRAM` (prefix); sum per subsystem; total = sum of subsystems
  (no single "total" channel exists). Read `IOReportChannelGetUnitLabel` per channel.
- **`PowerSample`** (`Equatable, Sendable`): `isAvailable: Bool`, `cpuWatts`,
  `gpuWatts`, `aneWatts`, `dramWatts: Double`; computed `totalWatts`; `headlineFormatted`
  = `"\(cpu)·\(gpu) W"`; `loadPercent` driven by the store's session-peak (see below);
  `static let empty` = `isAvailable: false`. Same hide-gate shape as `GPUSample.empty` /
  `FanSample.empty`.
- **Session peak** lives where state persists across ticks — the simplest home is the
  sampler (carry `peakTotal`, ratchet up each tick, expose normalized `loadPercent` on
  the emitted sample). Resets on relaunch by design (per the chosen answer).
- **Wiring (same chokepoints D-017 used):** add `.power` to `StatKind` (+ `displayName`,
  `settingsSymbol`) in `Model/StatDescriptor.swift` and a `descriptor(for:)` case;
  add a published `power` sample + sampler ownership in `Model/StatsStore.swift`. The
  exhaustive `StatKind` switches force every display path to handle the new case.
- **Not visibility-gated** — IOReport reads are cheap in-process calls; run continuously
  like CPU/GPU/Fan (only the costly `top` sampler stays gated to panel-visibility).
- **Tile glyph:** candidate SF Symbol `bolt.fill` (power/energy); confirm in the design
  pass (GPU's `cpu.fill` placeholder is already flagged — avoid a second near-collision).

### Performance
- ~1 Hz default (follows the user's `interval` setting), off the main thread. IOReport
  sample calls are lightweight userspace IOKit reads; no measurable UI cost expected.
- Do not sample below ~100 ms (energy counters quantize at ~1 mJ — sub-100ms windows are
  noise). The app's interval floor already sits well above this.

### Security / Permissions
- **No root, no entitlement, no prompt, notarizable.** Confirmed posture for direct /
  notarized distribution (this app's model). **Not App-Sandbox-safe** and **not Mac App
  Store-eligible** (private framework) — identical caveat to D-014 (`top`) and D-017, so
  **no new distribution constraint** is introduced.

---

## Out of Scope

Explicitly excluded from this spec:
- **Temperatures** — separate increment, D-018.
- **Per-process power attribution** — no permission-free public API (same wall as
  per-process network in D-013).
- **Battery watts / charge-rate** — the Battery tile (D-007 era) already covers the
  power-source side; this tile is SoC draw.
- **Total wall/AC power** — Energy Model exposes SoC subsystems, not the whole-machine
  PSU draw; out of scope.
- **Power history graph / sparkline** — the strip is a glance HUD (D-006); no time series.
- **Mac App Store / sandbox support** — unchanged from D-014/D-017.
- **Fan/GPU changes** — shipped in D-017; untouched here.

---

## Open Questions

| Question | Status | Answer |
|----------|--------|--------|
| Headline format — total vs split? | Resolved | **CPU·GPU split** (`⚡ 8·4 W`); total lives in the detail card. |
| Tint normalization for "hot"? | Resolved | **Auto-track session peak** of total SoC watts; resets on relaunch. |
| Does a signed + hardened-runtime binary linking `-lIOReport` pass `notarytool`? | **Open** | No web source proves it. **Verify with a tiny signed test binary through notarytool before committing** (the one empirically-unconfirmed claim). |
| Include ANE + DRAM in the tint "total", or just CPU+GPU? | Open | Lean: total = CPU+GPU+ANE+DRAM for the detail Total row and tint; headline stays CPU·GPU. Confirm during build. |
| Fixed-width slot worst case for the split — `88·88 W`? | Open | Reserve a worst-case template (Ultra package can exceed 99 W total but per-subsystem rarely >99) per the D-008 hidden-template pattern; finalize width when seen on screen. |
| Tile glyph — `bolt.fill`? | Open | Confirm in the design pass alongside GPU's flagged `cpu.fill`. |

---

## Related

- **Decisions:** D-019 (to be written on ship); builds on D-017 (GPU+Fan, same
  permission-free + hide-when-absent + free-migration pattern), D-014 (sandbox/`top`
  caveat), D-002/D-003 (permission-free principle).
- **Research:** session 2026-06-15 — IOReport "Energy Model" path; primary precedent
  `macmon` (Rust, no-sudo: `src/sources.rs` `cfio_watts`, `src/metrics.rs` channel
  routing), `socpowerbud` (ObjC, `-lIOReport` bridging pattern), `NeoAsitop` (Swift),
  `zeus-apple-silicon` (channel-naming volatility incl. M5). Permission verdict: no root,
  no entitlement; fragility = channel names drift per chip generation (silent zeros, not
  crashes) → hide-on-unavailable is mandatory.
- **Cookbook candidate:** a new entry "permission-free SoC power via IOReport Energy
  Model" alongside 66/68/69/74 once shipped.
- **Reuse:** `Sampling/NetworkSampler.swift` (delta-per-tick shape), `Sampling/
  FanSampler.swift` (long-lived connection ownership), `Sampling/GPUSampler.swift`
  (hide-when-absent `empty` gate).
</content>
</invoke>
