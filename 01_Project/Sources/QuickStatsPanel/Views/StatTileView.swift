import SwiftUI

/// One compact stat in the strip: SF Symbol + primary value, tinted by status
/// band. Click toggles the detail card (D-006: click-to-expand). The card itself
/// is a separate flat panel drawn by `DetailPanelController` / `StatDetailView` —
/// this tile just reports the tap; it no longer owns popover state or content.
///
/// Color is resolved upstream (the store fills `tint` with hysteresis), and the
/// **font weight ramps with `band`** as a non-color severity cue (AC-5) so "hot"
/// is legible in Mono / greyscale. The ramp is width-neutral: the hidden width
/// template reserves the heaviest weight and the icon sits in a fixed-width frame,
/// so a band change never resizes the tile (preserving the jitter-free strip).
struct StatTileView: View {
    let symbol: String
    let value: String
    /// Worst-case value string used to reserve a constant field width (e.g.
    /// "888,88 GB", "100%") so the tile — and the whole strip — never resizes as
    /// the number changes. Adapted from Penumbra's TimecodeView.
    let widestValue: String
    /// Optional second value section (e.g. Network's "↑ …" upload beside its
    /// download), rendered in its own reserved-width slot so the sections never
    /// shift against each other. nil for single-value tiles.
    var secondaryValue: String? = nil
    var widestSecondaryValue: String? = nil
    /// Resolved status band — drives the font-weight severity cue.
    let band: Band
    /// Resolved status color for the icon (neutral under Mono).
    let tint: Color
    /// Called when the tile is clicked, so the owner can toggle this stat's detail
    /// card. The owner anchors the card and pulls live detail rows from the store.
    let onTap: () -> Void

    var body: some View {
        let theme = AppSettings.shared.theme
        let weight = theme.weight(for: band)
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: weight))
                    .foregroundStyle(tint)
                    // Fixed width so the icon's weight ramp can't shift the value.
                    .frame(width: 16, alignment: .center)
                // Hidden template reserves the worst-case width at the *heaviest*
                // weight; the visible value rides on top with its current weight
                // (never wider), so the field holds size as value AND band change.
                ZStack(alignment: .leading) {
                    Text(widestValue).fontWeight(.heavy).hidden()
                    Text(value).fontWeight(weight)
                }
                .font(theme.fonts.value)
                .foregroundStyle(theme.colors.primaryText)
                // Second section (e.g. upload) in its own reserved slot, so the
                // down/up fields can't push each other around as digits change.
                if let secondaryValue, let widestSecondaryValue {
                    ZStack(alignment: .leading) {
                        Text(widestSecondaryValue).fontWeight(.heavy).hidden()
                        Text(secondaryValue).fontWeight(weight)
                    }
                    .font(theme.fonts.value)
                    .foregroundStyle(theme.colors.primaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
