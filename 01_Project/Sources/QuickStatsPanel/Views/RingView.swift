#if DEBUG
import SwiftUI

/// Draws the favourite ring from the summon snapshot's frozen geometry. Input and
/// accessibility live in `RingInputView`, which consumes the same geometry; this view
/// is drawing only and hidden from accessibility so the two never duplicate elements.
struct RingView: View {
    let snapshot: RingSnapshot
    let state: RingPresentationState
    /// Live reading per stat. Called inside `body`, so Observation tracks the store.
    let reading: (StatKind) -> RingReading

    var body: some View {
        let theme = AppSettings.shared.theme
        let geometry = snapshot.geometry
        ZStack(alignment: .topLeading) {
            ForEach(geometry.wedges, id: \.kind) { wedge in
                wedgeView(wedge, geometry: geometry, theme: theme)
            }
            hub(geometry: geometry, theme: theme)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func wedgeView(_ wedge: RingGeometry.Wedge, geometry: RingGeometry, theme: Theme) -> some View {
        let live = reading(wedge.kind)
        let outline = Path { path in
            let points = geometry.outline(of: wedge)
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
        let hovered = state.hovered == .wedge(wedge.kind)
        let selected = state.selectedKind == wedge.kind
        return ZStack(alignment: .topLeading) {
            outline.fill(theme.colors.background)
            outline.fill(theme.color(for: live.band).opacity(live.isAvailable ? 0.22 : 0))
            outline.fill(theme.colors.primaryText.opacity(hovered ? 0.14 : 0))
            outline.stroke(selected ? theme.colors.primaryText : theme.colors.divider,
                           lineWidth: selected ? 2 : 1)
            textBlock(wedge, live: live, theme: theme)
        }
        .opacity(live.isAvailable ? 1 : 0.7)
    }

    /// Horizontal label, headline and optional secondary at the baseline sizes; never
    /// rotated, scaled or truncated. The frame is the measured worst-case block.
    private func textBlock(_ wedge: RingGeometry.Wedge, live: RingReading, theme: Theme) -> some View {
        VStack(spacing: RingTypography.lineSpacing) {
            Text(wedge.kind.displayName)
                .font(.system(size: RingTypography.labelSize, weight: .medium))
                .foregroundStyle(theme.colors.secondaryText)
            Text(live.value)
                .font(.system(size: RingTypography.valueSize, weight: theme.weight(for: live.band)).monospacedDigit())
                .foregroundStyle(live.isAvailable ? theme.colors.primaryText : theme.colors.secondaryText)
            if let secondary = live.secondary {
                Text(secondary)
                    .font(.system(size: RingTypography.secondarySize, weight: .regular).monospacedDigit())
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .frame(width: wedge.textRect.width, height: wedge.textRect.height)
        .position(x: wedge.textRect.midX, y: wedge.textRect.midY)
    }

    private func hub(geometry: RingGeometry, theme: Theme) -> some View {
        let center = geometry.center
        let radius = RingGeometry.hubRadius
        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(theme.colors.background)
                .overlay(Circle().stroke(theme.colors.divider, lineWidth: 1))
                .frame(width: radius * 2, height: radius * 2)
                .position(x: center.x, y: center.y)

            if AppSettings.shared.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .position(x: center.x, y: center.y - 58)
            }

            if let more = geometry.moreFrame {
                control(more, hovered: state.hovered == .more, theme: theme) {
                    HStack(spacing: 6) {
                        Text("More")
                        Text("\(geometry.moreCount)").foregroundStyle(theme.colors.secondaryText)
                    }
                }
            }
            control(geometry.settingsFrame, hovered: state.hovered == .settings, theme: theme) {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
            }

            if let message = snapshot.emptyMessage {
                Text(message)
                    .font(.system(size: RingTypography.secondarySize))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: center.x, y: center.y + 56)
            }
        }
    }

    private func control<Label: View>(_ frame: CGRect, hovered: Bool, theme: Theme,
                                      @ViewBuilder label: () -> Label) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.colors.primaryText.opacity(hovered ? 0.20 : 0.08))
            label()
                .font(.system(size: RingTypography.secondarySize, weight: .medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }
}
#endif
