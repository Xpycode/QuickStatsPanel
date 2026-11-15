# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** build · **Phase:** Ring gauges — owner review (E1) in progress <!-- Phase changed: 2026-11-14 -->
- **Focus:** v1.2.1 universal app/DMG notarized and local signed update feed verified. Published version remains v1.2.0; [release preparation](evidence/release-1.2.1.md).
- **Blockers:** Strongbox backup confirmed incomplete; remaining updater controls and real upgrade acceptance open.
- **Execution:** [Gauge ring prototype plan](../IMPLEMENTATION_PLAN.md) — 8/8 tasks complete. **E1 in progress:** 12 rows pass, A1 skipped; fix pass 1 built for F2/F4 and owner corrections; [results](evidence/gauge-ring-prototype.md#owner-results).
- **Feature definition:** [Panel layouts and dynamic appearance](../specs/panel-layouts-and-appearance.md) — revised 2026-11-13 for **D-035/D-036** (gauge wedges, size presets, small hub, More wedge at six o'clock, sub-rings as outer arcs, AC-24…AC-41). Its Proposed/Open rows are built as provisional prototype baselines and decided at the plan's E1; fixtures-first for sub-ring parts was decided in planning.
- **Current handoff:** [E1 in progress, fix pass 1 built](sessions/2026-11-15.md#resume--e1-in-progress-fix-pass-1-built).
- **Validation:** 1.2.1: 19 focused hostless tests, Debug build/deep signature, signed-feed/tamper and release-tool fixture checks passed. Paired displays and live manual no-update check accepted; other updater controls and real upgrade untested.
- **Next:** Owner rechecks fix pass 1 on the running build, then E1 continues at Step 3 (~30 rows + S1/Q1–Q9) → close the plan. Push `7a8f331`. Separately: Strongbox backup, updater/upgrade acceptance and publication for 1.2.1.
- **Last updated:** 2026-11-15

## Recent
- **2026-11-15** — E1 review run in batches: most branch, More and placement rows pass; clipped card notes and a Space switch on drag found and fixed with the owner's arc and card corrections; fresh build running.
- **2026-11-14** — Wave 5 done: Release check clean (no `--ring-` literal or ring view symbol), 390 hostless tests pass (reconciled against 212), independent review PASS with one minor fixture-Settings concern; evidence and a finite E1 checklist written; fresh build launched.
- **2026-11-14** — Wave 4 built: native sub-ring and More arcs with hover captions and segment accessibility; 3.1 shims gone, band on; review found clicks falling through transparent inside areas (fixed with a hit fill); 288 ring tests pass; fresh build launched on fixtures.
- **2026-11-14** — Wave 3 built: any wedge can own the outer arc and card (band stays off until Wave 4), cards no longer scroll or clip under always-visible scroll bars, long wedge values fit; review found and fixed a More flicker; 273 ring tests pass; fresh build launched.
- **2026-11-14** — Owner chose icon-only at Medium/8 (D-037); gauge ring 2.1 built: presets, real-data gauges, small hub, More wedge at six o'clock; 229 ring tests pass; fresh build launched.

## What we're building
Press a global hotkey → a **thin** wide strip appears near the cursor showing live stats as compact
tiles. Click a tile → detail card. Press again / Esc / click-away → dismiss. **No Dock icon, no
menu-bar item** — settings and quit live in the panel. Small corner radius (deliberately *not* the
heavy macOS "Tahoe" rounding).

**Stats roadmap: complete** — CPU, Memory, Disk, Network, Battery, Load, Uptime, Top-process, GPU,
Fans, Power, Temperatures, plus per-stat history graphs (2026-07-27).

## Progress
**Features** ✅ roadmap + retained transfers shipped · **UI** ✅ approved release scope; remaining manual checks deferred ·
**Testing** ✅ 390 hostless tests + bounded hardware probes · **Docs** ✅ ·
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
