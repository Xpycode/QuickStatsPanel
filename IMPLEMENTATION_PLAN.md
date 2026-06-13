# Implementation Plan — Themes (Named Presets + Custom)

> **Persists across sessions.** Regenerate when wrong rather than patching.
> Source spec: `specs/themes.md` (finalized 2026-06-13, 4/6 open Qs resolved).

## Goal
Turn the static `Theme` enum into a selectable, persisted token value on `AppSettings.shared`,
exposing four named presets (Default/Mono/Vitals/Neon) + a Custom theme, follow-system light+dark,
and a unified hysteresis-backed status-color function — all updating the panel live.

## Acceptance Criteria (from spec — abbreviated; see specs/themes.md for Given/When/Then)
- [ ] AC-1 Preset selection applies panel-wide, live, across strip + detail card + hint
- [ ] AC-2 Selection persists across relaunch (store preset id, not the struct)
- [ ] AC-3 Follow system light+dark; **no** manual appearance toggle
- [ ] AC-4 Primary text ≥ 4.5:1 contrast in every preset/appearance; high-translucency dims
- [ ] AC-5 Severity conveyed by more than color alone (works in Mono / color-blind)
- [ ] AC-6 One `usageColor(zones:reversed:)` covers CPU/mem/disk/net **and** battery; `100-percent` hack gone
- [ ] AC-7 Hysteresis (~±5%) prevents band-flicker
- [ ] AC-8 Mono suppresses status color (keeps the non-color cue)
- [ ] AC-9 Custom theme round-trips (Color.Resolved sRGB)
- [ ] AC-10 Compact density floor: text ≥ 10pt, controls ≥ 20×20pt
- [ ] AC-11 Honors Reduce Transparency / Increase Contrast

## Locked design decisions (don't re-litigate)
- **Singleton, not `@Environment`** — theme rides `AppSettings.shared` (`@Observable`); views read
  `AppSettings.shared.theme.…` inside `body`. ([rationale: spec — multi-NSHostingView topology])
- **Flat fill, not Material** — keep `Color.opacity()`; add manual Reduce-Transparency fallback.
- **Density = font + spacing (+ radius) only** — existing `stripHeight` slider stays the lone height source.
- **Default = today's exact dark tokens verbatim** (+ a new light variant); upgrade seamless for dark users.
- **Accent follows macOS system accent** (`Color.accentColor`); Neon/Mono may pin their own.
- **Status color resolved in the store** (descriptor carries the tint) so hysteresis state lives in one
  store-side `[StatKind: Band]` map — views never compute color.

## Specs
- `specs/themes.md` — full requirements, research provenance, resolved open questions.

---

## Tasks

### Wave 1 ✅ (parallel — new standalone files, no deps) — done 2026-06-13, commit `3fe3bb4`

- [x] **1.1**: Color ↔ Codable helpers → `Model/Theme/ColorCodable.swift`
  - `Color.Resolved` (sRGB-pinned) ↔ `Codable` round-trip + `Color(hex:)`/`toHex` convenience.
  - Success: a `ThemeData` payload can encode/decode a color losslessly in sRGB; unit-checkable in a `#Preview` or a tiny `assert`.
  - Backpressure: builds; round-trips a known color (e.g. `#000000D1` ≈ black 0.82) within 1/255.

- [x] **1.2**: Preset + custom-payload types → `Model/Theme/ThemePreset.swift`
  - `enum ThemePreset: String, CaseIterable, Codable, Identifiable { default, mono, vitals, neon, custom }` + `displayName`.
  - `struct ThemeData: Codable, Sendable` — accent, background, opacity, cornerRadius, density (the custom payload).
  - Success: types compile; `ThemePreset.allCases` excludes nothing; `.custom` carries a `ThemeData`.
  - Backpressure: builds.

- [x] **1.3**: Status band + hysteresis (pure logic) → `Model/Theme/StatusBand.swift`
  - `enum Band { calm, busy, hot }`; `func band(forPercent:reversed:zones:previous:) -> Band` applying ~±5% hysteresis against `previous`.
  - Success: a value oscillating 79–81% around an 80% boundary does **not** change band without crossing ±5%; battery `reversed:true` inverts.
  - Backpressure: builds; inline asserts for the oscillation + reversed cases pass.

### Wave 2 ✅ (the chokepoint — sequential; everything else depends on it) — done 2026-06-13

- [x] **2.1**: Refactor `Theme` static enum → token **struct** → `Theme.swift`
  - `struct Theme { var colors; var metrics; var fonts; func usageColor(band:on:emphasis:) -> Color; func tint(for:reversed:previous:) }`.
  - Colors resolve **light + dark** (take a `ColorScheme` or use dynamic `Color`s) — Default-dark = today's verbatim values.
  - `static func make(_ preset:, custom: ThemeData?, reduceTransparency: Bool) -> Theme` defining all 4 presets.
  - Keep a **transitional `enum Theme` facade** forwarding `Theme.Colors.X`→`AppSettings.shared.theme.colors.X` so views still compile until Wave 3. *(Read inside `body` only.)*
  - Depends on: 1.1, 1.2, 1.3
  - Success: project builds with views untouched; `make(.default,…)` dark == current pixels.
  - Backpressure: `xcodegen generate && xcodebuild … build` clean.

- [x] **2.2**: Wire theme into `AppSettings` → `Model/AppSettings.swift`
  - Add `themePreset` (persisted), `customTheme: ThemeData?` (persisted via 1.1), derived `private(set) var theme: Theme` recomputed in `didSet` + on `reduceTransparency` change; new `Keys`.
  - Observe `NSWorkspace.accessibilityDisplayOptionsDidChange` (Reduce Transparency / Increase Contrast) → rebuild theme.
  - Extend `resetToDefaults` path (model side) to reset `themePreset`/`customTheme`.
  - Depends on: 2.1
  - Success: `AppSettings.shared.theme` reflects the picked preset; survives relaunch; reduce-transparency flips opacity.
  - Backpressure: build clean; `defaults read com.sim.QuickStatsPanel themePreset` shows the value after a change.

### Wave 3 ✅ (migrate consumers) — done 2026-06-13, commit `332bbbe`

- [x] **3.1**: Migrate strip → `Views/StatsStripView.swift`
  - `Theme.*` → `AppSettings.shared.theme.*`; pull `tileSpacing`/`cornerRadius`/`horizontalPadding` from theme density; **remove `.preferredColorScheme(.dark)`**.
  - Depends on: 2.2 — Success: strip renders identically on Default/dark; follows system in Light.
  - Backpressure: build clean; visual unchanged on Default.

- [x] **3.2**: Migrate tile + status tint → `Views/StatTileView.swift`
  - Replace `Theme.loadColor(forPercent:)` with the store-resolved `stat.tint`; add the **non-color severity cue** (AC-5 — lean: SF Symbol weight/variant or a small leading dot per band). Migrate fonts/colors.
  - Depends on: 2.2, 3.5 (tint on descriptor) — Success: hot stat distinguishable in Mono & greyscale.
  - Backpressure: build clean; Mono shows no status hue but still signals "hot".

- [x] **3.3**: Migrate detail card → `Views/StatDetailView.swift`
  - `Theme.*` → `theme.*`; **remove `.preferredColorScheme(.dark)`**; radius from theme.
  - Depends on: 2.2 — Success: card matches strip on every preset/appearance.
  - Backpressure: build clean.

- [x] **3.4**: Migrate first-run hint → `Views/FirstRunHintView.swift`
  - `Theme.*` → `theme.*`; **remove `.preferredColorScheme(.dark)`**; keycap chip tint from theme.
  - Depends on: 2.2 — Success: hint matches active theme.
  - Backpressure: build clean.

- [x] **3.5**: Store-resolved tint + drop battery hack → `Model/StatDescriptor.swift` (+ `StatsStore`, `Sampling/BatterySampler.swift`)
  - Add `tint: Color` to `StatDescriptor`, resolved in the store via `theme.tint(for:reversed:previous:)` using a store-side `[StatKind: Band]` hysteresis map; battery passes `reversed: true` here instead of the `100 - percent` inversion (remove that from sampler/descriptor).
  - Depends on: 2.2 — Success: AC-6 (one function) + AC-7 (hysteresis) hold; battery still reads "low = hot".
  - Backpressure: build clean; battery + CPU both resolve via the same call.

### Wave 4 (Settings UI — depends on Wave 2)

- [ ] **4.1**: Theme picker section → `Views/SettingsView.swift`
  - New "Appearance" `Section` with a `Picker` bound to `settings.themePreset` (presets + Custom); live preview swatch optional.
  - Depends on: 2.2 — Success: switching the picker changes the live panel (AC-1).
  - Backpressure: build clean; pick each preset → panel updates.

- [ ] **4.2**: Customize… disclosure + reset → `Views/SettingsView.swift`
  - `DisclosureGroup("Customize…")` shown when `.custom` (or always, selecting `.custom` on edit): `ColorPicker` accent + background, opacity `Slider`, corner-radius `Slider`, density `Picker`; writes `settings.customTheme`. Extend `resetToDefaults()` to reset theme.
  - Depends on: 2.2, 4.1 — Success: AC-9 round-trips; reset returns to Default.
  - Backpressure: build clean; edit custom → relaunch → restored.

### Wave 5 (verification)

- [ ] **5.1**: macOS 15 observation + clean build → `01_Project/project.yml` (Info.plist)
  - Add `NSObservationTrackingEnabled=YES` (hosting-view redraw on singleton mutation on 15.x); `xcodegen generate`; full clean build, no warnings.
  - Backpressure: `xcodebuild clean build` → `** BUILD SUCCEEDED **`, 0 warnings.

- [ ] **5.2**: Manual verification of user flows (signed run)
  - Live-switch all 4 presets + Custom (AC-1); relaunch persistence (AC-2/9); toggle system Light/Dark (AC-3); contrast eyeball over bright + dark desktop (AC-4); Mono greyscale severity (AC-5/8); battery low = hot (AC-6); hover a value at a band edge for flicker (AC-7); compact density legibility (AC-10); System Settings → Reduce Transparency (AC-11).
  - Backpressure: each AC visually confirmed; note results in session log.

- [ ] **5.3**: Adversarial review (2–3 passes)
  - Stale-panel check (does every one of the 3 hosting roots update live?); Observation-tracking check (no theme snapshot captured outside `body`); color round-trip precision; hysteresis edge cases; light-mode-upgrade surprise for existing light-mode users.
  - Backpressure: `/code-review` on the diff; findings triaged.

---

## Operational Learnings
- Adding files requires `cd 01_Project && xcodegen generate` before `xcodebuild` (CLAUDE.md / cookbook 47).
- SourceKit may emit false "Theme not found" diagnostics during the migration; trust `xcodebuild`, not the indexer (seen 2026-06-13). In Wave 2 the indexer briefly flagged *every* cross-file type (`StatKind`, `PanelAnchor`, `HotKeyService`, …) as "not found" — pure index staleness; `xcodebuild` compiled clean.
- **Wave 2 gotchas (real, caught by `xcodebuild`):** (1) a private static helper `metrics(…)`/`fonts(…)` collides with the instance properties `var metrics`/`var fonts` on the same struct → renamed to `makeMetrics`/`makeFonts`. (2) Reading `self.themePreset`/`self.customTheme` to derive `theme` in `init` fails ("self used before all stored properties initialized") because `theme` is still unset — compute via **locals**, assign, then build `theme` from the locals.
- **Facade design that worked:** `Theme` is now a `struct`; the transitional facade is `@MainActor static var`s in extensions of `Theme.Colors`/`Metrics`/`Fonts` (+ `Theme.loadColor`). Static `Theme.Colors.background` and instance `theme.colors.background` coexist (different access paths, no recursion). **Facade deleted in Wave 3** (commit `332bbbe`) after a grep confirmed only doc-comment mentions remained.
- **Wave 3 — in-body band cache is safe:** the per-`StatKind` hysteresis map (`lastBands`) is written inside `visibleStats` (a `body` read). Marking it `@ObservationIgnored` means the write triggers no Observation invalidation → no re-render loop; verified empirically by a synthetic-summon probe that completed (a loop would freeze the run loop). Do NOT make `lastBands` an observed `var`.
- **Wave 3 — width-neutral weight ramp:** the AC-5 severity cue ramps font weight (calm/busy/hot → regular/semibold/heavy). To keep the jitter-free strip, the hidden width-template reserves `.heavy` always and the icon sits in a `.frame(width: 16)`, so a band change never changes tile width.
- **Wave 3 — parallel-agent split:** delegated the two *independent* mechanical view migrations (3.3 detail, 3.4 hint) to parallel `developer` agents (edit-only, no build — concurrent `xcodebuild` collides); kept the coupled core (3.1 strip ⇄ 3.2 tile API contract ⇄ 3.5 store tint) in the orchestrator. Worked cleanly.
- **Deferred to Wave 4 (from 2.2):** the model-side reset of `themePreset`/`customTheme` was NOT added (no `resetToDefaults` exists on `AppSettings` yet). Wire it into the Settings "Reset" path in **4.2**.

## Blocked Tasks / Notes
- **Light-mode upgrade nuance:** today the panel is force-dark even in Light mode. Removing
  `.preferredColorScheme(.dark)` means existing *Light-mode* users see a (new) light panel on
  upgrade — "seamless" holds for dark-mode users only. Decide during 3.x whether Default should
  stay force-dark or embrace its light variant. (Lean: embrace light — more HIG-correct.)
- **Open Q #6 (concrete non-color cue)** and **Q #3 (hysteresis margin/state location)** settle
  during 3.2 / 3.5 respectively — both have a documented "lean" above.

---

## Execution Log
| Wave | Started | Completed | Commits |
|------|---------|-----------|---------|
| 1 | 2026-06-13 | 2026-06-13 | 3fe3bb4 |
| 2 | 2026-06-13 | 2026-06-13 | caf5694 |
| 3 | 2026-06-13 | 2026-06-13 | 332bbbe |
| 4 | | | |
| 5 | | | |

---
*Delete when all tasks complete; archive to sessions/ if useful.*
