import Foundation

// MARK: - ThemePreset

/// The stable, persisted identifier for which theme the user has selected.
/// Only this tiny string is stored — never the full rendered token set. Built-in
/// preset tokens live in code (a later task), so future updates can fix them
/// without migrating stored data.
enum ThemePreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case `default`
    case mono
    case vitals
    case neon
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .mono:    return "Mono"
        case .vitals:  return "Vitals"
        case .neon:    return "Neon"
        case .custom:  return "Custom"
        }
    }
}

// MARK: - ThemeDensity

/// Controls font size, spacing, and corner radius tightness across the strip.
/// Density deliberately does NOT touch panel height — that is the separate
/// `stripHeight` slider (D-006), so the two axes stay orthogonal: the user can
/// have a tall comfortable layout or a compact one inside any height.
enum ThemeDensity: String, CaseIterable, Codable, Sendable {
    case compact
    case comfortable

    var displayName: String {
        switch self {
        case .compact:     return "Compact"
        case .comfortable: return "Comfortable"
        }
    }
}

// MARK: - ThemeData

/// The user's hand-tuned theme, persisted as-is to UserDefaults as JSON.
///
/// Colors are stored via `CodableColor` (sRGB round-trip) rather than SwiftUI
/// `Color` directly, which is not `Codable`. `opacity` is the panel background
/// translucency knob — it is *separate* from `background.opacity` by design: the
/// Settings "opacity" slider drives this float, while `background` encodes the
/// hue/chroma the user picked; mixing them into a single RGBA value would make
/// the slider fight the color picker.
///
/// `cornerRadius` is the flat non-Tahoe radius already in `Theme.Metrics`. It
/// lives here so the custom theme can deviate from the default without touching
/// built-in preset values.
struct ThemeData: Codable, Sendable, Equatable {

    /// Accent color: tile value text, highlight bars, load-color overrides.
    var accent: CodableColor

    /// Background hue of the panel material (pre-opacity; translucency is
    /// applied separately via `opacity` so hue and transparency stay decoupled).
    var background: CodableColor

    /// Panel background translucency, 0 (fully transparent) … 1 (fully opaque).
    /// Drives `NSVisualEffectView` blending or a plain fill depending on the
    /// renderer — the meaning is "how much of the desktop bleeds through".
    var opacity: Double

    /// Corner radius in points. Intentionally small — this is a HUD strip, not a
    /// Tahoe sheet. The default matches `Theme.Metrics.cornerRadius`.
    var cornerRadius: Double

    /// Layout density axis (font size + spacing only; panel height is independent).
    var density: ThemeDensity

    /// Baseline the "Customize…" sheet opens on. Values mirror the current hard-
    /// coded `Theme` tokens so the user's first edit starts from the familiar look,
    /// not an arbitrary placeholder.
    static let `default` = ThemeData(
        accent:       CodableColor(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0),
        background:   CodableColor(red: 0.0, green: 0.0, blue: 0.0, opacity: 1.0),
        opacity:      0.82,   // matches Theme.Colors.background (.black.opacity(0.82))
        cornerRadius: 12,     // matches Theme.Metrics.cornerRadius
        density:      .comfortable
    )
}
