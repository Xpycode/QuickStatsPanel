# Tasks Archive

> **Completed tasks archive.** Used for progress calculation.

## Stats
- **Total archived:** 16
- **Last updated:** 2026-09-01

## Completed

- [x] **Graph peak strategy** — chose sample-driven 10% decay: peaks rise immediately and fall once
      per new sample, never once per SwiftUI redraw; repeated strip/detail renders cannot accelerate
      the scale. Hostless logic tests cover rise, decay, and redraw idempotence. (2026-09-01)

<!-- Newest at top. Added by /log when tasks complete. -->
<!-- Format: - [x] Task description (YYYY-MM-DD) -->

<!-- Archived 2026-07-27 by /log: D-019 + D-017 both shipped 2026-06-15 but sat in TASKS.md
     for six weeks while D-020/D-021/D-022/D-023/D-024 shipped around them. -->

- [x] **D-019 Power tile via IOReport** — permission-free CPU·GPU split watts via un-entitled `IOReport` "Energy Model" channels, hide-when-absent. 4 waves, 11 ACs. Plan archived `sessions/IMPLEMENTATION_PLAN-power-DONE.md` (2026-06-15)
- [x] T4 — Clean build (0 warnings), on-screen verify (tile + 5-row detail), migration AC-9, seed/leak paths *(D-019 Wave 4)* (2026-06-15)
- [x] T3.1–3.3 — Wire into strip: `StatKind` `.power` + `StatsStore` sample/sampler + `descriptor(for:)` tile *(D-019 Wave 3)* (2026-06-15)
- [x] T2.1 — `Sampling/PowerSampler.swift` + `PowerSample` (delta-per-tick, session-peak tint) *(D-019 Wave 2)* (2026-06-15)
- [x] T1.1 — Bridging header + `-lIOReport` + `Sampling/IOReport.swift` wrapper — validated un-elevated: CPU→~6 W under load, GPU/ANE flat *(D-019 Wave 1)* (2026-06-15)
- [x] **D-017 GPU + Fan stats** — GPU = IOKit `IOAccelerator` utilization; Fans = read-only `AppleSMC` `flt` decode; both hide-when-absent, free migration. Plan archived `sessions/IMPLEMENTATION_PLAN-gpu-fan-DONE.md` (2026-06-15)
- [x] T4 — Verify on-screen, migration + Settings, hide-paths, doc D-017 — GPU tracks Activity Monitor; fans 0→2483 rpm under stress; AC-7 verified *(D-017 Wave 4)* (2026-06-15)
- [x] T3.1–3.3 — Wire into strip: `StatKind` `.gpu`/`.fan` + `StatsStore` samples/samplers + `descriptor(for:)` tiles ✅ `31bf97f` *(D-017 Wave 3)* (2026-06-15)
- [x] T2.1 — `Sampling/FanSampler.swift` + `FanSample`: FNum/F0Ac via SMC ✅ `1dc398a` — fastest-fan headline, clamped `loadPercent` *(D-017 Wave 2)* (2026-06-15)
- [x] T1.2 — `Sampling/GPUSampler.swift` + `GPUSample`: IOAccelerator utilization — verified isAvailable, 15%, AGXAcceleratorG16X *(D-017 Wave 1)* (2026-06-15)
- [x] T1.1 — `Sampling/SMC.swift`: read-only AppleSMC reader (flt-correct decode) — verified FNum=2, F0 range 2317–7826 rpm *(D-017 Wave 1)* (2026-06-15)

- [x] **Themes (named presets)** — full theming system: 4 presets (Default/Mono/Vitals/Neon) + Custom, follow-system light+dark, unified `usageColor`/hysteresis, Settings picker + Customize editor. All 11 ACs verified. Full record: `IMPLEMENTATION_PLAN.md` (archived to `sessions/`). (2026-06-13)
- [x] **W5 — Verify** (5.1 macOS-15 `NSObservationTrackingEnabled`, 5.2 on-screen ACs, 5.3 adversarial review) ✅ `7e2ee79` `46b87d6` (2026-06-13)
- [x] **W4 — Settings UI** (4.1 theme picker, 4.2 Customize… + reset) ✅ `8ad4324` `00d9880` (2026-06-13)
- [x] **W3 — Migrate consumers** (3.1 strip, 3.2 tile+severity-cue, 3.3 detail, 3.4 hint, 3.5 store-tint + drop battery hack) ✅ `332bbbe` (2026-06-13)
- [x] **W2 — Chokepoint** (2.1 `Theme` static→struct + facade, 2.2 wire into `AppSettings` + reduce-transparency) ✅ `caf5694` (2026-06-13)
- [x] **W1 — Theme foundation types** (1.1 ColorCodable, 1.2 ThemePreset+ThemeData, 1.3 StatusBand+hysteresis) ✅ `3fe3bb4` (2026-06-13)

---
*Auto-updated by /log. Count used for progress calculation.*
