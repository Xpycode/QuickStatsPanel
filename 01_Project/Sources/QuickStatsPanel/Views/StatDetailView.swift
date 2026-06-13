import SwiftUI

/// The detail card shown when a stat tile is tapped. Drawn with the panel's own
/// `Theme` — flat dark fill and the *same* small continuous corner radius as the
/// strip (`Theme.Metrics.cornerRadius`), no arrow — so it reads as part of the
/// app rather than a system popover. It lives in its own borderless panel
/// (`DetailPanelController`), which replaced SwiftUI's native `.popover` (whose
/// large "Tahoe" rounding, translucent material, and arrow clashed with the strip).
///
/// Re-derives the current descriptor from `store` inside `body`, so Observation
/// keeps the card live: values tick and the top-process list refreshes while it's
/// open — matching the old `.popover`. (The window is sized once on open, so this
/// refresh never resizes it; see `DetailPanelController`.)
struct StatDetailView: View {
    let store: StatsStore
    let kind: StatKind

    var body: some View {
        // Tolerate the stat vanishing while open (e.g. battery unplugged) by
        // collapsing to an empty card rather than crashing on a stale lookup.
        let descriptor = store.visibleStats.first { $0.kind == kind }
        Group {
            if let descriptor { content(descriptor) }
        }
        .padding(12)
        .frame(minWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
                .fill(Theme.Colors.background)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(_ descriptor: StatDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(descriptor.detail, id: \.0) { row in
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

            // iStat-Menus-style top-processes list (CPU / Memory tiles).
            if let section = descriptor.processSection, !section.rows.isEmpty {
                Divider().padding(.vertical, 2)
                Text(section.title)
                    .font(Theme.Fonts.detailTitle)
                    .foregroundStyle(Theme.Colors.secondaryText)
                // Reserve a constant slot count so the card height never changes as
                // the active-app count varies tick-to-tick. Real rows render; empty
                // slots render an invisible row of identical height. Cookbook 67,
                // applied vertically.
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
    }
}
