import AppKit
import SwiftUI

/// The detail panel stays nonactivating: these target/action controls do not
/// request keyboard focus or install key equivalents.
struct TransferPeriodControl: NSViewRepresentable {
    let statName: String
    let background: Color
    @Binding var selection: TransferHistoryPeriod
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: TransferHistoryPeriod.allCases.map(\.title),
                                         trackingMode: .selectOne,
                                         target: context.coordinator,
                                         action: #selector(Coordinator.changed(_:)))
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        control.refusesFirstResponder = true
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.appearance = transferControlAppearance(background: background, colorScheme: colorScheme)
        control.selectedSegment = TransferHistoryPeriod.allCases.firstIndex(of: selection) ?? 0
        control.setAccessibilityLabel("\(statName) history period")
        control.setAccessibilityHelp("Choose the graph and selected byte totals period. Missing time is unobserved.")
        for (index, period) in TransferHistoryPeriod.allCases.enumerated() {
            control.setToolTip("\(statName) activity over \(period.title)", forSegment: index)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: TransferPeriodControl
        init(parent: TransferPeriodControl) { self.parent = parent }

        @objc func changed(_ sender: NSSegmentedControl) {
            let periods = TransferHistoryPeriod.allCases
            guard periods.indices.contains(sender.selectedSegment) else { return }
            parent.selection = periods[sender.selectedSegment]
        }
    }
}

struct TransferHistoryButton: NSViewRepresentable {
    let title: String
    let accessibilityLabel: String
    let help: String
    let background: Color
    var isEnabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator,
                              action: #selector(Coordinator.clicked(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.refusesFirstResponder = true
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.appearance = transferControlAppearance(background: background, colorScheme: colorScheme)
        button.title = title
        button.isEnabled = isEnabled
        button.toolTip = help
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityHelp(help)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: TransferHistoryButton
        init(parent: TransferHistoryButton) { self.parent = parent }

        @objc func clicked(_ sender: NSButton) {
            guard parent.isEnabled else { return }
            parent.action()
        }
    }
}

/// Neon and custom surfaces can differ from the system appearance. Resolve dynamic
/// theme colors in the SwiftUI environment, then give native controls matching chrome.
private func transferControlAppearance(background: Color, colorScheme: ColorScheme) -> NSAppearance? {
    let environment = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    var isDark = colorScheme == .dark
    environment?.performAsCurrentDrawingAppearance {
        if let rgb = NSColor(background).usingColorSpace(.sRGB) {
            let brightness = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            isDark = brightness < 0.5
        }
    }
    return NSAppearance(named: isDark ? .darkAqua : .aqua)
}
