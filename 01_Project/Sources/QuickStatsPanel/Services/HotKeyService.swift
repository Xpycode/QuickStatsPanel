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

        /// Default summon hotkey: ⌃⌥⌘Q (control + option + command + Q).
        static let `default` = Binding(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        )

        /// Default "Keep on Screen" (pin) toggle: ⌃⌥⌘P. Like the summon hotkey
        /// it's user-rebindable; unlike it, it's registered only while the panel
        /// is visible (pinning is meaningless when nothing is shown).
        static let defaultPin = Binding(
            keyCode: UInt32(kVK_ANSI_P),
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

    // MARK: - Shared Carbon plumbing
    //
    // ONE application-level event handler for the whole process, plus a registry
    // of hotkey-id → callback. Installing a handler *per instance* (the previous
    // design) was subtly broken: Carbon calls same-target handlers newest-first and
    // STOPS at the first that returns `noErr` — which every handler did — so only
    // the last-registered hotkey ever fired and all the others were silently
    // shadowed (the ⌘,/Esc "do nothing" bug). A single handler that dispatches by
    // id can't shadow anything, and the id filtering lives in the dictionary lookup.

    /// The one installed handler, kept so we install it exactly once. Never removed:
    /// it lives for the whole app run (a `@MainActor` deinit is nonisolated under
    /// Swift 6 and can't touch this safely), which is fine for a process-lifetime
    /// singleton — teardown of individual hotkeys goes through `unregister()`.
    private static var sharedHandler: EventHandlerRef?

    /// hotkey id → what to run when it fires. Mutated only on the main actor
    /// (register/unregister are `@MainActor`; the C callback hops to it before
    /// reading), so it needs no extra synchronization.
    private static var callbacks: [UInt32: () -> Void] = [:]

    /// Install the shared hotkey-pressed handler once, on first `register`.
    private static func installSharedHandlerIfNeeded() {
        guard sharedHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                // Which hotkey fired? Read its id, then dispatch to the matching
                // callback on the main actor. The closure captures nothing (it only
                // touches the static registry), so it converts to a C function ptr.
                var firedID = EventHotKeyID()
                GetEventParameter(event,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil,
                                  &firedID)
                let firedRawID = firedID.id
                Task { @MainActor in
                    HotKeyService.callbacks[firedRawID]?()
                }
                return noErr
            },
            1, &spec, nil, &sharedHandler
        )
    }

    /// Distinguishes this service's hotkey from any other instance's — it's the
    /// registry key, and the `EventHotKeyID.id` Carbon stamps on this hotkey's
    /// presses, so a fired press routes back to exactly this instance's callback.
    private let id: UInt32

    private var hotKeyRef: EventHotKeyRef?

    /// - Parameter id: unique per instance (e.g. 1 = toggle, 2 = dismiss).
    init(id: UInt32 = 1) {
        self.id = id
    }

    /// (Re)registers the hotkey. Calling again replaces any previous binding.
    func register(_ binding: Binding = .default, onTrigger: @escaping () -> Void) {
        unregister()
        HotKeyService.installSharedHandlerIfNeeded()
        HotKeyService.callbacks[id] = onTrigger

        // 'QSTP' signature keeps our hotkey distinct from other apps'; `id`
        // distinguishes this instance's hotkey from our other instances'.
        let hotKeyID = EventHotKeyID(signature: OSType(0x51535450), id: id)
        RegisterEventHotKey(binding.keyCode, binding.modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        HotKeyService.callbacks[id] = nil
    }

    // No `deinit` cleanup: a @MainActor class's deinit is nonisolated under
    // Swift 6 and can't safely touch the Carbon pointers. This service lives for
    // the whole app run; cleanup goes through `unregister()` (called from
    // AppDelegate.applicationWillTerminate).
}
