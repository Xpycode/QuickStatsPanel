# Themes (Named Presets + Custom) Specification

**Status:** Draft
**Created:** 2026-06-13
**Feature owner:** user · drafted by Claude (research-driven: Apple HIG MCP, Apple docs/WWDC, web/competitor analysis)
**Related:** TASKS.md backlog "Themes (named presets)" · D-015 (flat detail card) · `Theme.swift`

---

## Problem Statement

The panel's entire visual language — background color/opacity, corner radius, status-color
bands, fonts, density — is hardcoded in a static `Theme` enum (compile-time constants, ~38
call sites across 4 views). Users cannot change the look, cannot adapt it to taste, and the
app forces `.preferredColorScheme(.dark)` so it ignores the system appearance. The user wants
**pickable, named themes** (not loose knobs scattered through Settings) plus the ability to
fine-tune a custom look.

## Proposed Solution

Refactor `Theme` from a static namespace into a **selectable, persisted token value** carried
on the existing `AppSettings.shared` `@Observable` singleton. Settings gains a **Theme picker**
listing four curated named presets — **Default**, **Mono**, **Vitals**, **Neon** — plus a
**Customize…** disclosure exposing raw knobs (accent, background, opacity, radius, density)
that defines a persisted **Custom** theme. Each preset ships **light + dark color sets** and
the panel **follows the system appearance** (no per-app light/dark toggle — HIG-compliant).
All three `NSHostingView` panels (strip, detail card, hint) read the active theme inside their
`body` and re-render **live** when the selection changes.

### Key capabilities
1. **Named preset picker** — one Settings control selects Default / Mono / Vitals / Neon / Custom; applies panel-wide and persists.
2. **Live switching** — changing the theme updates the strip, detail card, and hint immediately (no relaunch, no re-summon).
3. **Follow-system light + dark** — every preset renders correctly in both appearances; the panel tracks the system setting automatically.
4. **Custom theme** — a "Customize…" section with accent color, background color, opacity, corner radius, and density; persisted across launches.
5. **Unified status color + hysteresis** — one `usageColor(zones:reversed:)` function drives CPU/mem/disk/net **and** battery (via `reversed`), with hysteresis on band crossings to kill flicker; each preset decides whether status color is on, off (Mono), or emphasized (Vitals).

### Architecture decision (locked from research)

Put the theme on the **existing singleton**, not SwiftUI `@Environment`.

```
// Selection — small, stable, persisted (store this, NOT the token struct)
enum ThemePreset: String, CaseIterable, Codable, Identifiable {
    case `default`, mono, vitals, neon, custom
}

// Token value — flat bag the views read; derived, never persisted directly
struct Theme: Sendable {
    var colors: Colors      // resolves light/dark at read time
    var metrics: Metrics    // cornerRadius, spacing, stripHeight knobs
    var fonts: Fonts
    func usageColor(zones: (warn: Double, hot: Double), reversed: Bool, current: Color?) -> Color
    static func make(_ preset: ThemePreset, custom: ThemeData?) -> Theme
}

@Observable @MainActor final class AppSettings {
    var themePreset: ThemePreset { didSet { rebuildTheme(); persist } }   // observed + persisted
    var customTheme: ThemeData?  { didSet { rebuildTheme(); persist } }   // Codable payload
    private(set) var theme: Theme                                          // observed; views read this
}
```

Views change only their **source path**: `Theme.Colors.background` → `AppSettings.shared.theme.colors.background`, read **inside `body`** so Observation tracks it.

**Why the singleton, not `@Environment`:** SwiftUI Observation tracks dependencies even on a
global/singleton when a property is read in `body`, and re-renders per hosting root
independently. `@Environment` is **not shared across separate `NSHostingView` roots** — it
would have to be injected and re-injected into each of the three panels on every rebuild, and
missing one leaves a stale panel. The views already read `AppSettings.shared` directly today,
so the theme rides a mechanism already proven in this app. (Apple: *Managing model data*;
*Migrating to the Observable macro*; WWDC26-272 *Use SwiftUI with AppKit and UIKit*.)

---

## Acceptance Criteria

### AC-1 — Preset selection applies panel-wide
**Given** the panel is visible with the Default theme,
**when** the user opens Settings and selects "Neon",
**then** the strip background, accent, corner radius, and tile colors all change to the Neon
bundle **without** relaunch or re-summon, and **all three** surfaces (strip, detail card if
open, first-run hint) update together.

### AC-2 — Selection persists
**Given** the user has selected "Mono",
**when** they quit and relaunch the app,
**then** the panel summons in Mono. (Persist the **preset id**, not the derived struct.)

### AC-3 — Follow-system light + dark
**Given** any preset is selected,
**when** the system appearance switches between Light and Dark (System Settings or auto
schedule),
**then** the panel re-renders in that appearance's color set, and **no** in-app control offers
a manual light/dark override. (HIG *Dark Mode → Best practices*: don't offer app-specific
appearance settings.)

### AC-4 — Legibility floor in every preset / appearance
**Given** any preset in either appearance, over either a bright or a dark desktop behind the
translucent panel,
**when** the panel is shown,
**then** primary text meets a **≥ 4.5:1** contrast ratio against its effective background, and
high-translucency presets apply a dimming layer (or thicken the material) to guarantee it.
(HIG *Accessibility* contrast; *Materials* dimming-layer guidance.)

### AC-5 — Status color never the sole signal
**Given** a stat is in the "hot" band,
**when** it is rendered,
**then** severity is conveyed by **more than color alone** (e.g. SF Symbol/glyph or label),
so it is distinguishable under color-blindness and in Mono (where status color is off).
(HIG *Color → Inclusive color*; *Accessibility*.)

### AC-6 — Unified status function covers battery
**Given** CPU at 85% and battery at 8%,
**when** their tiles render with status color on,
**then** both resolve "hot" via the **same** `usageColor(zones:reversed:)` — CPU normally,
battery with `reversed: true` — and the old `100 - percent` battery hack in `BatterySampler`
is gone.

### AC-7 — Hysteresis prevents band flicker
**Given** a value oscillating around a band boundary (e.g. CPU hovering at 79–81% with an 80%
hot threshold),
**when** it crosses the boundary,
**then** the displayed color steps **up** only after the value exceeds the boundary by the
hysteresis margin (~5%) and steps **down** only after it drops below by the same margin — no
per-tick color thrash.

### AC-8 — Mono suppresses status color
**Given** the Mono preset,
**when** any stat is in any band,
**then** all tiles render in a single neutral tint (status color **off**), while the redundant
non-color severity cue (AC-5) remains so "hot" is still perceivable.

### AC-9 — Custom theme round-trips
**Given** the user opens "Customize…", sets a custom accent + background + opacity + radius +
density,
**when** they relaunch,
**then** the Custom theme is restored exactly. (Colors persisted via `Color.Resolved`
(macOS 14+, Codable) in a fixed sRGB color space; the struct is the `ThemeData` payload.)

### AC-10 — Density floor respected
**Given** the most compact density setting (preset or custom),
**when** the panel renders,
**then** body text stays **≥ 10 pt** and any in-panel interactive control (gear, quit) stays
**≥ 20×20 pt** with adequate padding. (HIG *Accessibility* type-size & control-size floors.)

### AC-11 — Honors system accessibility toggles
**Given** **Reduce Transparency** or **Increase Contrast** is enabled in System Settings,
**when** the panel renders,
**then** presets fall back to a more opaque / higher-contrast variant rather than the default
translucency. (HIG *Materials*; *Color*.)

---

## Technical Considerations

- **Refactor surface:** ~38 `Theme.*` call sites across `StatsStripView`, `StatTileView`,
  `StatDetailView`, `FirstRunHintView`. Mechanical path-swap. Optionally keep the old static
  `Theme` enum briefly **forwarding** to `AppSettings.shared.theme` to migrate views
  incrementally — but the forwarding must be read inside `body` to preserve Observation.
- **Remove forced dark:** `.preferredColorScheme(.dark)` is currently set in `StatsStripView.swift:47`,
  `FirstRunHintView.swift:24`, `StatDetailView.swift:32`. These must be removed (or driven by
  the theme) for "follow system" to work — otherwise the panel stays dark in Light mode.
- **macOS 15 Observation gotcha:** AppKit-hosted SwiftUI auto-observation is default-on in the
  2026 OSes but may require `NSObservationTrackingEnabled=YES` in Info.plist on macOS 15.x for
  hosting-view redraws to fire on singleton mutations. **Target is macOS 15+** → set it
  explicitly and **test live theme switching on a 15.x machine**, not only on 26.
- **Color model:** built-in preset colors are **code constants** (no serialization). Only the
  **Custom** theme serializes colors — use `Color.Resolved` pinned to **sRGB/extended-sRGB**
  (`cgColor.components` arity varies by color space — a known footgun). Don't persist the
  derived `Theme` struct; persist `themePreset` + `ThemeData?`.
- **Status color as a function, not a constant:** model exactly like the Stats app's
  `usageColor(zones:reversed:)` — `(warn, hot)` thresholds + `reversed` flag handle CPU/mem/
  disk/net **and** battery in one place. **Thresholds are a correctness concern, shared across
  presets** (not per-preset aesthetics); a preset only chooses on/off/emphasis. Hysteresis
  needs the *previous* band per tile — small per-tile state (the sampler or the descriptor
  carries last band), since color is now history-dependent.
- **Materials over raw alpha:** express "opacity" against a real `NSVisualEffectView` / SwiftUI
  `Material` where possible rather than a hand-tuned `Color.black.opacity()`, so Reduce
  Transparency and desktop tinting behave. (HIG *Materials*.) — evaluate vs. the current flat
  `Color.black.opacity(0.82)`; may stay a fill if material conflicts with the "not-Tahoe"
  flat look (D-015). Decide during /plan.
- **Settings UI:** add a Theme picker + a `Customize…` disclosure to `SettingsView`. Lead with
  the named presets; bury raw pickers under the disclosure (research: leading with 20+ raw
  color slots loses users — Stats #2377).
- **Live update across 3 roots:** verified pattern — each panel's `body` reads
  `AppSettings.shared.theme.…`; no environment plumbing.

## Out of Scope

- **Per-tile / per-module color overrides** (iStat/Stats fragment the look per module). A
  unified HUD wants one coherent panel-wide look. Possible future escape hatch only.
- **Manual per-app light/dark toggle** — explicitly excluded (HIG). System drives appearance.
- **Liquid Glass styling on the stat tiles** — HIG: glass is for the control/navigation layer,
  not content. Tiles stay on standard materials/flat fills.
- **Importing/exporting/sharing themes**, theme marketplace, or more than one saved custom theme.
- **Per-preset threshold customization** — thresholds are global/correctness, not per-theme.
- **Animated theme transitions** (cross-fade between themes) — nice-to-have, not v1.

## Open Questions

**Resolved 2026-06-13 (user):**
1. ✅ **Background = flat fill, not Material.** Keep `Color.opacity()` (preserves the deliberate
   not-Tahoe D-015 flatness); add an **explicit Reduce-Transparency fallback** — bump opacity
   toward opaque (~0.98) when the system flag is set. No `NSVisualEffectView`.
2. ✅ **Density varies font size + tile spacing (+ corner radius) only.** The existing
   `stripHeight` slider stays the **single source of truth for height**, fully independent of
   theme — no override/seed logic, no second source of truth.
4. ✅ **"Default" reproduces today's exact look verbatim** (black 0.82, green/yellow/red bands,
   12pt radius) — now follow-system aware. **Upgrade is visually seamless**; new themes are
   opt-in only.
5. ✅ **Accent follows the macOS system accent** (`controlAccentColor`/`Color.accentColor`) for
   non-status highlights. Individual presets may still pin their own accent (Neon = fixed
   saturated; Mono = neutral).

**Still open (settle in /plan or design):**
3. **Hysteresis margin:** ±5% fixed, or proportional per metric? Where does the per-tile "last
   band" state live — `StatDescriptor`, the sampler, or a small store-side map? *(Lean: fixed
   ±5%, last-band in a small store-side `[StatKind: Band]` map — color is now history-dependent
   and the store already owns per-tick state.)*
6. **Non-color severity cue (AC-5):** concrete cue — leading SF Symbol per tile, weight change,
   or a small dot? Needs a design pass (ties into `02_Design/design-prompts.md`).

---

## Research provenance

- **Apple HIG** (Color, Materials, Dark Mode, Layout, Accessibility) — appearance/contrast/
  density/translucency constraints → AC-3/4/5/10/11.
- **Apple docs + WWDC26-272 / WWDC22-10075** — Observation across multiple `NSHostingView`
  roots; singleton-as-source-of-truth → architecture decision.
- **Competitor teardown** (iStat Menus, Stats/exelban, iGlance, MenuMeters) — nobody ships
  named curated bundles (differentiation); `usageColor(zones:reversed:)` model; 60/80 stepped
  bands; no one does live-color hysteresis (our edge) → capabilities + AC-6/7/8.

---
*Next: review & refine ACs → resolve Open Questions → `/plan` to create implementation waves.*
