# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

The whole stats roadmap has shipped (D-017/D-018/D-019 + D-024), and configurable tiles + activity
graphs shipped 2026-07-27 (D-025). Remaining work is release ceremony plus the tails below.
**This file is the backlog** — `PROJECT_STATE.md` is a digest and points here.

### Release
- [ ] **v1.1.0 release** — D-024's temps/power work has been on `main` since 2026-07-12 and D-025's
      tiles/graphs since 2026-07-27; neither is in a tagged artifact. Notarize → staple → DMG chain
      is already proven; run `/check ship` first (phase is shipping).
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
- [ ] **Disk free-space accuracy** — `DiskSampler.swift:108` (`statfs f_bavail`) reads **600.62 GB**
      where Finder shows **617.24 GB**: a **16.62 GB** purgeable gap, twice-measured. exelban/stats
      matches Finder via `CSDiskSpaceGetRecoveryEstimate` (CoreServices, cached 30 s,
      `Modules/Disk/readers.swift:144`) — **undocumented SPI**, consistent with QSP's IOReport/IOHID
      posture but another one. Alternative `volumeAvailableCapacityForImportantUsageKey` is a
      **required-reason API** (matters only if a `PrivacyInfo.xcprivacy` is ever added). Never
      display `…ForOpportunisticUsage` — it is *smaller* than plain available. ⚠️ The existing
      `used = total − free` derivation (line 109) is **correct**; don't "fix" it.

### Features not started
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

### Polish / nice-to-haves (from visual verify)
- [ ] **⏳ USER:** tune `Theme.loadColor(forPercent:)` thresholds — at-a-glance color bands.
      Open questions: same bands for CPU vs memory? gradient vs steps? hysteresis to stop flicker?
- [ ] Memory readout shows 2 decimals ("16,85 GB") — consider 1 decimal for faster glancing.
- [ ] `cornerRadius` 12pt reads fine at the snug width — revisit if it ever feels too round.

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

_Empty — D-019 and D-017 archived to `tasks-archive.md` on 2026-07-27 (both shipped 2026-06-15;
they sat here for six weeks while D-020→D-024 shipped around them). D-025 shipped same-day and
never entered a sprint. Next obvious sprint is the **v1.1.0 release**._

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
