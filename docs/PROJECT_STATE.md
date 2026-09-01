# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** build · **Phase:** Shipping — v1.0.0 notarized and published <!-- Phase changed: 2026-07-12 -->
- **Focus:** v1.1.0 build 3 is stabilized and user-verified: accurate physical-link network totals,
  smooth sample-driven graph scaling, native panel dragging, clearer hotkey labels, and the first
  automated tests. A signed universal Developer ID archive/export was proven in `/tmp`.
- **Blockers:** Release candidate must be rebuilt after the final drag/typography fixes, then run
  through `/check ship`, notarization, packaging, and a final installed-app smoke test.
- **Next:** Rebuild the signed **v1.1.0** archive, run `/check ship`, notarize/staple/package it, then
  add the updater feed/install path. Do not publish the earlier pre-drag `/tmp` export.
- **Build status:** ✅ clean compile, **5/5 tests**, user-verified UI; Developer ID signing/export
  proven for build 3. Notarization proven end to end for v1.0.0, not yet run on this candidate.
- **Last updated:** 2026-09-01

## Recent
- **2026-09-01** — Stabilized v1.1.0: fixed inflated network totals and graph rescaling, restored
  smooth native dragging, clarified hotkey glyphs, added five passing tests, and proved signing.
- **2026-07-27** — Tiles became configurable and gained activity graphs: each stat can headline a
  different value (or both), and CPU/GPU/Memory/Network/Disk draw a mirrored bar history like
  iStat's, with the peak printed beside it. Defaults leave the strip looking exactly as it did.
  Same day: this file slimmed back to a digest, backlog moved to `TASKS.md`, all of it pushed.
- **2026-07-27** — Research-only day before that: found the app has **no update mechanism at all**,
  that per-tile options were mostly presentation work, and that graphs cost ~30 KB and no extra CPU.
  Also found disk "Free" reads 16.62 GB below Finder because it ignores purgeable space.
- **2026-07-12** — Real per-core temperatures and whole-machine watts, plus richer detail rows,
  using exelban/stats' crowd-sourced sensor-key tables. Fixed Settings reorder being dead on macOS 26.
- **2026-07-12** — Shipped **v1.0.0**: notarized DMG, GitHub release, README; then made the repo
  **public** under a noncommercial license after a clean full-history secret audit.

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
