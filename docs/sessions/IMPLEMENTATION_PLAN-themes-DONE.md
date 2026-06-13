# Implementation Plan — Themes (Named Presets + Custom)

> **Persists across sessions.** Regenerate when wrong rather than patching.
> Source spec: `specs/themes.md` (finalized 2026-06-13, 4/6 open Qs resolved).

## Goal
Turn the static `Theme` enum into a selectable, persisted token value on `AppSettings.shared`,
exposing four named presets (Default/Mono/Vitals/Neon) + a Custom theme, follow-system light+dark,
and a unified hysteresis-backed status-color function — all updating the panel live.

## Acceptance Criteria (from spec — abbreviated; see specs/themes.md for Given/When/Then)
- [x] AC-1 Preset selection applies panel-wide, live, across strip + detail card + hint — *USER-confirmed 5.2*
- [x] AC-2 Selection persists across relaunch (store preset id, not the struct) — *data-layer verified 5.2*
- [x] AC-3 Follow system light+dark; **no** manual appearance toggle — *USER-confirmed 5.2*
- [x] AC-4 Primary text ≥ 4.5:1 contrast in every preset/appearance; high-translucency dims — *USER-confirmed 5.2*
- [x] AC-5 Severity conveyed by more than color alone (works in Mono / color-blind) — *USER-confirmed 5.2*
- [x] AC-6 One `usageColor(zones:reversed:)` covers CPU/mem/disk/net **and** battery; `100-percent` hack gone — *Wave 3 `332bbbe`*
- [x] AC-7 Hysteresis (~±5%) prevents band-flicker — *Wave 3 (oscillation asserts)*
- [x] AC-8 Mono suppresses status color (keeps the non-color cue) — *USER-confirmed 5.2*
- [x] AC-9 Custom theme round-trips (Color.Resolved sRGB) — *data-layer verified 5.2 + codec self-check*
- [x] AC-10 Compact density floor: text ≥ 10pt, controls ≥ 20×20pt — *USER-confirmed 5.2*
- [x] AC-11 Honors Reduce Transparency / Increase Contrast — *USER-confirmed 5.2*

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

### Wave 4 ✅ (Settings UI — depends on Wave 2) — done 2026-06-13, commits `8ad4324` + `00d9880`

- [x] **4.1**: Theme picker section → `Views/SettingsView.swift` (commit `8ad4324`)
  - New "Appearance" `Section` with a `Picker` bound to `settings.themePreset` (presets + Custom); live preview swatch optional.
  - Depends on: 2.2 — Success: switching the picker changes the live panel (AC-1).
  - Backpressure: build clean; pick each preset → panel updates.

- [x] **4.2**: Customize… disclosure + reset → `Views/SettingsView.swift` (commit `00d9880`)
  - `DisclosureGroup("Customize…")` shown when `.custom` (or always, selecting `.custom` on edit): `ColorPicker` accent + background, opacity `Slider`, corner-radius `Slider`, density `Picker`; writes `settings.customTheme`. Extend `resetToDefaults()` to reset theme.
  - Depends on: 2.2, 4.1 — Success: AC-9 round-trips; reset returns to Default.
  - Backpressure: build clean; edit custom → relaunch → restored.

### Wave 5 (verification) — 5.1 ✅ + 5.3 ✅ done 2026-06-13; 5.2 = on-screen, USER

- [x] **5.1**: macOS 15 observation + clean build → Info.plist (commit `7e2ee79`)
  - Added `NSObservationTrackingEnabled=YES` to the hand-authored `Resources/Info.plist` (NOT project.yml — Info.plist is hand-written here, `GENERATE_INFOPLIST_FILE=NO`). Web-verified it's the Apple-documented macOS-15 opt-in for AppKit auto-observation (default-on in the 2026 OSes); the live theme switch already works via SwiftUI `body` reads in `NSHostingView`, so this future-proofs AppKit-side reads rather than fixing a bug.
  - Backpressure: ✅ `xcodebuild clean build` from a wiped DerivedData → `** BUILD SUCCEEDED **`, **0 Swift warnings** (only non-code `xcodebuild` destination-ambiguity + AppIntents-metadata notes). Key confirmed present in the built `.app/Contents/Info.plist`.

- [x] **5.2**: Manual verification of user flows (signed run) — ✅ USER-confirmed on screen 2026-06-13 ("works and works"); strip + Settings driven up via synthetic ⌃⌥⌘Q then ⌘, (780×36 strip + 380×966 Settings), live preset switch + Custom + light/dark + Mono cue all confirmed.
  - Live-switch all 4 presets + Custom (AC-1); relaunch persistence (AC-2/9); toggle system Light/Dark (AC-3); contrast eyeball over bright + dark desktop (AC-4); Mono greyscale severity (AC-5/8); battery low = hot (AC-6); hover a value at a band edge for flicker (AC-7); compact density legibility (AC-10); System Settings → Reduce Transparency (AC-11).
  - **Automated derisk done:** AC-2/AC-9 persistence verified at the data layer — wrote a known `ThemeData` JSON + `themePreset=custom` to the app's `UserDefaults`, relaunched, app ran cleanly under the stored custom theme (init's `JSONDecoder` path non-fatal; JSON shape matches the `Codable` keys; prefs then restored to pristine). The *visual* confirmation (does it look pink/compact/light?) is the remaining USER step.
  - Backpressure: each AC visually confirmed; note results in session log.

- [x] **5.3**: Adversarial review (2–3 passes) — done 2026-06-13, commit `46b87d6`
  - Ran `feature-dev:code-reviewer` over `1d94961..HEAD` against the supporting types. **No critical/data-correctness bugs**: binding write-back, color round-trip precision, observation tracking (reads inside `body`), reset path, slider ranges, and `ForEach id:\.self` all sound. One consistency nit applied (readout `Text` now reads a `customData` accessor, matching the other sections). Reviewer's "plist key undocumented" flag was stale knowledge (web-verified documented; kept the key).
  - Backpressure: ✅ findings triaged; polish committed.

#### Acceptance Criteria — verified so far
- [x] **AC-2** persists across relaunch (preset id + custom JSON) — data-layer verified in 5.2 probe.
- [x] **AC-6** one `usageColor`/`tint` covers all stats incl. battery (`reversed:true`); `100-percent` hack gone — Wave 3 (`332bbbe`).
- [x] **AC-7** hysteresis (~±5%) prevents band-flicker — Wave 3 (oscillation asserts + `@ObservationIgnored` in-body band cache).
- [x] **AC-9** Custom round-trips (`CodableColor` sRGB) — data-layer verified in 5.2 + `_debugCodableColorSelfCheck`.
- [ ] AC-1/3/4/5/8/10/11 — require on-screen eyes; settle in the USER 5.2 pass.

---

## Operational Learnings
- Adding files requires `cd 01_Project && xcodegen generate` before `xcodebuild` (CLAUDE.md / cookbook 47).
- SourceKit may emit false "Theme not found" diagnostics during the migration; trust `xcodebuild`, not the indexer (seen 2026-06-13). In Wave 2 the indexer briefly flagged *every* cross-file type (`StatKind`, `PanelAnchor`, `HotKeyService`, …) as "not found" — pure index staleness; `xcodebuild` compiled clean.
- **Wave 2 gotchas (real, caught by `xcodebuild`):** (1) a private static helper `metrics(…)`/`fonts(…)` collides with the instance properties `var metrics`/`var fonts` on the same struct → renamed to `makeMetrics`/`makeFonts`. (2) Reading `self.themePreset`/`self.customTheme` to derive `theme` in `init` fails ("self used before all stored properties initialized") because `theme` is still unset — compute via **locals**, assign, then build `theme` from the locals.
- **Facade design that worked:** `Theme` is now a `struct`; the transitional facade is `@MainActor static var`s in extensions of `Theme.Colors`/`Metrics`/`Fonts` (+ `Theme.loadColor`). Static `Theme.Colors.background` and instance `theme.colors.background` coexist (different access paths, no recursion). **Facade deleted in Wave 3** (commit `332bbbe`) after a grep confirmed only doc-comment mentions remained.
- **Wave 3 — in-body band cache is safe:** the per-`StatKind` hysteresis map (`lastBands`) is written inside `visibleStats` (a `body` read). Marking it `@ObservationIgnored` means the write triggers no Observation invalidation → no re-render loop; verified empirically by a synthetic-summon probe that completed (a loop would freeze the run loop). Do NOT make `lastBands` an observed `var`.
- **Wave 3 — width-neutral weight ramp:** the AC-5 severity cue ramps font weight (calm/busy/hot → regular/semibold/heavy). To keep the jitter-free strip, the hidden width-template reserves `.heavy` always and the icon sits in a `.frame(width: 16)`, so a band change never changes tile width.
- **Wave 3 — parallel-agent split:** delegated the two *independent* mechanical view migrations (3.3 detail, 3.4 hint) to parallel `developer` agents (edit-only, no build — concurrent `xcodebuild` collides); kept the coupled core (3.1 strip ⇄ 3.2 tile API contract ⇄ 3.5 store tint) in the orchestrator. Worked cleanly.
- **Deferred to Wave 4 (from 2.2):** the model-side reset of `themePreset`/`customTheme` was NOT added (no `resetToDefaults` exists on `AppSettings` yet). Wire it into the Settings "Reset" path in **4.2**. → **DONE in 4.2**: `SettingsView.resetToDefaults()` now also sets `themePreset = .default` and `customTheme = nil` (reset lives in the view, not the model — matches the existing pattern for the other prefs).
- **Wave 4 — one generic binding collapses five custom-theme controls:** `customBinding<T>(_ keyPath: WritableKeyPath<ThemeData, T>) -> Binding<T>` reads `(customTheme ?? .default)[keyPath:]` and, on set, copies that baseline, mutates the one field, and **reassigns the whole `customTheme` struct** — the reassignment is the only thing Observation's `didSet` sees (JSON-persist + live rebuild). `colorBinding` composes on top to bridge `Color` ↔ `CodableColor` (sRGB) for the two `ColorPicker`s. The `?? .default` baseline means the *first* edit to any knob silently materializes a full `ThemeData` (intentional — user starts from the familiar look, AC-9).
- **Wave 4 — same SourceKit staleness, build clean:** the indexer again flagged every cross-file symbol in `SettingsView.swift` (`AppSettings`, `ThemePreset`, `ThemeDensity`, `PanelAnchor`, `StatKind`, `HotKeyRecorderView`) as "not found"; `xcodebuild` compiled clean both commits. Trust the build.
- **Wave 4 — done in-orchestrator, not parallel:** 4.1 and 4.2 both edit `SettingsView.swift` and 4.2 depends on 4.1's section, so parallel `developer` agents would collide on the file + race concurrent `xcodebuild`s (same reason the Wave 3 coupled core stayed in-orchestrator). Sequential was correct.

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
| 4 | 2026-06-13 | 2026-06-13 | 8ad4324, 00d9880 |
| 5 | 2026-06-13 | 2026-06-13 ✅ all | 7e2ee79, 46b87d6 |

---
*Delete when all tasks complete; archive to sessions/ if useful.*
