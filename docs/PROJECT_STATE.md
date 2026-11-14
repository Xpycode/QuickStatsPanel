# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** build · **Phase:** Ring gauges — prototype built, awaiting owner review (E1) <!-- Phase changed: 2026-11-14 -->
- **Focus:** v1.2.1 universal app/DMG notarized and local signed update feed verified. Published version remains v1.2.0; [release preparation](evidence/release-1.2.1.md).
- **Blockers:** Strongbox backup confirmed incomplete; remaining updater controls and real upgrade acceptance open.
- **Execution:** [Gauge ring prototype plan](../IMPLEMENTATION_PLAN.md) — Waves 1–5 complete (8/8). **Awaiting acceptance:** E1 owner review, [checklist](evidence/gauge-ring-prototype.md#e1-owner-review-checklist).
- **Feature definition:** [Panel layouts and dynamic appearance](../specs/panel-layouts-and-appearance.md) — revised 2026-11-13 for **D-035/D-036** (gauge wedges, size presets, small hub, More wedge at six o'clock, sub-rings as outer arcs, AC-24…AC-41). Its Proposed/Open rows are built as provisional prototype baselines and decided at the plan's E1; fixtures-first for sub-ring parts was decided in planning.
- **Current handoff:** [Wave 5 done](sessions/2026-11-14.md#resume--gauge-prototype-wave-5-done-e1-ready).
- **Validation:** 1.2.1: 19 focused hostless tests, Debug build/deep signature, signed-feed/tamper and release-tool fixture checks passed. Paired displays and live manual no-update check accepted; other updater controls and real upgrade untested.
- **Next:** Owner runs the E1 batch on the running build (PID 92319) and returns results → record, fix bounded corrections, close the plan. Push `main` (local commits). Separately: Strongbox backup, updater/upgrade acceptance and publication for 1.2.1.
- **Last updated:** 2026-11-14

## Recent
- **2026-11-14** — Wave 5 done: Release check clean (no `--ring-` literal or ring view symbol), 390 hostless tests pass (reconciled against 212), independent review PASS with one minor fixture-Settings concern; evidence and a finite E1 checklist written; fresh build launched.
- **2026-11-14** — Wave 4 built: native sub-ring and More arcs with hover captions and segment accessibility; 3.1 shims gone, band on; review found clicks falling through transparent inside areas (fixed with a hit fill); 288 ring tests pass; fresh build launched on fixtures.
- **2026-11-14** — Wave 3 built: any wedge can own the outer arc and card (band stays off until Wave 4), cards no longer scroll or clip under always-visible scroll bars, long wedge values fit; review found and fixed a More flicker; 273 ring tests pass; fresh build launched.
- **2026-11-14** — Owner chose icon-only at Medium/8 (D-037); gauge ring 2.1 built: presets, real-data gauges, small hub, More wedge at six o'clock; 229 ring tests pass; fresh build launched.
- **2026-11-14** — Gauge prototype Wave 1 built in parallel (geometry kit, gauge content/parts, card Close fix); 211 focused tests pass. Geometry check shows Medium with 8 favourites is too tight for values — stopped for an owner decision.
- **2026-11-14** — Gauge ring prototype planned: 7 tasks in 5 waves, fixtures first for sub-ring parts, owner review (E1) at the end. Nothing built or run.

## What we're building
Press a global hotkey → a **thin** wide strip appears near the cursor showing live stats as compact
tiles. Click a tile → detail card. Press again / Esc / click-away → dismiss. **No Dock icon, no
menu-bar item** — settings and quit live in the panel. Small corner radius (deliberately *not* the
heavy macOS "Tahoe" rounding).

**Stats roadmap: complete** — CPU, Memory, Disk, Network, Battery, Load, Uptime, Top-process, GPU,
Fans, Power, Temperatures, plus per-stat history graphs (2026-07-27).

## Progress
**Features** ✅ roadmap + retained transfers shipped · **UI** ✅ approved release scope; remaining manual checks deferred ·
**Testing** ✅ 390 hostless tests (incl. 270 ring) + bounded hardware probes · **Docs** ✅ ·
**Distribution** ✅ v1.2.0 notarized + released; GitHub and website downloads verified

## Detail (read only if needed)
- **Decisions:** `decisions.md` — D-001…D-036, full rationale for every locked choice. Load-bearing:
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
