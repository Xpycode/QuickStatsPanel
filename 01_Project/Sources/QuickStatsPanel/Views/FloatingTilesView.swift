#if DEBUG
import SwiftUI

/// One overview tile of the floating-tile prototype: its own calm surface, the stat's identity
/// and its existing display text. Value widths are reserved (hidden widest text), so changing
/// digits never move anything; the frame itself is frozen by `FloatingTilePlan`. Unavailable
/// readings keep their slot and say so rather than showing zero.
struct FloatingTileCardView: View {
    let store: StatsStore
    let kind: StatKind
    let isLarge: Bool

    var body: some View {
        let theme = AppSettings.shared.theme
        let descriptor = store.resolvedDescriptor(for: kind)
        let weight = descriptor.map { theme.weight(for: $0.band) } ?? .regular
        ZStack(alignment: .topLeading) {
            FloatingTileSurface()
            VStack(alignment: .leading, spacing: isLarge ? 8 : 4) {
                HStack(spacing: 6) {
                    Image(systemName: descriptor?.symbol ?? kind.settingsSymbol)
                        .font(.system(size: isLarge ? 15 : 12, weight: weight))
                        .foregroundStyle(descriptor?.tint ?? theme.colors.secondaryText)
                        .frame(width: 18)
                    Text(kind.displayName)
                        .font(theme.fonts.detailTitle)
                        .foregroundStyle(theme.colors.secondaryText)
                }
                if let descriptor {
                    reserved(descriptor.value, widest: descriptor.widestValue, weight: weight, theme: theme)
                    if let secondary = descriptor.secondaryValue, let widest = descriptor.widestSecondaryValue {
                        reserved(secondary, widest: widest, weight: weight, theme: theme)
                    }
                } else {
                    Text("Unavailable")
                        .font(theme.fonts.detailValue)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .padding(10)
        }
    }

    private func reserved(_ value: String, widest: String, weight: Font.Weight, theme: Theme) -> some View {
        ZStack(alignment: .leading) {
            Text(widest).fontWeight(.heavy).hidden()
            Text(value).fontWeight(weight)
        }
        .font(isLarge ? .system(size: 26, weight: weight, design: .rounded).monospacedDigit()
                      : .system(size: 17, weight: weight, design: .rounded).monospacedDigit())
        .foregroundStyle(theme.colors.primaryText)
        .lineLimit(1)
    }
}

/// The switcher surface behind its item controls.
struct FloatingTileSwitcherBackground: View {
    var body: some View { FloatingTileSurface() }
}

/// A switcher item. The current stat has a distinct outline and a marker dot, visible without
/// colour (Mono); it stays inert when selected again.
struct FloatingTileSwitcherItemView: View {
    let kind: StatKind
    let isCurrent: Bool

    var body: some View {
        let theme = AppSettings.shared.theme
        VStack(spacing: 2) {
            Image(systemName: kind.settingsSymbol)
                .font(.system(size: 13, weight: isCurrent ? .bold : .regular))
            Text(kind.displayName)
                .font(.system(size: 10, weight: isCurrent ? .semibold : .regular))
                .lineLimit(1)
        }
        .foregroundStyle(isCurrent ? theme.colors.primaryText : theme.colors.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(theme.colors.primaryText.opacity(isCurrent ? 0.9 : 0.15),
                              lineWidth: isCurrent ? 1.5 : 1)
        )
    }
}

/// The "All statistics" return control.
struct FloatingTileAllStatisticsView: View {
    var body: some View {
        let theme = AppSettings.shared.theme
        HStack(spacing: 4) {
            Image(systemName: "square.grid.2x2")
            Text("All statistics").lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(theme.colors.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(theme.colors.primaryText.opacity(0.15), lineWidth: 1)
        )
    }
}

/// A group-bar control (move handle, Settings, Quit) drawn as a small glyph.
struct FloatingTileBarItemView: View {
    let symbol: String

    var body: some View {
        let theme = AppSettings.shared.theme
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.colors.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif

#if DEBUG
/// The stat whose detail is open, observed by the switcher items so the current-item cue updates
/// without rebuilding (or moving) any switcher control.
@Observable
@MainActor
final class FloatingTileSelectionModel {
    var current: StatKind?
}

/// Switcher item bound to the selection model.
struct FloatingTileSwitcherItem: View {
    let kind: StatKind
    let selection: FloatingTileSelectionModel

    var body: some View {
        FloatingTileSwitcherItemView(kind: kind, isCurrent: selection.current == kind)
    }
}
#endif
