# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

- [ ] **Themes (named presets)** — user wants a full theming system selectable in
      Settings, bundling: (1) accent / load colors (`Theme.loadColor` thresholds —
      presets, solid vs gradient bands), (2) background color & opacity (currently
      flat black 0.82; presets + possible light mode), (3) corner radius / density
      (roundness, spacing, font-size presets: compact vs comfortable). Deliver as
      pickable named themes ("Default", "Mono", "Neon", …), not loose knobs.
      Requires refactoring `Theme` from a static enum into a selectable, persisted
      value (AppSettings) that the strip + detail card both read.

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->
<!-- Themes feature — full breakdown in IMPLEMENTATION_PLAN.md (5 waves, 12 tasks). -->

- [ ] **W1 — Theme foundation types** (1.1 ColorCodable, 1.2 ThemePreset+ThemeData, 1.3 StatusBand+hysteresis)
- [ ] **W2 — Chokepoint** (2.1 `Theme` static→struct + facade, 2.2 wire into `AppSettings` + reduce-transparency)
- [ ] **W3 — Migrate consumers** (3.1 strip, 3.2 tile+severity-cue, 3.3 detail, 3.4 hint, 3.5 store-tint + drop battery hack)
- [ ] **W4 — Settings UI** (4.1 theme picker, 4.2 Customize… + reset)
- [ ] **W5 — Verify** (5.1 macOS-15 observation + clean build, 5.2 manual ACs, 5.3 adversarial review)

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
