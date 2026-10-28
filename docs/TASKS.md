# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Active plan

[24-hour transfer history and totals](../IMPLEMENTATION_PLAN.md) owns task status/evidence:
**8/8 implementation tasks complete**, external acceptance **E1 open**. Full **113-test** suite and
final standalone Debug build passed. Next: the finite user-operated [E1 batch](sessions/2026-10-21.md#e1-acceptance)
on the exact TransferHistoryRun08 artifact. Network gap display and Disk periods/theme/edge checks accepted;
retention accepted 2026-10-23; independent reset/cancel/persistence batch accepted 2026-10-26.
Sleep/wake and network reconnect accepted 2026-10-26. Next: remaining broader card checks and
explicit conditional storage hot-plug status (the aggregate pass did not identify hardware availability).
Remaining E1 checks open. Keep the plan and mapped Backlog entries active until
acceptance; there is no additional implementation phase awaiting permission.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

The whole stats roadmap has shipped (D-017/D-018/D-019 + D-024), and configurable tiles + activity
graphs shipped 2026-07-27 (D-025). v1.1.0 was published 2026-10-03. Remaining work is the follow-up backlog below.
**This file is the backlog** — `PROJECT_STATE.md` is a digest and points here.

### History and transfer totals
- [ ] **Longer graphs and cumulative transfer totals** — user requested network download/upload
      and disk read/write history (2026-10-03). Define retained periods, persistence across app
      restarts, total/reset semantics and sleep/interface-change handling before implementation.
      Existing one-minute graphs remain available in v1.1. Spec: `../specs/transfer-history.md`;
      24-hour retention across restarts and both period/“Since reset” totals confirmed;
      detail-card placement, period selector and gap/reset behavior confirmed. Selected plan:
      `../IMPLEMENTATION_PLAN.md`, tasks 1.1–6.1 and E1. Implementation 8/8 validated; E1 manual acceptance open.

### Distribution
- [ ] **Updater** — QSP has **no updater of any kind**. "Sparkle *vs* SilentUpdateKit" is a false
      dichotomy: they're different halves. **Sparkle 2** = discovery (appcast) + install + UI, the
      de-facto house standard (ClipSmart, Magpie, DiskVerdict, Conjoyn, TimeCodeEditor,
      ScreenshotFromVideos, VideoContainerSwitcher). **SilentUpdateKit**
      (`1-macOS/zPackages/Sources/SilentUpdateKit` — **not** `~/ProgrammingProjects/zPackages`,
      which holds a different set) is explicitly *"free of any appcast/scanner concepts"*:
      install-only — verify Sparkle-format Ed25519 sig via CryptoKit, Team-ID match, extract, quit,
      swap bundle, old version → Trash. **No Sparkle.framework → no nested XPC re-signing**, which
      is exactly what `scripts/package-dmg.sh` currently benefits from. **Recommendation:**
      SilentUpdateKit + a small feed check for an `LSUIElement` HUD; the signature format stays
      Sparkle-compatible, so graduating later needs no re-keying. ⚠️ If full Sparkle is chosen,
      **pin a current release** — older lines carry fixed security advisories, and a portfolio-wide
      version sweep is worth doing separately. (Specific versions/advisory IDs deliberately not
      recorded — this repo is public.)

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
- [ ] **Transfer-rate continuity** — track per-interface baselines and elapsed time so interface
      reconnection or delayed ticks cannot inflate rates; assess disk timing too. Relevant prerequisite
      for cumulative transfer history (source review 2026-10-03; no runtime failure reproduced).
      Mapped to `../IMPLEMENTATION_PLAN.md`, tasks 1.1 and 2.1 (automated checks passed);
      real-device continuity remains part of E1. Completion evidence lives in the selected plan.
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
      and has Quit but no Restart. Implementation has not started; separate from transfer-history E1.
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
- [ ] **Fail packaging on rejected Gatekeeper assessment** — `package-dmg.sh` currently masks
      the final `spctl` result with `|| true`. v1.1 passed independent required app/DMG checks;
      make those checks mandatory in the script for future releases.

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

_The selected transfer-history plan is linked under Active plan; no duplicate task checkboxes here.
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
