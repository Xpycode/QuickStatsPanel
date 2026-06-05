import SwiftUI

/// The real settings surface, shown in the standard `Settings` window (opened
/// from the panel's gear). Edits `AppSettings.shared` directly; persistence and
/// side-effects (hotkey re-register, sampler restart) happen in the model's
/// `didSet` hooks, so this view stays declarative.
struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            statsSection
            samplingSection
            panelSection
            hotkeySection

            Section {
                HStack {
                    Button("Reset to Defaults", action: resetToDefaults)
                    Spacer()
                    Button("Quit QuickStatsPanel") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Stats (toggle + drag-to-reorder)

    private var statsSection: some View {
        Section("Stats") {
            // Order here = strip order. Drag to reorder; toggle to show/hide.
            // Unavailable stats (e.g. battery on a desktop) stay listed but won't
            // appear in the strip — availability is filtered in `visibleStats`.
            List {
                ForEach(settings.statOrder) { kind in
                    Toggle(isOn: enabledBinding(kind)) {
                        Label(kind.displayName, systemImage: kind.settingsSymbol)
                    }
                }
                .onMove { settings.statOrder.move(fromOffsets: $0, toOffset: $1) }
            }
            // Height scales with the number of stats (~34pt/row) so added kinds
            // don't clip the list — was a hardcoded 170 sized for the original five.
            .frame(height: CGFloat(settings.statOrder.count) * 34)
            Text("Drag to reorder · toggle to show or hide")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Sampling

    private var samplingSection: some View {
        Section("Sampling") {
            VStack(alignment: .leading) {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Text(String(format: "%.2f s", settings.interval))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.interval, in: 0.25...5, step: 0.25)
            }
        }
    }

    // MARK: - Panel placement & size

    private var panelSection: some View {
        Section("Panel") {
            Picker("Appears", selection: $settings.anchor) {
                ForEach(PanelAnchor.allCases) { anchor in
                    Text(anchor.label).tag(anchor)
                }
            }
            VStack(alignment: .leading) {
                HStack {
                    Text("Strip height")
                    Spacer()
                    Text("\(Int(settings.stripHeight)) pt")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.stripHeight, in: 22...44, step: 1)
            }
            Text("Placement and height apply the next time the panel is summoned.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Hotkey

    private var hotkeySection: some View {
        Section("Global Hotkey") {
            HStack {
                Text("Summon panel")
                Spacer()
                HotKeyRecorderView(binding: $settings.hotKey)
            }
        }
    }

    // MARK: - Helpers

    private func enabledBinding(_ kind: StatKind) -> Binding<Bool> {
        Binding(get: { settings.isEnabled(kind) },
                set: { settings.setEnabled(kind, $0) })
    }

    private func resetToDefaults() {
        settings.statOrder = StatKind.allCases
        settings.enabledStats = Set(StatKind.allCases)
        settings.interval = 1.0
        settings.anchor = .cursor
        settings.stripHeight = 36
        settings.hotKey = .default
    }
}
