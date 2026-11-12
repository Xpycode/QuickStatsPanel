# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Active plan

None. Transfer history shipped as **v1.2.0 (1200)** on 2026-10-28: 8/8 implementation tasks complete;
remaining E1 checks explicitly deferred by the owner to everyday use, not marked as tested.
[Archived plan](sessions/IMPLEMENTATION_PLAN-transfer-history-DONE.md) ·
[Release evidence](evidence/release-1.2.0.md). No further acceptance batch is required before ordinary use.

## Current standalone work

- Power input/system, CPU usage/temperature and Battery charge/time pairs implemented for 1.2.1 (1201); 19 focused tests and Debug build passed. User accepted the latest paired-display build (“works. pass.”); no claim of exhaustive live hardware-state testing. See [handoff](sessions/2026-11-11.md#resume).
- Sparkle 2.10.0 integrated; initial signed empty feed published and verified. Live manual no-update check passed by user screenshot on 2026-11-12; remaining updater controls, real upgrade, Strongbox backup and release packaging remain open.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

The whole stats roadmap has shipped (D-017/D-018/D-019 + D-024), and configurable tiles + activity
graphs shipped 2026-07-27 (D-025). Retained transfers shipped in v1.2.0 on 2026-10-28. Remaining work is the follow-up backlog below.
**This file is the backlog** — `PROJECT_STATE.md` is a digest and points here.

### Distribution
- [ ] **Sparkle release acceptance** — requested 2026-11-11. Integration, dedicated signing key, signed empty feed and packaging validation implemented for 1.2.1. Initial signed empty feed published and verified; validate manual check and opt-in checkbox, back up key to Strongbox, package/notarize release, and test a real upgrade with retained preferences/history. 1.2.0 must upgrade manually. See `sparkle-updates.md`.

### D-025 tails
- [ ] **Detail-card headline pair** (optional) — the big `61 KB/s / Upload` block from the iStat
      reference. Omitted deliberately: the strip and the card's own rows already show those values.
- [ ] **Text-template tile values** (power-user escape hatch) — Stats' `$capacity.free/$capacity.total`
      syntax (`Kit/Widgets/Text.swift:83`) is the only mechanism in either reference product that
      lets a user say "free, not used" in arbitrary form. Best power-to-complexity ratio if the
      per-stat enums ever feel limiting. Not for v1.

### Accuracy
- [ ] **Actual memory pressure and swap** — current `MemorySampler.pressurePercent` is used RAM
      divided by total RAM and is labeled "Pressure" in the detail card. Keep utilization distinct
      from system memory-pressure state; consider swap detail (confirmed source review 2026-10-03).
- [ ] **Disk free-space accuracy** — `DiskSampler.swift:108` (`statfs f_bavail`) reads **600.62 GB**
      where Finder shows **617.24 GB**: a **16.62 GB** purgeable gap, twice-measured. exelban/stats
      matches Finder via `CSDiskSpaceGetRecoveryEstimate` (CoreServices, cached 30 s,
      `Modules/Disk/readers.swift:144`) — **undocumented SPI**, consistent with QSP's IOReport/IOHID
      posture but another one. Alternative `volumeAvailableCapacityForImportantUsageKey` is a
      **required-reason API** (matters only if a `PrivacyInfo.xcprivacy` is ever added). Never
      display `…ForOpportunisticUsage` — it is *smaller* than plain available. ⚠️ The existing
      `used = total − free` derivation (line 109) is **correct**; don't "fix" it.

### Features not started
- [ ] **Right-click Restart QuickStatsPanel** — user request, 2026-10-26; saved for later.
      Add Restart to the strip's context menu. Relaunch the same app bundle through normal
      termination/startup so saved preferences, retained history and cumulative totals survive.
      Current menu lives in `01_Project/Sources/QuickStatsPanel/AppDelegate.swift` (`makePanelMenu`)
      and has Quit but no Restart. Implementation has not started; separate from the shipped transfer-history work.
- [ ] **Vertical strip orientation** — a portrait variant (tiles stacked, anchored to a screen edge).
      Touches D-006/D-008 (thin-strip + content-driven-width assumptions), `PanelWindowController`
      sizing/anchors, and the tile layout — needs a small spec before building.
- [ ] **Per-volume disk rows** — middle ground from the exelban/stats review; adds card height.
      Available on request. (Also reviewed and **rejected** then: usage donuts — user since said
      "donuts later perhaps"; **public IP** — needs an external HTTP call, and QSP making *zero*
      network requests is a privacy property worth keeping; **MAC address** — not glanceable.)
- [ ] **Hover-to-expand tile detail** — later enhancement; needs tracking-area work.
- [ ] **Per-app CPU smoothing** — only if grouped readings flicker; revisit grouping edge cases
      (apps outside an `.app` bundle).

### Release tooling
- [x] **Fail packaging on rejected Gatekeeper assessment** — implemented 2026-11-11 with required app/DMG checks and nested Sparkle signature validation; fixtures passed, real release packaging pending.

### Polish / nice-to-haves (from visual verify)
- [ ] **⏳ USER:** tune `Theme.loadColor(forPercent:)` thresholds — at-a-glance color bands.
      Open questions: same bands for CPU vs memory? gradient vs steps? hysteresis to stop flicker?
- [ ] Memory readout shows 2 decimals ("16,85 GB") — consider 1 decimal for faster glancing.
- [ ] `cornerRadius` 12pt reads fine at the snug width — revisit if it ever feels too round.

## Inbox
- [ ] **Power sampler stop/restart race — awaiting reproduction (2026-10-03).** Review found
      timer cancellation followed by main-thread reader/SMC teardown while a queued tick may still
      run. No crash reproduced. Validate queue-confined teardown before changing sampler lifecycle.

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

_No active implementation plan; completed transfer-history evidence is linked above.
Preferences redesign remains accepted and unreleased._

---

## Progress Calculation

```
Sprint Progress = checked in Current Sprint / total in Current Sprint
Overall Progress = (archived count + checked) / (backlog + current + archived)
```

Archived task count is read from `tasks-archive.md` header.

## Workflow Integration

| Command | Action |
|---------|--------|
| `/interview` | Adds tasks to Backlog |
| `/plan` | Moves Backlog → Current Sprint |
| `/execute` | Checks off tasks as waves complete |
| `/log` | Archives checked tasks, updates PROJECT_STATE.md progress bar |
| `/status` | Reports progress from checkbox counts |

---
*Location: `docs/TASKS.md`. Parsed by Directions app.*
