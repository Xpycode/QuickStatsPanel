import AppKit
import Carbon.HIToolbox

/// Display + conversion helpers for a `HotKeyService.Binding`. Kept separate from
/// the registration logic so the recorder UI and the settings label can render a
/// binding without touching Carbon registration.
extension HotKeyService.Binding {

    // MARK: - Build from a key event

    /// Carbon modifier mask (`cmdKey`, `optionKey`, …) for a Cocoa modifier set.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option)  { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift)   { mask |= UInt32(shiftKey) }
        return mask
    }

    /// Build a binding from a `keyDown` event (NSEvent.keyCode *is* the Carbon
    /// virtual key code, so it carries straight over).
    init(event: NSEvent) {
        self.init(keyCode: UInt32(event.keyCode),
                  modifiers: Self.carbonModifiers(from: event.modifierFlags))
    }

    // MARK: - Validation  ⟵ USER CONTRIBUTION POINT (see below)

    /// Whether this binding is acceptable as a **global** hotkey.
    ///
    /// A global hotkey is captured system-wide, ahead of the focused app. That
    /// makes a bare key — or a Shift-only combo — dangerous: `⇧A` would intercept
    /// every capital "A" the user types anywhere. So we require at least one of
    /// the "real" modifiers (⌘ / ⌥ / ⌃), which are rare in everyday typing. Shift
    /// may ride along (e.g. ⇧⌘Q) but never stand alone.
    var isValidAsGlobalHotKey: Bool {
        let strong = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
        return modifiers & strong != 0
    }

    // MARK: - Human-readable string

    /// e.g. `⌃⌥⌘Q`. Modifier order follows Apple's convention (⌃⌥⇧⌘).
    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += Self.keyLabel(for: keyCode)
        return s
    }

    /// Settings-friendly form with thin spaces between symbols (`⌃ ⌥ ⌘ Q`).
    /// The compact form above stays appropriate in the narrow first-run hint;
    /// recorder rows have room to favor recognition over density.
    var spacedDisplayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(Self.keyLabel(for: keyCode))
        return parts.joined(separator: "\u{2009}")
    }

    /// Best-effort label for a Carbon virtual key code. Covers the keys most
    /// people pick for a hotkey; anything else falls back to a numeric tag.
    private static func keyLabel(for code: UInt32) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"; case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"; case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"; case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"; case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"; case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"; case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"; case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"; case kVK_Tab: return "⇥"
        case kVK_F1: return "F1"; case kVK_F2: return "F2"
        case kVK_F3: return "F3"; case kVK_F4: return "F4"
        case kVK_F5: return "F5"; case kVK_F6: return "F6"
        case kVK_F7: return "F7"; case kVK_F8: return "F8"
        case kVK_F9: return "F9"; case kVK_F10: return "F10"
        case kVK_F11: return "F11"; case kVK_F12: return "F12"
        case kVK_ANSI_Minus: return "-"; case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Slash: return "/"; case kVK_ANSI_Period: return "."
        case kVK_ANSI_Comma: return ","; case kVK_ANSI_Semicolon: return ";"
        default: return "key \(code)"
        }
    }
}
