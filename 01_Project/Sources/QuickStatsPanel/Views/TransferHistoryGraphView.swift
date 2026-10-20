import SwiftUI

/// Transfer-only graph. Its immutable packet already contains aligned time slots and scales;
/// rendering never queries retained history, samples a clock, or advances peak memory.
struct TransferHistoryGraphView: View {
    let data: TransferHistoryGraph
    private let width: CGFloat = 220
    private let height: CGFloat = 44

    var body: some View {
        let theme = AppSettings.shared.theme
        VStack(spacing: 2) {
            Canvas { context, size in
                draw(in: &context, size: size, theme: theme)
            }
            .frame(width: width, height: height)
            HStack(spacing: 0) {
                Text(data.axisLabels[0])
                Spacer(minLength: 0)
                Text(data.axisLabels[1])
                Spacer(minLength: 0)
                Text(data.axisLabels[2])
            }
            .font(theme.fonts.detailTitle)
            .foregroundStyle(theme.colors.secondaryText)
            .frame(width: width)
        }
        .accessibilityHidden(true) // The card announces totals, coverage and the estimate help.
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, theme: Theme) {
        if data.slots.isEmpty {
            missing(in: &context, rect: CGRect(origin: .zero, size: size), fraction: 1, theme: theme)
        }
        for slot in data.slots {
            let x = CGFloat(slot.startFraction) * size.width
            let width = CGFloat(max(0, slot.endFraction - slot.startFraction)) * size.width
            guard width > 0 else { continue }
            let rect = CGRect(x: x, y: 0, width: width, height: size.height)
            if slot.missingFraction > 0 || slot.accountingUnavailable {
                missing(in: &context, rect: rect,
                        fraction: slot.accountingUnavailable ? 1 : slot.missingFraction, theme: theme)
            }
            if !slot.accountingUnavailable {
                bar(in: &context, rect: rect, rate: slot.firstRate, peak: data.firstPeak,
                    upward: true, color: theme.colors.graphPrimary)
                bar(in: &context, rect: rect, rate: slot.secondRate, peak: data.secondPeak,
                    upward: false, color: theme.colors.graphSecondary)
            }
            if slot.partialFraction > 0 {
                // A separate top-edge marker distinguishes partial-source time even in Mono.
                // Its width represents the fraction; it does not claim a sub-slot timestamp.
                let markerWidth = max(1, rect.width * slot.partialFraction)
                var marker = Path()
                marker.move(to: CGPoint(x: rect.minX, y: 1))
                marker.addLine(to: CGPoint(x: min(rect.maxX, rect.minX + markerWidth), y: 1))
                context.stroke(marker, with: .color(theme.colors.primaryText), lineWidth: 2)
            }
        }
        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: size.height / 2))
        baseline.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(baseline, with: .color(theme.colors.divider), style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
    }

    private func missing(in context: inout GraphicsContext, rect: CGRect, fraction: Double, theme: Theme) {
        var clipped = context
        clipped.clip(to: Path(rect))
        clipped.fill(Path(rect), with: .color(theme.colors.secondaryText.opacity(0.04 + 0.08 * fraction)))
        var hatch = Path()
        // Anchor the pattern to the plot, so neighboring missing slots share one stable hatch.
        for x in stride(from: -height, through: width + height, by: 5) {
            hatch.move(to: CGPoint(x: x, y: height))
            hatch.addLine(to: CGPoint(x: x + height, y: 0))
        }
        clipped.stroke(hatch, with: .color(theme.colors.secondaryText.opacity(0.15 + 0.2 * fraction)), lineWidth: 0.6)
    }

    private func bar(in context: inout GraphicsContext, rect: CGRect, rate: Double,
                     peak: Double, upward: Bool, color: Color) {
        guard rate > 0, rate.isFinite, peak.isFinite, peak > 0 else { return }
        let half = rect.height / 2
        let barHeight = min(half - 1, max(1, CGFloat(min(1, rate / peak)) * (half - 1)))
        let gap = min(0.6, rect.width / 4)
        let bar = CGRect(x: rect.minX + gap / 2, y: upward ? half - barHeight : half,
                         width: max(0.1, rect.width - gap), height: barHeight)
        context.fill(Path(bar), with: .color(color))
    }
}

/// Direction text and positional markers carry identity without depending on graph hues.
/// Pattern/edge examples explain the coverage marks independently from the byte totals.
struct TransferHistoryGraphLegend: View {
    let data: TransferHistoryGraph

    var body: some View {
        let theme = AppSettings.shared.theme
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                entry(marker: data.firstMarker, label: data.firstLabel, peak: data.firstPeakText,
                      color: theme.colors.graphPrimary, theme: theme)
                Spacer(minLength: 0)
                entry(marker: data.secondMarker, label: data.secondLabel, peak: data.secondPeakText,
                      color: theme.colors.graphSecondary, theme: theme)
            }
            HStack(spacing: 10) {
                Text("╱ Missing")
                Text("━ Partial sources")
            }
            .font(theme.fonts.detailTitle)
            .foregroundStyle(theme.colors.secondaryText)
        }
        .frame(width: 220, alignment: .leading)
    }

    private func entry(marker: String, label: String, peak: String, color: Color, theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(marker) \(label)")
                .font(theme.fonts.detailTitle)
                .foregroundStyle(color)
            Text("Peak \(peak)")
                .font(theme.fonts.detailValue)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
