import SwiftUI

/// Visual tokens for the panel content. (The App Shell Standard `Theme` is for
/// windowed apps; this is the panel-scoped equivalent — see CLAUDE.md.)
enum Theme {

    // MARK: Layout
    enum Metrics {
        static let stripHeight: CGFloat = 36     // configurable later (D-006: ~22–44)
        // Width is content-driven: the panel hugs its tiles (measured via
        // NSHostingView.fittingSize) and grows as stat tiles are added.
        static let cornerRadius: CGFloat = 12     // small, deliberately NOT "Tahoe"
        static let tileSpacing: CGFloat = 14
        static let horizontalPadding: CGFloat = 14
    }

    // MARK: Colors
    enum Colors {
        static let background = Color.black.opacity(0.82)
        static let primaryText = Color.white
        static let secondaryText = Color.white.opacity(0.55)
        static let divider = Color.white.opacity(0.12)

        static let calm = Color.green
        static let busy = Color.yellow
        static let hot = Color.red
    }

    // MARK: Type
    enum Fonts {
        static let value = Font.system(size: 13, weight: .semibold).monospacedDigit()
        static let label = Font.system(size: 9, weight: .medium)
        static let detailTitle = Font.system(size: 12, weight: .semibold)
        static let detailValue = Font.system(size: 12, weight: .regular).monospacedDigit()
    }

    /// Maps a 0–100 utilization figure to a status color for at-a-glance reading.
    ///
    /// TODO(user): tune these thresholds to your sense of "busy". This default is
    /// intentionally simple — calm < 50, busy 50–80, hot ≥ 80. You might want
    /// CPU and memory to use *different* bands (memory pressure feels different
    /// from CPU load), a smooth gradient instead of hard steps, or a hysteresis
    /// band so a value hovering at the threshold doesn't flicker between colors.
    static func loadColor(forPercent percent: Double) -> Color {
        switch percent {
        case ..<50:  return Colors.calm
        case ..<80:  return Colors.busy
        default:     return Colors.hot
        }
    }
}
