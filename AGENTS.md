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
