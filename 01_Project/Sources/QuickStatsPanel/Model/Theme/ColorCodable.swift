import SwiftUI

/// The one place SwiftUI `Color` is (de)serialized for persisted themes. Stores
/// components in sRGB so values round-trip predictably (cgColor component arity
/// varies by color space — a known footgun, so we pin sRGB here).
struct CodableColor: Codable, Sendable, Equatable {
    var red: Double      // 0...1 sRGB
    var green: Double
    var blue: Double
    var opacity: Double  // 0...1

    // Synthesized Codable over the four Doubles is all we need — no custom
    // encode/decode, no conformance on Apple types (avoids symbol collisions if
    // Apple ever adds their own).

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red     = red
        self.green   = green
        self.blue    = blue
        self.opacity = opacity
    }

    /// Resolves `color` into sRGB components via `Color.resolve(in:)` (macOS 14+).
    /// `Color.Resolved` is already sRGB-normalized, so the cast Float → Double is
    /// lossless for practical purposes. We clamp defensively: synthetic or
    /// extended-range colors can have out-of-gamut components.
    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.red     = Double(resolved.red).clamped(to: 0...1)
        self.green   = Double(resolved.green).clamped(to: 0...1)
        self.blue    = Double(resolved.blue).clamped(to: 0...1)
        self.opacity = Double(resolved.opacity).clamped(to: 0...1)
    }

    /// Parses "#RRGGBB" (opaque) or "#RRGGBBAA" (with alpha). Leading `#` is
    /// optional; matching is case-insensitive. Returns nil on any parse failure so
    /// callers can surface a recoverable error rather than crashing on a bad pref.
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("#") { raw = String(raw.dropFirst()) }
        raw = raw.uppercased()

        guard raw.allSatisfy({ $0.isHexDigit }) else { return nil }

        let count = raw.count
        guard count == 6 || count == 8 else { return nil }

        // Parse as a single UInt32 so we avoid per-character substring overhead.
        guard let value = UInt32(raw, radix: 16) else { return nil }

        if count == 6 {
            // No alpha channel in the string → treat as fully opaque.
            self.red     = Double((value >> 16) & 0xFF) / 255
            self.green   = Double((value >>  8) & 0xFF) / 255
            self.blue    = Double((value      ) & 0xFF) / 255
            self.opacity = 1
        } else {
            // 8-digit form: RRGGBBAA
            self.red     = Double((value >> 24) & 0xFF) / 255
            self.green   = Double((value >> 16) & 0xFF) / 255
            self.blue    = Double((value >>  8) & 0xFF) / 255
            self.opacity = Double((value      ) & 0xFF) / 255
        }
    }

    /// Reconstructs in `.sRGB` so the round-trip stays in the space we stored.
    /// Using the explicit colorSpace init avoids SwiftUI's adaptive color
    /// machinery re-resolving the value against the current environment.
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// Eight-digit "#RRGGBBAA" uppercase. Rounding via Int conversion mirrors
    /// what init?(hex:) does on the way back in, so encode→decode is stable.
    var hex: String {
        let r = Int((red     * 255).rounded())
        let g = Int((green   * 255).rounded())
        let b = Int((blue    * 255).rounded())
        let a = Int((opacity * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

// MARK: - Comparable helpers (private)

private extension Double {
    /// Returns the value clamped to `range`. Defined here (not on Comparable) to
    /// avoid colliding with any project-wide `clamped` extensions.
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Debug self-check

#if DEBUG
/// Call from a unit test or a playground to verify the core round-trip guarantee.
/// NOT auto-run — it exists to document correctness assumptions inline.
///
/// The canonical test case is `Color.black.opacity(0.82)`:
///   • 0.82 × 255 ≈ 209.1, rounds to 209 = 0xD1
///   • hex output must be "#000000D1"
///   • parsing "#000000D1" must recover opacity within 1/255 ≈ 0.004
func _debugCodableColorSelfCheck() {
    // ── Round-trip via components ─────────────────────────────────────────────
    let black82 = CodableColor(red: 0, green: 0, blue: 0, opacity: 0.82)
    assert(black82.hex == "#000000D1",
           "Expected #000000D1, got \(black82.hex)")

    // ── Round-trip via hex parser ─────────────────────────────────────────────
    let parsed = CodableColor(hex: "#000000D1")
    assert(parsed != nil, "Hex parser returned nil for a valid 8-digit string")
    // 0xD1 = 209; 209/255 ≈ 0.81961 — within 1/255 of 0.82
    let delta = abs((parsed?.opacity ?? 0) - (209.0 / 255.0))
    assert(delta < 1e-9, "Opacity did not round-trip exactly: \(delta)")

    // ── Case-insensitive and no-hash variants ─────────────────────────────────
    let lower = CodableColor(hex: "000000d1")
    assert(lower != nil, "Lowercase hex without # failed to parse")
    assert(lower?.opacity == parsed?.opacity, "Case changed the parsed value")

    // ── 6-digit form → opaque ─────────────────────────────────────────────────
    let opaque = CodableColor(hex: "#FF8800")
    assert(opaque != nil)
    assert(opaque?.opacity == 1.0, "6-digit hex should produce opacity = 1")

    // ── Malformed inputs must return nil ─────────────────────────────────────
    assert(CodableColor(hex: "#GGGGGG") == nil, "Non-hex chars must return nil")
    assert(CodableColor(hex: "#12345")  == nil, "5-digit hex must return nil")
    assert(CodableColor(hex: "")        == nil, "Empty string must return nil")

    // ── init(_ color:) integration ────────────────────────────────────────────
    // Color.black.opacity(0.82) resolves to sRGB (0,0,0,0.82). The Float → Double
    // conversion will be very close but not necessarily 0.82 exactly, so we use
    // a loose tolerance here.
    let fromColor = CodableColor(Color.black.opacity(0.82))
    assert(fromColor.red < 1e-6 && fromColor.green < 1e-6 && fromColor.blue < 1e-6,
           "RGB channels for black should be ≈ 0")
    assert(abs(fromColor.opacity - 0.82) < 0.005,
           "Opacity from Color.resolve should be within Float precision of 0.82")
}
#endif
