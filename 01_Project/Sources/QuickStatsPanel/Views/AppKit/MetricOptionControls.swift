import AppKit
import SwiftUI

/// Native popup for per-stat headline choices. Refresh the coordinator with each
/// SwiftUI update so it always writes through the current selection binding.
struct MetricOptionPopup<Item: Hashable>: NSViewRepresentable {
    let items: [Item]
    let titleForItem: (Item) -> String
    @Binding var selection: Item
    var accessibilityLabel = "Panel value"

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selected(_:))
        popup.setAccessibilityLabel(accessibilityLabel)
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        popup.setAccessibilityLabel(accessibilityLabel)
        let titles = items.map(titleForItem)
        if popup.itemTitles != titles {
            popup.removeAllItems()
            popup.addItems(withTitles: titles)
        }
        if let index = items.firstIndex(of: selection) {
            popup.selectItem(at: index)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: MetricOptionPopup

        init(parent: MetricOptionPopup) { self.parent = parent }

        @objc func selected(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard parent.items.indices.contains(index) else { return }
            parent.selection = parent.items[index]
        }
    }
}

/// Native checkbox for showing or hiding a row in a metric detail card.
struct MetricOptionCheckbox: NSViewRepresentable {
    let title: String
    @Binding var isOn: Bool

    func makeNSView(context: Context) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title,
                                target: context.coordinator,
                                action: #selector(Coordinator.toggled(_:)))
        checkbox.controlSize = .small
        checkbox.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        checkbox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return checkbox
    }

    func updateNSView(_ checkbox: NSButton, context: Context) {
        context.coordinator.isOn = $isOn
        checkbox.title = title
        checkbox.state = isOn ? .on : .off
    }

    func makeCoordinator() -> Coordinator { Coordinator(isOn: $isOn) }

    @MainActor
    final class Coordinator: NSObject {
        var isOn: Binding<Bool>

        init(isOn: Binding<Bool>) { self.isOn = isOn }

        @objc func toggled(_ sender: NSButton) {
            isOn.wrappedValue = sender.state == .on
        }
    }
}
