# Project State — QuickStatsPanel

> **Lean digest — keep under ~70 lines.** Position only. Detail lives in
> `decisions.md`, `sessions/_index.md`, and `TASKS.md` (see **Detail** below).

## Identity
- **Project:** QuickStatsPanel
- **One-liner:** Hotkey-summoned wide HUD strip of live Mac stats, for a quick glance.
- **Tags:** macOS, SwiftUI, AppKit, NSPanel, system-stats, utility
- **Started:** 2026-06-04 · **Target:** macOS 15+ · **License:** PolyForm Noncommercial 1.0.0 (public repo)

## Now
- **Funnel:** build · **Phase:** Floating tiles — prototype implemented, owner review (E1) <!-- Phase changed: 2026-11-27 -->
- **Focus:** bounded native floating-tile prototype; [spec defaults](../specs/floating-tiles.md) remain provisional until owner review. Circle review remains parked (D-040).
- **Blockers:** tile E1 needs the owner. Parked ring E1 open. Separate release gates: Strongbox backup, remaining updater controls and real upgrade acceptance.
- **Execution:** [Floating-tile prototype plan](IMPLEMENTATION_PLAN-floating-tiles.md) — 4/4 complete; awaiting owner review E1 ([review packet](evidence/floating-tiles-prototype.md#e1-owner-review-packet)). [Ring plan](../IMPLEMENTATION_PLAN.md) remains 12/12 implemented, E1 open and parked.
- **Feature definition:** [Floating tiles](../specs/floating-tiles.md), with provisional native defaults. [Earlier layouts/ring spec](../specs/panel-layouts-and-appearance.md) and remaining ring E1 decisions stay parked.
- **Current handoff:** [Pre-clear after tile Wave 4](sessions/2026-11-27.md#resume--pre-clear-after-tile-wave-4) — unpushed commits; next: owner E1.
- **Validation:** W4: full hostless suite 462/0 (0 skipped), Debug/Release build, codesign, Release exclusion clean; Atlas Release Strip launch and Ring render pass. Ad-hoc Release cannot launch on the M4 Pro (hardened runtime vs Sparkle) — use a Developer ID local build. [Evidence](evidence/floating-tiles-prototype.md).
- **Next:** owner runs the E1 packet (cases A–F) on the Debug artifact and records results.
- **Release:** public v1.2.0; prepared v1.2.1 remains unpublished and separate from prototype work. [Release preparation](evidence/release-1.2.1.md).
- **Last updated:** 2026-11-27

## Recent
- **2026-11-27** — Tile 4.1 done: full suite 462/0, Release exclusion clean, Strip/Ring smoke in the helper, E1 review packet written. Tile plan 4/4; E1 open.
- **2026-11-27** — Tile 3.1 done: all detail cards, constrained/edge displays, keyboard (incl. already-active summon), group drag/dismiss/quit, VoiceOver tree; 86/0 focused. Tile plan 3/4; 4.1 ready.
- **2026-11-27** — Pushed; 2.1 dark check passed via helper System Settings → Dark (a global `defaults write` does not work there). Tile plan 2/4; 3.1 ready.
- **2026-11-27** — Tile Wave 2 implemented: all eleven stats in saved-order hierarchy with readings and usage colours; checks pass except dark mode, which the helper can't show yet.
- **2026-11-27** — Tile Wave 1 done on M4 Pro: isolated CPU/Network prototype (`--floating-tiles-prototype`) passes open/switch/return/dismiss, focus and click-through in Atlas. Xcode 26.3 type-check fix committed separately.

## What we're building
Press a global hotkey → a **thin** wide strip appears near the cursor showing live stats as compact
tiles. Click a tile → detail card. Press again / Esc / click-away → dismiss. **No Dock icon, no
menu-bar item** — settings and quit live in the panel. Small corner radius (deliberately *not* the
heavy macOS "Tahoe" rounding).

**Stats roadmap: complete** — CPU, Memory, Disk, Network, Battery, Load, Uptime, Top-process, GPU,
Fans, Power, Temperatures, plus per-stat history graphs (2026-07-27).

## Progress
**Features** ✅ roadmap + retained transfers shipped · **UI** ✅ approved release scope; remaining manual checks deferred ·
**Testing** ✅ 394 hostless tests + bounded hardware probes · **Docs** ✅ ·
**Distribution** ✅ v1.2.0 notarized + released; GitHub and website downloads verified

## Detail (read only if needed)
- **Decisions:** `decisions.md` — D-001…D-041, full rationale for every locked choice. Load-bearing:
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
