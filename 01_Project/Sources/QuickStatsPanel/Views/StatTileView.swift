import SwiftUI

/// One compact stat in the strip: SF Symbol + primary value, tinted by load.
/// Click toggles the detail card (D-006: click-to-expand). The card itself is a
/// separate flat panel drawn by `DetailPanelController` / `StatDetailView` — this
/// tile just reports the tap; it no longer owns popover state or content.
struct StatTileView: View {
    let symbol: String
    let value: String
    /// Worst-case value string used to reserve a constant field width (e.g.
    /// "888,88 GB", "100%") so the tile — and the whole strip — never resizes as
    /// the number changes. Adapted from Penumbra's TimecodeView.
    let widestValue: String
    let loadPercent: Double
    /// Called when the tile is clicked, so the owner can toggle this stat's detail
    /// card. The owner anchors the card and pulls live detail rows from the store.
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.loadColor(forPercent: loadPercent))
                // Hidden template reserves the worst-case width; the visible value
                // rides on top with monospaced digits (Theme.Fonts.value), so the
                // field holds its size as the number changes — no strip jitter.
                ZStack(alignment: .leading) {
                    Text(widestValue).hidden()
                    Text(value)
                }
                .font(Theme.Fonts.value)
                .foregroundStyle(Theme.Colors.primaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
