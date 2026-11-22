import AppKit
import SwiftUI
@testable import QuickStatsPanel

@main struct GraphProbe {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        defer { UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName) }
        for (preset, scheme, scenario) in [(ThemePreset.default, ColorScheme.light, "mixed"), (.default, .dark, "mixed"), (.neon, .light, "mixed"), (.mono, .light, "mixed"), (.default, .light, "empty"), (.default, .light, "idle")] {
            AppSettings.shared.themePreset = preset
            let theme = AppSettings.shared.theme
            let slots = (0..<120).map { i -> TransferPeriodSlot in
                let missing = scenario == "empty" || (scenario == "mixed" && (i < 42 || (45..<100).contains(i)))
                let mixed = scenario == "mixed" && i == 101
                let rate = Double((i * 17) % 23) * 40_000
                let bytes = missing || scenario == "idle" ? TransferBytes.zero : TransferBytes(first: UInt64(rate * 720), second: UInt64(rate * 24))
                return TransferPeriodSlot(start: Double(i) * 720, end: Double(i + 1) * 720,
                    bytes: bytes, fullyMeasuredDuration: missing || mixed ? 0 : 720,
                    partialDuration: mixed ? 360 : 0, accountingOverflow: false)
            }
            let result = TransferPeriodResult(stat: .network, start: 0, end: 86400,
                bytes: .zero, fullyMeasuredDuration: 0, partialDuration: 0,
                hasBoundaryEstimate: false, accountingOverflow: false, slots: slots)
            let graph = TransferHistoryGraph(result: result, period: .day)
            let content = VStack(spacing: 8) {
                TransferHistoryGraphView(data: graph)
                TransferHistoryGraphLegend(data: graph)
            }
            .padding(16)
            .background(theme.colors.background)
            .environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: content)
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let label = "\(preset.rawValue)-\(scheme)-\(scenario)"
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/qsp-e1-run08/\(label).png"))
            print("\(label): \(host.frame.size)")
        }
    }
}
