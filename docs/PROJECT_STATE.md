# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** plan · **Phase:** Native ring prototype planned; ready for build <!-- Phase changed: 2026-11-12 -->
- **Focus:** v1.2.1 universal app/DMG notarized and local signed update feed verified. Published version remains v1.2.0; [release preparation](evidence/release-1.2.1.md).
- **Blockers:** Strongbox backup confirmed incomplete; remaining updater controls and real upgrade acceptance open.
- **Execution:** [Native ring prototype plan](../IMPLEMENTATION_PLAN.md), 0/3 tasks; Wave 1 / 1.1 ready. Plan reviewed against source and amended (isolation, window model, visibility parity, early hover proof); execution not yet requested. E1 owner review gates all broader layout/appearance work.
- **Feature definition:** [Panel layouts and dynamic appearance](../specs/panel-layouts-and-appearance.md) drafted: four layouts, up to eight ring favourites plus hover details/More, bounded per-stat colouring. Wedge visual direction accepted (D-034); native prototype and settings review remain; no implementation authorized.
- **Current handoff:** [Native ring execution pickup](sessions/2026-11-12.md#resume--native-ring-execution).
- **Validation:** 1.2.1: 19 focused hostless tests, Debug build/deep signature, signed-feed/tamper and release-tool fixture checks passed. Paired displays and live manual no-update check accepted; other updater controls and real upgrade untested.
- **Next:** `/execute` (owner chose Opus) for the bounded native wedge prototype, then E1 working-prototype review before planning remaining layouts/appearance. Separately: Strongbox backup, updater/upgrade acceptance and publication verification for 1.2.1; Restart deferred.
- **Last updated:** 2026-11-12

## Recent
- **2026-11-12** — Ring prototype plan reviewed against the code and tightened; ready to execute next session.
- **2026-11-12** — Owner accepted the revised wedge ring direction; native interaction validation is next in planning.
- **2026-11-12** — Layout/appearance spec drafted from owner choices; ring supports both hover details and more stats. Existing 1.2.1 release gates preserved.
- **2026-11-12** — User confirmed the live update check; exit handoff prepared with release/backup gates retained.
- **2026-11-11** — Paired displays accepted; Sparkle integrated with signed feed and release tooling. Fresh Debug running; signed empty feed published and HTTPS/signature verified.

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
