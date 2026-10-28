# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** maintain · **Phase:** Published / everyday use <!-- Phase changed: 2026-10-28 -->
- **Focus:** Use v1.2.0 normally; investigate concrete feedback when it appears. Restart remains deferred.
- **Blockers:** none for the approved release scope; remaining manual checks explicitly owner-deferred.
- **Execution:** No active plan; [transfer-history plan archived](sessions/IMPLEMENTATION_PLAN-transfer-history-DONE.md), 8/8 tasks complete, E1 closed by scoped deferral.
- **Current handoff:** [Published release and everyday-use pickup](sessions/2026-10-28.md#resume).
- **Validation:** 113/113 fresh Release hostless tests; universal signed/notarized app and DMG; mounted package and live download identity verified.
- **Next:** Everyday use; capture reproducible issues without restarting the deferred acceptance checklist.
- **Last updated:** 2026-10-28

## Recent
- **2026-10-28** — v1.2.0 published to GitHub and website; exact fresh Release running; remaining manual checks deferred by owner.
- **2026-10-26** — Resets/persistence plus sleep/wake and network reconnect accepted; broader card checks remain.
- **2026-10-23** — Run08 refresh-interval/restart retention accepted; scoped resets next; E1 open.
- **2026-10-21** — Run08 Network visual and Disk periods/theme/edge checks accepted; remaining E1 open.
- **2026-10-20** — Physical 64-bit accounting, retained queries and bounded checkpoint recovery validated.

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
- **Decisions:** `decisions.md` — D-001…D-032, full rationale for every locked choice. Load-bearing:
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
