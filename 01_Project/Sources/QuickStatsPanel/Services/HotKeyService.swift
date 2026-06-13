import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide hotkey via Carbon's `RegisterEventHotKey`.
///
/// Chosen over `NSEvent` global monitors because it needs **no Accessibility /
/// Input-Monitoring permission** and fires regardless of which app is focused
/// (decision D-002). The user typically routes a mouse button → this key combo
/// via BetterMouse; Carbon sees the synthesized key event all the same.
@MainActor
final class HotKeyService {

    /// A Carbon virtual key code + Carbon modifier mask.
    struct Binding: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32

        /// Default: ⌃⌥⌘Q (control + option + command + Q).
        static let `default` = Binding(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        )

        /// Bare Escape (no modifiers) — used to dismiss the panel while visible.
        static let escape = Binding(keyCode: UInt32(kVK_Escape), modifiers: 0)

        /// ⌘, (the macOS-standard Settings shortcut) — opens Settings, scoped to
        /// while the panel is visible (same pattern as `.escape`; see D-010).
        static let commaSettings = Binding(
            keyCode: UInt32(kVK_ANSI_Comma),
            modifiers: UInt32(cmdKey)
        )
    }

    /// Distinguishes this service's hotkey from any other instance's. Each
    /// instance installs its own app-level handler, and Carbon dispatches every
    /// hotkey press to *all* installed handlers — so the callback must filter by
    /// id, or two services would both fire on any one press.
    private let id: UInt32

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    /// - Parameter id: unique per instance (e.g. 1 = toggle, 2 = dismiss).
    init(id: UInt32 = 1) {
        self.id = id
    }

    /// (Re)registers the hotkey. Calling again replaces any previous binding.
    func register(_ binding: Binding = .default, onTrigger: @escaping () -> Void) {
        unregister()
        self.onTrigger = onTrigger

        // Install one application-level handler for hotkey-pressed events.
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return noErr }
                // Which hotkey fired? Carbon delivers every press to all handlers,
                // so read the id and let the matching service decide.
                var firedID = EventHotKeyID()
                GetEventParameter(event,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil,
                                  &firedID)
                // The C callback is non-isolated; hop to the main actor before
                // touching `self` (which is @MainActor-isolated).
                Task { @MainActor in
                    let service = Unmanaged<HotKeyService>.fromOpaque(userData)
                        .takeUnretainedValue()
                    if firedID.id == service.id { service.onTrigger?() }
                }
                return noErr
            },
            1, &spec, selfPtr, &handlerRef
        )

        // 'QSTP' signature keeps our hotkey distinct from other apps'; `id`
        // distinguishes this instance's hotkey from our other instances'.
        let hotKeyID = EventHotKeyID(signature: OSType(0x51535450), id: id)
        RegisterEventHotKey(binding.keyCode, binding.modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let handlerRef { RemoveEventHandler(handlerRef); self.handlerRef = nil }
        onTrigger = nil
    }

    // No `deinit` cleanup: a @MainActor class's deinit is nonisolated under
    // Swift 6 and can't safely touch the Carbon pointers. This service lives for
    // the whole app run; cleanup goes through `unregister()` (called from
    // AppDelegate.applicationWillTerminate).
}
