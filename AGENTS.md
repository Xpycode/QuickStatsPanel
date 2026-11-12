# QuickStatsPanel — Codex Instructions

QuickStatsPanel is a macOS HUD utility showing glanceable live system statistics in a non-activating
floating panel. It has no Dock icon or menu-bar item.

## Stack and architecture

- Swift 5.10+, SwiftUI panel content, AppKit `NSPanel` window management.
- XcodeGen generates the project from `01_Project/project.yml`.
- Global hotkeys use Carbon `RegisterEventHotKey` and do not require Accessibility permission.
- Sampling uses timer-based samplers and Sendable value-type samples.
- Preserve `LSUIElement = YES`.
- The document/editor App Shell Standard does not apply; do not require a sidebar/HSplitView shell.

## Build and verification

```bash
cd 01_Project
xcodegen generate
xcodebuild -scheme QuickStatsPanel -destination 'platform=macOS' build
```

When testing a release, distinguish installed/public and Debug instances and verify the exact
artifact. Never publish an archive that predates its final fixes.

## Directions

Use the globally installed `directions` skill and the master `commands/*.md` procedures. Read
`docs/PROJECT_STATE.md`, `docs/decisions.md`, and `docs/sessions/`. Universal Directions guidance is
read on demand and must not be copied here.


<!-- DIRECTIONS-PROJECT:START -->
## Shared Directions workflow

- **Local master:** `/Users/sim/ProgrammingProjects/0-DIRECTIONS/__DIRECTIONS`.
- For Directions commands, use the installed Directions skill in Codex or read the master's
  `commands/<name>.md` completely. Slashless forms work too. Approved-plan continuation uses
  `commands/execute.md`; status alone does not authorize execution.
- Resolve shared `reference/...` from that master. Read universal guidance there on demand;
  use the relevant host global template's routing section if global guidance is unavailable.
  Report a missing master instead of using copied universal guides.
- This section supersedes older generic Directions workflow, copied-guide loading, automatic
  app-control and PR-ceremony instructions in this file. Preserve project-specific architecture,
  build commands, security constraints and product requirements above.
- Retained numbered guides in `docs/` are legacy references, not workflow authority. Preserve
  their project-specific additions; consult them only for relevant historical/project evidence.
- Preserve existing state, selected plans, open gates and session history. Legacy task/state
  reconciliation is separate work; never mark a manual gate complete from an old checkbox.
- Before builds/tests, read the master's `34_testing.md` and inspect startup effects. Desktop/app
  control requires explicit user permission; older automatic quit/launch instructions do not grant it.
  Give full absolute paths for user-operated file/app steps. Preserve dirty work and user limits.
<!-- DIRECTIONS-PROJECT:END -->
