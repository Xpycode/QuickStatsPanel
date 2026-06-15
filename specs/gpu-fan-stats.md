# GPU + Fan Stats Specification (D-017)

**Status:** Draft
**Created:** 2026-06-15
**Increment:** 1 of 2 in the "GPU / temps / fans" roadmap item (temps = D-018, separate spec)

## Problem Statement
The strip shows CPU, Memory, Disk, Network, Battery, Load, and Uptime, but nothing
about the GPU or cooling — two stats users glancing at a stats HUD expect, and the
last "core hardware" gaps before temperatures.

## Proposed Solution
Add two new permission-free stat tiles — **GPU utilization (%)** and **Fan speed
(rpm)** — that slot into the existing data-driven strip (`StatKind` →
`StatDescriptor` → `StatsStore.visibleStats`) exactly like the other stats. GPU is
read from the IOKit `IOAccelerator` registry (same pattern as `DiskSampler`); fans
are read from `AppleSMC` via a new minimal SMC reader that correctly decodes the
Apple-Silicon `flt` data type. Both tiles **hide themselves when the hardware is
absent** (no `IOAccelerator` utilization key / `FNum == 0`), mirroring how Battery
hides on desktop Macs.

### Key capabilities
1. **GPU tile** — headline integer "%": `PerformanceStatistics["Device Utilization %"]`
   (fallback `"GPU Activity(%)"`), clamped 0–100. Colors via the existing tint
   pipeline (busier = hotter). Detail card: Utilization, plus best-effort renderer/
   tiler split and device name when present.
2. **Fan tile** — headline rpm (the fastest fan if several). Detail card lists each
   fan: current / min / max rpm. `loadPercent` = current rpm normalized between this
   fan's min and max, so a fan near full tilt reads "hot".
3. **Minimal SMC reader** (`Sampling/SMC.swift`) — opens one `AppleSMC` connection,
   reads keys via the two-step `READ_KEYINFO` → `READ_BYTES` handshake, and decodes
   at least `flt`, `fpe2`, `ui8`, `ui16` data types. Read-only (never writes — fan
   *control* needs privileges; reading never does). Cribbed from exelban/stats
   `SMC/smc.swift`.
4. **Availability gating** — GPU hides if no `IOAccelerator` exposes a utilization
   key; Fan hides if `FNum == 0` (fanless Macs) or the SMC read fails. Probed each
   tick like the other samples; `descriptor(for:)` returns `nil` to hide.
5. **Auto-enabled for existing users** — relies on the established `knownStats`
   migration (`AppSettings.init`): a kind in `allCases` but not in stored
   `knownStats` defaults ON, and is appended to `statOrder`. No new migration code.

### User flow
1. User presses the summon hotkey → strip appears.
2. On a Mac with a GPU and fans (e.g. the M4 Pro target), two new tiles appear after
   the existing ones: e.g. `GPU 34%` and a fan glyph `2100 rpm`.
3. Click the GPU tile → detail card shows utilization (and renderer/tiler if read).
   Click the Fan tile → detail card lists each fan's current/min/max rpm.
4. On a fanless Mac (e.g. a base MacBook Air) the Fan tile simply never appears; in
   a VM with no `IOAccelerator`, the GPU tile never appears. No errors, no empty tile.
5. Settings → the two stats appear in the reorder/toggle list with static symbols
   (`cpu.fill`/`fanblades` or similar) and can be turned off / reordered like any other.

## Acceptance Criteria

**AC-1 — GPU tile shows live utilization**
Given the app is running on a Mac with a GPU,
when the strip is summoned and the GPU is doing work,
then a `GPU` tile shows an integer 0–100% that tracks Activity Monitor / powermetrics
within sampling lag, and colors hotter as it rises.

**AC-2 — GPU hides when unavailable**
Given a machine/VM where no `IOAccelerator` exposes a utilization key,
when the strip is summoned,
then no GPU tile appears (no zero tile, no crash) — `descriptor(for: .gpu)` returns nil.

**AC-3 — Fan tile shows live rpm**
Given the app is running on a Mac with fans (the M4 Pro target),
when the strip is summoned,
then a Fan tile shows current rpm matching a reference reader (e.g. iStat/TG Pro)
within sampling lag, using the fastest fan when more than one is present.

**AC-4 — Fan hides on fanless Macs**
Given a fanless Mac (`FNum == 0`) or an SMC read failure,
when the strip is summoned,
then no Fan tile appears.

**AC-5 — Detail cards**
Given the GPU or Fan tile is shown,
when the user clicks it,
then the detail card shows: GPU → Utilization (+ renderer/tiler/device when read);
Fan → one row per fan with current/min/max rpm.

**AC-6 — SMC `flt` decoding is correct**
Given Apple-Silicon fan keys report the `flt` data type,
when `SMC.swift` reads `F0Ac`,
then the decoded rpm is a sane positive number (not the garbage older `fpe2`-only
readers produce), cross-checked against a reference tool.

**AC-7 — Existing users get the new tiles once**
Given a user who has run a prior version (stored `knownStats` lacks `gpu`/`fan`),
when they launch this build,
then both new stats default ON and append to their `statOrder`, without disturbing
stats they had deliberately switched off.

**AC-8 — Permission-free & clean build**
Given a notarized, non-sandboxed Developer-ID build,
when the app reads GPU/fan stats,
then no entitlement, permission prompt, or root is required, and the project builds
clean from scratch with 0 Swift warnings.

## Technical Considerations
- **GPU:** `IOServiceMatching("IOAccelerator")` → `IORegistryEntryCreateCFProperties`
  → `["PerformanceStatistics"]` → `["Device Utilization %"]` (Int), fallback
  `["GPU Activity(%)"]`. Same registry-walk shape as `DiskSampler.readBlockStorageBytes`.
  Ship **native arm64** (Rosetta historically reports "no GPU").
- **Fans / SMC:** new `Sampling/SMC.swift`. Open `AppleSMC` once
  (`IOServiceGetMatchingService` + `IOServiceOpen`, connection type 0); read via
  `IOConnectCallStructMethod(conn, 2, …)` with `SMCKeyData_t`. Keys: `FNum` (count),
  `F<i>Ac` (actual rpm), `F<i>Mn`/`F<i>Mx` (min/max). Decode by the key's `dataType`
  field — `flt` (load Float LE), `fpe2`, `ui8`, `ui16`. FourCharCode helper for keys.
  Reference: exelban/stats `SMC/smc.swift` (decodes `flt`, unlike SMCKit/osx-cpu-temp).
- **Samplers:** two new `DispatchSourceTimer` samplers (`GPUSampler`, `FanSampler`)
  following the exact `BatterySampler`/`DiskSampler` skeleton (background queue,
  `@Sendable` value-type sample, callback hopping to `@MainActor` in `StatsStore`).
  `FanSampler` keeps the one open SMC connection for its lifetime; closes on `stop()`.
- **Wiring touch-points (traced):**
  - `Model/StatDescriptor.swift` — add `.gpu`, `.fan` to `StatKind` + `displayName`
    + `settingsSymbol`; add `.gpu`/`.fan` cases to `descriptor(for:)` with nil-gating.
  - `Model/StatsStore.swift` — add `gpu`/`fan` published samples + sampler fields +
    `start()`/`stop()`/`restart()` lines.
  - `Sampling/` — new `SMC.swift`, `GPUSampler.swift`, `FanSampler.swift`.
  - `project.yml` — new files picked up by `xcodegen generate` (sources are globbed,
    so likely automatic; re-generate per cookbook 47).
- **No UI-convention conflict:** these are tiles in the existing `StatsStripView` /
  `StatTileView` / `StatDetailView`; no NavigationSplitView/HSplitView/SwiftUI-Button
  concerns. The `Theme` struct already supplies tint/band.
- **Sampling cost:** GPU + fan reads are cheap, in-process registry/SMC reads — run
  continuously like CPU/Disk, NOT gated to panel-visible (only `top` is gated).

## Out of Scope
- **Temperatures** — deferred to **D-018** (IOHID thermal sensors + `thermalState`
  tile). Different, riskier API path; isolated on purpose.
- **GPU power (watts) / residency** via IOReport — IOAccelerator `%` is enough for a
  glance; IOReport is more fragile. Revisit only if a watts readout is wanted.
- **Fan control** (setting rpm) — read-only by design; control needs privileges and
  carries thermal risk.
- **Intel SMC temp keys** — belongs with D-018; this increment's SMC reader only needs
  the fan keys (the reader itself is arch-agnostic and reused by D-018).
- **Per-GPU breakout on multi-GPU Intel Macs** — show the primary accelerator only.

## Open Questions
1. **Fan headline when multiple fans:** fastest fan's rpm (proposed) vs. average?
   Fastest surfaces the one actually ramping; average smooths. → **Proposed: fastest.**
2. **GPU detail rows:** is renderer/tiler split worth showing, or is Utilization alone
   cleaner? (Renderer/Tiler are Apple-Silicon-only keys.) → lean **Utilization-only**,
   add device name if cheap.
3. **Fan tile symbol:** `fanblades` (static) vs. an animated/spinning cue? → **static
   `fanblades`** for v1 (matches the static-symbol convention; no animation infra).
4. **Cookbook entry:** no existing cookbook covers SMC/GPU sampling — worth adding a
   "permission-free GPU + SMC fan stats" entry after this ships? (Recommend yes.)
