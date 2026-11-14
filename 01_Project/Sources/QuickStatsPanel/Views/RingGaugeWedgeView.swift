#if DEBUG
import SwiftUI

// Drawing of one gauge wedge (D-035). Every radius and angle comes from the frozen
// `RingSector` and `RingFillScale`; the content rung and text frame come from `RingLayout`.
// This file never measures text or chooses a rung (D-037).

extension Color {
    init(_ rgb: RingRGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

/// An annular band in ring space whose two radii animate, so a fill eases between samples
/// (and steps when the animation is removed under Reduce Motion).
struct RingBandShape: Shape {
    let center: CGPoint
    let centerAngle: Double
    let halfSpan: Double
    var inner: CGFloat
    var outer: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(inner, outer) }
        set { inner = newValue.first; outer = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        Path(RingSector(center: center, innerRadius: inner, outerRadius: outer,
                        centerAngle: centerAngle, halfSpan: halfSpan).cgPath)
    }
}

/// A single arc line at `radius` across a sector's angular extent.
struct RingArcLineShape: Shape {
    let sector: RingSector
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = max(2, Int((sector.span / RingSector.outlineStep).rounded(.up)))
        for i in 0...steps {
            let angle = sector.startAngle + sector.span * Double(i) / Double(steps)
            let point = RingSector.point(center: sector.center, angle: angle, radius: radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Environment-dependent presentation switches, read once by the ring and passed down.
struct RingDrawingContext {
    let theme: Theme
    let fillScale: RingFillScale
    let reduceMotion: Bool
    /// Increase Contrast or Differentiate Without Colour: the fill edge is drawn as a line.
    let explicitEdge: Bool

    var isMono: Bool { theme.statusStyle == .suppressed }
    var ease: Animation? { reduceMotion ? nil : .easeOut(duration: 0.2) }

    func fillColor(_ rgb: RingRGB) -> Color {
        Color(isMono ? RingPalette.mono : rgb).opacity(RingPalette.fillStrength)
    }
}

/// One wedge: track, fill, reference arcs, peak, rim, marks, content at the frozen rung, and
/// a separate selection outline. Drawing only; input and accessibility live in the input view.
struct RingGaugeWedgeView: View {
    let kind: StatKind
    let sector: RingSector
    let rung: RingContentRung
    let textFrame: CGRect
    let live: RingReading
    let context: RingDrawingContext
    let hovered: Bool
    let selected: Bool

    private static let rimThickness: CGFloat = 3

    var body: some View {
        let theme = context.theme
        let gauge = live.gauge
        let available = live.isAvailable && (gauge?.isAvailable ?? true)
        ZStack(alignment: .topLeading) {
            shape(sector).fill(theme.colors.background)
            shape(sector).fill(theme.colors.primaryText.opacity(RingPalette.trackTint))
            if let gauge, gauge.isAvailable {
                gaugeLayers(gauge)
            }
            shape(sector).fill(theme.colors.primaryText.opacity(hovered ? 0.14 : 0))
            content(available: available)
            if let gauge, gauge.isAvailable, !gauge.marks.isEmpty {
                batteryMark(gauge)
            }
            outline(available: available)
        }
        .opacity(available ? 1 : 0.7)
    }

    private func shape(_ sector: RingSector) -> some Shape {
        RingBandShape(center: sector.center, centerAngle: sector.centerAngle, halfSpan: sector.halfSpan,
                      inner: sector.innerRadius, outer: sector.outerRadius)
    }

    // MARK: Gauge layers

    @ViewBuilder
    private func gaugeLayers(_ gauge: RingGauge) -> some View {
        let theme = context.theme
        let scale = context.fillScale
        let inner = sector.innerRadius, outer = sector.outerRadius

        // Thermal state tints the wedge from Fair upward.
        if case .thermalState(let state)? = gauge.badge, state.tintsWedge {
            shape(sector).fill(theme.color(for: state >= .serious ? .hot : .busy).opacity(0.18))
        }

        ZStack(alignment: .topLeading) {
            if let halves = gauge.halves {
                halfFill(sector.half(.left), fraction: halves.left, color: RingPalette.hue(for: kind))
                halfFill(sector.half(.right), fraction: halves.right, color: RingPalette.networkUpload)
            } else {
                stackFill(gauge, scale: scale, inner: inner, outer: outer)
            }
        }
        .animation(context.ease, value: gauge)

        referenceArcs(gauge, scale: scale)
        if let rim = gauge.rim {
            shape(sector.rim(thickness: Self.rimThickness))
                .fill(Color(context.isMono ? RingPalette.mono : RingPalette.diskRim).opacity(0.2 + 0.8 * rim))
        }
        peakTicks(gauge, scale: scale)
        if context.explicitEdge {
            edgeLines(gauge, scale: scale)
        }
    }

    private func slice(_ s: RingSector, from lo: CGFloat, to hi: CGFloat, color: RingRGB) -> some View {
        RingBandShape(center: s.center, centerAngle: s.centerAngle, halfSpan: s.halfSpan, inner: lo, outer: hi)
            .fill(context.fillColor(color))
    }

    @ViewBuilder
    private func stackFill(_ gauge: RingGauge, scale: RingFillScale, inner: CGFloat, outer: CGFloat) -> some View {
        if gauge.usesHeatRamp {
            // Heat colour is fixed to radius: each step is coloured by the fraction it reaches.
            let total = gauge.totalFraction
            let steps = 10
            ForEach(0..<steps, id: \.self) { step in
                let f0 = total * Double(step) / Double(steps), f1 = total * Double(step + 1) / Double(steps)
                slice(sector,
                      from: scale.radius(fraction: f0, inner: inner, outer: outer),
                      to: scale.radius(fraction: f1, inner: inner, outer: outer),
                      color: RingPalette.heat(fraction: (f0 + f1) / 2))
            }
        } else {
            let radii = scale.cumulativeRadii(fractions: gauge.components.map(\.fraction), inner: inner, outer: outer)
            ForEach(Array(gauge.components.enumerated()), id: \.offset) { index, component in
                slice(sector, from: index == 0 ? inner : radii[index - 1], to: radii[index],
                      color: RingPalette.color(for: component.component, stat: kind))
            }
        }
    }

    private func halfFill(_ half: RingSector, fraction: Double, color: RingRGB) -> some View {
        let r = context.fillScale.radius(fraction: fraction, inner: half.innerRadius, outer: half.outerRadius)
        return slice(half, from: half.innerRadius, to: r, color: color)
    }

    private func referenceArcs(_ gauge: RingGauge, scale: RingFillScale) -> some View {
        let primary = context.theme.colors.primaryText
        let radii: [CGFloat]
        var opacity = 0.22
        if gauge.halves != nil {
            // The Network scale is logarithmic: its marks (100 KB/s, 10 MB/s) replace the quarter arcs.
            radii = gauge.marks.compactMap { mark in
                if case .rate(let fraction, _) = mark {
                    return scale.radius(fraction: fraction, inner: sector.innerRadius, outer: sector.outerRadius)
                }
                return nil
            }
            opacity = 0.35
        } else {
            radii = scale.referenceRadii(inner: sector.innerRadius, outer: sector.outerRadius)
        }
        return ZStack {
            ForEach(Array(radii.enumerated()), id: \.offset) { _, radius in
                RingArcLineShape(sector: sector, radius: radius)
                    .stroke(primary.opacity(opacity), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
    }

    private func peakTicks(_ gauge: RingGauge, scale: RingFillScale) -> some View {
        let primary = context.theme.colors.primaryText.opacity(0.85)
        func tick(_ s: RingSector, _ fraction: Double?) -> some View {
            Group {
                if let fraction {
                    RingArcLineShape(sector: s, radius: scale.radius(fraction: fraction, inner: s.innerRadius, outer: s.outerRadius))
                        .stroke(primary, lineWidth: 2)
                }
            }
        }
        return ZStack {
            if let halves = gauge.halves {
                tick(sector.half(.left), halves.leftPeak)
                tick(sector.half(.right), halves.rightPeak)
            } else {
                tick(sector, gauge.peak)
            }
        }
    }

    /// Increase Contrast / Differentiate Without Colour: the level reads from a line, not a hue.
    private func edgeLines(_ gauge: RingGauge, scale: RingFillScale) -> some View {
        let primary = context.theme.colors.primaryText
        func edge(_ s: RingSector, _ fraction: Double) -> some View {
            RingArcLineShape(sector: s, radius: scale.radius(fraction: fraction, inner: s.innerRadius, outer: s.outerRadius))
                .stroke(primary, lineWidth: 2)
        }
        return ZStack {
            if let halves = gauge.halves {
                edge(sector.half(.left), halves.left)
                edge(sector.half(.right), halves.right)
            } else if gauge.hasFill {
                edge(sector, gauge.totalFraction)
            }
        }
    }

    // MARK: Marks

    private func batteryMark(_ gauge: RingGauge) -> some View {
        let theme = context.theme
        let point = RingSector.point(center: sector.center, angle: sector.centerAngle, radius: sector.outerRadius - 10)
        let mark = gauge.marks.first
        let symbol: String
        var color = theme.colors.primaryText
        switch mark {
        case .chargingBolt?: symbol = "bolt.fill"
        case .pluggedNotCharging?:
            symbol = "powerplug"
            if !context.isMono { color = theme.colors.busy }
        case .pluggedFull?: symbol = "powerplug.fill"
        default: return AnyView(EmptyView())
        }
        return AnyView(
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .position(x: point.x, y: point.y))
    }

    // MARK: Content

    private func content(available: Bool) -> some View {
        let theme = context.theme
        let primary = available ? theme.colors.primaryText : theme.colors.secondaryText
        return Group {
            switch rung {
            case .icon:
                icon(color: primary)
            case .iconValue:
                VStack(spacing: RingTypography.lineSpacing) {
                    icon(color: primary)
                    valueText(available: available)
                }
            case .labelValue:
                VStack(spacing: RingTypography.lineSpacing) {
                    labelText
                    valueText(available: available)
                }
            case .labelValueSecondary:
                VStack(spacing: RingTypography.lineSpacing) {
                    labelText
                    valueText(available: available)
                    if let secondary = live.secondary {
                        Text(secondary)
                            .font(.system(size: RingTypography.secondarySize, weight: .regular).monospacedDigit())
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .frame(width: textFrame.width, height: textFrame.height)
        .position(x: textFrame.midX, y: textFrame.midY)
    }

    private var labelText: some View {
        Text(kind.displayName)
            .font(.system(size: RingTypography.labelSize, weight: .medium))
            .foregroundStyle(context.theme.colors.secondaryText)
    }

    private func valueText(available: Bool) -> some View {
        Text(live.value)
            .font(.system(size: RingTypography.valueSize, weight: context.theme.weight(for: live.band)).monospacedDigit())
            .foregroundStyle(available ? context.theme.colors.primaryText : context.theme.colors.secondaryText)
    }

    private func icon(color: Color) -> some View {
        Image(systemName: kind.settingsSymbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(color)
            .frame(width: RingTypography.iconSide, height: RingTypography.iconSide)
    }

    // MARK: Outline

    /// A separate outline: heavier when this wedge owns the open branch. An unavailable wedge is
    /// dashed, so the state does not rest on dimming or hue alone.
    private func outline(available: Bool) -> some View {
        let theme = context.theme
        return shape(sector)
            .stroke(selected ? theme.colors.primaryText : theme.colors.divider,
                    style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: available ? [] : [4, 3]))
    }
}
#endif
