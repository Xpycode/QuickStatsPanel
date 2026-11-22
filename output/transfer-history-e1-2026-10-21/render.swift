import AppKit
import SwiftUI
@testable import QuickStatsPanel

@main
struct RenderProbe {
    @MainActor static func main() async throws {
        // Offscreen views only: no application delegate, windows, samplers or hotkeys.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let domain = ProcessInfo.processInfo.processName
        let defaults = UserDefaults.standard
        defaults.setVolatileDomain(["themePreset": "neon"], forName: UserDefaults.argumentDomain)
        let root = URL(fileURLWithPath: "/tmp/qsp-e1-run07/history-\(UUID().uuidString)")
        let store = StatsStore(transferHistoryRoot: root, transferHistoryAutomaticallySchedules: false)
        store.network = NetworkSample(downBytesPerSec: 37_000, upBytesPerSec: 12_000, interfaceName: "Wi-Fi (en0)", localIP: "192.0.2.10")
        store.startTransferHistory()
        store.setTransferDetailVisible(.network)
        if let controller = store.transferHistoryController {
            await withCheckedContinuation { continuation in controller.synchronize { continuation.resume() } }
        }
        for _ in 0..<40 { await Task.yield() }
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
        }
        var sizes: [CGSize] = []
        for (preset, scheme, confirm) in [(ThemePreset.neon, ColorScheme.light, false), (.neon, .light, true), (.default, .light, false), (.default, .dark, false), (.mono, .light, false)] {
            AppSettings.shared.themePreset = preset
            store.cancelTransferReset(for: .network)
            if confirm { store.requestTransferReset(for: .network) }
            let host = NSHostingView(rootView: StatDetailView(store: store, kind: .network).environment(\.colorScheme, scheme))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let size = host.fittingSize
            sizes.append(size)
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let label = "\(preset.rawValue)-\(scheme)-\(confirm ? "confirm" : "normal")"
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/qsp-e1-run07/\(label).png"))
            func native(_ view: NSView) {
                if view is NSSegmentedControl || view is NSButton {
                    print("\(label): \(type(of: view)) \(view.effectiveAppearance.name.rawValue)")
                }
                view.subviews.forEach(native)
            }
            native(host)
            print("\(label): \(size.width) × \(size.height)")
        }
        precondition(sizes[0] == sizes[1], "Confirmation resized the card")
        print("Stable confirmation size verified. Disposable namespace: \(domain)")
    }
}
