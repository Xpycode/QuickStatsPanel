#if DEBUG
import SwiftUI

/// One overview tile of the floating-tile prototype: its own calm surface, the stat's identity,
/// its configured primary/paired readings and, for the stats that have a meaningful fraction, an
/// explicit usage basis with a band-coloured meter. Value widths are reserved (hidden widest
/// text), so changing digits never move anything; the frame itself is frozen by `FloatingTilePlan`.
/// Unavailable readings keep their slot and say so rather than showing zero.
///
/// Meaning that does not rely on colour: the basis caption states the percentage and what it
/// measures, the meter length repeats it, the value weight follows the existing severity ramp,
/// and large/wide tiles add the band word ("Elevated", "High").
struct FloatingTileCardView: View {
    let store: StatsStore
    let kind: StatKind
    let isLarge: Bool

    /// Type tier by the frozen tile frame: the 2x2 first tile, 2x1 wide tiles, 1x1 small tiles.
    /// Fixed sizes per tier; nothing shrinks to fit.
    enum Tier {
        case large, wide, small
        init(size: CGSize, isLarge: Bool) {
            if isLarge || size.height > 150 { self = .large }
            else if size.width > 150 { self = .wide }
            else { self = .small }
        }
        var valueSize: CGFloat { self == .large ? 26 : (self == .wide ? 17 : 13) }
        var symbolSize: CGFloat { self == .large ? 15 : 12 }
        var padding: CGFloat { self == .small ? 8 : 10 }
        var spacing: CGFloat { self == .large ? 6 : 3 }
        /// Fixed per tier: small tiles use a smaller name so "Temperature" is never truncated.
        var nameSize: CGFloat { self == .small ? 11 : 12 }
        var headerSpacing: CGFloat { self == .small ? 4 : 6 }
        var symbolFrame: CGFloat { self == .small ? 16 : 18 }
    }

    var body: some View {
        GeometryReader { proxy in
            content(tier: Tier(size: proxy.size, isLarge: isLarge))
        }
    }

    private func content(tier: Tier) -> some View {
        let theme = AppSettings.shared.theme
        let reading = store.floatingTileReading(for: kind)
        let themeBand = reading.band?.themeBand ?? .calm
        let weight = theme.weight(for: themeBand)
        let tint = reading.band.map { theme.color(for: $0.themeBand) } ?? theme.colors.secondaryText
        return ZStack(alignment: .topLeading) {
            FloatingTileSurface()
            VStack(alignment: .leading, spacing: tier.spacing) {
                HStack(spacing: tier.headerSpacing) {
                    Image(systemName: store.resolvedDescriptor(for: kind)?.symbol ?? kind.settingsSymbol)
                        .font(.system(size: tier.symbolSize, weight: weight))
                        .foregroundStyle(reading.isAvailable ? tint : theme.colors.secondaryText)
                        .frame(width: tier.symbolFrame)
                    Text(kind.displayName)
                        .font(.system(size: tier.nameSize, weight: .semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
                if reading.isAvailable {
                    reserved(reading.primary, widest: reading.widestPrimary, weight: weight, theme: theme, tier: tier)
                    if let secondary = reading.secondary, let widest = reading.widestSecondary {
                        reserved(secondary, widest: widest, weight: weight, theme: theme, tier: tier)
                    }
                } else {
                    Text("Unavailable")
                        .font(.system(size: tier.valueSize, weight: .regular, design: .rounded))
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let percent = reading.usagePercent {
                    FloatingTileMeter(fraction: percent / 100, tint: tint)
                }
                Text(captionText(reading, tier: tier))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }
            .padding(tier.padding)
        }
        .help(reading.explanation)
    }

    private func captionText(_ reading: FloatingTileReading, tier: Tier) -> String {
        // The band word joins the caption where there is room; small tiles rely on the caption,
        // meter length and weight ramp.
        if tier != .small, let band = reading.band, band != .low { return "\(reading.caption) \u{00B7} \(band.word)" }
        return reading.caption
    }

    private func reserved(_ value: String, widest: String, weight: Font.Weight, theme: Theme, tier: Tier) -> some View {
        ZStack(alignment: .leading) {
            Text(widest).fontWeight(.heavy).hidden()
            Text(value).fontWeight(weight)
        }
        .font(.system(size: tier.valueSize, weight: weight, design: .rounded).monospacedDigit())
        .foregroundStyle(theme.colors.primaryText)
        .lineLimit(1)
    }
}

/// A thin usage meter: track plus fill. The fill length repeats the percentage without colour.
struct FloatingTileMeter: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        let theme = AppSettings.shared.theme
        let clamped = min(max(fraction, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.colors.secondaryText.opacity(0.22))
                Capsule().fill(tint).frame(width: max(clamped > 0 ? 3 : 0, proxy.size.width * clamped))
            }
        }
        .frame(height: 4)
    }
}

/// The compact empty state: nothing is enabled, and Settings and Quit stay in the group bar.
struct FloatingTileEmptyStateView: View {
    var body: some View {
        let theme = AppSettings.shared.theme
        ZStack(alignment: .leading) {
            FloatingTileSurface()
            VStack(alignment: .leading, spacing: 4) {
                Text("No statistics enabled")
                    .font(theme.fonts.detailTitle)
                    .foregroundStyle(theme.colors.primaryText)
                Text("Choose statistics in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .padding(12)
        }
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
