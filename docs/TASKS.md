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

- [ ] [Task description]

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
