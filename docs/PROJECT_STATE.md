# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** build · **Phase:** Polish — preferences redesign next <!-- Phase changed: 2026-10-20 -->
- **Focus:** Display customization accepted by the user. v1.1.0 remains the published release;
  the new settings are validated locally and unreleased.
- **Blockers:** none for the next design discussion; Developer ID certificate unavailable locally.
- **Next:** Redesign per-stat preferences: reduce the cumbersome nested controls and scrolling,
  starting from the saved Memory-settings screenshot. Preserve functionality and stored choices.
- **Current handoff:** [2026-10-20 Resume](sessions/2026-10-20.md#resume).
- **Build status:** ✅ fresh ad-hoc Debug, **17/17 hostless tests**, user reports “works” with screenshot.
- **Last updated:** 2026-10-20

## Recent
- **2026-10-20** — User accepted display customization across stats; 17 tests passed. Saved the
  settings screenshot and queued a simpler preferences layout for the next session.
- **2026-10-03** — Released v1.1.0 after fresh universal build, clean/upgrade smoke checks and
  Apple notarization; GitHub and website downloads verified against the final artifacts.
- **2026-09-01** — Prepared v1.1.0 build 1100 for release, fixed Xcode 17's delayed export-signature
  corruption, and passed the installed upgrade smoke test with v1.0 preferences intact.
- **2026-09-01** — Stabilized v1.1.0: fixed inflated network totals and graph rescaling, restored
  smooth native dragging, clarified hotkey glyphs, added five passing tests, and proved signing.
- **2026-07-27** — Tiles became configurable and gained activity graphs: each stat can headline a
  different value (or both), and CPU/GPU/Memory/Network/Disk draw a mirrored bar history like
  iStat's, with the peak printed beside it. Defaults leave the strip looking exactly as it did.
  Same day: this file slimmed back to a digest, backlog moved to `TASKS.md`, all of it pushed.

## What we're building
Press a global hotkey → a **thin** wide strip appears near the cursor showing live stats as compact
tiles. Click a tile → detail card. Press again / Esc / click-away → dismiss. **No Dock icon, no
menu-bar item** — settings and quit live in the panel. Small corner radius (deliberately *not* the
heavy macOS "Tahoe" rounding).

**Stats roadmap: complete** — CPU, Memory, Disk, Network, Battery, Load, Uptime, Top-process, GPU,
Fans, Power, Temperatures, plus per-stat history graphs (2026-07-27).

## Progress
**Features** ✅ roadmap + D-025 · **UI** ✅ strip, card, 5-pane Settings, themes ·
**Testing** ✅ 17 logic tests + user acceptance (new display settings) · **Docs** ✅ ·
**Distribution** ✅ v1.1.0 notarized + released; GitHub and website downloads verified

## Detail (read only if needed)
- **Decisions:** `decisions.md` — D-001…D-029, full rationale for every locked choice. Load-bearing:
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
