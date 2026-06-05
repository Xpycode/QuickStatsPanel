import SwiftUI

/// One compact stat in the strip: SF Symbol + primary value, tinted by load.
/// Click reveals a detail popover (D-006: click-to-expand for v1).
struct StatTileView: View {
    let symbol: String
    let value: String
    /// Worst-case value string used to reserve a constant field width (e.g.
    /// "888,88 GB", "100%") so the tile — and the whole strip — never resizes as
    /// the number changes. Adapted from Penumbra's TimecodeView.
    let widestValue: String
    let loadPercent: Double
    /// Detail rows shown in the popover: (label, value).
    let detail: [(String, String)]
    /// Optional ranked "top processes" list shown beneath the detail rows.
    var processSection: StatDescriptor.ProcessSection? = nil

    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail.toggle()
        } label: {
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
        .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
            detailPopover
        }
    }

    private var detailPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(detail, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .font(Theme.Fonts.detailTitle)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Spacer(minLength: 24)
                    Text(row.1)
                        .font(Theme.Fonts.detailValue)
                        .foregroundStyle(Theme.Colors.primaryText)
                }
            }

            // iStat-Menus-style top-processes list (CPU / Memory / Disk tiles).
            if let section = processSection, !section.rows.isEmpty {
                Divider().padding(.vertical, 2)
                Text(section.title)
                    .font(Theme.Fonts.detailTitle)
                    .foregroundStyle(Theme.Colors.secondaryText)
                // Reserve a constant `reservedRows` slots so the popover height never
                // changes as the active-app count varies tick-to-tick (rate lists
                // like CPU fluctuate). Real rows render; missing slots render an
                // invisible row of identical height. Cookbook 67, applied vertically.
                ForEach(0..<section.reservedRows, id: \.self) { i in
                    let row: (String, String)? = i < section.rows.count ? section.rows[i] : nil
                    HStack {
                        Text(row?.0 ?? " ")                      // process name leads
                            .font(Theme.Fonts.detailValue)
                            .foregroundStyle(Theme.Colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 24)
                        Text(row?.1 ?? " ")                      // its metric value
                            .font(Theme.Fonts.detailValue)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .opacity(row == nil ? 0 : 1)                 // pad slots stay invisible
                }
            }
        }
        .padding(12)
        .frame(minWidth: 200)
    }
}
