import SwiftUI

/// The activity graph: discrete vertical bars, newest at the right, drawn from a
/// baseline — mirrored into two series when the stat has a natural pair
/// (Network ↓/↑, Disk Read/Write), single-sided otherwise (CPU, GPU, Memory).
///
/// **Hand-drawn `Canvas`, not Swift Charts** (D-025, following D-015's precedent
/// for the detail card): Swift Charts brings its own axes, insets, gridlines and
/// animation curves, all of which read as system chrome against this app's flat
/// self-drawn surfaces — and `DiskVerdict`'s `TrendChart.swift` is 437 lines for
/// an analytics window, an order of magnitude past what a 34pt strip slot needs.
///
/// **Fixed geometry.** Every call site passes an explicit width and height (floating-tile
/// cards pass the ideal width and stretch to the card's content width, D-046), and the
/// bar count is derived from the drawn width — never from the sample count. The strip
/// depends on this for D-008 (a tile that resizes as history accumulates would
/// shift every tile beside it), and the detail card depends on it because
/// `DetailPanelController` measures the card exactly once when it opens.
struct ActivityGraphView: View {
    let data: GraphData
    let width: CGFloat
    let height: CGFloat

    /// Bar geometry. The defaults suit the detail card; the strip passes thinner
    /// bars so a 34pt slot still shows a readable stretch of history.
    var barWidth: CGFloat = 2
    var barGap: CGFloat = 1
    /// Defaults to the strip's tail (its look is unchanged); detail cards pass `.wholeHistory`.
    var fit: GraphFit = .recentTail
    /// Floating-tile cards (D-046): `width` is the graph's ideal (and minimum) width and the
    /// graph stretches to the card's content width. The ideal is a constant, so the card's
    /// once-at-open measurement never depends on the sample count.
    var fillsWidth = false

    var body: some View {
        let theme = AppSettings.shared.theme
        let canvas = Canvas { context, size in
            draw(in: &context, size: size, theme: theme)
        }
        Group {
            if fillsWidth {
                canvas.frame(minWidth: width, idealWidth: width, maxWidth: .infinity,
                             minHeight: height, idealHeight: height, maxHeight: height)
            } else {
                canvas.frame(width: width, height: height)
            }
        }
        // The graph is decorative detail beside a value that is already announced;
        // VoiceOver reading a bar series adds noise, not information.
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, theme: Theme) {
        // Mirrored: baseline down the middle, each half gets half the height.
        // Single: baseline on the floor, the series owns the full height.
        let baselineY = data.isMirrored ? size.height / 2 : size.height
        let halfHeight = data.isMirrored ? size.height / 2 : size.height

        drawBaseline(in: &context, size: size, y: baselineY, theme: theme)

        drawBars(in: &context, series: data.upper, width: size.width,
                 baselineY: baselineY, maxHeight: halfHeight, upward: true,
                 color: theme.colors.graphPrimary)

        if let lower = data.lower {
            drawBars(in: &context, series: lower, width: size.width,
                     baselineY: baselineY, maxHeight: halfHeight, upward: false,
                     color: theme.colors.graphSecondary)
        }
    }

    /// The dotted zero line. In the mirrored form it is what makes "above" and
    /// "below" read as two series rather than one jagged shape.
    private func drawBaseline(in context: inout GraphicsContext, size: CGSize,
                              y: CGFloat, theme: Theme) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(path, with: .color(theme.colors.divider),
                       style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
    }

    /// One series of bars, newest at the right edge and history running leftward — the
    /// direction every comparable macOS monitor uses. Slot assignment is `GraphBarLayout`.
    private func drawBars(in context: inout GraphicsContext,
                          series: GraphSeries, width: CGFloat,
                          baselineY: CGFloat, maxHeight: CGFloat,
                          upward: Bool, color: Color) {
        for bar in GraphBarLayout.bars(for: series.values, width: width, barWidth: barWidth,
                                       barGap: barGap, fit: fit) {
            let fraction = min(max(bar.value / series.peak, 0), 1)
            guard fraction > 0 else { continue }
            // Sub-pixel bars vanish entirely; a floor keeps light activity visible
            // rather than silently rounding it away to nothing.
            let barHeight = max(fraction * maxHeight, 1)
            let rect = CGRect(x: bar.x,
                              y: upward ? baselineY - barHeight : baselineY,
                              width: bar.width,
                              height: barHeight)
            context.fill(Path(rect), with: .color(color))
        }
    }
}

// MARK: - Legend

/// The peak row beneath a graph in the detail card: a color swatch, the series
/// name, and the value that maps to a full-height bar.
///
/// This row is what licenses the rebasing scale. A rate graph normalized to a
/// rolling peak is only honest while that peak is on screen next to it —
/// otherwise a flat idle line and a flat saturated line are indistinguishable.
struct ActivityGraphLegend: View {
    let data: GraphData

    var body: some View {
        let theme = AppSettings.shared.theme
        HStack(spacing: 12) {
            entry(data.upper, color: theme.colors.graphPrimary, theme: theme)
            if let lower = data.lower {
                entry(lower, color: theme.colors.graphSecondary, theme: theme)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func entry(_ series: GraphSeries, color: Color, theme: Theme) -> some View {
        // Only meaningful for peak-scaled series; percentage graphs have an
        // implicit 100% ceiling and print nothing.
        if let peak = series.peakFormatted {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text("Peak \(series.marker.isEmpty ? series.label : series.marker)")
                    .font(theme.fonts.detailTitle)
                    .foregroundStyle(theme.colors.secondaryText)
                Text(peak)
                    .font(theme.fonts.detailValue)
                    .foregroundStyle(theme.colors.primaryText)
            }
        }
    }
}
