# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** build · **Phase:** Shipping — v1.0.0 released <!-- Phase changed: 2026-07-12 -->
- **Focus:** Feature work is done and unreleased. Configurable tiles + activity graphs shipped
  2026-07-27 (D-025), on `main`, user-verified — but like D-024's temps/power work before it, they
  sit in no tagged artifact.
- **Blockers:** None blocking. One open *choice*: the graph peak strategy (`PeakStrategy.resolve`)
  still returns plain `windowMax`, so a spike ageing off the left edge rescales every bar at once.
  Three options are written up in-code; the app builds and runs as-is. ⚠️ A *decaying* choice needs
  a tick counter — `graphPeak` runs once per body pass, not once per sample.
- **Next:** Cut **v1.1.0**. The notarize → staple → DMG chain is proven, so this is the tag plus the
  release; run `/check ship` first (phase is shipping). Then pick the peak strategy.
- **Build status:** ✅ clean from scratch, **0 Swift warnings**, signed (team `FDMSRXXN73`).
  Notarization proven end to end 2026-07-03; private IOReport/IOHID linkage needs no entitlement.
- **Last updated:** 2026-07-27

## Recent
- **2026-07-27** — Tiles became configurable and gained activity graphs: each stat can headline a
  different value (or both), and CPU/GPU/Memory/Network/Disk draw a mirrored bar history like
  iStat's, with the peak printed beside it. Defaults leave the strip looking exactly as it did.
  Same day: this file slimmed back to a digest, its open backlog moved to `TASKS.md`.
- **2026-07-27** — Research-only day before that: found the app has **no update mechanism at all**,
  that per-tile options were mostly presentation work, and that graphs cost ~30 KB and no extra CPU.
  Also found disk "Free" reads 16.62 GB below Finder because it ignores purgeable space.
- **2026-07-12** — Real per-core temperatures and whole-machine watts, plus richer detail rows,
  using exelban/stats' crowd-sourced sensor-key tables. Fixed Settings reorder being dead on macOS 26.
- **2026-07-12** — Shipped **v1.0.0**: notarized DMG, GitHub release, README; then made the repo
  **public** under a noncommercial license after a clean full-history secret audit.
- **2026-07-11** — Network tile started showing upload beside download, and the first notarized,
  distributable build was produced.

## What we're building
Press a global hotkey → a **thin** wide strip appears near the cursor showing live stats as compact
tiles. Click a tile → detail card. Press again / Esc / click-away → dismiss. **No Dock icon, no
menu-bar item** — settings and quit live in the panel. Small corner radius (deliberately *not* the
heavy macOS "Tahoe" rounding).

**Stats roadmap: complete** — CPU, Memory, Disk, Network, Battery, Load, Uptime, Top-process, GPU,
Fans, Power, Temperatures, plus per-stat history graphs (2026-07-27).

## Progress
**Features** ✅ roadmap + D-025 · **UI** ✅ strip, card, 5-pane Settings, themes ·
**Testing** 🔶 on-screen only, no automated suite · **Docs** ✅ ·
**Distribution** 🔶 v1.0.0 notarized + released, **v1.1.0 untagged**

## Detail (read only if needed)
- **Decisions:** `decisions.md` — D-001…D-025, full rationale for every locked choice. Load-bearing:
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
