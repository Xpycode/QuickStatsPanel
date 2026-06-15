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
            appearanceSection
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

    // MARK: - Appearance (theme preset + custom)

    /// Theme selection. Picking a preset rebuilds `AppSettings.theme` in its
    /// `didSet`; the three panels read `theme` in their `body`, so the switch is
    /// live (AC-1) with no glue here. `.custom` reveals the Customize editor below.
    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.themePreset) {
                ForEach(ThemePreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            Text("Theme applies live across the strip, detail card, and hint.")
                .font(.caption).foregroundStyle(.secondary)

            // Custom-theme knobs only appear when the Custom preset is selected;
            // editing any of them materializes `customTheme` from the baseline.
            if settings.themePreset == .custom {
                DisclosureGroup("Customize…") {
                    customizeControls
                }
            }
        }
    }

    /// The five custom-theme knobs. Each is bound to one `ThemeData` field via the
    /// `customBinding` / `colorBinding` helpers below, so editing one writes the
    /// whole struct back through `settings.customTheme` (→ persist + live rebuild).
    @ViewBuilder private var customizeControls: some View {
        ColorPicker("Accent", selection: colorBinding(\.accent), supportsOpacity: false)
        ColorPicker("Background", selection: colorBinding(\.background), supportsOpacity: false)

        VStack(alignment: .leading) {
            HStack {
                Text("Background opacity")
                Spacer()
                Text(String(format: "%.0f%%", customData.opacity * 100))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            // Floor at 0.3 so the panel never becomes invisible (AC-4 legibility).
            Slider(value: customBinding(\.opacity), in: 0.3...1, step: 0.01)
        }

        VStack(alignment: .leading) {
            HStack {
                Text("Corner radius")
                Spacer()
                Text("\(Int(customData.cornerRadius)) pt")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            // Capped at 20 — this is a flat HUD strip, not a Tahoe sheet.
            Slider(value: customBinding(\.cornerRadius), in: 0...20, step: 1)
        }

        Picker("Density", selection: customBinding(\.density)) {
            ForEach(ThemeDensity.allCases, id: \.self) { density in
                Text(density.displayName).tag(density)
            }
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
            HStack {
                Text("Keep on screen")
                Spacer()
                HotKeyRecorderView(binding: $settings.pinHotKey)
            }
            Text("“Keep on screen” works while the panel is showing; it also lives in the strip’s right-click menu.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func enabledBinding(_ kind: StatKind) -> Binding<Bool> {
        Binding(get: { settings.isEnabled(kind) },
                set: { settings.setEnabled(kind, $0) })
    }

    // MARK: Custom-theme field bindings

    /// The custom payload to *read* for display, materializing the baseline when
    /// none exists yet. Read inside `body`, so Observation tracks `customTheme`.
    /// Mirrors the other sections' pattern: `Text` reads the value, the control
    /// takes the `Binding`.
    private var customData: ThemeData { settings.customTheme ?? .default }

    /// Bridges a single `ThemeData` field to a SwiftUI `Binding`.
    ///
    /// ⚠️ **Learning placeholder — currently read-only.** It returns the right
    /// *value* (so the controls show correct baselines), but edits don't persist
    /// because it's a `.constant`. Replace the body to make the knobs write back.
    ///
    /// What it must do:
    ///   • **read**  — `(settings.customTheme ?? .default)[keyPath: keyPath]`
    ///                 (fall back to the baseline when no custom theme exists yet)
    ///   • **write** — copy `settings.customTheme ?? .default`, set the field on the
    ///                 copy via `keyPath`, assign it back to `settings.customTheme`
    ///                 (its `didSet` then JSON-persists + rebuilds the live theme)
    ///
    /// The whole-struct write-back is deliberate: `customTheme` is one `@Observable`
    /// optional, so mutating a field means reassigning the property — that's what
    /// triggers persistence and the live panel rebuild.
    private func customBinding<T>(_ keyPath: WritableKeyPath<ThemeData, T>) -> Binding<T> {
        Binding(
            get: { (settings.customTheme ?? .default)[keyPath: keyPath] },
            set: { newValue in
                var data = settings.customTheme ?? .default
                data[keyPath: keyPath] = newValue
                settings.customTheme = data   // didSet → JSON persist + live rebuild
            }
        )
    }

    /// `ColorPicker` speaks `Color`; `ThemeData` stores `CodableColor` (sRGB
    /// round-trip). This composes the generic field binding across that boundary,
    /// so the color knobs reuse all of `customBinding`'s read/write logic.
    private func colorBinding(_ keyPath: WritableKeyPath<ThemeData, CodableColor>) -> Binding<Color> {
        let field = customBinding(keyPath)
        return Binding(get: { field.wrappedValue.color },
                       set: { field.wrappedValue = CodableColor($0) })
    }

    private func resetToDefaults() {
        settings.statOrder = StatKind.allCases
        settings.enabledStats = Set(StatKind.allCases)
        settings.interval = 1.0
        settings.anchor = .cursor
        settings.stripHeight = 36
        settings.hotKey = .default
        settings.pinHotKey = .defaultPin
        // Theme reset (the model-side reset deferred from 2.2): back to the stock
        // Default preset, and drop any custom payload so it doesn't linger on disk.
        settings.themePreset = .default
        settings.customTheme = nil
    }
}
