# Implementation Plan — GPU + Fan Stats (D-017)

> **Persists across sessions.** Regenerate when wrong rather than patching.
> Source spec: `specs/gpu-fan-stats.md` (drafted 2026-06-15).
> Increment 1 of 2 in the GPU/temps/fans roadmap item. Temps = D-018 (separate plan).

## Goal
Add two new permission-free stat tiles — **GPU utilization (%)** and **Fan speed (rpm)** —
to the data-driven strip, reusing the existing `StatKind` → `StatDescriptor` →
`StatsStore.visibleStats` pipeline. GPU is an IOKit `IOAccelerator` registry read (same shape
as `DiskSampler`); fans use a new minimal read-only `AppleSMC` reader that correctly decodes
the Apple-Silicon `flt` type. Both hide when the hardware is absent, like Battery on desktops.

## Acceptance Criteria (from spec — abbreviated; see `specs/gpu-fan-stats.md` for Given/When/Then)
- [ ] AC-1 GPU tile shows live 0–100% tracking Activity Monitor, colors hotter as it rises
- [ ] AC-2 GPU tile hidden when no `IOAccelerator` utilization key (VM / headless)
- [ ] AC-3 Fan tile shows live rpm matching a reference reader (fastest fan if several)
- [ ] AC-4 Fan tile hidden on fanless Macs (`FNum == 0`) / SMC read failure
- [ ] AC-5 Detail cards: GPU → Utilization (+ device name); Fan → per-fan current/min/max
- [ ] AC-6 SMC `flt` decoding correct (sane positive rpm, not `fpe2`-garbage)
- [ ] AC-7 Existing users get both tiles ON once via the `knownStats` migration, order preserved
- [ ] AC-8 Permission-free, notarizable, builds clean from scratch with 0 Swift warnings

## Locked design decisions (don't re-litigate)
- **GPU read = `IOServiceMatching(kIOAcceleratorClassName)`** (the SDK constant == `"IOAccelerator"`),
  walk services, read `props["PerformanceStatistics"]["Device Utilization %"]` (Int 0–100),
  fallback `"GPU Activity(%)"`. Same registry walk as `DiskSampler.readBlockStorageBytes`.
- **SMC reader is READ-ONLY** — open `AppleSMC` once, never write (fan *control* needs privileges;
  reading never does). Lives in `Sampling/SMC.swift`, owned by `FanSampler` (closed on `stop()`).
- **`flt` is native little-endian; `ui16`/`ui32`/`sp**` are big-endian.** This is the crux —
  decode `flt` via `load(as: Float.self)`, assemble integer types MSB-first. (Old readers that only
  know `fpe2`/`sp78` read garbage for the `flt` fan keys M-series uses → AC-6.)
- **`loadPercent` feeds the existing tint pipeline** (no per-tile color code): GPU = utilization %
  (higher = hotter); Fan = current rpm normalized between this fan's min/max (near full tilt = hot),
  guarded against `max == min`.
- **Hide-when-absent via `descriptor(for:)` returning `nil`** — identical to Battery's
  `guard battery.isPresent` (StatDescriptor.swift:193). No new mechanism.
- **Not gated to panel-visible** — GPU + SMC reads are cheap in-process reads; run continuously like
  CPU/Disk. Only the costly `top` sampler stays visibility-gated.
- **Migration is free** — the `knownStats` logic (AppSettings.swift:205–219) defaults any new
  `StatKind` ON and appends it to `statOrder`. No migration code to write (verify in AC-7).

## Open questions carried from spec (defaults chosen; override anytime)
1. Multiple fans → headline = **fastest fan's rpm**. *(default)*
2. GPU detail rows = **Utilization + device name**; no renderer/tiler split. *(default)*
3. Fan tile symbol = **`fanblades`** (static). GPU tile/settings symbol = **`cpu.fill`** —
   ⚠ weak choice (reads near "CPU"); flag for the design pass, easy one-line swap. *(default, low-confidence)*
4. New cookbook entry (permission-free GPU + SMC fan stats) — **after ship** (Wave 4 follow-up).

## Specs
- `specs/gpu-fan-stats.md` — full Given/When/Then, research provenance, technical considerations.

## Grounded reference (live source, fetched 2026-06-15 — embed these so execution needs no re-research)
- **SMC reader** distilled from `exelban/stats` `SMC/smc.swift` (master): structs `SMCKeyData_t`
  (+ nested `vers_t`/`LimitData_t`/`keyInfo_t`) and `SMCVal_t`; constants `kernelIndex=2`,
  `READ_BYTES=5`, `READ_KEYINFO=9` (command byte → `input.data8`); open via
  `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))` +
  `IOServiceOpen(...,0,&conn)`; two-step `IOConnectCallStructMethod(conn, 2, &in, stride, &out, &outSize)`
  (reset `outSize` to `stride` each call; feed `keyInfo.dataSize` from step 1 into step 2); decode by
  4-char `dataType` (`flt `→`load(as:Float)`, `fpe2`→`(b0<<6)+(b1>>2)`, `ui8/ui16/ui32` big-endian,
  `sp78`→`/256`, …). Fan keys: `FNum`, `F<i>Ac`, `F<i>Mn`, `F<i>Mx`.
- **GPU read** distilled from `exelban/stats` `Modules/GPU/reader.swift` + `Kit/helpers.swift`:
  `IOServiceMatching(kIOAcceleratorClassName)` → `IOServiceGetMatchingServices` → `IOIteratorNext`
  (release each entry) → `IORegistryEntryCreateCFProperties` → `["PerformanceStatistics"]` sub-dict →
  `"Device Utilization %"` (Int) ?? `"GPU Activity(%)"`; clamp 0–100; device name from
  `props["model"]` (ASCII `Data`, NUL-stripped). Return `nil` ⇒ hide.

---

## Tasks

### Wave 1 — Independent foundation (parallel; no shared deps)

**T1.1 — `Sampling/SMC.swift`: read-only AppleSMC reader**
- *Files:* new `01_Project/Sources/QuickStatsPanel/Sampling/SMC.swift`
- *Build:* `final class SMC` — open in `init` (match `AppleSMC`, `IOServiceOpen`, release device/iterator;
  set `conn=0` on failure), `close()`/`deinit` via `IOServiceClose`. Private `SMCKeyData_t` structs with
  exact field order, `FourCharCode(fromString:)` + `toString()`, two-step `read(_:)`, and public
  `value(forKey:) -> Double?` dispatching on `dataType` (handle `flt `, `fpe2`, `ui8`, `ui16`, `ui32`,
  `sp78`). Guard `dataSize > 0`; bound the 32-byte copy by `min(dataSize,32)`.
- *Success:* compiles; a throwaway `main`/test prints `FNum` ≥ 1 and `F0Ac` as a plausible rpm
  (~1000–6000) **matching iStat Menus / `sudo powermetrics --samplers smc` within lag** (AC-6).
- *Backpressure:* `xcodebuild -scheme QuickStatsPanel build` clean; manual rpm cross-check.

**T1.2 — `Sampling/GPUSampler.swift` + `GPUSample`: IOAccelerator utilization**
- *Files:* new `01_Project/Sources/QuickStatsPanel/Sampling/GPUSampler.swift`
- *Build:* `struct GPUSample: Equatable, Sendable` (`var isAvailable: Bool`, `var utilizationPercent: Double`,
  `var deviceName: String?`, `static let empty`, plus `percentFormatted` "34%" and `loadPercent`).
  `final class GPUSampler` on the `BatterySampler`/`DiskSampler` `DispatchSourceTimer` skeleton; a static
  `readGPUUtilization() -> (percent: Double, name: String?)?` doing the registry walk (return `nil` ⇒
  `isAvailable=false`). No SMC dependency.
- *Success:* compiles; throwaway print shows utilization tracking Activity Monitor's GPU History while a
  GPU load runs (AC-1), and `nil`/`isAvailable=false` path is reachable.
- *Backpressure:* build clean; manual cross-check vs Activity Monitor (Window ▸ GPU History).

### Wave 2 — Fan sampler (depends on T1.1)

**T2.1 — `Sampling/FanSampler.swift` + `FanSample`**
- *Files:* new `01_Project/Sources/QuickStatsPanel/Sampling/FanSampler.swift`
- *Build:* `struct FanSample: Equatable, Sendable` carrying `hasFans: Bool` and `fans: [Fan]`
  (`Fan { current, min, max: Double }`, all rpm), `static let empty`, plus computed `headlineRPM`
  (**fastest** fan), `headlineFormatted` ("2100 rpm"), and `loadPercent` (fastest fan's current
  normalized in [min,max], guard `max>min`). `final class FanSampler` owns one `SMC` instance, reads
  `FNum` then loops `F<i>Ac`/`F<i>Mn`/`F<i>Mx`; `hasFans = FNum>0 && !fans.isEmpty`; `stop()` closes SMC.
- *Success:* compiles; throwaway print shows N fans with sane current/min/max on the M4 Pro;
  `hasFans=false` when `FNum==0` (AC-3/AC-4/AC-6).
- *Backpressure:* build clean; rpm cross-check vs reference reader.

### Wave 3 — Wire into the strip (depends on Waves 1–2; one compile unit)

> A new `StatKind` case forces exhaustive switches to update, so 3.1–3.3 land together and compile as one.

**T3.1 — `StatKind`: add `.gpu`, `.fan`**
- *Files:* `Model/StatDescriptor.swift`
- *Build:* add `gpu, fan` to the enum; add `displayName` ("GPU", "Fans") and `settingsSymbol`
  ("cpu.fill" ⚠ / "fanblades") cases. Place after `battery`/before `loadAverage`, or end — order only
  affects default strip position; pick GPU + Fan adjacent.
- *Success:* enum exhaustive; Settings list would show both. *Backpressure:* build clean.

**T3.2 — `StatsStore`: publish samples + own samplers**
- *Files:* `Model/StatsStore.swift`
- *Build:* add `var gpu: GPUSample = .empty`, `var fan: FanSample = .empty`; sampler fields
  `gpuSampler`/`fanSampler`; create+start in `start()` (continuous, NOT visibility-gated), stop+nil in
  `stop()`. `restart()` already calls stop+start.
- *Success:* samplers tick; `store.gpu`/`store.fan` update. *Backpressure:* build clean.

**T3.3 — `descriptor(for:)`: GPU + Fan tiles with hide-gating**
- *Files:* `Model/StatDescriptor.swift` (the `StatsStore` extension)
- *Build:* `.gpu` → `guard gpu.isAvailable else { return nil }`; headline `gpu.percentFormatted`,
  `widestValue:"100%"`, `loadPercent: gpu.utilizationPercent`, detail `[("Utilization", …)]` + device name.
  `.fan` → `guard fan.hasFans else { return nil }`; headline `fan.headlineFormatted`,
  `widestValue:"8888 rpm"`, `loadPercent: fan.loadPercent`, detail one row per fan (current) + a
  range row. Symbols: GPU "cpu.fill" ⚠, Fan "fanblades".
- *Success:* both tiles render on the M4 Pro; nil-paths hide cleanly. *Backpressure:* build clean.

### Wave 4 — Verify, migrate, document

**T4.1 — Clean build from scratch, 0 warnings**
- `cd 01_Project && xcodegen generate` (confirm new files in target) `&&` kill app, clean DerivedData,
  `xcodebuild -scheme QuickStatsPanel build`. *Success:* `** BUILD SUCCEEDED **`, 0 Swift warnings (AC-8).

**T4.2 — On-screen verify (AC-1/3/5)**
- Launch, summon strip → GPU + Fan tiles present after the existing tiles. Run a GPU load (e.g. a
  shader/scroll), confirm GPU % tracks Activity Monitor and the fan rpm matches a reference reader and
  rises under load. Click each tile → detail card correct. Colors ramp hotter with load.

**T4.3 — Migration + Settings (AC-7)**
- Fresh-install path: both tiles default ON. Existing-user path: with a stored `knownStats` lacking
  `gpu`/`fan` (simulate via `defaults write com.sim.QuickStatsPanel knownStats -array cpu memory disk …`),
  relaunch → both light up ON and append to `statOrder` without disturbing deliberately-off stats.
  Settings list shows both; toggle off → tile vanishes; reorder persists.

**T4.4 — Hide-path check (AC-2/4)**
- Can't fully test fanless/no-GPU on the M4 Pro, so **verify the nil-paths by inspection + a forced
  return**: temporarily stub `isAvailable=false` / `hasFans=false`, confirm the tile disappears with no
  empty slot or crash, then revert. Note the limit honestly in the session log (no silent "covered it").

**T4.5 — Document & log**
- Add **D-017** to `docs/decisions.md` (GPU via IOAccelerator; read-only SMC fan reader; `flt` decode;
  hide-when-absent; not visibility-gated). Update `PROJECT_STATE.md` (mark D-017 shipped, roadmap row).
  Add a session-log entry. Archive this plan to `docs/sessions/IMPLEMENTATION_PLAN-gpu-fan-DONE.md`.
- *Follow-up (not blocking):* draft cookbook entry "permission-free GPU + SMC fan stats".

---

## Risk / sequencing notes
- **SMC.swift (T1.1) is the only fiddly task** — struct field order and `flt`/big-endian decode are
  load-bearing; the embedded reference above is drop-in. Do it first and cross-check rpm *before*
  building the sampler on top, so a decode bug surfaces in isolation, not buried in the tile.
- **T1.1 and T1.2 are genuinely parallel** (SMC vs IOAccelerator — no shared code). Wave 2/3 serialize.
- **Distribution caveat (unchanged):** all reads are notarizable & permission-free but **not
  App-Sandbox-safe** — consistent with the existing D-014 `top` caveat. Fine for direct/notarized.
</content>
