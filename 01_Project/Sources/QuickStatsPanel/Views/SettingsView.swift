import SwiftUI
import AppKit
import ServiceManagement

/// Shared navigation between the native toolbar and SwiftUI pane content.
@Observable
final class SettingsNavigation {
    var pane: SettingsPane = .stats
    var stat: StatKind? = .cpu
}

/// Settings continue to edit AppSettings directly; only navigation and layout
/// live here. The window controller owns the native category toolbar.
struct SettingsView: View {
    let store: StatsStore
    let navigation: SettingsNavigation

    var body: some View {
        detail
            .frame(minWidth: 660, minHeight: 420)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.pane {
        case .stats:      StatsSettingsPane(store: store, navigation: navigation)
        case .appearance: AppearanceSettingsPane()
        case .panel:      PanelSettingsPane()
        case .hotkeys:    HotkeySettingsPane()
        case .about:      AboutSettingsPane()
        }
    }
}

/// Declaration order matches the native settings toolbar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case stats, appearance, panel, hotkeys, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .stats:      return "Stats"
        case .appearance: return "Appearance"
        case .panel:      return "Panel"
        case .hotkeys:    return "Hotkeys"
        case .about:      return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .stats:      return "square.grid.2x2"
        case .appearance: return "paintbrush"
        case .panel:      return "macwindow"
        case .hotkeys:    return "keyboard"
        case .about:      return "info.circle"
        }
    }
}

// MARK: - Stats (toggle + drag-to-reorder)

private struct StatsSettingsPane: View {
    let store: StatsStore
    @Bindable private var settings = AppSettings.shared

    @Bindable var navigation: SettingsNavigation

    var body: some View {
        // The list keeps its own scroll container (see the D-020 note about a bare
        // List filling the pane); the per-stat options sit beside it rather than
        // inside the row. A second control *in* the row would re-enter exactly the
        // macOS 26 conflict D-024 fixed — an interactive control wins the
        // mouse-down and .onMove's drag recognizer never fires — so the options
        // deliberately live outside the drag surface.
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statList
                    .frame(width: 190)
                Divider()
                optionsPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            Text("Drag to reorder · select a stat to configure")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    /// Order here = strip order. Unavailable stats (e.g. battery on a desktop)
    /// stay listed but won't appear in the strip — availability is filtered in
    /// `visibleStats`.
    private var statList: some View {
        // `id: \.self` so each row's selection tag is the StatKind itself and not
        // its String id — the same trap the sidebar hit in D-020, where tagging by
        // Identifiable id meant the selection binding never updated.
        List(selection: $navigation.stat) {
            ForEach(settings.statOrder, id: \.self) { kind in
                // Checkbox and label are SEPARATE views: when the Toggle owned
                // the whole row (label included), every point in the row was an
                // interactive control, and under macOS 26 the control wins the
                // mouse-down — .onMove's per-row drag recognizer never fires and
                // reorders silently stop committing to `statOrder`. With the
                // label inert, it (plus the spacer) initiates the row drag; only
                // the checkbox itself toggles. (Trade-off: clicking the row text
                // no longer flips the toggle — it drags instead.)
                HStack(spacing: 8) {
                    MetricOptionCheckbox(title: "", isOn: enabledBinding(kind))
                        .frame(width: 18, height: 22)
                        .accessibilityLabel("Show \(kind.displayName)")
                    Label(kind.displayName, systemImage: kind.settingsSymbol)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .onMove { settings.statOrder.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.inset)
    }

    /// Per-stat display options (D-025): **which** value the tile headlines and
    /// **how** it is drawn — two orthogonal settings, matching how both reference
    /// products model this rather than one flat combined enum.
    @ViewBuilder
    private var optionsPane: some View {
        if let kind = navigation.stat {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(kind.displayName).font(.title2.weight(.semibold))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Strip").font(.headline)
                        stripOptions(for: kind)
                        if kind.supportsGraph {
                            optionRow("Display") {
                                MetricOptionPopup(items: TileStyle.allCases,
                                                  titleForItem: { $0.displayName },
                                                  selection: styleBinding(kind),
                                                  accessibilityLabel: "Strip display")
                            }
                            helpText("The detail card always shows the graph.")
                        }
                    }

                    let rows = store.detailRowOptions(for: kind)
                    if !rows.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Detail card rows").font(.headline)
                            // Short fixed labels fit in two columns. Hardware names
                            // can be long, so fan/sensor rows use the full width.
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                                     count: kind == .temps || kind == .fan ? 1 : 2),
                                      alignment: .leading, spacing: 6) {
                                ForEach(rows, id: \.self) { label in
                                    MetricOptionCheckbox(title: label,
                                                         isOn: detailRowBinding(kind, label))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(height: 24)
                                }
                            }
                            helpText("Unavailable hardware readings stay hidden.")
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(kind) // Start each newly selected stat at the top of its options.
        } else {
            Text("Select a stat")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func stripOptions(for kind: StatKind) -> some View {
        switch kind {
        case .power:
            optionRow("Panel value") {
                MetricOptionPopup(items: PowerDisplayMode.allCases,
                                  titleForItem: { $0.displayName },
                                  selection: $settings.powerDisplayMode)
            }
            helpText("System is whole-machine power. Chip total adds CPU, GPU, Neural Engine and DRAM. Charger input can also supply battery charging. Unavailable readings appear as —.")
            helpText("Power color reflects chip activity relative to its peak since sampling started.")
        case .temps:
            optionRow("Panel value") {
                MetricOptionPopup(items: TemperatureDisplayMode.allCases,
                                  titleForItem: { $0.displayName },
                                  selection: $settings.temperatureDisplayMode)
            }
            optionRow("Unit") {
                MetricOptionPopup(items: TemperatureUnit.allCases,
                                  titleForItem: { $0.displayName },
                                  selection: $settings.temperatureUnit,
                                  accessibilityLabel: "Temperature unit")
            }
            helpText("The unit applies to all temperature readings, including CPU, GPU and Battery detail cards. Unavailable sensor readings appear as —.")
            helpText("Temperature color reflects macOS thermal status, regardless of the panel value.")
        case .disk:
            optionRow("Panel value") {
                MetricOptionPopup(items: DiskDisplayMode.allCases,
                                  titleForItem: { $0.displayName },
                                  selection: $settings.diskDisplayMode)
            }
            helpText("Activity shows live read/write speeds. The graph always shows activity; disk color reflects used capacity.")
        case .loadAverage:
            optionRow("Panel value") {
                MetricOptionPopup(items: LoadDisplayMode.allCases,
                                  titleForItem: { $0.displayName },
                                  selection: $settings.loadDisplayMode)
            }
            helpText("Load is runnable work averaged over 1, 5 or 15 minutes, not CPU usage %. Comparing load with the core count gives a rough guide to CPU demand.")
        default:
            EmptyView()
        }

        if let pair = valuePair(for: kind) {
            optionRow("Value") {
                MetricOptionPopup(items: TileValueMode.allCases,
                                  titleForItem: { $0.displayName(pair: pair) },
                                  selection: valueModeBinding(kind),
                                  accessibilityLabel: "Value")
            }
        }
        if kind.valuePair == nil && !kind.supportsGraph
            && kind != .power && kind != .temps && kind != .loadAverage {
            helpText("This stat has a single strip value.")
        }
    }

    private func optionRow<Control: View>(_ title: String,
                                          @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 90, alignment: .leading)
            control().frame(maxWidth: .infinity).frame(height: 24)
        }
    }

    private func helpText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func valuePair(for kind: StatKind) -> (first: String, second: String)? {
        if kind == .disk && settings.diskDisplayMode == .activity {
            return ("Read", "Write")
        }
        return kind.valuePair
    }

    private func enabledBinding(_ kind: StatKind) -> Binding<Bool> {
        Binding(get: { settings.isEnabled(kind) },
                set: { settings.setEnabled(kind, $0) })
    }

    private func valueModeBinding(_ kind: StatKind) -> Binding<TileValueMode> {
        Binding(get: { settings.valueMode(kind) },
                set: { settings.setValueMode(kind, $0) })
    }

    private func styleBinding(_ kind: StatKind) -> Binding<TileStyle> {
        Binding(get: { settings.style(kind) },
                set: { settings.setStyle(kind, $0) })
    }

    private func detailRowBinding(_ kind: StatKind, _ label: String) -> Binding<Bool> {
        Binding(get: { settings.isDetailRowVisible(kind, label) },
                set: { settings.setDetailRowVisible(kind, label, $0) })
    }
}

// MARK: - Appearance (theme preset + custom)

private struct AppearanceSettingsPane: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            // Theme selection. Picking a preset rebuilds `AppSettings.theme` in its
            // `didSet`; the panels read `theme` in their `body`, so the switch is live
            // (AC-1) with no glue here. `.custom` reveals the Customize editor below.
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
        .formStyle(.grouped)
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

    // MARK: Custom-theme field bindings

    /// The custom payload to *read* for display, materializing the baseline when
    /// none exists yet. Read inside `body`, so Observation tracks `customTheme`.
    private var customData: ThemeData { settings.customTheme ?? .default }

    /// Bridges a single `ThemeData` field to a SwiftUI `Binding`.
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
    /// round-trip). Composes the generic field binding across that boundary so the
    /// color knobs reuse all of `customBinding`'s read/write logic.
    private func colorBinding(_ keyPath: WritableKeyPath<ThemeData, CodableColor>) -> Binding<Color> {
        let field = customBinding(keyPath)
        return Binding(get: { field.wrappedValue.color },
                       set: { field.wrappedValue = CodableColor($0) })
    }
}

// MARK: - Panel (sampling cadence + placement & size)

private struct PanelSettingsPane: View {
    @Bindable private var settings = AppSettings.shared

    /// Mirrors the login-item registration for the toggle. **Not** persisted in
    /// `AppSettings` — the OS's `SMAppService.mainApp.status` is the single source of
    /// truth, so this is a view-local reflection of it, re-read on `.onAppear` so the
    /// switch can never silently disagree with the real registry state.
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }
                Text("Starts QuickStatsPanel in the background when you log in, ready for the hotkey.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // Reconcile the toggle with the real registration state whenever the pane
            // appears, so a failed register/unregister — or a change made in System
            // Settings ▸ General ▸ Login Items — is reflected instead of a stale switch.
            .onAppear { launchAtLogin = (SMAppService.mainApp.status == .enabled) }

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

            Section("Placement") {
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
        .formStyle(.grouped)
    }

    /// Register or unregister the app as a macOS login item.
    ///
    /// Because the app is **non-sandboxed** (see `QuickStatsPanel.entitlements`),
    /// `SMAppService.mainApp` enrols the main bundle itself — no separate login-helper
    /// target. `register()` / `unregister()` are `throws`.
    ///
    /// Design notes / trade-offs to weigh in the body:
    ///  • Idempotency — calling `register()` when `.status` is already `.enabled`
    ///    throws. Guard on the current `.status` before acting, or let it throw and
    ///    swallow it? (macOS may also report `.requiresApproval` if the user disabled
    ///    the item in System Settings.)
    ///  • Failure honesty — if the call throws, the OS state didn't change but
    ///    `launchAtLogin` already flipped to `newValue`. Re-sync it to the *real*
    ///    `SMAppService.mainApp.status == .enabled` so the switch can't lie.
    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                // Guard so a redundant register() (item already enabled) can't throw.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // The OS call failed, but the toggle already flipped to `enabled`. Re-sync
            // it to the real registry state so the switch reflects reality, not intent.
            NSLog("Launch at login: failed to \(enabled ? "register" : "unregister"): \(error)")
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}

// MARK: - Hotkeys

private struct HotkeySettingsPane: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
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
        .formStyle(.grouped)
    }
}

// MARK: - About (identity + global actions)

private struct AboutSettingsPane: View {
    @Bindable private var settings = AppSettings.shared
    @State private var confirmingReset = false

    /// Marketing version from the bundle (`MARKETING_VERSION` in project.yml).
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Monotonic release identifier used by the future update feed.
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            // The bundled AppIcon — valid even for an LSUIElement agent app, which
            // has no Dock icon but still ships an icon in its bundle.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 2) {
                Text("QuickStatsPanel")
                    .font(.title2).bold()
                Text("Version \(version) (build \(build))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Text("A glanceable HUD of live Mac stats, summoned with a hotkey.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.horizontal, 40)

            VStack(spacing: 10) {
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Text("Reset to Defaults").frame(maxWidth: 220)
                }
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit QuickStatsPanel").frame(maxWidth: 220)
                }
            }
            .controlSize(.large)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A wipe of every preference deserves a confirm — there's no undo.
        .confirmationDialog("Reset all settings to defaults?",
                            isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive, action: resetToDefaults)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stats, theme, panel placement, and hotkeys all return to their original values.")
        }
    }

    private func resetToDefaults() {
        settings.statOrder = StatKind.allCases
        settings.enabledStats = Set(StatKind.allCases)
        settings.tileValueModes = [:]
        settings.tileStyles = [:]
        settings.powerDisplayMode = .system
        settings.loadDisplayMode = .oneMinute
        settings.temperatureDisplayMode = .status
        settings.temperatureUnit = .celsius
        settings.diskDisplayMode = .capacity
        settings.hiddenDetailRows = [:]
        settings.interval = 1.0
        settings.anchor = .cursor
        settings.stripHeight = 36
        settings.hotKey = .default
        settings.pinHotKey = .defaultPin
        // Theme reset: back to the stock Default preset, and drop any custom payload
        // so it doesn't linger on disk.
        settings.themePreset = .default
        settings.customTheme = nil
    }
}
