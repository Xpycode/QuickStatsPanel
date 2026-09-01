import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A "click to record, then press a combo" control for the global hotkey.
///
/// **Why a local event monitor:** while recording we install
/// `NSEvent.addLocalMonitorForEvents(.keyDown)` and *return nil* to swallow the
/// event, so the keystroke configures the hotkey instead of typing into anything.
/// A local monitor only fires while our app is active and a window is key — which
/// is exactly why the gear opens the *Settings window* (it can become key) rather
/// than recording inside the non-activating panel.
struct HotKeyRecorderView: View {
    @Binding var binding: HotKeyService.Binding

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(binding.spacedDisplayString)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .frame(minWidth: 92, alignment: .trailing)
                .foregroundStyle(isRecording ? .secondary : .primary)

            Button(isRecording ? "Press a combo… (⎋ cancels)" : "Record") {
                isRecording ? stopRecording() : startRecording()
            }

            if let hint {
                Text(hint).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stopRecording)   // never leak the monitor
    }

    private func startRecording() {
        hint = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil          // swallow: don't let the keystroke reach the UI
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        // Bare Escape cancels recording (with a modifier it's a legitimate combo).
        let mods = HotKeyService.Binding.carbonModifiers(from: event.modifierFlags)
        if Int(event.keyCode) == kVK_Escape && mods == 0 {
            stopRecording()
            return
        }

        let candidate = HotKeyService.Binding(event: event)
        if candidate.isValidAsGlobalHotKey {
            binding = candidate          // writes through to AppSettings.hotKey
            stopRecording()
        } else {
            // Keep listening; tell the user why their press was rejected.
            hint = "Add a modifier (⌘ ⌥ ⌃)"
        }
    }
}
