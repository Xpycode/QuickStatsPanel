# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** build · **Phase:** Floating tiles — prototype implemented, owner review (E1) <!-- Phase changed: 2026-11-27 -->
- **Focus:** bounded native floating-tile prototype; [spec defaults](../specs/floating-tiles.md) remain provisional until owner review. Circle review remains parked (D-040).
- **Blockers:** tile E1 needs the owner. Parked ring E1 open. Separate release gates: Strongbox backup, remaining updater controls and real upgrade acceptance.
- **Execution:** [Floating-tile prototype plan](IMPLEMENTATION_PLAN-floating-tiles.md) — 7/7 implemented; 5.3 (D-045: trimmed details, one top line, 6 pt gap) awaiting owner look; E1 open.
- **Feature definition:** [Floating tiles](../specs/floating-tiles.md), with provisional native defaults. [Earlier layouts/ring spec](../specs/panel-layouts-and-appearance.md) and remaining ring E1 decisions stay parked.
- **Current handoff:** [After 5.2](sessions/2026-11-27.md#resume--after-52-d-044) — pushed.
- **Validation:** W4: full hostless suite 462/0 (0 skipped), Debug/Release build, codesign, Release exclusion clean; Atlas Release Strip launch and Ring render pass. Ad-hoc Release cannot launch on the M4 Pro (hardened runtime vs Sparkle) — use a Developer ID local build. [Evidence](evidence/floating-tiles-prototype.md).
- **Next:** owner looks at the 5.3 build; then decide whether E1 can close.
- **Release:** public v1.2.0; prepared v1.2.1 remains unpublished and separate from prototype work. [Release preparation](evidence/release-1.2.1.md).
- **Last updated:** 2026-11-27

## Recent
- **2026-11-27** — Owner saw 5.2 (sides right); D-045 trims details, aligns all to the overview top, 6 pt gap. 5.3 built and checked in the helper; one flaky persistence memory test logged.
- **2026-11-27** — Interviewed owner → D-044 (clicked primary stays, others hide, detail opens inward, no switcher). 5.2 built: 473/0; native look blocked by a busy shared helper.
- **2026-11-27** — E1 case B failed; built a version keeping the overview with cards opening outward, then the owner clarified they want other tiles hidden and detail opening inward. Design talk next.
- **2026-11-27** — Tile 4.1 done: full suite 462/0, Release exclusion clean, Strip/Ring smoke in the helper, E1 review packet written. Tile plan 4/4; E1 open.
- **2026-11-27** — Tile 3.1 done: all detail cards, constrained/edge displays, keyboard (incl. already-active summon), group drag/dismiss/quit, VoiceOver tree; 86/0 focused. Tile plan 3/4; 4.1 ready.
- **2026-11-27** — Pushed; 2.1 dark check passed via helper System Settings → Dark (a global `defaults write` does not work there). Tile plan 2/4; 3.1 ready.
- **2026-11-27** — Tile Wave 2 implemented: all eleven stats in saved-order hierarchy with readings and usage colours; checks pass except dark mode, which the helper can't show yet.

## What we're building
Press a global hotkey → a **thin** wide strip appears near the cursor showing live stats as compact
tiles. Click a tile → detail card. Press again / Esc / click-away → dismiss. **No Dock icon, no
menu-bar item** — settings and quit live in the panel. Small corner radius (deliberately *not* the
heavy macOS "Tahoe" rounding).

**Stats roadmap: complete** — CPU, Memory, Disk, Network, Battery, Load, Uptime, Top-process, GPU,
Fans, Power, Temperatures, plus per-stat history graphs (2026-07-27).

## Progress
**Features** ✅ roadmap + retained transfers shipped · **UI** ✅ approved release scope; remaining manual checks deferred ·
**Testing** ✅ 394 hostless tests + bounded hardware probes · **Docs** ✅ ·
**Distribution** ✅ v1.2.0 notarized + released; GitHub and website downloads verified

## Detail (read only if needed)
- **Decisions:** `decisions.md` — D-001…D-041, full rationale for every locked choice. Load-bearing:
  **D-001** HUD `NSPanel` · **D-002** Carbon hotkey, no permissions · **D-003** `LSUIElement` ·
  **D-006** thin strip + click-to-expand · **D-008** content-driven width and fixed-width value
  slots (jitter discipline — read this before touching tile layout) · **D-015** self-drawn card.
- **Backlog & tasks:** `TASKS.md` — release, updater, D-025 tails, disk accuracy, vertical strip, polish.
- **Session history:** `sessions/_index.md` → individual logs.
- **Design briefs:** `02_Design/design-prompts.md` — 6 paste-ready briefs + locked design-values table.
- **⚠️ App Shell Standard does not apply here** — HUD panel app, not a document/editor app. Don't
  run `/shell-check` against it expecting HSplitView. See `CLAUDE.md`.

---
*Updated by Claude. Source of truth for project position.*
