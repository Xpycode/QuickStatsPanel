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
    /// Optional second value section (e.g. Network's upload beside its download).
    /// Gets its own worst-case slot in the tile so the two sections never shift
    /// against each other as digit counts change tick-to-tick.
    let secondaryValue: String?
    let widestSecondaryValue: String?
    let loadPercent: Double
    /// Popover rows: (label, value).
    let detail: [(String, String)]
    /// Optional iStat-Menus-style "top processes" list shown beneath `detail`.
    let processSection: ProcessSection?
    /// Activity history for this stat, already scaled (D-025). `nil` for stats
    /// that keep no history — a graph of free disk space is a flat line.
    let graph: GraphData?

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
         secondaryValue: String? = nil, widestSecondaryValue: String? = nil,
         loadPercent: Double, detail: [(String, String)],
         processSection: ProcessSection? = nil,
         graph: GraphData? = nil) {
        self.graph = graph
        self.kind = kind
        self.symbol = symbol
        self.value = value
        self.widestValue = widestValue
        self.secondaryValue = secondaryValue
        self.widestSecondaryValue = widestSecondaryValue
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

    // MARK: - Value mode (D-025)

    /// Resolve a stat's two candidate values against the user's chosen mode into
    /// the primary/secondary slots `StatTileView` renders.
    ///
    /// Markers ("U", "F", "↓") appear **only** in the combined modes: with two
    /// numbers side by side "16,85 GB  617,24 GB" is ambiguous, while a lone value
    /// is unambiguous by construction — so single-value modes stay exactly as
    /// narrow as they are today.
    private func resolved(_ kind: StatKind, _ first: TileValue, _ second: TileValue)
    -> (value: String, widest: String, secondary: String?, widestSecondary: String?) {
        let mode = AppSettings.shared.valueMode(kind)
        let combined = mode.isCombined
        switch mode {
        case .both:
            return (first.rendered(combined: combined), first.renderedWidest(combined: combined),
                    second.rendered(combined: combined), second.renderedWidest(combined: combined))
        case .bothReversed:
            return (second.rendered(combined: combined), second.renderedWidest(combined: combined),
                    first.rendered(combined: combined), first.renderedWidest(combined: combined))
        case .first:
            return (first.rendered(combined: false), first.renderedWidest(combined: false), nil, nil)
        case .second:
            return (second.rendered(combined: false), second.renderedWidest(combined: false), nil, nil)
        }
    }

    // MARK: - Graph construction (D-025)

    /// A percentage series against the implicit 0–100 ceiling. No legend peak —
    /// printing "Peak 100%" would state the axis, not a measurement.
    private func percentSeries(_ values: [Double], label: String) -> GraphSeries {
        GraphSeries(values: values, label: label, marker: "",
                    peak: 100, peakFormatted: nil)
    }

    /// A byte-rate series normalized to its own rolling peak, which the legend
    /// then prints. Each series gets its own peak: on a link doing 34 MB/s down
    /// and 124 KB/s up, a shared scale would flatten the upload series into the
    /// baseline and show nothing at all.
    private func rateSeries(_ values: [Double], kind: StatKind, key: String,
                            label: String, marker: String) -> GraphSeries {
        let windowMax = values.max() ?? 0
        let peak = graphPeak(kind, series: key, windowMax: windowMax)
        return GraphSeries(values: values, label: label, marker: marker,
                           peak: peak, peakFormatted: NetworkSample.rate(peak))
    }

    private func descriptor(for kind: StatKind) -> StatDescriptor? {
        switch kind {
        case .cpu:
            var cpuDetail: [(String, String)] = [
                ("User", "\(Int(cpu.userPercent.rounded()))%"),
                ("System", "\(Int(cpu.systemPercent.rounded()))%"),
                ("Idle", "\(Int(cpu.idlePercent.rounded()))%"),
            ]
            // Cross-tile touch (2026-07-12): surface this die's CPU temperature
            // right where the load is read. Fed by the temps sample's per-role
            // SMC/IOHID merge; absent (Intel/VM) ⇒ no row.
            if let t = temps.sensors.first(where: { $0.label == "CPU" }) {
                cpuDetail.append(("Temp", String(format: "%.0f°C", t.celsius)))
            }
            return StatDescriptor(
                kind: .cpu, symbol: "cpu",
                value: "\(Int(cpu.totalUsagePercent.rounded()))%",
                widestValue: "100%",
                loadPercent: cpu.totalUsagePercent,
                detail: cpuDetail,
                processSection: section("Top by CPU",
                                        topProcesses.cpuRows(Self.topProcessRows)),
                graph: GraphData(
                    upper: percentSeries(cpuHistory.elements.map(\.totalUsagePercent),
                                         label: "CPU"),
                    lower: nil))

        case .memory:
            let mem = resolved(.memory,
                               TileValue(label: "Used", marker: "U",
                                         text: memory.usedFormatted, widest: "888,88 GB"),
                               TileValue(label: "Free", marker: "F",
                                         text: memory.freeFormatted, widest: "888,88 GB"))
            // Plot used *as a share of total*, matching the headline. Pressure has
            // its own detail row and a different meaning — a Mac can sit at 90%
            // used with low pressure, so graphing pressure under a "Used" headline
            // would draw a line that contradicts the number above it.
            let memoryUsage = memoryHistory.elements.map { sample -> Double in
                sample.totalBytes > 0
                    ? Double(sample.usedBytes) / Double(sample.totalBytes) * 100
                    : 0
            }
            return StatDescriptor(
                kind: .memory, symbol: "memorychip",
                value: mem.value,
                widestValue: mem.widest,
                secondaryValue: mem.secondary,
                widestSecondaryValue: mem.widestSecondary,
                loadPercent: memory.pressurePercent,
                detail: [
                    ("Used", memory.usedFormatted),
                    ("Free", memory.freeFormatted),
                    ("App", memory.appFormatted),
                    ("Wired", memory.wiredFormatted),
                    ("Compressed", memory.compressedFormatted),
                    ("Total", memory.totalFormatted),
                    ("Pressure", "\(Int(memory.pressurePercent.rounded()))%"),
                ],
                processSection: section("Top by memory",
                                        topProcesses.memoryRows(Self.topProcessRows)),
                graph: GraphData(upper: percentSeries(memoryUsage, label: "Used"),
                                 lower: nil))

        case .disk:
            let dsk = resolved(.disk,
                               TileValue(label: "Free", marker: "F",
                                         text: disk.freeFormatted, widest: "888,88 GB"),
                               TileValue(label: "Used", marker: "U",
                                         text: disk.usedFormatted, widest: "888,88 GB"))
            // The graph plots **I/O throughput**, not capacity: capacity moves in
            // gigabytes per hour and would draw a flat line at this timescale.
            // Read above the baseline, Write below — matching iStat's arrangement.
            let diskSamples = diskHistory.elements
            return StatDescriptor(
                kind: .disk, symbol: "internaldrive",
                value: dsk.value,
                widestValue: dsk.widest,
                secondaryValue: dsk.secondary,
                widestSecondaryValue: dsk.widestSecondary,
                loadPercent: disk.usedPercent,         // color: fuller = hotter
                detail: [
                    ("Used", disk.usedFormatted),
                    ("Free", disk.freeFormatted),
                    ("Total", disk.totalFormatted),
                    ("Read", disk.readFormatted),       // live I/O throughput
                    ("Write", disk.writeFormatted),
                ],
                graph: GraphData(
                    upper: rateSeries(diskSamples.map(\.readBytesPerSec),
                                      kind: .disk, key: "read",
                                      label: "Read", marker: "R"),
                    lower: rateSeries(diskSamples.map(\.writeBytesPerSec),
                                      kind: .disk, key: "write",
                                      label: "Write", marker: "W")))
                // No per-process "Top by disk I/O": `top` has no per-process disk
                // column, and the entitled API behind Activity Monitor's Disk tab
                // isn't available to us. Disk shows aggregate Read/Write only.

        case .network:
            var networkDetail: [(String, String)] = [
                ("Down", network.downFormatted),
                ("Up", network.upFormatted),
            ]
            // Which pipe is carrying this, and where we are on it (2026-07-12).
            // No public IP by design — that would need an external request.
            if let name = network.interfaceName { networkDetail.append(("Interface", name)) }
            if let ip = network.localIP { networkDetail.append(("Local IP", ip)) }
            // Network shipped showing both directions, so its markers are the
            // arrows it already used — `.both` here reproduces the current strip
            // byte for byte, and the other modes trade a direction for width.
            let net = resolved(.network,
                               TileValue(label: "Down", marker: "↓",
                                         text: network.downFormatted, widest: "888 MB/s"),
                               TileValue(label: "Up", marker: "↑",
                                         text: network.upFormatted, widest: "888 MB/s"))
            let netSamples = networkHistory.elements
            return StatDescriptor(
                kind: .network, symbol: "network",
                value: net.value,
                widestValue: net.widest,
                secondaryValue: net.secondary,
                widestSecondaryValue: net.widestSecondary,
                loadPercent: network.activityPercent,  // color: busier link = hotter
                detail: networkDetail,
                graph: GraphData(
                    upper: rateSeries(netSamples.map(\.upBytesPerSec),
                                      kind: .network, key: "up",
                                      label: "Up", marker: "↑"),
                    lower: rateSeries(netSamples.map(\.downBytesPerSec),
                                      kind: .network, key: "down",
                                      label: "Down", marker: "↓")))

        case .battery:
            // Portables only — IOKit reports no source on desktop Macs.
            guard battery.isPresent else { return nil }
            var batteryDetail: [(String, String)] = [
                ("Charge", battery.percentFormatted),
                ("State", battery.stateLabel),
                ("Time", battery.timeFormatted),
            ]
            // Longevity rows from AppleSmartBattery (2026-07-12) — the numbers
            // System Settings' Battery Health panel shows. Hidden when unreadable.
            if let health = battery.healthFormatted { batteryDetail.append(("Health", health)) }
            if let cycles = battery.cyclesFormatted { batteryDetail.append(("Cycles", cycles)) }
            if let temp = battery.temperatureFormatted { batteryDetail.append(("Temp", temp)) }
            return StatDescriptor(
                kind: .battery, symbol: battery.symbolName,  // level/charging-aware glyph
                value: battery.percentFormatted,             // headline: charge %
                widestValue: "100%",
                loadPercent: battery.loadPercent,             // inverted: low charge = hot
                detail: batteryDetail)

        case .gpu:
            // Hidden when no IOAccelerator exposes a utilization key (VM / headless),
            // mirroring battery's desktop gate.
            guard gpu.isAvailable else { return nil }
            var detail: [(String, String)] = [("Utilization", gpu.percentFormatted)]
            if let name = gpu.deviceName { detail.append(("Device", name)) }
            // Same cross-tile temperature touch as the CPU card (2026-07-12).
            if let t = temps.sensors.first(where: { $0.label == "GPU" }) {
                detail.append(("Temp", String(format: "%.0f°C", t.celsius)))
            }
            return StatDescriptor(
                kind: .gpu, symbol: "cpu.fill",         // kept in design pass 2026-07-03 (see settingsSymbol)
                value: gpu.percentFormatted,            // headline: GPU load %
                widestValue: "100%",
                loadPercent: gpu.utilizationPercent,    // color: busier = hotter
                detail: detail,
                graph: GraphData(
                    upper: percentSeries(gpuHistory.elements.map(\.utilizationPercent),
                                         label: "GPU"),
                    lower: nil))

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
            // Whole-machine context after the SoC split: "System" = everything the
            // Mac draws (display, SSD, …) via SMC PSTR; "DC In" = charger input via
            // PDTR. Rows absent when this Mac lacks the keys (nil-formatted).
            var powerDetail: [(String, String)] = [
                ("CPU", power.cpuFormatted),
                ("GPU", power.gpuFormatted),
                ("ANE", power.aneFormatted),
                ("DRAM", power.dramFormatted),
                ("Total", power.totalFormatted),
            ]
            if let system = power.systemFormatted { powerDetail.append(("System", system)) }
            if let dcIn = power.dcInFormatted { powerDetail.append(("DC In", dcIn)) }
            return StatDescriptor(
                kind: .power, symbol: "bolt.fill",
                value: power.headlineFormatted,         // headline: "cpu·gpu W" split
                widestValue: "88·88 W",                 // worst-case slot (D-008); Ultra GPU >99W clips, acceptable
                loadPercent: power.loadPercent,         // color: total ÷ session-peak (set by the sampler)
                detail: powerDetail)

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
