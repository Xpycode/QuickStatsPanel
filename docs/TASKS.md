# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

The whole stats roadmap has shipped (D-017/D-018/D-019 + D-024), and configurable tiles + activity
graphs shipped 2026-07-27 (D-025). Remaining work is release ceremony plus small tails.
Full detail: `PROJECT_STATE.md` backlog.

- [ ] **v1.1.0 release** — D-024's temps/power work has been on `main` since 2026-07-12 but is in
      no tagged artifact. Notarize → staple → DMG chain is already proven; run `/check ship` first.
- [ ] **Graph peak strategy** — `PeakStrategy.resolve` (`Model/StatHistory.swift`) returns plain
      `windowMax`, so a spike ageing off the left edge rescales every bar at once. Three options
      documented in-code; a *decaying* one needs a tick counter (`graphPeak` runs per body pass).
- [ ] **Detail-card headline pair** (optional) — the big `61 KB/s / Upload` block from the iStat
      reference. Omitted deliberately: the strip and the card's own rows already show those values.
- [ ] **Disk free-space accuracy** — `statfs f_bavail` reads 16.62 GB under Finder (purgeable gap).
- [ ] **Updater** — SilentUpdateKit (recommended) vs full Sparkle ≥2.9.4.

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

_Empty — D-019 and D-017 archived to `tasks-archive.md` on 2026-07-27 (both shipped 2026-06-15;
they sat here for six weeks while D-020→D-024 shipped around them). Next sprint starts once the
two blocking questions in `PROJECT_STATE.md` → Blockers are answered._

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
