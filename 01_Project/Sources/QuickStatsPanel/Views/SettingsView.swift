import SwiftUI
import AppKit
import ServiceManagement

/// The real settings surface, shown in the self-managed Settings window (opened
/// from the panel's gear). A sidebar (`NavigationSplitView`) splits the old single
/// scrolling form into focused panes — Stats / Appearance / Panel / Hotkeys /
/// About — matching the sibling HUD app's house style.
///
/// Every pane edits `AppSettings.shared` directly; persistence and side-effects
/// (hotkey re-register, sampler restart, live theme rebuild) happen in the model's
/// `didSet` hooks, so the views stay declarative.
struct SettingsView: View {
    // Single-select `List` wants an optional binding (macOS); default to the first
    // pane and coalesce nil → .stats in `detail` so a pane is always shown.
    @State private var selection: SettingsPane? = .stats

    var body: some View {
        NavigationSplitView {
            // `id: \.self` makes each row's selection tag the *element* (SettingsPane),
            // matching the `SettingsPane?` binding — without it, List tags rows with the
            // Identifiable id (String) and selection never updates. Sidebar-toggle is
            // removed so the nav can't be collapsed away inside a small settings window.
            List(SettingsPane.allCases, id: \.self, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
            }
            .navigationSplitViewColumnWidth(180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            // NavigationSplitView fills its container, so the detail carries the size
            // floor (the window controller sets the default + min window size to match).
            detail
                .frame(minWidth: 380, minHeight: 420)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .stats {
        case .stats:      StatsSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .panel:      PanelSettingsPane()
        case .hotkeys:    HotkeySettingsPane()
        case .about:      AboutSettingsPane()
        }
    }
}

/// Which Settings pane the sidebar shows. Declaration order = sidebar order.
private enum SettingsPane: String, CaseIterable, Identifiable {
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
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        // A bare List that *fills* the pane (not a fixed-height List nested in a
        // grouped Form) — one natural scroll container, so the list scrolls only when
        // the stats overflow rather than the whole pane gaining a spurious scrollbar.
        // Order here = strip order. Drag to reorder; toggle to show/hide. Unavailable
        // stats (e.g. battery on a desktop) stay listed but won't appear in the strip —
        // availability is filtered in `visibleStats`.
        VStack(spacing: 0) {
            List {
                ForEach(settings.statOrder) { kind in
                    // Checkbox and label are SEPARATE views: when the Toggle owned
                    // the whole row (label included), every point in the row was an
                    // interactive control, and under macOS 26 the control wins the
                    // mouse-down — .onMove's per-row drag recognizer never fires and
                    // reorders silently stop committing to `statOrder`. With the
                    // label inert, it (plus the spacer) initiates the row drag; only
                    // the checkbox itself toggles. (Trade-off: clicking the row text
                    // no longer flips the toggle — it drags instead.)
                    HStack(spacing: 8) {
                        Toggle("", isOn: enabledBinding(kind))
                            .labelsHidden()
                        Label(kind.displayName, systemImage: kind.settingsSymbol)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .onMove { settings.statOrder.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset)

            Divider()
            Text("Drag to reorder · toggle to show or hide")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private func enabledBinding(_ kind: StatKind) -> Binding<Bool> {
        Binding(get: { settings.isEnabled(kind) },
                set: { settings.setEnabled(kind, $0) })
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
                Text("Version \(version)")
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
