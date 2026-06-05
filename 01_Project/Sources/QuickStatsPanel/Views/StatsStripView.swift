import SwiftUI

/// The thin horizontal strip: a row of stat tiles on a rounded dark background.
/// Reads `@Observable` `StatsStore` directly — body access auto-tracks updates.
struct StatsStripView: View {
    let store: StatsStore
    /// Opens the Settings window (provided by AppDelegate — it must activate the
    /// agent app first so the window can become key).
    var onOpenSettings: () -> Void

    var body: some View {
        // Data-driven: the store maps its live samples to an ordered, availability-
        // filtered [StatDescriptor]; we render one tile each with dividers between.
        // Reading store.visibleStats here keeps Observation tracking the samples.
        let stats = store.visibleStats
        HStack(spacing: Theme.Metrics.tileSpacing) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                if index > 0 { divider }
                StatTileView(
                    symbol: stat.symbol,
                    value: stat.value,
                    widestValue: stat.widestValue,
                    loadPercent: stat.loadPercent,
                    detail: stat.detail,
                    processSection: stat.processSection
                )
            }
            // Gear lives at the trailing end and is always present — even with
            // every stat disabled — so the panel is never a dead end.
            if !stats.isEmpty { divider }
            gearButton
        }
        // Refuse horizontal compression so values never wrap (e.g. "16,97 GB"
        // splitting at the space). This also makes the content's *minimum* width
        // equal its *ideal* width, so PanelWindowController's fittingSize measures
        // the snug strip correctly instead of the over-compressed one.
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, Theme.Metrics.horizontalPadding)
        .frame(height: AppSettings.shared.stripHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
                .fill(Theme.Colors.background)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
        .preferredColorScheme(.dark)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Colors.divider)
            .frame(width: 1, height: 18)
    }

    /// Trailing gear → opens Settings. Styled to read as a quiet affordance, not a
    /// stat (secondary tint, no value, no popover).
    private var gearButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.secondaryText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
    }
}
