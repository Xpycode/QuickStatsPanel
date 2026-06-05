import Foundation

/// Where the strip appears when summoned (decision D-007). `cursor` is the
/// default, glanceable behavior (appear under the pointer); the fixed modes pin
/// it to a screen position regardless of where the mouse is.
///
/// The actual origin math lives in `PanelWindowController` (it needs the screen's
/// visible frame and the measured strip size). This enum is just the persistable
/// choice the user picks in Settings.
enum PanelAnchor: String, CaseIterable, Identifiable, Sendable {
    case cursor
    case screenCenter
    case topCenter
    case bottomCenter

    var id: String { rawValue }

    /// Human label for the Settings picker.
    var label: String {
        switch self {
        case .cursor:       return "At cursor"
        case .screenCenter: return "Screen center"
        case .topCenter:    return "Top center"
        case .bottomCenter: return "Bottom center"
        }
    }
}
