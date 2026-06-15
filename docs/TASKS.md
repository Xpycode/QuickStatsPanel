# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

_(empty — Themes shipped 2026-06-13; see tasks-archive.md)_

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

**D-017 GPU + Fan stats** — plan: `IMPLEMENTATION_PLAN.md` · spec: `specs/gpu-fan-stats.md`

- [x] T1.1 — `Sampling/SMC.swift`: read-only AppleSMC reader (flt-correct decode) *(Wave 1)* — verified: FNum=2, F0 range 2317–7826 rpm, flt decode proven sane
- [x] T1.2 — `Sampling/GPUSampler.swift` + `GPUSample`: IOAccelerator utilization *(Wave 1)* — verified: isAvailable, 15%, AGXAcceleratorG16X (M4 Pro GPU)
- [ ] T2.1 — `Sampling/FanSampler.swift` + `FanSample`: FNum/F0Ac via SMC *(Wave 2)*
- [ ] T3.1–3.3 — Wire into strip: `StatKind` `.gpu`/`.fan` + `StatsStore` samples/samplers + `descriptor(for:)` tiles *(Wave 3)*
- [ ] T4 — Verify on-screen (vs Activity Monitor / iStat), migration + Settings, hide-paths, doc D-017 *(Wave 4)*

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
