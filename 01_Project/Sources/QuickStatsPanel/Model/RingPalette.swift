import Foundation

// Pure colour values for the gauge ring (D-035). No SwiftUI types: the view layer converts
// `RingRGB` when it draws. Hues follow output/ring-gauges/ring-gauges.html, with the darkest
// steps lifted so every fill edge reaches 3:1 against the track on dark panels.

/// sRGB components, 0...1.
struct RingRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = RingGaugeMath.clamp01(red)
        self.green = RingGaugeMath.clamp01(green)
        self.blue = RingGaugeMath.clamp01(blue)
    }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// WCAG relative luminance.
    var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// This colour at `alpha` composited over an opaque `background`.
    func over(_ background: RingRGB, alpha: Double) -> RingRGB {
        let a = RingGaugeMath.clamp01(alpha)
        return RingRGB(red: red * a + background.red * (1 - a),
                       green: green * a + background.green * (1 - a),
                       blue: blue * a + background.blue * (1 - a))
    }

    /// Linear mix in sRGB; `t` 0 is `self`, 1 is `other`.
    func mixed(with other: RingRGB, _ t: Double) -> RingRGB {
        over(other, alpha: 1 - RingGaugeMath.clamp01(t))
    }
}

enum RingPalette {

    /// Fixed mockup defaults: fill strength 80 %, track tint 10 %.
    static let fillStrength = 0.8
    static let trackTint = 0.1
    /// Minimum contrast between a fill edge and the track beside it.
    static let edgeContrastMinimum = 3.0

    /// Single neutral fill for the Mono theme.
    static let mono = RingRGB(hex: 0xE8EBEF)

    // MARK: Hues

    /// The stat's base hue (its first or only fill colour).
    static func hue(for stat: StatKind) -> RingRGB {
        switch stat {
        case .cpu:         return RingRGB(hex: 0x3F8FE0)
        case .memory:      return RingRGB(hex: 0x8F6FF0)
        case .disk:        return RingRGB(hex: 0x35B2A2)
        case .network:     return RingRGB(hex: 0x4FC3D9)
        case .battery:     return RingRGB(hex: 0x5CC26B)
        case .gpu:         return RingRGB(hex: 0xD46FD0)
        case .power:       return RingRGB(hex: 0xF0A03C)
        case .temps:       return heat(fraction: 0.72)
        case .fan:         return RingRGB(hex: 0x8AD06A)
        case .loadAverage: return RingRGB(hex: 0xE0875A)
        case .uptime:      return mono
        }
    }

    /// Fill colour for one stacked component; lighter steps for the stacked parts of a stat.
    static func color(for component: RingComponent, stat: StatKind) -> RingRGB {
        switch (stat, component) {
        case (.cpu, .system):          return RingRGB(hex: 0x8FC2F5)
        case (.cpu, .nice):            return RingRGB(hex: 0xC6D9EE)
        case (.memory, .wired):        return RingRGB(hex: 0xBBA6F7)
        case (.memory, .compressed):   return RingRGB(hex: 0x9078E0)
        case (.memory, .otherUsed):    return RingRGB(hex: 0xDDD3FB)
        case (.power, .gpu):           return RingRGB(hex: 0xD46FD0)
        case (.power, .neuralEngine):  return RingRGB(hex: 0x4FC3D9)
        case (.power, .dram):          return RingRGB(hex: 0x9AA3AD)
        case (.power, .restOfSystem):  return RingRGB(hex: 0x8A919A)
        default:                       return hue(for: stat)
        }
    }

    /// Upload hue on the Network wedge's right half (download uses `hue(for: .network)`).
    static let networkUpload = RingRGB(hex: 0xF0B24F)
    /// Disk I/O rim at full brightness.
    static let diskRim = RingRGB(hex: 0xA3E3D9)

    // MARK: Heat ramp

    /// Magma-like stops; relative luminance rises with heat so the ramp survives colour blindness.
    static let heatStops: [(at: Double, color: RingRGB)] = [
        (0.00, RingRGB(hex: 0xAC6AE0)),
        (0.40, RingRGB(hex: 0xE0609F)),
        (0.72, RingRGB(hex: 0xF0743A)),
        (1.00, RingRGB(hex: 0xFBE27A))
    ]

    /// Heat colour at a radius fraction, 0...1.
    static func heat(fraction: Double) -> RingRGB {
        let f = RingGaugeMath.clamp01(fraction)
        for i in 1..<heatStops.count where f <= heatStops[i].at {
            let a = heatStops[i - 1], b = heatStops[i]
            return a.color.mixed(with: b.color, (f - a.at) / (b.at - a.at))
        }
        return heatStops[heatStops.count - 1].color
    }

    // MARK: Contrast

    /// WCAG contrast ratio, 1...21.
    static func contrastRatio(_ a: RingRGB, _ b: RingRGB) -> Double {
        let la = a.relativeLuminance, lb = b.relativeLuminance
        return (Swift.max(la, lb) + 0.05) / (Swift.min(la, lb) + 0.05)
    }

    /// The empty track: the panel foreground at `trackTint` over the panel background.
    static func track(foreground: RingRGB, background: RingRGB) -> RingRGB {
        foreground.over(background, alpha: trackTint)
    }

    /// A fill colour as drawn: at `fillStrength` over the panel background.
    static func drawnFill(_ color: RingRGB, background: RingRGB) -> RingRGB {
        color.over(background, alpha: fillStrength)
    }

    /// Contrast of a drawn fill edge against the track beside it.
    static func edgeContrast(fill: RingRGB, foreground: RingRGB, background: RingRGB) -> Double {
        contrastRatio(drawnFill(fill, background: background),
                      track(foreground: foreground, background: background))
    }

    /// Every colour the palette can draw as a fill edge: stat hues, stacked components and
    /// the heat ramp sampled across its radius.
    static var allFillColors: [(name: String, color: RingRGB)] {
        var out: [(String, RingRGB)] = []
        let stacks: [(StatKind, [RingComponent])] = [
            (.cpu, [.user, .system, .nice]),
            (.memory, [.app, .wired, .compressed, .otherUsed]),
            (.power, [.cpu, .gpu, .neuralEngine, .dram, .restOfSystem])
        ]
        for stat in StatKind.allCases where stat != .temps && stat != .uptime {
            out.append(("\(stat.rawValue)", hue(for: stat)))
        }
        for (stat, comps) in stacks {
            for c in comps { out.append(("\(stat.rawValue).\(c.rawValue)", color(for: c, stat: stat))) }
        }
        out.append(("network.upload", networkUpload))
        for i in 0...10 { out.append(("heat.\(i)", heat(fraction: Double(i) / 10))) }
        return out
    }
}
