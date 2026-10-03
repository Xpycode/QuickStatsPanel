# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** build · **Phase:** Shipping — v1.1.0 published <!-- Phase changed: 2026-10-03 -->
- **Focus:** v1.1.0 (1100) is signed, notarized, stapled, installed and published on GitHub
  and the product website. User accepted the exact installed release before publication.
- **Blockers:** none for v1.1; longer-history persistence and retention requirements remain open.
- **Next:** Define longer network/disk graphs and cumulative downloaded/uploaded/read/written
  totals, including whether history survives app restarts and which time ranges to retain.
- **Build status:** ✅ universal Release, **5/5 tests**, preserved all 14 existing preference values,
  clean-launch hint, installed smoke acceptance, app/DMG Gatekeeper checks and download checksums.
- **Last updated:** 2026-10-03

## Recent
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
- **2026-07-27** — Research-only day before that: found the app has **no update mechanism at all**,
  that per-tile options were mostly presentation work, and that graphs cost ~30 KB and no extra CPU.
  Also found disk "Free" reads 16.62 GB below Finder because it ignores purgeable space.

## What we're building
Press a global hotkey → a **thin** wide strip appears near the cursor showing live stats as compact
tiles. Click a tile → detail card. Press again / Esc / click-away → dismiss. **No Dock icon, no
menu-bar item** — settings and quit live in the panel. Small corner radius (deliberately *not* the
heavy macOS "Tahoe" rounding).

**Stats roadmap: complete** — CPU, Memory, Disk, Network, Battery, Load, Uptime, Top-process, GPU,
Fans, Power, Temperatures, plus per-stat history graphs (2026-07-27).

## Progress
**Features** ✅ roadmap + D-025 · **UI** ✅ strip, card, 5-pane Settings, themes ·
**Testing** ✅ 5 logic tests + clean/upgrade smoke + user acceptance · **Docs** ✅ ·
**Distribution** ✅ v1.1.0 notarized + released; GitHub and website downloads verified

## Detail (read only if needed)
- **Decisions:** `decisions.md` — D-001…D-027, full rationale for every locked choice. Load-bearing:
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
