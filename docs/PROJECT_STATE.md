# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** build · **Phase:** Ring gauges — prototype Wave 2 done, Wave 3 ready <!-- Phase changed: 2026-11-14 -->
- **Focus:** v1.2.1 universal app/DMG notarized and local signed update feed verified. Published version remains v1.2.0; [release preparation](evidence/release-1.2.1.md).
- **Blockers:** Strongbox backup confirmed incomplete; remaining updater controls and real upgrade acceptance open.
- **Execution:** [Gauge ring prototype plan](../IMPLEMENTATION_PLAN.md) — Waves 1–2 complete (4/7; 2.1 `ad22329`, replanned under **D-037**: icon-only accepted at Medium/8). **Ready:** Wave 3 (3.1, branch state + outer band), needs a new request. E1 open.
- **Feature definition:** [Panel layouts and dynamic appearance](../specs/panel-layouts-and-appearance.md) — revised 2026-11-13 for **D-035/D-036** (gauge wedges, size presets, small hub, More wedge at six o'clock, sub-rings as outer arcs, AC-24…AC-41). Its Proposed/Open rows are built as provisional prototype baselines and decided at the plan's E1; fixtures-first for sub-ring parts was decided in planning.
- **Current handoff:** [Wave 2 done](sessions/2026-11-14.md#resume--gauge-prototype-wave-2-done).
- **Validation:** 1.2.1: 19 focused hostless tests, Debug build/deep signature, signed-feed/tamper and release-tool fixture checks passed. Paired displays and live manual no-update check accepted; other updater controls and real upgrade untested.
- **Next:** Optional early look at the running gauge ring → `/execute` Wave 3. Push `main` (7 local commits). Separately: Strongbox backup, updater/upgrade acceptance and publication for 1.2.1.
- **Last updated:** 2026-11-14

## Recent
- **2026-11-14** — Owner chose icon-only at Medium/8 (D-037); gauge ring 2.1 built: presets, real-data gauges, small hub, More wedge at six o'clock; 229 ring tests pass; fresh build launched.
- **2026-11-14** — Gauge prototype Wave 1 built in parallel (geometry kit, gauge content/parts, card Close fix); 211 focused tests pass. Geometry check shows Medium with 8 favourites is too tight for values — stopped for an owner decision.
- **2026-11-14** — Gauge ring prototype planned: 7 tasks in 5 waves, fixtures first for sub-ring parts, owner review (E1) at the end. Nothing built or run.
- **2026-11-13** — Layout spec revised for the gauge ring after code and web research; owner chose sub-ring + card together and a narrow More wedge (D-036).
- **2026-11-13** — Owner review closed early: hover/hold/Escape/drag/pin/placement pass; look redirected to the gauge mockup (D-035: small hub, sub-rings from wedges, equal-area gauges).
- **2026-11-13** — Ring step 3: confirmed the prototype is left out of Release builds, all 212 tests pass, owner review checklist ready.

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
