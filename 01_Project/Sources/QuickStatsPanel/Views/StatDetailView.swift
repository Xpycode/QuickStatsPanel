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

    /// Card graph geometry. Wide enough for roughly a minute of 2pt bars — the
    /// same buffer the 34pt strip slot shows only the tail of.
    private static let graphWidth: CGFloat = 220
    private static let graphHeight: CGFloat = 44
    private static let transferWidth: CGFloat = 260

    private var transferStat: TransferStat? {
        switch kind {
        case .network: return .network
        case .disk: return .disk
        default: return nil
        }
    }

    var body: some View {
        let theme = AppSettings.shared.theme
        // Tolerate the stat vanishing while open (e.g. battery unplugged) by
        // collapsing to an empty card rather than crashing on a stale lookup.
        let descriptor = store.visibleStats.first { $0.kind == kind }
        Group {
            if let descriptor { content(descriptor, theme: theme) }
        }
        .frame(width: transferStat == nil ? nil : Self.transferWidth, alignment: .leading)
        .padding(12)
        .frame(minWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: theme.metrics.cornerRadius, style: .continuous)
                .fill(theme.colors.background)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.cornerRadius, style: .continuous))
        .onDisappear {
            if let transferStat { store.cancelTransferReset(for: transferStat) }
        }
    }

    @ViewBuilder
    private func content(_ descriptor: StatDescriptor, theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if transferStat == nil && descriptor.detail.isEmpty && descriptor.graph == nil && descriptor.processSection == nil {
                Text("No detail rows selected.")
                    .font(theme.fonts.detailTitle)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            // Activity graph (D-025). Present whenever the stat keeps history —
            // the per-stat *style* setting governs the strip only, where width is
            // scarce; the card always has room, matching iStat, whose dropdown
            // always carries the graph regardless of the menu-bar element.
            //
            // Fixed size on purpose: `DetailPanelController` measures this card
            // exactly once when it opens, so a graph that grew with its sample
            // count would be clipped for the rest of the card's life.
            if let transferStat {
                transferContent(for: transferStat, theme: theme)
                Divider().padding(.vertical, 2)
            } else if let graph = descriptor.graph {
                ActivityGraphView(data: graph,
                                  width: Self.graphWidth,
                                  height: Self.graphHeight)
                ActivityGraphLegend(data: graph)
                Divider().padding(.vertical, 2)
            }

            if kind == .network {
                networkLegacyRows(descriptor, theme: theme)
            } else {
                ForEach(descriptor.detail, id: \.0) { row in
                    HStack {
                        Text(row.0)
                            .font(theme.fonts.detailTitle)
                            .foregroundStyle(theme.colors.secondaryText)
                        Spacer(minLength: 24)
                        Text(row.1)
                            .font(theme.fonts.detailValue)
                            .foregroundStyle(theme.colors.primaryText)
                    }
                }
            }

            // iStat-Menus-style top-processes list (CPU / Memory tiles).
            if let section = descriptor.processSection, !section.rows.isEmpty {
                Divider().padding(.vertical, 2)
                Text(section.title)
                    .font(theme.fonts.detailTitle)
                    .foregroundStyle(theme.colors.secondaryText)
                // Reserve a constant slot count so the card height never changes as
                // the active-app count varies tick-to-tick. Real rows render; empty
                // slots render an invisible row of identical height. Cookbook 67,
                // applied vertically.
                ForEach(0..<section.reservedRows, id: \.self) { i in
                    let row: (String, String)? = i < section.rows.count ? section.rows[i] : nil
                    HStack {
                        Text(row?.0 ?? " ")                      // process name leads
                            .font(theme.fonts.detailValue)
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 24)
                        Text(row?.1 ?? " ")                      // its metric value
                            .font(theme.fonts.detailValue)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                    .opacity(row == nil ? 0 : 1)                 // pad slots stay invisible
                }
            }
        }
    }

    /// Interface/IP metadata can disappear while offline. Reserve each enabled
    /// row even then, so reconnecting cannot grow a card measured while offline.
    /// An unavailable row has no visible or accessible label/value.
    private func networkLegacyRows(_ descriptor: StatDescriptor, theme: Theme) -> some View {
        let labels = kind.configurableDetailRows.filter {
            AppSettings.shared.isDetailRowVisible(kind, $0)
        }
        return ForEach(labels, id: \.self) { label in
            let row = descriptor.detail.first { $0.0 == label }
            HStack {
                Text(row?.0 ?? " ")
                    .font(theme.fonts.detailTitle)
                    .foregroundStyle(theme.colors.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 24)
                Text(row?.1 ?? " ")
                    .font(theme.fonts.detailValue)
                    .foregroundStyle(theme.colors.primaryText)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(height: 18)
            .help(row.map { "\($0.0): \($0.1)" } ?? "")
            .opacity(row == nil ? 0 : 1)
            .accessibilityHidden(row == nil)
        }
    }

    /// Every changing element has a reserved slot. The hosting panel measures
    /// only on opening; loading, period changes and reset/save results must fit
    /// that same size. Legacy detail rows below continue to use their descriptor.
    private func transferContent(for stat: TransferStat, theme: Theme) -> some View {
        let state = store.transferDetailStates[stat] ?? TransferDetailState(stat: stat)
        let presentation = store.transferPresentations[stat]
        // Queries finish asynchronously. Never relabel an old graph or period
        // total with the new selection while waiting for its matching packet.
        let selected = presentation?.period == state.period ? presentation : nil
        let name = stat == .network ? "Network" : "Disk"
        let warning = [state.resetError, presentation?.warningText]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")

        return VStack(alignment: .leading, spacing: 4) {
            TransferPeriodControl(statName: name, selection: Binding(
                get: { store.transferDetailStates[stat]?.period ?? .minute },
                set: { store.selectTransferPeriod($0, for: stat) }))
                .frame(height: 24)

            Group {
                if let selected {
                    VStack(spacing: 6) {
                        TransferHistoryGraphView(data: selected.graph).frame(height: 64)
                        TransferHistoryGraphLegend(data: selected.graph).frame(height: 50)
                    }
                } else {
                    Text("Loading \(state.period.title) history…")
                        .font(theme.fonts.detailTitle)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .frame(width: Self.transferWidth, height: 120)
            .help("Rates use measured activity. ╱ marks unobserved time; the top-edge marker identifies partial-source coverage.")

            Text("Selected period · \(state.period.title)")
                .font(theme.fonts.detailTitle)
                .foregroundStyle(theme.colors.secondaryText)
                .frame(height: 18, alignment: .leading)
            transferTotals(selected?.selectedTotals, stat: stat, section: "Selected period",
                           estimateHelp: selected?.boundaryEstimateHelp, theme: theme)

            HStack {
                Text("Since reset")
                    .font(theme.fonts.detailTitle)
                    .foregroundStyle(theme.colors.secondaryText)
                Spacer(minLength: 0)
                TransferHistoryButton(title: "Reset…", accessibilityLabel: "Reset \(name) cumulative totals",
                    help: "Ask to reset only \(name) cumulative totals. History is kept.",
                    isEnabled: presentation != nil && !state.isResetPending && !state.isConfirmingReset) {
                    store.requestTransferReset(for: stat)
                }
                .frame(width: 62, height: 22)
            }
            .frame(height: 22)
            transferTotals(presentation?.cumulativeTotals, stat: stat, section: "Since reset", theme: theme)
            transferTextSlot(presentation?.resetStartedText ?? "Loading start time…", lines: 2, height: 32, theme: theme)

            transferTextSlot(selected?.coverageText ?? "Loading measured coverage…", lines: 3, height: 46,
                help: "\(selected?.coverageText ?? "Coverage is loading.") Partial time includes only readable sources. Missing time is unobserved. Totals include measured activity only. \(selected?.boundaryEstimateHelp ?? "")",
                theme: theme)
            transferTextSlot(state.isResetPending ? "Reset pending · waiting for durable save…" :
                (presentation?.saveText ?? "Loading saved history…"), lines: 2, height: 32, theme: theme)
            transferTextSlot(warning, lines: 2, height: 32, theme: theme)

            Group {
                if state.isConfirmingReset {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(state.confirmationTitle)
                                .font(theme.fonts.detailTitle)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                            TransferHistoryButton(title: "Reset", accessibilityLabel: "Confirm reset \(name) totals",
                                help: state.confirmationHelp) { store.confirmTransferReset(for: stat) }
                                .frame(width: 48, height: 22)
                            TransferHistoryButton(title: "Cancel", accessibilityLabel: "Cancel reset \(name) totals",
                                help: "Keep cumulative totals and history.") { store.cancelTransferReset(for: stat) }
                                .frame(width: 50, height: 22)
                        }
                        Text(state.confirmationHelp)
                            .font(theme.fonts.detailValue)
                            .lineLimit(2)
                    }
                    .foregroundStyle(theme.colors.primaryText)
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(height: 54, alignment: .topLeading)
        }
        .frame(width: Self.transferWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) transfer history")
    }

    private func transferTotals(_ totals: TransferPairedTotals?, stat: TransferStat, section: String,
                                estimateHelp: String? = nil, theme: Theme) -> some View {
        let labels = stat == .network ? ("↓ Downloaded", "↑ Uploaded") : ("R Read", "W Written")
        return VStack(spacing: 2) {
            transferTotalRow(totals?.first, placeholderLabel: labels.0, section: section,
                             estimateHelp: estimateHelp, theme: theme)
            transferTotalRow(totals?.second, placeholderLabel: labels.1, section: section,
                             estimateHelp: estimateHelp, theme: theme)
        }
        .frame(height: 34)
    }

    private func transferTotalRow(_ total: TransferDirectionTotal?, placeholderLabel: String, section: String,
                                  estimateHelp: String?, theme: Theme) -> some View {
        let label = total.map { "\($0.marker) \($0.label)" } ?? placeholderLabel
        let value = total?.value ?? "Loading…"
        // exactValue is the integer query allocation, which remains an estimate
        // when a sampling interval crosses a query boundary. Keep that caveat
        // beside the full byte count in both help and accessibility.
        let detail = "\(total?.exactValue ?? "Loading bytes.") \(estimateHelp ?? "")"
        return HStack {
            Text(label).foregroundStyle(theme.colors.secondaryText)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(theme.colors.primaryText)
        }
        .font(theme.fonts.detailValue)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .help(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(section), \(label), \(value). \(detail)")
    }

    private func transferTextSlot(_ text: String, lines: Int, height: CGFloat,
                                  help: String? = nil, theme: Theme) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(theme.fonts.detailValue)
            .foregroundStyle(theme.colors.secondaryText)
            .lineLimit(lines)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height, alignment: .topLeading)
            .help(help ?? text)
            .accessibilityLabel(help ?? text)
            .accessibilityHidden(text.isEmpty)
    }
}
