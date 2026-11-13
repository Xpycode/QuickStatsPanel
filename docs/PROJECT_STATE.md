# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** build · **Phase:** Native ring prototype — Wave 1 verified, Wave 2 next <!-- Phase changed: 2026-11-13 -->
- **Focus:** v1.2.1 universal app/DMG notarized and local signed update feed verified. Published version remains v1.2.0; [release preparation](evidence/release-1.2.1.md).
- **Blockers:** Strongbox backup confirmed incomplete; remaining updater controls and real upgrade acceptance open.
- **Execution:** [Native ring prototype plan](../IMPLEMENTATION_PLAN.md) · 1/3 — 1.1 **owner-verified 2026-11-13** (hover with another app frontmost, detail, Escape/click-away, hub drag all pass). Wave 2 (1.2) ready; carries a fixture-mode fix for Disk/Network cards stuck on "Loading…". E1 gates broader layout work.
- **Feature definition:** [Panel layouts and dynamic appearance](../specs/panel-layouts-and-appearance.md) drafted: four layouts, up to eight ring favourites plus hover details/More, bounded per-stat colouring. Wedge visual direction accepted (D-034); native prototype and settings review remain; no implementation authorized.
- **Current handoff:** [Wedge gauge planning](sessions/2026-11-13.md#resume--wedge-gauge-planning) (ring 1.1 checks: [here](sessions/2026-11-12.md#resume--ring-11-remaining-native-checks)).
- **Validation:** 1.2.1: 19 focused hostless tests, Debug build/deep signature, signed-feed/tamper and release-tool fixture checks passed. Paired displays and live manual no-update check accepted; other updater controls and real upgrade untested.
- **Next:** `/execute` Wave 2 (1.2: hover/hold timing, More branch, edge placement + fixture transfer-history fix) → 1.3 → E1 working-prototype review. In parallel the owner answers the [gauge mockup](https://claude.ai/artifact/WNNwTzTsSQDTR63E8YUj9g) questions (fill scale, disk mode, size presets) → D-035 + spec section. Separately: Strongbox backup, updater/upgrade acceptance and publication verification for 1.2.1; Restart deferred.
- **Last updated:** 2026-11-13

## Recent
- **2026-11-13** — Owner passed all four ring 1.1 native checks; fixture Disk/Network cards stuck loading (carried to 1.2).
- **2026-11-13** — Explored wedges as radial fill gauges; interactive mockup published, owner choices pending before planning.
- **2026-11-12** — Owner saw the ring prototype running and accepted the concept; sizing deferred to the later review, interaction checks still to report.
- **2026-11-12** — Ring prototype 1.1 built (Debug-only `--ring-prototype`, fixtures, 16 geometry tests); native check pending.
- **2026-11-12** — Ring prototype plan reviewed against the code and tightened; ready to execute next session.

## What we're building
Press a global hotkey → a **thin** wide strip appears near the cursor showing live stats as compact
tiles. Click a tile → detail card. Press again / Esc / click-away → dismiss. **No Dock icon, no
menu-bar item** — settings and quit live in the panel. Small corner radius (deliberately *not* the
heavy macOS "Tahoe" rounding).

**Stats roadmap: complete** — CPU, Memory, Disk, Network, Battery, Load, Uptime, Top-process, GPU,
Fans, Power, Temperatures, plus per-stat history graphs (2026-07-27).

## Progress
**Features** ✅ roadmap + retained transfers shipped · **UI** ✅ approved release scope; remaining manual checks deferred ·
**Testing** ✅ 113 hostless tests + bounded hardware probes · **Docs** ✅ ·
**Distribution** ✅ v1.2.0 notarized + released; GitHub and website downloads verified

## Detail (read only if needed)
- **Decisions:** `decisions.md` — D-001…D-034, full rationale for every locked choice. Load-bearing:
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
