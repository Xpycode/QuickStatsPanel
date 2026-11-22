# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** plan · **Phase:** Floating tiles — prototype planned <!-- Phase changed: 2026-11-22 -->
- **Focus:** bounded native floating-tile prototype; [spec defaults](../specs/floating-tiles.md) remain provisional until owner review. Circle review remains parked (D-040).
- **Blockers:** none for tile Wave 1; tile acceptance and parked ring E1 remain open. Separate release gates: Strongbox backup, remaining updater controls and real upgrade acceptance.
- **Execution:** [Floating-tile prototype plan](IMPLEMENTATION_PLAN-floating-tiles.md) — 0/4 tasks, four serial waves; Wave 1 (1.1) has no prerequisites and is ready when execution is requested. Tile E1 open. [Ring plan](../IMPLEMENTATION_PLAN.md) remains 12/12 implemented, E1 open and parked.
- **Feature definition:** [Floating tiles](../specs/floating-tiles.md), with provisional native defaults. [Earlier layouts/ring spec](../specs/panel-layouts-and-appearance.md) and remaining ring E1 decisions stay parked.
- **Current handoff:** [After Git closeout](sessions/2026-11-22.md#resume--after-git-closeout) — all work committed and pushed; pickup per [pre-clear Resume](sessions/2026-11-22.md#resume--pre-clear-floating-tile-implementation-next).
- **Validation:** C7 view correction Debug/Release, signature and Release exclusion pass; C7 visual correction accepted. Prior 394/0 hostless result unchanged. [Owner evidence](evidence/gauge-ring-prototype.md#owner-results).
- **Next:** `/execute` — Wave 1: prove CPU/Network select, switch, return and dismissal with isolated preferences/history and native focus checks. Execution not yet requested; no production wave authorized.
- **Release:** public v1.2.0; prepared v1.2.1 remains unpublished and separate from prototype work. [Release preparation](evidence/release-1.2.1.md).
- **Last updated:** 2026-11-22

## Recent
- **2026-11-22** — Floating mockup explored: separate tiles, content-sized detail, stationary switcher and usage colours. Spec and four-task prototype plan prepared; defaults provisional, execution not started; circle parked. All Nov 15–22 work committed and pushed.
- **2026-11-17** — Pre-clear handoff saved; accepted review results retained, artifact hashes reverified. Q1 arc arrangement still awaits a decision.
- **2026-11-16** — C7 peak-line/text clearance accepted after screenshot review; Debug/Release/signature pass. C5 battery-power display passed by screenshots; C6 accepted. Next Q1 design decision.
- **2026-11-16** — B4 and real-data B5/C1/Network C2 passed; history/labels work. C4 scroll-bar setting check passed; next C7 CPU spacing; fixture query limitation diagnosed.
- **2026-11-16** — Owner accepted equal CPU segment widths; pre-clear handoff saved with exact remaining review boundary.

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
