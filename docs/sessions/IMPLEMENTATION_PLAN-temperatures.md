# Implementation Plan — Temperatures Tile (D-018)

> **Status: WAVE 1 IN PROGRESS.** Decision: `decisions.md` D-018. Last roadmap stat;
> increment after D-019 (Power). Run `/execute` or work the waves in order.

## Goal
Add one permission-free **Temperatures tile** to the data-driven strip, reusing the existing
`StatKind` → `StatDescriptor` → `StatsStore.visibleStats` pipeline. **Two layers:**
- **Headline = `ProcessInfo.thermalState`** (`Nominal`/`Fair`/`Serious`/`Critical`) — public,
  guaranteed, permission-free → the tile is **always visible** (never `nil`-descriptors), the
  project's first always-on *optional* tile.
- **Detail card = best-effort per-sensor °C via IOHID** (`IOHIDEventSystemClient` +
  `kIOHIDEventTypeTemperature`) — named sensors grouped CPU/GPU/SoC/Battery, sanity-clamped,
  with a `Pressure: <state>` fallback row when IOHID enumerates nothing.

## Acceptance Criteria
- [ ] AC-1 Tile is **always visible** (thermalState headline); shows `Nominal`/`Fair`/`Serious`/`Critical`.
- [ ] AC-2 Headline color **and** font-weight escalate via the shared `tint(for:percent:)` pipeline (state→loadPercent 0/40/75/100; calm→hot, `reversed:false`).
- [ ] AC-3 Detail card lists **named** per-sensor °C (CPU/GPU/SoC/Battery best-effort) read via IOHID, un-elevated (no sudo, no entitlement, no prompt).
- [ ] AC-4 Readings **sanity-clamped** — 0 / NaN / out-of-range (e.g. <-20 or >130 °C) dropped, never shown as "0°C".
- [ ] AC-5 IOHID returns no sensors (Intel / VM / renamed chip) ⇒ tile **still shows** (thermalState) with a `Pressure: <state>` fallback row — no crash, no empty card.
- [ ] AC-6 Fixed-width headline (widest `Critical`) — no jitter as the state word changes (Penumbra pattern).
- [ ] AC-7 `knownStats` migration: existing users get `.temps` ON, appended to `statOrder`; deliberately-off stats preserved.
- [ ] AC-8 No CF leak: per-tick `CopyEvent`/`CopyProperty` `Unmanaged` released each tick; client + services `CFArray` released on teardown; memory flat over time. All IOHID calls on the sampler's serial queue.
- [ ] AC-9 Clean build from scratch, **0 Swift warnings**; `-framework IOKit` in the link line; notarytool+IOHID flagged as a **release gate** (not dev-blocking), like D-019.
- [ ] AC-10 On-screen verified on Apple Silicon: tile present after Power, named sensors with plausible °C (ballpark cross-check vs Stats / `sudo powermetrics --samplers thermal` — user).

## Locked design decisions (don't re-litigate — see D-018)
- **Headline = thermalState badge** (word), NOT a hottest-°C number. *(user choice)* ⇒ descriptor **never returns `nil`** — the first always-visible optional tile. Do not "fix" into hiding.
- **state → loadPercent = nominal 0 / fair 40 / serious 75 / critical 100** — feeds the existing tint + weight pipeline, `reversed:false` (hotter = worse). Numbers tunable on screen (AC-2).
- **Detail = IOHID named sensors**, NOT SMC reuse — Apple-Silicon SMC temp keys (`Tp01`/`Tg05`) are undocumented, per-machine, identity-less; IOHID returns named float sensors. Reference: `fermion-star/apple_sensors`, `exelban/stats reader.m`.
- **Match dict `{ "PrimaryUsagePage": 0xff00, "PrimaryUsage": 5 }`**; value field `IOHIDEventGetFloatValue(event, kIOHIDEventTypeTemperature << 16)` (`kIOHIDEventTypeTemperature = 15` → field `0x000F0000`).
- **Prefix→cluster grouping** (avg per cluster): `pACC`/`eACC` → CPU, `GPU` → GPU, `SOC` → SoC, `gas gauge battery` → Battery. Finalized from the Wave-1 dump (sensor names drift per SoC).
- **Poll thermalState each tick** in the sampler — NOT `thermalStateDidChangeNotification` (background-queue + priming-read footgun). Matches all 10 existing samplers.
- **Bridging header is the existing one** (2nd consumer after IOReport) + `-framework IOKit`. No `dlopen`.
- **Not visibility-gated** — cheap in-process reads, run continuously like CPU/GPU/Fan/Power. **Migration free** via `knownStats`.
- **Distribution caveat unchanged** — permission-free & notarizable, **not** App-Sandbox-safe (private framework); same class as D-014/D-017/D-019.

## Grounded reference (live source, fetched 2026-06-15 — embed so execution needs no re-research)

**Bridging-header `extern` block** (append to the existing `QuickStatsPanel-Bridging-Header.h`; distinct opaque tags so Swift imports the client/service as `OpaquePointer` and the Copy results as `Unmanaged<…>`):
```c
// --- IOHID temperature sensors (D-018 Temperatures detail card) ---
typedef struct __IOHIDEventSystemClient* IOHIDEventSystemClientRef;  // → Swift OpaquePointer
typedef struct __IOHIDServiceClient*     IOHIDServiceClientRef;      // → Swift OpaquePointer

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void      IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
extern CFTypeRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern double    IOHIDEventGetFloatValue(CFTypeRef event, int32_t field);
```
- `project.yml` `settings.base`: change `OTHER_LDFLAGS: -lIOReport` → `OTHER_LDFLAGS: -lIOReport -framework IOKit`. (`SWIFT_OBJC_BRIDGING_HEADER` already set.)

**Call sequence + CF accounting (matches `fermion-star/apple_sensors temp_sensor.m`):**
- **Init once (in the reader):** `client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)` (+1, opaque → release in `deinit` via `Unmanaged.fromOpaque(...).release()`, like IOReport's `sub`). `IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage":0xff00,"PrimaryUsage":5] as CFDictionary)`. `services = IOHIDEventSystemClientCopyServices(client)` → `Unmanaged<CFArray>` → `takeRetainedValue()`, hold it (retains the service clients). Cache `[(label, OpaquePointer(serviceClient), name)]` by reading `IOHIDServiceClientCopyProperty(svc, "Product" as CFString)` per service (`CFArrayGetValueAtIndex` → `OpaquePointer`).
- **Per tick (`read() -> [TempReading]`):** for each cached `(label, svc)`: `guard let ev = IOHIDServiceClientCopyEvent(svc, 15, 0, 0)` (may be NULL → skip); `let event = ev.takeRetainedValue()` (ARC releases); `let c = IOHIDEventGetFloatValue(event, 15 << 16)`; clamp/validate; collect. Group by prefix, average per cluster.
- **Teardown (`deinit`):** drop the services `CFArray` (ARC, since held as a Swift `CFArray`); `Unmanaged.fromOpaque(UnsafeRawPointer(client)).release()` once.

**Strict-concurrency:** `IOHIDEventSystemClientRef`, the service pointers, and `CFArray` are non-Sendable → confine to the sampler's serial `DispatchQueue`. Only the value-type `TemperatureSample: Sendable` escapes. Same confinement Fan/Power use. Don't `@unchecked Sendable` unless every access is queue-gated.

**Codebase touch points (verified file:line, 2026-06-15):**
- `QuickStatsPanel-Bridging-Header.h` (40 lines): append the IOHID `extern` block.
- `01_Project/project.yml` (~55): `OTHER_LDFLAGS: -lIOReport` → `… -framework IOKit`.
- `Sampling/SMC.swift:5`: delete the stale "will be reused for Intel temperature keys in D-018" comment (we went IOHID).
- `Model/StatDescriptor.swift`: `StatKind` (line 8) add `temps` (after `power`); `displayName` (17–30) `"Temperature"`; `settingsSymbol` (34–47) `"thermometer"`; `descriptor(for:)` (139–282) add `.temps` case — **no `guard`** (always shows). `StatDescriptor` fields: `kind, symbol, value, widestValue, loadPercent, detail:[(String,String)], processSection?`.
- `Model/StatsStore.swift`: published samples (14–24) add `var temps: TemperatureSample = .empty`; sampler fields (27–37) add `private var temperatureSampler: TemperatureSampler?`; `start()` create + `.start()` after `power` (110, **un-gated**) + assign (121); `stop()` (135/146) add `temperatureSampler?.stop()` + `= nil`.
- `Views/StatDetailView.swift`, `StatTileView.swift`, `StatsStripView.swift`, `Model/AppSettings.swift`: **no change** (generic + free migration).

---

## Tasks

### Wave 1 — IOHID foundation + de-risking spike (the only novel part; do FIRST, in isolation)

**T1.1 — Bridging header + linker config + `Sampling/TemperatureReader.swift` wrapper**
- *Files:* append the IOHID `extern` block to `QuickStatsPanel-Bridging-Header.h`; `project.yml` `OTHER_LDFLAGS` += `-framework IOKit`; new `Sources/QuickStatsPanel/Sampling/TemperatureReader.swift` (`final class IOHIDTemperatureReader` — serial-queue-confined client; enumerate + cache named sensors at init; `read() -> [TempReading]`; full CF accounting; `var isAvailable: Bool` = "did ≥1 temperature sensor enumerate").
- *Build:* `IOHIDEventSystemClientCreate` → `SetMatching {0xff00,5}` → `CopyServices` → cache `(name, svc)`; per tick `CopyEvent(svc,15,0,0)` → `IOHIDEventGetFloatValue(event, 15<<16)`; clamp `-20…130 °C`, drop 0/NaN. A `#if DEBUG debugDump()` printing every sensor's **raw `"Product"` name + °C** (so Wave 2's prefix→cluster mapping is grounded in this Mac's actual names).
- *Success:* `xcodegen generate` picks up the header + flag; project **links** (`-framework IOKit` in the line); the dump prints named sensors with plausible °C (~30–80 idle) **un-elevated**.
- *Backpressure:* `cd 01_Project && xcodegen generate && xcodebuild -scheme QuickStatsPanel build` clean, 0 warnings. **Record the printed sensor-name list in this plan** before Wave 2 (it decides the cluster prefixes).

> **Wave 1 result — ✅ DONE 2026-06-15 (M4 Pro, un-elevated uid 501).** Standalone `swiftc`
> spike (`/tmp/iohid_spike`, `-import-objc-header bridge.h -framework IOKit`) **links and runs
> un-elevated**; then the real `IOHIDTemperatureReader` + bridging-header block + `project.yml`
> `-framework IOKit` **build clean in the app target, 0 warnings** (link line shows
> `-lIOReport -framework IOKit`).
>
> **Key empirical finding (reshapes the role mapping):** page **`0xff00/5` is the only one that
> returns sensors** (0xff05/5, 0xff00/1, 0xff08/5 → nil). It yields **77 services / 6 distinct
> names** — and the role-named `pACC`/`GPU MTR Temp Sensor` set the research expected is **NOT
> present on this chip**. Actual families:
> | name | °C | → role |
> |------|----|--------|
> | `PMU tdie*` (~14) | 36–37 | **SoC** (numbered dies — CPU/GPU not separable) |
> | `gas gauge battery` | 31 | **Battery** |
> | `NAND CH* temp` | 33 | **SSD** |
> | `PMU tcal` | 51.8 | calibration ref → **excluded** |
> | `PMU tdev*` | **−9200** | sentinel/garbage → **excluded** (clamp `0<c<130`) |
>
> So a CPU-vs-GPU headline split is impossible on this chip — the honest detail card is
> **SoC / SSD / Battery**. `IOHIDTemperatureReader.role(for:)` maps names→roles defensively:
> it *upgrades* to CPU/GPU rows on any chip that exposes `pACC`/`eACC`/`GPU` sensors, else
> collapses the dies into one SoC row. SourceKit shows false "cannot find in scope" markers on
> the IOHID symbols (live-indexer doesn't apply the bridging header) — the `xcodebuild` compile
> is authoritative and passed. **Wave 2 may proceed: `IOHIDTemperatureReader.read() -> [TempReading]`
> + `isAvailable` are the contract.**

### Wave 2 — TemperatureSampler + TemperatureSample (depends on T1.1)

**T2.1 — `Sampling/TemperatureSampler.swift` + `TemperatureSample`**
- *Files:* new `Sources/QuickStatsPanel/Sampling/TemperatureSampler.swift`.
- *Build:* `struct TemperatureSample: Equatable, Sendable` — `thermalState: ProcessInfo.ThermalState` (Sendable), `sensors: [TempReading]` (`struct TempReading: Equatable, Sendable { let label: String; let celsius: Double }`), `static let empty`; computed `headlineFormatted` (the state word), `loadPercent` (state→0/40/75/100), and `detailRows: [(String,String)]` (CPU/GPU/SoC/Battery clusters formatted `"%.0f°C"`, or `[("Pressure", word)]` fallback when `sensors` empty). `final class TemperatureSampler` on the `GPUSampler` `DispatchSourceTimer` skeleton, owning one `IOHIDTemperatureReader` (created `start()`, torn down `stop()`); each tick reads `ProcessInfo.processInfo.thermalState` + `reader.read()`, groups sensors by prefix, emits the sample.
- *Success:* compiles 0 warnings; a throwaway dump shows the state word + clustered rows; empty-sensors path yields the fallback row.
- *Backpressure:* build clean; rows sane vs the T1.1 raw dump.

### Wave 3 — Wire into the strip (depends on Wave 2; ONE compile unit — new `StatKind` forces exhaustive switches)

**T3.1 — `StatKind`: add `.temps`** — `Model/StatDescriptor.swift`: add `temps` (after `power`); `displayName "Temperature"`; `settingsSymbol "thermometer"`. *Backpressure:* build clean.

**T3.2 — `StatsStore`: publish `temps` + own `temperatureSampler`** — add `var temps: TemperatureSample = .empty`; field; create + `.start()` after `power` (**un-gated**); assign; `stop()` + nil. *Backpressure:* `store.temps` updates each tick.

**T3.3 — `descriptor(for: .temps)`: always-visible tile** — **no `guard`**; `symbol:"thermometer"`, `value: temps.headlineFormatted`, `widestValue:"Critical"`, `loadPercent: temps.loadPercent`, `detail: temps.detailRows`. *Success:* tile renders; empty-sensor path still shows tile with fallback row.

### Wave 4 — Verify, migrate, document

**T4.1 — Clean build from scratch, 0 warnings** — `cd 01_Project && xcodegen generate` (confirm new files in target) `&&` kill app, clean DerivedData, `xcodebuild -scheme QuickStatsPanel build`. *Success:* `** BUILD SUCCEEDED **`, 0 Swift warnings, `-framework IOKit` in the link line (AC-9).

**T4.2 — On-screen verify (AC-1/AC-2/AC-3/AC-6)** — Launch, summon → Temperatures tile after Power showing `Nominal`. Drive a sustained CPU+GPU load → if `thermalState` escalates, the word + color + weight ramp (escalation may not trigger without prolonged heat — **honest limit, note it**). Click → detail card shows named CPU/GPU/SoC/Battery °C. **Cross-check vs Stats / `sudo powermetrics --samplers thermal` (user).**

**T4.3 — Migration + Settings (AC-7)** — Existing-user sim: `defaults write com.sim.QuickStatsPanel knownStats -array cpu memory disk network battery gpu fan power loadAverage uptime` (omit `temps`), relaunch → Temperatures lights up ON + appends to `statOrder`, a deliberately-off stat stays off. Settings shows it; toggle/reorder persist.

**T4.4 — Fallback + clamp + leak (AC-4/AC-5/AC-8)** — **AC-5:** force `reader` empty (stub) → tile still shows with `Pressure: <state>` row, no crash; revert. **AC-4:** confirm out-of-range/0 sensors dropped (inject a bogus value in the DEBUG dump). **AC-8:** ~10 min panel-open soak, watch RSS in Activity Monitor — flat.

**T4.5 — Document & log** — Mark D-018 shipped in `decisions.md` + `PROJECT_STATE.md` (roadmap Temperatures row → ✅); fix `SMC.swift:5` stale comment; add a session-log entry; archive this plan → `IMPLEMENTATION_PLAN-temperatures-DONE.md`. **Notarytool smoke** (release-gate): leave flagged in D-018 if notarization isn't wired this cycle — don't claim verified.
- *Follow-up (not blocking):* cookbook entry "permission-free Apple-Silicon temperatures via IOHID + thermalState" (alongside 66/68/69/74).

---

## Risk / sequencing notes
- **T1.1 is the whole risk** — the IOHID symbols, `-framework IOKit` link, matching dict, and `Unmanaged` accounting are novel to this codebase (though the bridging-header *pattern* is now established from D-019). Validate the sensor dump **before** building the sampler/tile, exactly how IOReport (D-019) and SMC (D-017) were de-risked first.
- **Always-visible is deliberate** (not a bug) — thermalState can't fail, so `descriptor(for: .temps)` has no `guard`. The detail °C is the only fragile part, and it degrades to a fallback row.
- **thermalState escalation is hard to force** — it needs sustained real heat; on-screen AC-2 verification of the *hot* colors may stay at `Nominal`. Note honestly; the loadPercent mapping + tint reuse the shipped, already-verified pipeline.
- **notarytool (flagged, unproven)** — same release gate as D-019's `-lIOReport`. Fallback `dlopen` if it ever fails.
- **Wave ordering:** 1 → 2 → 3 serialize; Wave 3's 3.1–3.3 are one compile unit (new `StatKind` breaks exhaustive switches until all land). Wave 4 is verification.
