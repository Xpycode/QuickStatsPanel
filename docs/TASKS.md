# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

_(D-018 Temperatures queued — `ProcessInfo.thermalState` tile + best-effort IOHID per-sensor °C.)_

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

**D-019 Power tile via IOReport** — ✅ **SHIPPED 2026-06-15** (4 waves; commits `5778f09`+`fa713ff`+`0a520bd`+docs). Permission-free CPU·GPU split watts via the un-entitled `IOReport` "Energy Model" channels, hide-when-absent. Decision D-019; plan archived `docs/sessions/IMPLEMENTATION_PLAN-power-DONE.md`.

- [x] T1.1 — Bridging header + `-lIOReport` + `Sampling/IOReport.swift` wrapper *(Wave 1 — validated un-elevated: CPU→~6 W under load, GPU/ANE flat)*
- [x] T2.1 — `Sampling/PowerSampler.swift` + `PowerSample` (delta-per-tick, session-peak tint) *(Wave 2)*
- [x] T3.1–3.3 — Wire into strip: `StatKind` `.power` + `StatsStore` sample/sampler + `descriptor(for:)` tile *(Wave 3, one compile unit)*
- [x] T4 — Clean build (0 warnings), on-screen verify (tile + 5-row detail), migration AC-9 (data-layer), seed/leak paths *(Wave 4)*. **Left to user:** exact `sudo powermetrics` cross-check; **release gate:** `notarytool`+`-lIOReport` (unproven).

---

### Shipped (awaiting archive by `/log`)

**D-017 GPU + Fan stats — ✅ DONE** — plan archived: `docs/sessions/IMPLEMENTATION_PLAN-gpu-fan-DONE.md`

- [x] T1.1 — `Sampling/SMC.swift`: read-only AppleSMC reader (flt-correct decode) *(Wave 1)* — verified: FNum=2, F0 range 2317–7826 rpm, flt decode proven sane
- [x] T1.2 — `Sampling/GPUSampler.swift` + `GPUSample`: IOAccelerator utilization *(Wave 1)* — verified: isAvailable, 15%, AGXAcceleratorG16X (M4 Pro GPU)
- [x] T2.1 — `Sampling/FanSampler.swift` + `FanSample`: FNum/F0Ac via SMC *(Wave 2)* — `1dc398a`; fastest-fan headline, clamped `loadPercent`
- [x] T3.1–3.3 — Wire into strip: `StatKind` `.gpu`/`.fan` + `StatsStore` samples/samplers + `descriptor(for:)` tiles *(Wave 3)* — `31bf97f`
- [x] T4 — Verify on-screen, migration + Settings, hide-paths, doc D-017 *(Wave 4)* — GPU tracks AM; fans 0→2483 rpm under stress; AC-7 verified; AC-2/4 by mechanism

---

## Progress Calculation

```
Sprint Progress = checked in Current Sprint / total in Current Sprint
Overall Progress = (archived count + checked) / (backlog + current + archived)
```

Archived task count is read from `tasks-archive.md` header.

## Workflow Integration

| Command | Action |
|---------|--------|
| `/interview` | Adds tasks to Backlog |
| `/plan` | Moves Backlog → Current Sprint |
| `/execute` | Checks off tasks as waves complete |
| `/log` | Archives checked tasks, updates PROJECT_STATE.md progress bar |
| `/status` | Reports progress from checkbox counts |

---
*Location: `docs/TASKS.md`. Parsed by Directions app.*
