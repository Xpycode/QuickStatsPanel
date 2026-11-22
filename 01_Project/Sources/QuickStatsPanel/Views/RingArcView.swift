#if DEBUG
import SwiftUI

/// Draws one open outer-band arc inside its own panel: the More arc as full gauge wedges at
/// the rung chosen at summon, or a favourite's sub-ring as part segments on the parent's scale
/// with the hover caption in its reserved slot. Every sector comes from the snapshot's frozen
/// arc, moved into the panel's space; input and accessibility live in the panel's input view
/// and the base ring's wedge elements, so this view is hidden from accessibility.
struct RingArcView: View {
    let snapshot: RingSnapshot
    let owner: RingArcOwner
    let geometry: RingArcPanelGeometry
    let state: RingPresentationState
    /// Live reading per stat. Called inside `body`, so Observation tracks the store.
    let reading: (StatKind) -> RingReading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    /// A fixed, theme-independent hit fill: derived from the theme background it would scale
    /// with the Custom opacity and could quantise to fully transparent, passing clicks through.
    static let hitFill = Color.black.opacity(0.02)

    var body: some View {
        let context = RingDrawingContext(theme: AppSettings.shared.theme, fillScale: snapshot.fillScale,
                                         reduceMotion: reduceMotion,
                                         explicitEdge: differentiateWithoutColor || contrast == .increased)
        ZStack(alignment: .topLeading) {
            if let arc = snapshot.arcs[owner] {
                // The surface the resolver counts as arc, gap and separators included, carries a
                // barely visible fill: fully transparent pixels would pass clicks through the panel.
                let surface = geometry.local(arc.surface)
                let surfaceShape = RingBandShape(center: surface.center, centerAngle: surface.centerAngle,
                                                 halfSpan: surface.halfSpan,
                                                 inner: surface.innerRadius, outer: surface.outerRadius)
                surfaceShape.fill(Self.hitFill)
                // The caption slot is inside for the resolver whether or not a caption shows, so
                // it carries the same hit fill; otherwise a click there reaches the app below.
                if case .stat = owner, let slot = snapshot.captionSlots[owner] {
                    let local = geometry.local(slot)
                    Rectangle().fill(Self.hitFill)
                        .frame(width: local.width, height: local.height)
                        .position(x: local.midX, y: local.midY)
                }
                // Outlines are clipped to the hit surface: a stroke past it would draw where a
                // click resolves outside and hides the HUD.
                Group {
                    switch owner {
                    case .more:
                        moreEntries(arc, context: context)
                    case .stat(let kind):
                        segments(kind, arc: arc, context: context)
                    }
                }
                .clipShape(surfaceShape)
                if case .stat(let kind) = owner {
                    hoverCaption(kind)
                }
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    // MARK: More arc

    private func moreEntries(_ arc: RingArcLayout, context: RingDrawingContext) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(arc.segments, id: \.index) { segment in
                if snapshot.moreKinds.indices.contains(segment.index),
                   let rung = snapshot.moreArcRung, let textFrame = segment.textFrame {
                    let kind = snapshot.moreKinds[segment.index]
                    RingGaugeWedgeView(kind: kind, sector: geometry.local(segment.sector), rung: rung,
                                       textFrame: geometry.local(textFrame), live: reading(kind),
                                       context: context,
                                       hovered: state.hoveredMoreKind == kind,
                                       selected: state.selectedMoreKind == kind)
                }
            }
        }
    }

    // MARK: Sub-ring

    private func hoveredIndex(_ kind: StatKind) -> Int? {
        state.hoveredSegment.flatMap { $0.stat == kind ? $0.index : nil }
    }

    private func segments(_ kind: StatKind, arc: RingArcLayout, context: RingDrawingContext) -> some View {
        let parts = snapshot.parts[kind]?.parts ?? []
        let hovered = hoveredIndex(kind)
        return ZStack(alignment: .topLeading) {
            ForEach(arc.segments, id: \.index) { segment in
                if parts.indices.contains(segment.index) {
                    RingPartSegmentView(stat: kind, part: parts[segment.index],
                                        sector: geometry.local(segment.sector),
                                        textFrame: segment.textFrame.map(geometry.local),
                                        context: context, hovered: hovered == segment.index)
                }
            }
        }
    }

    @ViewBuilder
    private func hoverCaption(_ kind: StatKind) -> some View {
        let parts = snapshot.parts[kind]?.parts ?? []
        if let slot = snapshot.captionSlots[.stat(kind)], let index = hoveredIndex(kind), parts.indices.contains(index) {
            caption(RingCaption.text(for: parts[index], stat: kind), in: geometry.local(slot),
                    theme: AppSettings.shared.theme)
        }
    }

    /// The caption fills its reserved slot; its text is never wider than the slot measured at summon.
    private func caption(_ text: String, in frame: CGRect, theme: Theme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.colors.background)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(theme.colors.divider, lineWidth: 1)
            Text(text)
                .font(.system(size: RingTypography.secondarySize, weight: .regular).monospacedDigit())
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }
}

/// One part of a sub-ring: track, the part's gauge on the parent's scale and colour basis,
/// a one-line label where the summon measured that it fits, and a separate outline. A part
/// that went missing keeps its position and draws the empty track, dashed.
struct RingPartSegmentView: View {
    let stat: StatKind
    let part: RingPart
    let sector: RingSector
    let textFrame: CGRect?
    let context: RingDrawingContext
    let hovered: Bool

    static let efficiencyFillOpacity = 0.5

    private var isEfficiencyCore: Bool { stat == .cpu && part.group == "Efficiency" }

    var body: some View {
        let theme = context.theme
        let gauge = part.gauge(stat: stat)
        let shape = RingBandShape(center: sector.center, centerAngle: sector.centerAngle, halfSpan: sector.halfSpan,
                                  inner: sector.innerRadius, outer: sector.outerRadius,
                      startInset: sector.startInset, endInset: sector.endInset, edgeReferenceRadius: sector.edgeReferenceRadius)
        ZStack(alignment: .topLeading) {
            shape.fill(theme.colors.background)
            shape.fill(theme.colors.primaryText.opacity(RingPalette.trackTint))
            if gauge.isAvailable {
                // Efficiency cores draw a dimmer fill so the core classes read apart (E1).
                RingGaugeFill(kind: stat, sector: sector, gauge: gauge, context: context, showsReferenceArcs: false)
                    .opacity(isEfficiencyCore ? Self.efficiencyFillOpacity : 1)
            }
            shape.fill(theme.colors.primaryText.opacity(hovered ? 0.18 : 0))
            if let textFrame {
                Text("\(part.name) \(part.labelValue(stat: stat))")
                    .font(.system(size: RingTypography.secondarySize, weight: .regular).monospacedDigit())
                    .foregroundStyle(part.isAvailable ? theme.colors.primaryText : theme.colors.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: textFrame.width, height: textFrame.height)
                    .position(x: textFrame.midX, y: textFrame.midY)
            }
            shape.stroke(hovered ? theme.colors.primaryText : theme.colors.divider,
                         style: StrokeStyle(lineWidth: hovered ? 1.5 : 1, dash: part.isAvailable ? [] : [3, 2]))
        }
        .opacity(part.isAvailable ? 1 : 0.7)
    }
}
#endif
