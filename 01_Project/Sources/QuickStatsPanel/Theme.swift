import SwiftUI
import AppKit

/// Visual tokens for the panel content, as a **selectable value** rather than a
/// static namespace. (The App Shell Standard `Theme` is for windowed apps; this
/// is the panel-scoped equivalent — see CLAUDE.md.)
///
/// The old `enum Theme` (compile-time constants) is now this `struct`: the live
/// value lives on `AppSettings.shared.theme` and is swapped when the user picks a
/// preset. Views read `AppSettings.shared.theme.…` inside their `body`, so SwiftUI
/// Observation re-renders each of the three `NSHostingView` panels live on a
/// switch. (Wave 2 added the struct behind a transitional facade; Wave 3 migrated
/// the views and removed the facade.)
///
/// Built-in preset colors are *code constants*; only the **Custom** theme
/// serializes (via `ThemeData` → `CodableColor`). Don't persist this struct —
/// persist `themePreset` + `ThemeData?` and rebuild with `make(_:custom:reduceTransparency:)`.
struct Theme: Sendable {

    var colors: Colors
    var metrics: Metrics
    var fonts: Fonts

    /// How this preset treats the at-a-glance status color. Lets Mono drop hue
    /// entirely (relying on the redundant non-color cue, AC-5/8) while Vitals can
    /// lean into it — without each tile knowing which preset is active.
    var statusStyle: StatusStyle

    enum StatusStyle: Sendable {
        case standard      // green / yellow / red bands (Default, Neon)
        case suppressed    // single neutral tint, status hue OFF (Mono)
        case emphasized    // bands, intended to read louder (Vitals)
    }

    // MARK: Nested token groups

    /// Colors are appearance-adaptive: each is built from a dynamic `NSColor`
    /// that resolves light vs. dark at draw time, so a single `Color` follows the
    /// system. (Inert in Wave 2 — the views still force `.preferredColorScheme(.dark)`;
    /// the light variants come alive when Wave 3 removes that.)
    struct Colors: Sendable {
        var background: Color
        var primaryText: Color
        var secondaryText: Color
        var divider: Color
        var calm: Color
        var busy: Color
        var hot: Color
    }

    /// Layout density knobs (font/spacing/radius). Panel **height is NOT here** —
    /// it stays the `AppSettings.stripHeight` slider's sole job (locked decision),
    /// so theme density and panel height are orthogonal axes.
    struct Metrics: Sendable {
        var cornerRadius: CGFloat
        var tileSpacing: CGFloat
        var horizontalPadding: CGFloat
    }

    struct Fonts: Sendable {
        var value: Font
        var label: Font
        var detailTitle: Font
        var detailValue: Font
    }

    // MARK: Status color

    /// Maps a resolved `Band` to this theme's color, honoring `statusStyle`.
    /// `.suppressed` (Mono) collapses every band to the neutral primary tint —
    /// severity is then carried only by the non-color cue (AC-5).
    func color(for band: Band) -> Color {
        guard statusStyle != .suppressed else { return colors.primaryText }
        switch band {
        case .calm: return colors.calm
        case .busy: return colors.busy
        case .hot:  return colors.hot
        }
    }

    /// One call that (a) resolves the band with hysteresis against `previous` and
    /// (b) maps it to a color — returning both so the caller can persist the new
    /// band for next tick. The store (Wave 3.5) owns the per-`StatKind` `previous`
    /// map; battery passes `reversed: true` here, retiring the `100 - percent` hack.
    func tint(forPercent percent: Double,
              reversed: Bool = false,
              previous: Band?) -> (band: Band, color: Color) {
        let band = resolveBand(percent: percent, reversed: reversed, previous: previous)
        return (band, color(for: band))
    }

    /// Font weight for a severity band — the **non-color** severity cue (AC-5).
    /// Heavier = hotter, so "hot" stays legible in Mono and in greyscale /
    /// color-blind viewing where the status hue is suppressed or indistinct.
    /// Width-neutral: only the weight changes, so the jitter-free strip keeps its
    /// reserved field widths.
    func weight(for band: Band) -> Font.Weight {
        switch band {
        case .calm: return .regular
        case .busy: return .semibold
        case .hot:  return .heavy
        }
    }

    // MARK: Preset construction

    /// Build the token value for a preset (or the user's custom payload). The only
    /// place preset values are defined.
    ///
    /// - `reduceTransparency`: when the system flag is set, presets push the
    ///   background toward opaque (flat-fill fallback, no `NSVisualEffectView`).
    static func make(_ preset: ThemePreset,
                     custom: ThemeData?,
                     reduceTransparency: Bool) -> Theme {
        switch preset {
        case .default: return makeDefault(reduceTransparency: reduceTransparency)
        case .mono:    return makeMono(reduceTransparency: reduceTransparency)
        case .vitals:  return makeVitals(reduceTransparency: reduceTransparency)
        case .neon:    return makeNeon(reduceTransparency: reduceTransparency)
        case .custom:  return makeCustom(custom ?? .default, reduceTransparency: reduceTransparency)
        }
    }

    // MARK: - Preset builders (private)

    /// Background opacity, bumped toward opaque under Reduce Transparency (AC-11).
    private static func bgOpacity(_ base: Double, reduceTransparency: Bool) -> Double {
        reduceTransparency ? Swift.max(base, 0.98) : base
    }

    /// **Default** — today's exact dark look, verbatim, now follow-system capable.
    /// Dark pixels MUST match the pre-Themes app (`black.opacity(0.82)`, white text,
    /// green/yellow/red, 12pt radius). The light variant is a placeholder until the
    /// Wave 3 light-mode pass (it is never shown while the panel forces dark).
    private static func makeDefault(reduceTransparency: Bool) -> Theme {
        let a = bgOpacity(0.82, reduceTransparency: reduceTransparency)
        return Theme(
            colors: Colors(
                background:    .dynamic(light: .white.opacity(a), dark: .black.opacity(a)),
                primaryText:   .dynamic(light: .black, dark: .white),
                secondaryText: .dynamic(light: .black.opacity(0.55), dark: .white.opacity(0.55)),
                divider:       .dynamic(light: .black.opacity(0.12), dark: .white.opacity(0.12)),
                calm: .green, busy: .yellow, hot: .red
            ),
            metrics: makeMetrics(density: .comfortable, cornerRadius: 12),
            fonts:   makeFonts(density: .comfortable),
            statusStyle: .standard
        )
    }

    /// **Mono** — neutral, status hue suppressed; severity rides the non-color cue.
    private static func makeMono(reduceTransparency: Bool) -> Theme {
        let a = bgOpacity(0.85, reduceTransparency: reduceTransparency)
        let neutral = Color.dynamic(light: .black, dark: .white)
        return Theme(
            colors: Colors(
                background:    .dynamic(light: .white.opacity(a), dark: .black.opacity(a)),
                primaryText:   neutral,
                secondaryText: .dynamic(light: .black.opacity(0.5), dark: .white.opacity(0.5)),
                divider:       .dynamic(light: .black.opacity(0.1), dark: .white.opacity(0.1)),
                // Suppressed at render time, but defined so `color(for:)` is total.
                calm: neutral, busy: neutral, hot: neutral
            ),
            metrics: makeMetrics(density: .compact, cornerRadius: 8),
            fonts:   makeFonts(density: .compact),
            statusStyle: .suppressed
        )
    }

    /// **Vitals** — status color forward, slightly warmer surface.
    private static func makeVitals(reduceTransparency: Bool) -> Theme {
        let a = bgOpacity(0.82, reduceTransparency: reduceTransparency)
        return Theme(
            colors: Colors(
                background:    .dynamic(light: .white.opacity(a), dark: .black.opacity(a)),
                primaryText:   .dynamic(light: .black, dark: .white),
                secondaryText: .dynamic(light: .black.opacity(0.6), dark: .white.opacity(0.6)),
                divider:       .dynamic(light: .black.opacity(0.14), dark: .white.opacity(0.14)),
                calm: Color(red: 0.30, green: 0.85, blue: 0.45),
                busy: Color(red: 1.00, green: 0.78, blue: 0.20),
                hot:  Color(red: 1.00, green: 0.30, blue: 0.30)
            ),
            metrics: makeMetrics(density: .comfortable, cornerRadius: 12),
            fonts:   makeFonts(density: .comfortable),
            statusStyle: .emphasized
        )
    }

    /// **Neon** — saturated accent on near-black, pinned (does not follow the
    /// system accent). Always dark-leaning even in Light mode.
    private static func makeNeon(reduceTransparency: Bool) -> Theme {
        let a = bgOpacity(0.9, reduceTransparency: reduceTransparency)
        let bg = Color(red: 0.03, green: 0.03, blue: 0.06).opacity(a)
        return Theme(
            colors: Colors(
                background:    bg,
                primaryText:   Color(red: 0.85, green: 1.0, blue: 0.95),
                secondaryText: Color(red: 0.55, green: 0.75, blue: 0.85),
                divider:       Color(red: 0.0, green: 1.0, blue: 0.85).opacity(0.18),
                calm: Color(red: 0.20, green: 1.00, blue: 0.80),
                busy: Color(red: 1.00, green: 0.85, blue: 0.20),
                hot:  Color(red: 1.00, green: 0.25, blue: 0.55)
            ),
            metrics: makeMetrics(density: .comfortable, cornerRadius: 12),
            fonts:   makeFonts(density: .comfortable),
            statusStyle: .standard
        )
    }

    /// **Custom** — built from the user's persisted `ThemeData`. The `opacity`
    /// slider drives the background translucency (decoupled from the picked hue);
    /// Reduce Transparency still overrides it toward opaque.
    private static func makeCustom(_ data: ThemeData, reduceTransparency: Bool) -> Theme {
        let a = bgOpacity(data.opacity, reduceTransparency: reduceTransparency)
        let bgHue = data.background.color          // hue/chroma the user picked
        let accent = data.accent.color
        return Theme(
            colors: Colors(
                background:    bgHue.opacity(a),
                primaryText:   accent,
                secondaryText: accent.opacity(0.6),
                divider:       accent.opacity(0.14),
                // Custom keeps the standard semantic bands; only the surface/accent
                // are user-driven for now (per-band custom colors are out of scope).
                calm: .green, busy: .yellow, hot: .red
            ),
            metrics: makeMetrics(density: data.density, cornerRadius: CGFloat(data.cornerRadius)),
            fonts:   makeFonts(density: data.density),
            statusStyle: .standard
        )
    }

    // MARK: - Density → metrics / fonts

    /// Density adjusts spacing + radius (NOT height). `comfortable` reproduces the
    /// pre-Themes spacing verbatim.
    private static func makeMetrics(density: ThemeDensity, cornerRadius: CGFloat) -> Metrics {
        switch density {
        case .comfortable:
            return Metrics(cornerRadius: cornerRadius, tileSpacing: 14, horizontalPadding: 14)
        case .compact:
            return Metrics(cornerRadius: cornerRadius, tileSpacing: 10, horizontalPadding: 10)
        }
    }

    /// Density adjusts font sizes. `comfortable` reproduces the pre-Themes fonts
    /// verbatim. `compact` keeps body text ≥ 10pt (AC-10 floor).
    private static func makeFonts(density: ThemeDensity) -> Fonts {
        switch density {
        case .comfortable:
            return Fonts(
                value:       .system(size: 13, weight: .semibold).monospacedDigit(),
                label:       .system(size: 9,  weight: .medium),
                detailTitle: .system(size: 12, weight: .semibold),
                detailValue: .system(size: 12, weight: .regular).monospacedDigit()
            )
        case .compact:
            return Fonts(
                value:       .system(size: 11, weight: .semibold).monospacedDigit(),
                label:       .system(size: 10, weight: .medium),
                detailTitle: .system(size: 11, weight: .semibold),
                detailValue: .system(size: 11, weight: .regular).monospacedDigit()
            )
        }
    }
}

// MARK: - Appearance-adaptive Color helper

private extension Color {
    /// A single `Color` that resolves to `light` in Light Mode and `dark` in Dark
    /// Mode, by wrapping a dynamic `NSColor`. Built on the main actor (in `make`),
    /// returns a `Sendable` `Color`.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}
