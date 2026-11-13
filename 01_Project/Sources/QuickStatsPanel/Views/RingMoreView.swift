#if DEBUG
import SwiftUI

/// Draws the outer More ring from its frozen geometry. Drawing only: input and
/// accessibility live in `RingSurfaceInputView`, so this view is hidden from both.
struct RingMoreRingView: View {
    let geometry: RingMoreGeometry
    let state: RingPresentationState
    let reading: (StatKind) -> RingReading

    var body: some View {
        let theme = AppSettings.shared.theme
        ZStack(alignment: .topLeading) {
            ForEach(geometry.entries, id: \.kind) { entry in
                entryView(entry, theme: theme)
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func entryView(_ entry: RingMoreGeometry.Entry, theme: Theme) -> some View {
        let live = reading(entry.kind)
        let outline = Path { path in
            let points = geometry.outline(of: entry)
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
        let hovered = state.hoveredMoreKind == entry.kind
        let selected = state.selectedMoreKind == entry.kind
        return ZStack(alignment: .topLeading) {
            outline.fill(theme.colors.background)
            outline.fill(theme.color(for: live.band).opacity(live.isAvailable ? 0.22 : 0))
            outline.fill(theme.colors.primaryText.opacity(hovered ? 0.14 : 0))
            outline.stroke(selected ? theme.colors.primaryText : theme.colors.divider, lineWidth: selected ? 2 : 1)
            RingTextBlock(name: entry.kind.displayName, live: live, theme: theme)
                .frame(width: entry.textRect.width, height: entry.textRect.height)
                .position(x: entry.textRect.midX, y: entry.textRect.midY)
        }
        .opacity(live.isAvailable ? 1 : 0.7)
    }
}

/// Horizontal label, headline and optional secondary at the ring's baseline sizes;
/// never rotated, scaled or truncated.
struct RingTextBlock: View {
    let name: String
    let live: RingReading
    let theme: Theme

    var body: some View {
        VStack(spacing: RingTypography.lineSpacing) {
            Text(name)
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
    }
}

/// Compact labelled list: the side More list, or the whole-list fallback with its fixed
/// drag header and Settings row. Rows scroll by the model's offset; the view never owns a
/// scroll view, so drawing, hit testing and the wheel always agree.
struct RingListView: View {
    let layout: RingListLayout
    let state: RingPresentationState
    let reading: (StatKind) -> RingReading

    var body: some View {
        let theme = AppSettings.shared.theme
        let scrolled = layout.scrolled(by: state.listOffset)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: theme.metrics.cornerRadius, style: .continuous)
                .fill(theme.colors.background)
            RoundedRectangle(cornerRadius: theme.metrics.cornerRadius, style: .continuous)
                .stroke(theme.colors.divider, lineWidth: 1)

            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { index, node in
                    row(node, frame: scrolled.rowFrame(at: index), theme: theme)
                }
            }
            .frame(width: layout.viewport.width, height: layout.viewport.height, alignment: .topLeading)
            .offset(y: layout.viewport.minY)
            .clipped()

            if layout.hasChrome {
                header(frame: layout.headerFrame, theme: theme)
                settingsRow(frame: layout.footerFrame, theme: theme)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func kind(of node: RingNode) -> StatKind? {
        switch node {
        case .wedge(let kind), .moreItem(let kind): return kind
        case .more: return nil
        }
    }

    private func row(_ node: RingNode, frame: CGRect, theme: Theme) -> some View {
        let kind = kind(of: node)
        let live = kind.map(reading)
        let hovered = kind != nil && state.hoveredNodeKind == kind
        let selected = kind != nil && (state.selectedKind == kind || state.selectedMoreKind == kind)
        // Row frames are in list space; the clipped container is offset by the viewport.
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(live.map { theme.color(for: $0.band).opacity($0.isAvailable ? 0.18 : 0) } ?? .clear)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(theme.colors.primaryText.opacity(hovered ? 0.14 : 0))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(selected ? theme.colors.primaryText : .clear, lineWidth: 1.5)
            HStack(spacing: 8) {
                Text(kind?.displayName ?? "")
                    .font(.system(size: RingTypography.labelSize, weight: .medium))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer(minLength: 8)
                if let live {
                    Text(live.isAvailable
                         ? [live.value, live.secondary].compactMap { $0 }.joined(separator: "  ")
                         : "Unavailable")
                        .font(.system(size: RingTypography.secondarySize).monospacedDigit())
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .opacity((live?.isAvailable ?? true) ? 1 : 0.7)
        }
        .frame(width: frame.width - 8, height: frame.height - 2)
        .position(x: frame.midX, y: frame.midY - layout.viewport.minY)
    }

    private func header(frame: CGRect, theme: Theme) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.fill")
                .opacity(AppSettings.shared.isPinned ? 1 : 0)
            Text("Quick Stats")
        }
        .font(.system(size: RingTypography.secondarySize, weight: .medium))
        .foregroundStyle(theme.colors.secondaryText)
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    private func settingsRow(frame: CGRect, theme: Theme) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "gearshape")
            Text("Settings")
        }
        .font(.system(size: RingTypography.secondarySize, weight: .medium))
        .foregroundStyle(theme.colors.primaryText)
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }
}
#endif
