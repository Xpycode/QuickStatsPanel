# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** build · **Phase:** Ring gauges — prototype review closed, gauge step to plan <!-- Phase changed: 2026-11-13 -->
- **Focus:** v1.2.1 universal app/DMG notarized and local signed update feed verified. Published version remains v1.2.0; [release preparation](evidence/release-1.2.1.md).
- **Blockers:** Strongbox backup confirmed incomplete; remaining updater controls and real upgrade acceptance open.
- **Execution:** No active plan. Ring prototype plan complete and [archived](sessions/IMPLEMENTATION_PLAN-ring-prototype-DONE.md); E1 closed — interaction accepted, look/structure redirected to the gauge mockup ([results](evidence/ring-prototype.md#owner-results)).
- **Feature definition:** [Panel layouts and dynamic appearance](../specs/panel-layouts-and-appearance.md) + **D-035**: wedges become equal-area radial gauges, Disk capacity + I/O rim, size presets, small hub (gear + drag), sub-rings open from stat wedges (not the centre). Spec not yet updated for D-035.
- **Current handoff:** [Gauge planning](sessions/2026-11-13.md#resume--gauge-ring-planning).
- **Validation:** 1.2.1: 19 focused hostless tests, Debug build/deep signature, signed-feed/tamper and release-tool fixture checks passed. Paired displays and live manual no-update check accepted; other updater controls and real upgrade untested.
- **Next:** Update the spec for D-035 (gauges, small hub, More wedge, sub-rings: CPU cores, Disk volumes, Network interfaces, Temperature sensors) → `/make-plan` the gauge prototype step (include C1 card Close-clipping fix). Separately: Strongbox backup, updater/upgrade acceptance and publication for 1.2.1.
- **Last updated:** 2026-11-13

## Recent
- **2026-11-13** — Owner review closed early: hover/hold/Escape/drag/pin/placement pass; look redirected to the gauge mockup (D-035: small hub, sub-rings from wedges, equal-area gauges).
- **2026-11-13** — Ring step 3: confirmed the prototype is left out of Release builds, all 212 tests pass, owner review checklist ready.
- **2026-11-13** — Ring step 2 built: hover/hold timing, More branch and screen-edge placement; reviewed, 110 tests pass; fresh build running.
- **2026-11-13** — Owner passed all four ring 1.1 native checks; fixture Disk/Network cards stuck loading (carried to 1.2).
- **2026-11-13** — Explored wedges as radial fill gauges; interactive mockup published, owner choices pending before planning.

## What we're building
Press a global hotkey → a **thin** wide strip appears near the cursor showing live stats as compact
tiles. Click a tile → detail card. Press again / Esc / click-away → dismiss. **No Dock icon, no
menu-bar item** — settings and quit live in the panel. Small corner radius (deliberately *not* the
heavy macOS "Tahoe" rounding).

**Stats roadmap: complete** — CPU, Memory, Disk, Network, Battery, Load, Uptime, Top-process, GPU,
Fans, Power, Temperatures, plus per-stat history graphs (2026-07-27).

## Progress
**Features** ✅ roadmap + retained transfers shipped · **UI** ✅ approved release scope; remaining manual checks deferred ·
**Testing** ✅ 212 hostless tests (incl. 92 ring) + bounded hardware probes · **Docs** ✅ ·
**Distribution** ✅ v1.2.0 notarized + released; GitHub and website downloads verified

## Detail (read only if needed)
- **Decisions:** `decisions.md` — D-001…D-035, full rationale for every locked choice. Load-bearing:
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
