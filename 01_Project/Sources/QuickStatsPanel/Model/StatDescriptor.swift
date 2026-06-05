import Foundation

/// Stable identity for each stat the panel can show. Drives display order
/// (declaration order via `allCases`) and is the hook for a future "stat
/// selection" setting — users will enable/reorder these without touching views.
enum StatKind: String, CaseIterable, Identifiable, Sendable {
    case cpu, memory, disk, network, battery, loadAverage, uptime
    var id: String { rawValue }

    // NOTE: `.topProcess` was retired once top-process lists moved into the CPU /
    // Memory / Disk popovers (iStat-Menus style). A persisted "topProcess" in a
    // user's stored order/enabled set simply fails to decode and is dropped by the
    // `compactMap` in `AppSettings.init` — no explicit migration needed.

    /// Display name for the Settings stat list.
    var displayName: String {
        switch self {
        case .cpu:         return "CPU"
        case .memory:      return "Memory"
        case .disk:        return "Disk"
        case .network:     return "Network"
        case .battery:     return "Battery"
        case .loadAverage: return "Load Avg"
        case .uptime:      return "Uptime"
        }
    }

    /// A static representative SF Symbol for the Settings list (the strip itself
    /// may use a dynamic glyph, e.g. battery level/charging state).
    var settingsSymbol: String {
        switch self {
        case .cpu:         return "cpu"
        case .memory:      return "memorychip"
        case .disk:        return "internaldrive"
        case .network:     return "network"
        case .battery:     return "battery.100"
        case .loadAverage: return "speedometer"
        case .uptime:      return "clock"
        }
    }
}

/// A render-ready, UI-agnostic snapshot of one stat: everything `StatTileView`
/// needs, already formatted to strings. No SwiftUI types here — the view applies
/// `Theme.loadColor(forPercent:)` to `loadPercent` itself.
struct StatDescriptor: Identifiable {
    let kind: StatKind
    let symbol: String
    let value: String
    /// Worst-case value string reserving constant field width (Penumbra pattern).
    let widestValue: String
    let loadPercent: Double
    /// Popover rows: (label, value).
    let detail: [(String, String)]
    /// Optional iStat-Menus-style "top processes" list shown beneath `detail`.
    let processSection: ProcessSection?

    var id: String { kind.id }

    /// A ranked process list for a popover: a title plus pre-formatted rows.
    struct ProcessSection {
        let title: String
        let rows: [(String, String)]   // (process name, formatted value)
    }

    init(kind: StatKind, symbol: String, value: String, widestValue: String,
         loadPercent: Double, detail: [(String, String)],
         processSection: ProcessSection? = nil) {
        self.kind = kind
        self.symbol = symbol
        self.value = value
        self.widestValue = widestValue
        self.loadPercent = loadPercent
        self.detail = detail
        self.processSection = processSection
    }
}

extension StatsStore {
    /// The stats to render, in display order. Three filters compose at this single
    /// chokepoint — views stay untouched:
    ///   1. **Order** — the user's `statOrder` from Settings.
    ///   2. **Enabled** — only stats the user switched on (`enabledStats`).
    ///   3. **Availability** — `descriptor(for:)` returns nil for stats that don't
    ///      exist on this Mac (e.g. battery on a desktop).
    ///
    /// Read inside a SwiftUI body, so Observation tracks both the settings
    /// (`statOrder`/`enabledStats`) and the underlying sample access (`cpu`,
    /// `memory`, …) — the strip refreshes as values tick *and* as settings change.
    var visibleStats: [StatDescriptor] {
        let settings = AppSettings.shared
        return settings.statOrder
            .filter(settings.isEnabled)
            .compactMap(descriptor(for:))
    }

    /// Top-N count shown in each tile's "top processes" popover section.
    private static let topProcessRows = 5

    /// Build a process section, or nil when there's nothing to show yet (e.g.
    /// before the second tick has seeded CPU/disk rates) so the divider is hidden.
    private func section(_ title: String, _ rows: [(String, String)]) -> StatDescriptor.ProcessSection? {
        rows.isEmpty ? nil : StatDescriptor.ProcessSection(title: title, rows: rows)
    }

    private func descriptor(for kind: StatKind) -> StatDescriptor? {
        switch kind {
        case .cpu:
            return StatDescriptor(
                kind: .cpu, symbol: "cpu",
                value: "\(Int(cpu.totalUsagePercent.rounded()))%",
                widestValue: "100%",
                loadPercent: cpu.totalUsagePercent,
                detail: [
                    ("User", "\(Int(cpu.userPercent.rounded()))%"),
                    ("System", "\(Int(cpu.systemPercent.rounded()))%"),
                    ("Idle", "\(Int(cpu.idlePercent.rounded()))%"),
                ],
                processSection: section("Top by CPU",
                                        topProcesses.cpuRows(Self.topProcessRows)))

        case .memory:
            return StatDescriptor(
                kind: .memory, symbol: "memorychip",
                value: memory.usedFormatted,
                widestValue: "888,88 GB",
                loadPercent: memory.pressurePercent,
                detail: [
                    ("Used", memory.usedFormatted),
                    ("Total", memory.totalFormatted),
                    ("Pressure", "\(Int(memory.pressurePercent.rounded()))%"),
                ],
                processSection: section("Top by memory",
                                        topProcesses.memoryRows(Self.topProcessRows)))

        case .disk:
            return StatDescriptor(
                kind: .disk, symbol: "internaldrive",
                value: disk.freeFormatted,             // headline: free space
                widestValue: "888,88 GB",
                loadPercent: disk.usedPercent,         // color: fuller = hotter
                detail: [
                    ("Used", disk.usedFormatted),
                    ("Free", disk.freeFormatted),
                    ("Total", disk.totalFormatted),
                    ("Read", disk.readFormatted),       // live I/O throughput
                    ("Write", disk.writeFormatted),
                ],
                processSection: section("Top by disk I/O",
                                        topProcesses.diskRows(Self.topProcessRows)))

        case .network:
            return StatDescriptor(
                kind: .network, symbol: "network",
                value: network.downFormatted,          // headline: download rate
                widestValue: "888 MB/s",
                loadPercent: network.activityPercent,  // color: busier link = hotter
                detail: [
                    ("Down", network.downFormatted),
                    ("Up", network.upFormatted),
                ])

        case .battery:
            // Portables only — IOKit reports no source on desktop Macs.
            guard battery.isPresent else { return nil }
            return StatDescriptor(
                kind: .battery, symbol: battery.symbolName,  // level/charging-aware glyph
                value: battery.percentFormatted,             // headline: charge %
                widestValue: "100%",
                loadPercent: battery.loadPercent,             // inverted: low charge = hot
                detail: [
                    ("Charge", battery.percentFormatted),
                    ("State", battery.stateLabel),
                    ("Time", battery.timeFormatted),
                ])

        case .loadAverage:
            return StatDescriptor(
                kind: .loadAverage, symbol: "speedometer",
                value: loadAverage.oneFormatted,        // headline: 1-min load
                widestValue: "88.88",
                loadPercent: loadAverage.saturationPercent,  // color: load ÷ cores
                detail: [
                    ("1 min", loadAverage.oneFormatted),
                    ("5 min", loadAverage.fiveFormatted),
                    ("15 min", loadAverage.fifteenFormatted),
                    ("Cores", "\(ProcessInfo.processInfo.activeProcessorCount)"),
                ])

        case .uptime:
            return StatDescriptor(
                kind: .uptime, symbol: "clock",
                value: uptime.compactFormatted,         // headline: "3d 4h"
                widestValue: "88d 88h",
                loadPercent: 0,                          // no "load" — always calm tint
                detail: [
                    ("Uptime", uptime.compactFormatted),
                    ("Booted", uptime.bootDateFormatted),
                ])
        }
    }
}
