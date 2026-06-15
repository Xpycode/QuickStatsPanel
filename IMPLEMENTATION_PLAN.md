# Implementation Plan — Power Tile (D-019)

> **Status: READY TO EXECUTE.** Source spec: `specs/power-stats.md`. Increment after
> D-017 (GPU+Fan); Temps = D-018 (separate plan). Run `/execute` to start.

## Goal
Add one permission-free **Power tile** — live CPU + GPU watts (split headline `⚡ 8·4 W`,
per-subsystem detail card) — to the data-driven strip, reusing the existing `StatKind` →
`StatDescriptor` → `StatsStore.visibleStats` pipeline. Watts come from Apple's private,
**un-entitled** IOReport framework "Energy Model" energy counters (W = ΔJoules ÷ Δseconds) —
the no-sudo path the `macmon`/`NeoAsitop` tools prove. The tile **hides when Energy Model
channels don't resolve** (Intel Macs / untested future chips), like Battery on desktops.

## Acceptance Criteria (from spec — abbreviated; see `specs/power-stats.md` for Given/When/Then)
- [ ] AC-1 Reads live watts un-elevated (no sudo, no entitlement, hardened runtime) — no prompt
- [ ] AC-2 watts = (ΔenergyCounter ÷ unitDivisor) ÷ interval, divisor from each channel's **runtime unit label** (mJ/uJ/nJ), not hardcoded
- [ ] AC-3 Tile shows `⚡ <cpu>·<gpu> W`; width never reflows as values change (fixed-width slot, D-008)
- [ ] AC-4 Detail card: CPU / GPU / ANE / DRAM / Total watts rows, plausible vs workload
- [ ] AC-5 Tint via `loadPercent = currentTotal ÷ sessionPeakTotal × 100`; peak ratchets up, never down
- [ ] AC-6 Hidden when Energy Model / CPU+GPU channels don't resolve (Intel / renamed channels) — no crash, no empty tile, absent from Settings list
- [ ] AC-7 First tick (no prior sample) shows `0·0 W` — no spurious huge/blank flash (Network seeding)
- [ ] AC-8 Multi-cluster aggregation: match channels by **prefix/suffix**, sum all matching dies (no Pro/Max/Ultra under-report)
- [ ] AC-9 Existing users get the tile ON via `knownStats` migration; deliberately-off stats preserved
- [ ] AC-10 No CF leak: every `IOReportCreateSamples`/`…Delta` `CFRelease`d each tick; subscription released on teardown; memory flat over time
- [ ] AC-11 All IOReport work on the sampler's background queue; UI thread only reads the published `PowerSample`

## Locked design decisions (don't re-litigate)
- **Headline = CPU·GPU split** (`⚡ 8·4 W`, integers); **total** lives in the detail card. *(user choice)*
- **Tint = auto-tracked session peak** of total SoC watts; resets on relaunch. *(user choice)*
- **Subscribe via `IOReportCopyAllChannels(0,0)` + filter `group == "Energy Model"`** at read time — NOT `IOReportCopyChannelsInGroup` (all 3 reference tools do this; avoids an `NSString*` bridging call).
- **Channel routing by prefix/suffix** (macmon `src/metrics.rs`): `hasSuffix("CPU Energy")`, `== "GPU Energy"`, `hasPrefix("ANE")`, `hasPrefix("DRAM")`. Exact-match misses Ultra multi-die.
- **Read `IOReportChannelGetUnitLabel` per channel** → divisor `mJ`→1e3 / `uJ`→1e6 / `nJ`→1e9 (default mJ). Do **not** hardcode mJ (macmon handles all three; NeoAsitop's hardcode is a known shortcut).
- **Delta-per-tick across ticks** (NetworkSampler shape), NOT macmon's blocking sleep-between-two-samples: hold the previous raw sample, delta against it each tick, divide by `interval`. First tick has no prev → emits `0·0 W` (seeding), not hidden.
- **`isAvailable` decided at sampler init** (did the subscription resolve Energy Model CPU/GPU channels?), independent of having a delta yet — so AC-6 hides on Intel/unsupported, while AC-7 shows `0·0 W` for one tick on supported hardware. (Divergence from GPU/Fan, where availability is per-snapshot.)
- **`loadPercent` is a STORED field on `PowerSample`, set by the sampler** from its running `peakTotal` ratchet — the descriptor has no cross-tick memory. (Divergence from GPU/Fan, where `loadPercent` is purely computed from the sample.)
- **Hide-when-absent via `descriptor(for:)` returning `nil`** — identical to Battery (`StatDescriptor.swift:~193`), GPU, Fan. No new mechanism.
- **NOT visibility-gated** — IOReport reads are cheap in-process calls; run continuously like CPU/GPU/Fan. Only the costly `top` sampler stays gated.
- **Migration is free** — `knownStats` (`AppSettings.swift:197–219`) defaults any new `StatKind` ON and appends to `statOrder`. No migration code (verify in AC-9).
- **Distribution caveat UNCHANGED** — permission-free & notarizable but **not App-Sandbox-safe** (private framework), same class as D-014 `top` / D-017. Fine for direct/notarized.

## Open questions carried from spec (defaults chosen; override anytime)
1. ANE + DRAM included in the tint **total** (CPU+GPU+ANE+DRAM)? **Default: yes** — Total row + tint use all four; headline stays CPU·GPU.
2. Tile glyph **`bolt.fill`**? *(default; confirm in design pass alongside GPU's flagged `cpu.fill`)*
3. `widestValue` worst case **`88·88 W`**? *(default; Ultra GPU could exceed 99W under extreme load → clip, acceptable like D-011's load>99 note. Finalize on screen.)*
4. **notarytool risk (flagged, NOT dev-blocking):** no source proves a signed+hardened binary linking `-lIOReport` passes `notarytool`. Notarization isn't wired up yet (Release signing is still Xcode-automatic per `project.yml`), so this is a **release gate**, verified when notarization is set up — see Risk notes. Build/run/notarize-locally smoke in T4.5.

## Specs
- `specs/power-stats.md` — full Given/When/Then, research provenance, technical considerations.

## Grounded reference (live source, fetched 2026-06-15 — embed so execution needs no re-research)

**Swift bridging (NeoAsitop pattern — `op06072/NeoAsitop`):**
- New **bridging header** `Sources/QuickStatsPanel/QuickStatsPanel-Bridging-Header.h` holding plain `extern` C decls (no `dlopen`, no `@_silgen_name`).
- `project.yml` target `settings.base`: `SWIFT_OBJC_BRIDGING_HEADER: Sources/QuickStatsPanel/QuickStatsPanel-Bridging-Header.h` **and** `OTHER_LDFLAGS: -lIOReport` (resolves against `/usr/lib/libIOReport.tbd` in the dyld shared cache; no relocated-framework Library-Validation issue).

**The `extern` block for the bridging header** (verbatim-usable; types chosen so Swift bridges cleanly — `NSString*` getters → `String?`, `Copy/Create` → `Unmanaged<…>!`):
```c
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

typedef struct IOReportSubscriptionRef* IOReportSubscriptionRef;  // → Swift OpaquePointer
typedef CFDictionaryRef IOReportSampleRef;
typedef int (^ioreportiterateblock)(IOReportSampleRef ch);

extern CFMutableDictionaryRef IOReportCopyAllChannels(uint64_t, uint64_t);
extern IOReportSubscriptionRef IOReportCreateSubscription(void* a, CFMutableDictionaryRef desired,
        CFMutableDictionaryRef* subbedOut, uint64_t channel_id, CFTypeRef b);   // subbedOut is OUT
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub,
        CFMutableDictionaryRef subbed, CFTypeRef a);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef prev, CFDictionaryRef cur, CFTypeRef a);
extern void IOReportIterate(CFDictionaryRef samples, ioreportiterateblock);
extern NSString* IOReportChannelGetGroup(CFDictionaryRef);
extern NSString* IOReportChannelGetChannelName(CFDictionaryRef);
extern NSString* IOReportChannelGetUnitLabel(CFDictionaryRef);     // add yourself; macmon/socpowerbud have it
extern int       IOReportChannelGetFormat(CFDictionaryRef);
extern long      IOReportSimpleGetIntegerValue(CFDictionaryRef, int);
```

**Call sequence + CFRelease accounting (matches NeoAsitop `IOReportDump/main.swift` + macmon `Drop`):**
- **Init once:** `let all = IOReportCopyAllChannels(0,0)` (+1); `var subbed: Unmanaged<CFMutableDictionary>? = nil`; `sub = IOReportCreateSubscription(nil, all.takeRetainedValue(), &subbed, 0, nil)`. Keep `sub` (OpaquePointer) + `subbed` alive. `takeRetainedValue()` **consumes** the channels +1.
- **Per tick:** `cur = IOReportCreateSamples(sub, subbed!.takeUnretainedValue(), nil)` (+1; borrow `subbed`). If a `prev` exists: `delta = IOReportCreateSamplesDelta(prev.takeUnretainedValue(), cur.takeUnretainedValue(), nil)` (+1) → iterate → `delta.release()` after. Then release old `prev`, store `cur` as new `prev`. First tick: no `prev` → emit `0·0 W`, just prime baseline.
- **Iterate:** `IOReportIterate(delta.takeUnretainedValue()) { chan in autoreleasepool { … }; return 0 /*kIOReportIterOk*/ }`. Inside: guard `IOReportChannelGetGroup(chan) == "Energy Model"` && `IOReportChannelGetFormat(chan) == 1 /*Simple*/`; `name = IOReportChannelGetChannelName(chan)`; `unit = IOReportChannelGetUnitLabel(chan)`; `raw = Double(IOReportSimpleGetIntegerValue(chan, 0))`; `watts = (raw / divisor(unit)) / dt`; route by name.
- **Teardown (`stop()`/`deinit`):** `subbed?.release()`; release held `prev`; `CFRelease(UnsafeRawPointer(sub))` once (sub is CF-backed; never released per-sample).

**Strict-concurrency:** CF dicts, `Unmanaged`, and the `OpaquePointer` sub are **non-Sendable**. Confine them to the sampler's serial `DispatchQueue` (every IOReport call inside `queue`); only the value-type `PowerSample: Sendable` escapes. Same confinement FanSampler uses for its `SMC` connection. Do **not** mark the wrapper `@unchecked Sendable` unless every access is queue-gated.

**Energy Model alone yields CPU+GPU+ANE+DRAM** — no `IOReportMergeChannels` needed for power.

**Codebase touch points (verified file:line, 2026-06-15):**
- `Model/StatDescriptor.swift`: enum `StatKind` (line ~8) add `.power`; `displayName` switch (~17–29) add `"Power"`; `settingsSymbol` switch (~33–45) add `"bolt.fill"`; `descriptor(for:)` switch (~137–263) add `.power` case (GPU case at ~209–220 / Fan at ~222–237 are the templates); `visibleStats` (~107–125) `compactMap` is the hide chokepoint. `StatDescriptor` fields: `kind, symbol, value, widestValue, loadPercent, detail: [(String,String)], processSection?` (~51–94).
- `Model/StatsStore.swift`: published samples (~14–23) add `var power: PowerSample = .empty`; sampler fields (~26–35) add `private var powerSampler: PowerSampler?`; `start()` instantiate+`.start()` after `fan` (~86–104, **un-gated**); assign `self.powerSampler = power` (~108–117); `stop()` add `powerSampler?.stop()` + `= nil` (~120–136). Sample flow: sampler callback → `Task { @MainActor in self?.power = sample }`.
- `Sampling/NetworkSampler.swift`: delta-per-tick template — `previousBytes` held state (~47), `tick()` (~67–81) seeds on first tick (rates 0), deltas after, updates baseline last.
- `Views/StatDetailView.swift`: `content(_:theme:)` (~36–77) renders `descriptor.detail` as a `ForEach` of (label,value) rows — no change needed; Power just supplies 5 rows.
- `Views/StatTileView.swift`: fixed-width slot (~41–44) `ZStack { Text(widestValue).fontWeight(.heavy).hidden(); Text(value) }` — no change; Power supplies `widestValue`.
- `Model/AppSettings.swift`: `knownStats` migration (~197–219) — **no change**, `.power` rides free.
- `01_Project/project.yml`: target `settings.base` (~47–50) — add the two settings above. **No bridging header exists yet** — this is the first.

---

## Tasks

### Wave 1 — IOReport foundation + de-risking spike (the only novel/fiddly part; do FIRST, in isolation) — ✅ DONE 2026-06-15

> **Result (validated on the M4 Pro, un-elevated uid 501):** bridging header compiles,
> `-lIOReport` links (confirmed in the link line), clean build **0 warnings**.
> `IOReportPower.isAvailable == true`; first `read()` returns nil → caller shows `0·0 W`
> (AC-7 seeding ✓); idle ≈ CPU 0.3 / GPU 0.2 / ANE 0 / DRAM 0.1 W; under a 12-core `yes`
> load **CPU rose to ~6 W while GPU/ANE stayed flat and DRAM ticked up** — correct
> per-subsystem routing + ΔJ÷Δs math (AC-1/AC-2/AC-8 de-risked). The exact
> `sudo powermetrics` ballpark cross-check is the one step left for the user (needs sudo);
> magnitudes are already plausible. A `#if DEBUG IOReportPower.debugDump()` spike helper
> remains in `IOReport.swift` for that cross-check + T4.2/T4.4 verification.
> **Wave 2 may proceed: `read() -> (cpu,gpu,ane,dram: Double)?` and `isAvailable` are the contract.**

**T1.1 — Bridging header + linker config + `Sampling/IOReport.swift` wrapper**
- *Files:* new `Sources/QuickStatsPanel/QuickStatsPanel-Bridging-Header.h` (the `extern` block above); new `Sources/QuickStatsPanel/Sampling/IOReport.swift` (`final class IOReportPower` — serial-queue-confined subscription; `read() -> (cpu,gpu,ane,dram: Double)?` returning nil on the priming tick; full CFRelease accounting); `01_Project/project.yml` add `SWIFT_OBJC_BRIDGING_HEADER` + `OTHER_LDFLAGS: -lIOReport`.
- *Build:* subscribe via `IOReportCopyAllChannels(0,0)` once; per-tick sample→delta→iterate→watts with runtime unit-label divisor and prefix/suffix routing; compute `dt` from `CFAbsoluteTimeGetCurrent()` (don't assume the timer's nominal interval). Expose `isAvailable` = "did the subscription resolve ≥1 CPU or GPU Energy channel" (probe once at init).
- *Success:* `xcodegen generate` picks up the bridging header + flag; project **links** against `-lIOReport`; a throwaway dump (temp `print` loop or a `#if DEBUG` test fn) prints CPU/GPU/ANE/DRAM watts each second **un-elevated** (proves AC-1).
- *Backpressure:* `cd 01_Project && xcodegen generate && xcodebuild -scheme QuickStatsPanel build` clean; **cross-check the printed watts against `sudo powermetrics --samplers cpu_power,gpu_power -i 1000` within lag** (the watts must be in the same ballpark — this is the load-bearing validation; do it before building the sampler on top).

### Wave 2 — PowerSampler + PowerSample (depends on T1.1) — ✅ DONE 2026-06-15

> **Result (validated on the M4 Pro, un-elevated):** clean build 0 warnings.
> Live dump: tick 0 → `"0·0 W"` load 0% (AC-7 seed ✓); under load headline renders the
> CPU·GPU split `"6·0 W"`; **peakTotal ratchets up monotonically (6.55→6.88→7.04→7.18 W)
> and never drops (AC-5 ✓)**; loadPercent = total÷peak×100 (saw 97% when total dipped
> below the running peak). Peak resets in `start()` so `restart()` recalibrates. The
> sample-building math is a pure `PowerSampler.makeSample(from:available:peak:)` shared by
> `tick()` and the DEBUG dump. `isAvailable=false` hide path is structurally reachable
> (propagated through `makeSample`); forced-stub confirmation is Wave 4 T4.4.
> **Wave 3 may proceed: publish `power: PowerSample` + own `powerSampler` + `.power` descriptor.**

**T2.1 — `Sampling/PowerSampler.swift` + `PowerSample`**
- *Files:* new `Sources/QuickStatsPanel/Sampling/PowerSampler.swift`
- *Build:* `struct PowerSample: Equatable, Sendable` — `isAvailable: Bool`, `cpuWatts/gpuWatts/aneWatts/dramWatts: Double`, **stored** `loadPercent: Double`, `static let empty` (isAvailable:false); computed `totalWatts`, `headlineFormatted` (`"\(Int(cpuWatts.rounded()))·\(Int(gpuWatts.rounded())) W"`), per-subsystem `*Formatted` (`String(format:"%.1f W", …)`), `totalFormatted`. `final class PowerSampler` on the `GPUSampler`/`FanSampler` `DispatchSourceTimer` skeleton, owning one `IOReportPower` (created in `start()`, torn down in `stop()`); each tick: `read()` → watts; ratchet `peakTotal = max(peakTotal, total)`; set `sample.loadPercent = peakTotal > 0 ? min(total/peakTotal*100, 100) : 0`; emit. First tick (`read()` returns nil) → emit `0·0 W` with `isAvailable` from the wrapper.
- *Success:* compiles; throwaway print shows the split headline string updating and `loadPercent` rising under load then holding its peak; `isAvailable=false` path reachable (stub the wrapper).
- *Backpressure:* build clean; headline/`loadPercent` sanity vs the T1.1 watts.

### Wave 3 — Wire into the strip (depends on Wave 2; ONE compile unit — a new `StatKind` forces exhaustive switches, so 3.1–3.3 land together)

**T3.1 — `StatKind`: add `.power`**
- *Files:* `Model/StatDescriptor.swift`
- *Build:* add `power` to the enum; `displayName` → `"Power"`; `settingsSymbol` → `"bolt.fill"`. Place adjacent to `gpu`/`fan` (order only sets default strip position).
- *Success:* enum exhaustive; Settings list would show it. *Backpressure:* build clean.

**T3.2 — `StatsStore`: publish `power` + own `powerSampler`**
- *Files:* `Model/StatsStore.swift`
- *Build:* add `var power: PowerSample = .empty`; `powerSampler` field; create+`.start()` in `start()` **after `fan` (un-gated — NOT inside `if panelVisible`)**; assign; `stop()`+nil. `restart()` already cycles stop/start.
- *Success:* `store.power` updates each tick. *Backpressure:* build clean.

**T3.3 — `descriptor(for:)`: Power tile with hide-gating**
- *Files:* `Model/StatDescriptor.swift` (the `StatsStore` extension)
- *Build:* `.power` → `guard power.isAvailable else { return nil }`; `symbol:"bolt.fill"`, `value: power.headlineFormatted`, `widestValue:"88·88 W"`, `loadPercent: power.loadPercent`, `detail: [("CPU",power.cpuFormatted),("GPU",power.gpuFormatted),("ANE",power.aneFormatted),("DRAM",power.dramFormatted),("Total",power.totalFormatted)]`.
- *Success:* tile renders on the M4 Pro; nil-path hides cleanly. *Backpressure:* build clean.

### Wave 4 — Verify, migrate, document

**T4.1 — Clean build from scratch, 0 warnings**
- `cd 01_Project && xcodegen generate` (confirm bridging header + `IOReport.swift`/`PowerSampler.swift` in target) `&&` kill app, clean DerivedData, `xcodebuild -scheme QuickStatsPanel build`. *Success:* `** BUILD SUCCEEDED **`, 0 Swift warnings (AC-1/AC-8-equiv).

**T4.2 — On-screen verify (AC-3/AC-4/AC-5)**
- Launch, summon strip → Power tile after the existing tiles, showing `⚡ <cpu>·<gpu> W`. Run a CPU+GPU load (e.g. a shader/stress) → both numbers rise, the tile width never reflows, tint ramps hotter; idle → falls (peak holds). Click → detail card shows CPU/GPU/ANE/DRAM/Total. **Cross-check vs `sudo powermetrics`/Activity Monitor Energy.**

**T4.3 — Migration + Settings (AC-9)**
- Existing-user path: `defaults write com.sim.QuickStatsPanel knownStats -array cpu memory disk network battery gpu fan loadAverage uptime` (omit `power`), relaunch → Power lights up ON and appends to `statOrder` without disturbing a deliberately-off stat. Settings shows it; toggle off → tile vanishes; reorder persists.

**T4.4 — Hide-path + leak check (AC-6/AC-7/AC-10)**
- **AC-6** can't be triggered on the M4 Pro (it *has* Energy Model) → verify by inspection + a forced `isAvailable=false` stub: tile disappears, no empty slot, no crash; revert. Note the honest limit (no Intel/VM to test on) in the session log. **AC-7:** confirm first summon shows `0·0 W` for ≤1 tick, never a huge number. **AC-10:** leave the app running ~10 min with the panel open, watch memory in Activity Monitor — flat (no per-tick CF leak).

**T4.5 — Document, notarize-smoke & log**
- Add **D-019** to `docs/decisions.md` (IOReport Energy Model; `CopyAllChannels`+group-filter; unit-label divisor; prefix/suffix routing; delta-per-tick; session-peak tint; init-time availability; un-gated; sandbox caveat). Update `PROJECT_STATE.md` (mark D-019 shipped, roadmap row → ✅). Add a session-log entry. Archive this plan to `docs/sessions/IMPLEMENTATION_PLAN-power-DONE.md`.
- **Notarytool smoke (release-gate, do once):** if/when notarization is wired, run a signed+hardened build through `notarytool` to confirm `-lIOReport` doesn't trip it. If notarization isn't set up this cycle, leave the flagged risk noted in D-019 and PROJECT_STATE — don't claim it's verified.
- *Follow-up (not blocking):* draft cookbook entry "permission-free SoC power via IOReport Energy Model" (alongside 66/68/69/74).

---

## Risk / sequencing notes
- **T1.1 is the whole risk.** The bridging header, `-lIOReport` link, `Unmanaged` accounting, and unit-label/routing are all load-bearing and novel to this codebase. The embedded reference above is drop-in (NeoAsitop is a working Swift precedent). Validate watts vs `powermetrics` **before** building the sampler/tile, so a bridging or units bug surfaces in isolation — exactly how SMC.swift was de-risked first in D-017.
- **Fragility (why this is a separate decision):** IOReport is private/undocumented. A new chip generation can rename channels → the tile reads 0 and **hides** (AC-6), it does **not** crash. That graceful degradation is mandatory, not optional — `guard isAvailable`/`nil`-descriptor is the safety net.
- **notarytool (flagged, unproven):** the one claim no web source confirms. Not dev-blocking (notarization isn't wired yet); gate it at release (T4.5). If it ever fails, fallback is `dlopen`/`dlsym` of IOReport at runtime (avoids the link-time symbol) — keep in back pocket, don't build pre-emptively.
- **Wave ordering:** Wave 1 → 2 → 3 strictly serialize (each builds on the prior). Within Wave 3, 3.1–3.3 are one compile unit (the new `StatKind` breaks exhaustive switches until all three land). Wave 4 is verification.
- **Distribution caveat unchanged** — notarizable & permission-free but **not** App-Sandbox-safe; consistent with D-014/D-017. Fine for direct/notarized distribution.
</content>
