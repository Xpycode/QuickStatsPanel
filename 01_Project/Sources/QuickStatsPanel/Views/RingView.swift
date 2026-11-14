#if DEBUG
import SwiftUI

/// Draws the gauge ring from the summon snapshot's frozen layout: favourite wedges at their
/// chosen content rung, the More wedge at six o'clock and the small hub. Input and
/// accessibility live in `RingInputView`, which consumes the same layout; this view is
/// drawing only and hidden from accessibility so the two never duplicate elements.
struct RingView: View {
    let snapshot: RingSnapshot
    let state: RingPresentationState
    /// Live reading per stat. Called inside `body`, so Observation tracks the store.
    let reading: (StatKind) -> RingReading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let theme = AppSettings.shared.theme
        let layout = snapshot.layout
        let context = RingDrawingContext(theme: theme, fillScale: snapshot.fillScale, reduceMotion: reduceMotion,
                                         explicitEdge: differentiateWithoutColor || contrast == .increased)
        ZStack(alignment: .topLeading) {
            ForEach(layout.favourites, id: \.order) { favourite in
                RingGaugeWedgeView(kind: favourite.kind, sector: favourite.sector, rung: favourite.rung,
                                   textFrame: favourite.textFrame, live: reading(favourite.kind),
                                   context: context,
                                   hovered: state.hovered == .wedge(favourite.kind),
                                   selected: state.selectedKind == favourite.kind)
            }
            if let more = layout.more {
                moreWedge(more, theme: theme)
            }
            hub(layout: layout, theme: theme)
            if let message = snapshot.emptyMessage {
                // Empty states live in the annulus, not the hub: twelve o'clock is free with no
                // favourites and with no stats at all.
                Text(message)
                    .font(.system(size: RingTypography.secondarySize))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: layout.center.x,
                              y: layout.center.y - (layout.preset.innerRadius + layout.preset.outerRadius) / 2)
            }
        }
        .frame(width: snapshot.size.width, height: snapshot.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    // MARK: More wedge

    /// A narrow wedge with an icon and the count of remaining stats; no gauge fill.
    private func moreWedge(_ more: RingLayout.MoreWedge, theme: Theme) -> some View {
        let sector = more.sector
        let active = state.hovered == .more || state.moreExpanded
        let shape = RingBandShape(center: sector.center, centerAngle: sector.centerAngle, halfSpan: sector.halfSpan,
                                  inner: sector.innerRadius, outer: sector.outerRadius)
        return ZStack(alignment: .topLeading) {
            shape.fill(theme.colors.background)
            shape.fill(theme.colors.primaryText.opacity(active ? 0.2 : RingPalette.trackTint))
            VStack(spacing: RingTypography.lineSpacing) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: RingTypography.iconSide, height: RingTypography.iconSide)
                Text("\(more.count)")
                    .font(.system(size: RingTypography.labelSize, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(theme.colors.primaryText)
            .lineLimit(1)
            .fixedSize()
            .frame(width: more.contentFrame.width, height: more.contentFrame.height)
            .position(x: more.contentFrame.midX, y: more.contentFrame.midY)
            shape.stroke(state.moreExpanded ? theme.colors.primaryText : theme.colors.divider,
                         lineWidth: state.moreExpanded ? 2 : 1)
        }
    }

    // MARK: Hub

    /// The hub offers only the gear and the drag area. The pin glyph shows Keep on Screen.
    private func hub(layout: RingLayout, theme: Theme) -> some View {
        let hub = layout.hub
        let gear = hub.gearFrame
        let hovered = state.hovered == .settings
        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(theme.colors.background)
                .overlay(Circle().stroke(theme.colors.divider, lineWidth: 1))
                .frame(width: hub.discRadius * 2, height: hub.discRadius * 2)
                .position(x: hub.center.x, y: hub.center.y)

            if AppSettings.shared.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .position(x: hub.center.x, y: hub.center.y - gear.height / 2 - 9)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.colors.primaryText.opacity(hovered ? 0.20 : 0.08))
                HStack(spacing: RingLayout.gearWordGap) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: RingSizePreset.minGearTarget - 8, height: RingSizePreset.minGearTarget - 8)
                    if hub.showsSettingsWord {
                        Text("Settings")
                            .font(.system(size: RingTypography.secondarySize, weight: .medium))
                    }
                }
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .fixedSize()
            }
            .frame(width: gear.width, height: gear.height)
            .position(x: gear.midX, y: gear.midY)
        }
    }
}
#endif
