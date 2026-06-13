import SwiftUI

/// One-time first-run hint card, shown beneath the auto-summoned strip on the very
/// first launch (`HintPanelController`). Because this is an `LSUIElement` agent app
/// — no Dock icon, no menu-bar item — the hotkey is the *only* way back once the
/// strip dismisses, so the first thing a new user needs is to learn it.
///
/// Drawn with the panel's own flat `Theme` (matching `StatDetailView`) so it reads
/// as part of the app, not a system alert.
struct FirstRunHintView: View {
    /// The currently-bound summon hotkey (e.g. "⌃⌥⌘Q"), rendered live so the hint
    /// always shows what the user actually has set — not a hard-coded default.
    let hotKey: String

    var body: some View {
        cardBody
            .padding(14)
            .frame(minWidth: 220)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
                    .fill(Theme.Colors.background)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous))
            .preferredColorScheme(.dark)
    }

    // MARK: - Card content  ⟵ USER CONTRIBUTION POINT
    //
    // This is the part worth shaping by hand — it's the first impression a new
    // user gets, and the whole point of the feature. The scaffold below is a clean
    // minimal default: a title, the live hotkey in a keycap chip, and a quiet
    // second line of secondary cues. Trade-offs to consider:
    //   • one tight line vs. the two-line layout here (title + cues)
    //   • keycap chips for Esc / ⚙ too, or keep them as plain glyphs in text
    //   • how much to say — discoverability vs. clutter on a HUD that's meant to
    //     read in a glance
    // Edit freely; the chrome above (padding / background / radius) stays put.
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You're all set 👋")
                .font(Theme.Fonts.detailTitle)
                .foregroundStyle(Theme.Colors.primaryText)

            HStack(spacing: 6) {
                Text("Press")
                    .foregroundStyle(Theme.Colors.secondaryText)
                keycap(hotKey)
                Text("anytime to pop up your stats.")
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .font(Theme.Fonts.detailTitle)

            Text("Esc or click away hides it · ⚙ for settings")
                .font(Theme.Fonts.label)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    /// A small keycap-style chip for a shortcut string, so the hotkey stands out
    /// from the surrounding prose.
    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.detailValue)
            .foregroundStyle(Theme.Colors.primaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
    }
}
