import Foundation
import SwiftUI

/// Stable identity for each stat the panel can show. Drives display order
/// (declaration order via `allCases`) and is the hook for a future "stat
/// selection" setting — users will enable/reorder these without touching views.
enum StatKind: String, CaseIterable, Identifiable, Sendable {
    case cpu, memory, disk, network, battery, gpu, fan, power, temps, loadAverage, uptime
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
        case .gpu:         return "GPU"
        case .fan:         return "Fans"
        case .power:       return "Power"
        case .temps:       return "Temperature"
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
        case .gpu:         return "cpu.fill"   // "other processor"; kept over cube/display in design pass (2026-07-03)
        case .fan:         return "fanblades"
        case .power:       return "bolt.fill"  // confirmed watts glyph, design pass 2026-07-03
        case .temps:       return "thermometer"
        case .loadAverage: return "speedometer"
        case .uptime:      return "clock"
        }
    }
}

/// A render-ready snapshot of one stat: everything `StatTileView` needs, already
/// formatted. The status **band** and its themed **tint** are resolved centrally
/// in `visibleStats` (with hysteresis), so the tile never computes color itself.
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

    /// Status band for this reading, resolved in `visibleStats` with hysteresis.
    /// Drives the non-color severity cue (font-weight ramp) so "hot" is legible in
    /// Mono / greyscale (AC-5). Defaults to `.calm` until the store fills it in.
    var band: Band = .calm
    /// The themed color for `band` (status hue, or neutral under Mono). Set by the
    /// store; `.primary` is a safe placeholder that `visibleStats` always overwrites.
    var tint: Color = .primary

    var id: String { kind.id }

    /// A ranked process list for a popover: a title plus pre-formatted rows.
    struct ProcessSection {
        let title: String
        let rows: [(String, String)]   // (process name, formatted value)
        /// Constant slot count the view reserves height for, so the popover never
        /// resizes as the active-app count varies tick-to-tick (rate lists like CPU
        /// fluctuate). Cookbook 67's "reserve worst-case" pattern, applied to height.
        let reservedRows: Int
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
            .map { desc in
                // Resolve the status band + themed tint once, here — the single
                // chokepoint. Battery is the only "less = worse" metric, so it
                // resolves reversed (low charge → hot). `tint(for:…)` reads the
                // live theme, so a preset switch recolors on the next body pass.
                var d = desc
                let resolved = tint(for: desc.kind,
                                    percent: desc.loadPercent,
                                    reversed: desc.kind == .battery)
                d.band = resolved.band
                d.tint = resolved.color
                return d
            }
    }

    /// Top-N count shown in each tile's "top processes" popover section.
    private static let topProcessRows = 10

    /// Build a process section, or nil when there's nothing to show yet (e.g.
    /// before the second tick has seeded CPU/disk rates) so the divider is hidden.
    private func section(_ title: String, _ rows: [(String, String)]) -> StatDescriptor.ProcessSection? {
        rows.isEmpty ? nil : StatDescriptor.ProcessSection(title: title, rows: rows,
                                                           reservedRows: Self.topProcessRows)
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
                ])
                // No per-process "Top by disk I/O": `top` has no per-process disk
                // column, and the entitled API behind Activity Monitor's Disk tab
                // isn't available to us. Disk shows aggregate Read/Write only.

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

        case .gpu:
            // Hidden when no IOAccelerator exposes a utilization key (VM / headless),
            // mirroring battery's desktop gate.
            guard gpu.isAvailable else { return nil }
            var detail: [(String, String)] = [("Utilization", gpu.percentFormatted)]
            if let name = gpu.deviceName { detail.append(("Device", name)) }
            return StatDescriptor(
                kind: .gpu, symbol: "cpu.fill",         // kept in design pass 2026-07-03 (see settingsSymbol)
                value: gpu.percentFormatted,            // headline: GPU load %
                widestValue: "100%",
                loadPercent: gpu.utilizationPercent,    // color: busier = hotter
                detail: detail)

        case .fan:
            // Hidden on fanless Macs (FNum == 0) or SMC read failure.
            guard fan.hasFans else { return nil }
            let multi = fan.fans.count > 1
            let detail: [(String, String)] = fan.fans.enumerated().map { i, f in
                let label = multi ? "Fan \(i + 1)" : "Fan"
                let rpm = Int(f.current.rounded())
                let lo = Int(f.min.rounded()), hi = Int(f.max.rounded())
                return (label, "\(rpm) rpm (\(lo)–\(hi))")
            }
            return StatDescriptor(
                kind: .fan, symbol: "fanblades",
                value: fan.headlineFormatted,           // headline: fastest fan rpm
                widestValue: "8888 rpm",
                loadPercent: fan.loadPercent,           // color: near full tilt = hot
                detail: detail)

        case .power:
            // Hidden when the IOReport "Energy Model" CPU/GPU channels don't resolve
            // (Intel Macs / renamed future chips), mirroring Battery/GPU/Fan's gate.
            guard power.isAvailable else { return nil }
            return StatDescriptor(
                kind: .power, symbol: "bolt.fill",
                value: power.headlineFormatted,         // headline: "cpu·gpu W" split
                widestValue: "88·88 W",                 // worst-case slot (D-008); Ultra GPU >99W clips, acceptable
                loadPercent: power.loadPercent,         // color: total ÷ session-peak (set by the sampler)
                detail: [
                    ("CPU", power.cpuFormatted),
                    ("GPU", power.gpuFormatted),
                    ("ANE", power.aneFormatted),
                    ("DRAM", power.dramFormatted),
                    ("Total", power.totalFormatted),
                ])

        case .temps:
            // Always visible — the headline is ProcessInfo.thermalState, which
            // never fails (D-018), so there is deliberately NO `guard`. This is the
            // project's first always-on optional tile. The detail card degrades to a
            // `Pressure: <state>` row when IOHID enumerates no sensors (Intel / VM).
            return StatDescriptor(
                kind: .temps, symbol: "thermometer",
                value: temps.headlineFormatted,     // headline: thermal-pressure word
                widestValue: "Critical",            // widest state word — no jitter (AC-6)
                loadPercent: temps.loadPercent,     // color/weight: calm→hot via state
                detail: temps.detailRows)

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
