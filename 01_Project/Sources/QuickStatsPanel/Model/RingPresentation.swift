import AppKit
import Foundation
import Observation

// MARK: - Reading

/// What a wedge shows for one stat. Live values change every tick; the `widest*`
/// strings are the worst case the geometry is measured against (D-008), so a tick
/// can never need more room than was reserved at summon.
struct RingReading: Equatable, Sendable {
    var value: String
    var secondary: String?
    var widestValue: String
    var widestSecondary: String?
    var isAvailable: Bool
    var band: Band
    /// Fill content of the wedge. `nil` draws the plain track (a reading built without sample
    /// data); an unavailable stat carries `RingGauge.unavailable`.
    var gauge: RingGauge?

    init(value: String, secondary: String? = nil, widestValue: String,
         widestSecondary: String? = nil, isAvailable: Bool = true, band: Band = .calm,
         gauge: RingGauge? = nil) {
        self.value = value
        self.secondary = secondary
        self.widestValue = widestValue
        self.widestSecondary = widestSecondary
        self.isAvailable = isAvailable
        self.band = band
        self.gauge = gauge
    }

    init(descriptor: StatDescriptor) {
        self.init(value: descriptor.value, secondary: descriptor.secondaryValue,
                  widestValue: descriptor.widestValue,
                  widestSecondary: descriptor.widestSecondaryValue,
                  isAvailable: true, band: descriptor.band)
    }

    /// An enabled stat with no current reading keeps its wedge. The dash is not a
    /// measured zero; the second line says so in words.
    static func unavailable(_ kind: StatKind) -> RingReading {
        RingReading(value: "\u{2014}", secondary: "Unavailable",
                    widestValue: kind.ringFallbackWidest, widestSecondary: "Unavailable",
                    isAvailable: false, band: .calm, gauge: .unavailable(kind))
    }

    /// The full reading as one string: what accessibility announces and what a wedge that
    /// shows only its icon still makes available.
    var accessibilityText: String {
        isAvailable ? [value, secondary].compactMap { $0 }.joined(separator: ", ") : "Unavailable"
    }
}

extension StatKind {
    /// Worst-case headline used to size a wedge whose stat has no reading at summon.
    var ringFallbackWidest: String {
        switch self {
        case .cpu, .battery, .gpu: return "100%"
        case .memory, .disk:       return "888,88 GB"
        case .network:             return "888 MB/s"
        case .fan:                 return "8888 rpm"
        case .power:               return "888.8 W"
        case .temps:               return "Critical"
        case .loadAverage:         return "88.88"
        case .uptime:              return "88d 88h"
        }
    }
}

// MARK: - Typography and measurement

/// Ring text baseline: 13-point label, 16-point headline, 12-point secondary. No
/// rotation and no shrink-to-fit. The view draws with the same sizes it measures here.
enum RingTypography {
    static let labelSize: CGFloat = 13
    static let valueSize: CGFloat = 16
    static let secondarySize: CGFloat = 12
    static let lineSpacing: CGFloat = 2
    /// Side of the square an icon occupies in the content ladder.
    static let iconSide: CGFloat = 18

    static var labelFont: NSFont { .systemFont(ofSize: labelSize, weight: .medium) }
    /// Heaviest severity weight (`Theme.weight(for: .hot)`), so a band change never widens a block.
    static var valueFont: NSFont { .monospacedDigitSystemFont(ofSize: valueSize, weight: .heavy) }
    static var secondaryFont: NSFont { .monospacedDigitSystemFont(ofSize: secondarySize, weight: .regular) }
    static var settingsWordFont: NSFont { .systemFont(ofSize: secondarySize, weight: .medium) }

    private static func width(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func height(_ font: NSFont) -> CGFloat {
        ceil((("Ag") as NSString).size(withAttributes: [.font: font]).height)
    }

    /// Width of the word shown beside the hub's gear in the presets that show it.
    static var settingsWordWidth: CGFloat { width("Settings", settingsWordFont) }

    /// Icon above the count of stats left in More; sized for a two-digit count.
    static var moreContentSize: CGSize {
        CGSize(width: max(iconSide, width("88", labelFont)), height: iconSide + lineSpacing + height(labelFont))
    }

    /// Size of the horizontal label / headline / optional secondary stack, measured
    /// against the worst-case strings rather than the current reading.
    static func blockSize(name: String, reading: RingReading) -> CGSize {
        var widest = width(name, labelFont)
        var total = height(labelFont)

        widest = max(widest, width(reading.value, valueFont), width(reading.widestValue, valueFont))
        total += lineSpacing + height(valueFont)

        if reading.secondary != nil || reading.widestSecondary != nil {
            let texts = [reading.secondary, reading.widestSecondary].compactMap { $0 }
            for text in texts { widest = max(widest, width(text, secondaryFont)) }
            total += lineSpacing + height(secondaryFont)
        }
        return CGSize(width: widest, height: total)
    }

    /// Worst-case size of each rung of the content ladder for one wedge. The layout chooses
    /// the rung once per summon from these; the view never measures or chooses.
    static func rungSizes(name: String, reading: RingReading) -> RingRungSizes {
        var plain = reading
        plain.secondary = nil
        plain.widestSecondary = nil
        let hasSecondary = reading.secondary != nil || reading.widestSecondary != nil
        let valueWidth = max(width(reading.value, valueFont), width(reading.widestValue, valueFont))
        return RingRungSizes(
            labelValueSecondary: hasSecondary ? blockSize(name: name, reading: reading) : nil,
            labelValue: blockSize(name: name, reading: plain),
            iconValue: CGSize(width: max(iconSide, valueWidth),
                              height: iconSide + lineSpacing + height(valueFont)),
            icon: CGSize(width: iconSide, height: iconSide))
    }
}

// MARK: - Snapshot

/// The summon snapshot: ordered stat identities, their readings at summon, and the
/// frozen layout (preset geometry, favourite sectors with their chosen content rung, the
/// More wedge and the hub). Built once per summon; sample ticks never rebuild it.
struct RingSnapshot: Sendable {
    struct Entry: Equatable, Sendable {
        let kind: StatKind
        let name: String
        let initialReading: RingReading
    }

    /// Identifies this summon for stale-callback checks in later waves.
    let generation: UUID
    let enabledKinds: [StatKind]
    let preset: RingSizePreset
    let fillScale: RingFillScale
    let favourites: [Entry]
    /// Enabled non-favourites in order, with their summon readings.
    let moreEntries: [Entry]
    var moreKinds: [StatKind] { moreEntries.map(\.kind) }
    let layout: RingLayout
    /// Explains an empty or favourite-less ring; `nil` otherwise.
    let emptyMessage: String?

    /// Footprint of the favourites ring alone; the base panel's size.
    var size: CGSize { preset.footprintRingOnly }

    /// - Parameters:
    ///   - favourites: explicit ordered favourites; `nil` takes the first eight enabled stats.
    ///     Entries that are not enabled or repeat an earlier one are dropped, at most eight kept.
    ///     Every other enabled stat is reachable through More.
    ///   - cap: the Wedge text preference, the richest content rung a wedge may use.
    ///   - measure: worst-case size of each content rung of a wedge.
    static func make(
        enabledKinds: [StatKind],
        favourites explicit: [StatKind]? = nil,
        preset: RingSizePreset = .medium,
        cap: RingTextCap = .label,
        fillScale: RingFillScale = .area,
        reading: (StatKind) -> RingReading,
        measure: (StatKind, RingReading) -> RingRungSizes = { kind, reading in
            RingTypography.rungSizes(name: kind.displayName, reading: reading)
        }
    ) -> RingSnapshot {
        var favouriteKinds: [StatKind] = []
        for kind in explicit ?? enabledKinds where enabledKinds.contains(kind) && !favouriteKinds.contains(kind) {
            favouriteKinds.append(kind)
            if favouriteKinds.count == RingLayout.maxFavourites { break }
        }
        let moreKinds = enabledKinds.filter { !favouriteKinds.contains($0) }
        let entries = favouriteKinds.map { Entry(kind: $0, name: $0.displayName, initialReading: reading($0)) }
        let moreEntries = moreKinds.map { Entry(kind: $0, name: $0.displayName, initialReading: reading($0)) }
        let layout = RingLayout(
            preset: preset,
            center: CGPoint(x: preset.outerRadius, y: preset.outerRadius),
            favourites: entries.map { RingFavouriteInput(kind: $0.kind, sizes: measure($0.kind, $0.initialReading)) },
            moreCount: moreKinds.count,
            cap: cap,
            moreContentSize: RingTypography.moreContentSize,
            settingsWordWidth: RingTypography.settingsWordWidth)
        let message: String? = enabledKinds.isEmpty ? "No stats enabled"
            : (entries.isEmpty ? "No favourites selected" : nil)
        return RingSnapshot(generation: UUID(), enabledKinds: enabledKinds, preset: preset, fillScale: fillScale,
                            favourites: entries, moreEntries: moreEntries, layout: layout, emptyMessage: message)
    }

    // MARK: Hit testing and frames

    /// What a point in ring space selects: a favourite, the More wedge, the gear, the hub's
    /// drag area, or nothing (separators, the inactive annulus, outside).
    func target(at point: CGPoint) -> RingTarget? {
        switch layout.target(at: point) {
        case .favourite(let order)?:
            return favourites.indices.contains(order) ? .wedge(favourites[order].kind) : nil
        case .more?: return .more
        case .gear?: return .settings
        case nil: return layout.hub.contains(point) ? .drag : nil
        }
    }

    /// Frame of a target in ring space; the reserved parent frame for detail placement.
    func frame(of target: RingTarget) -> CGRect? {
        switch target {
        case .wedge(let kind):
            return layout.favourites.first { $0.kind == kind }?.sector.boundingFrame
        case .more: return layout.more?.sector.boundingFrame
        case .settings: return layout.hub.gearFrame
        case .drag:
            let hub = layout.hub
            return CGRect(x: hub.center.x - hub.discRadius, y: hub.center.y - hub.discRadius,
                          width: hub.discRadius * 2, height: hub.discRadius * 2)
        }
    }
}

// MARK: - Pointer state

/// Pointer-derived hover for the ring. The pointer arrives in screen coordinates from
/// the visibility-scoped mouse-moved observation and is evaluated against the frozen
/// layout, so its position stays known between the ring and the detail panel.
@Observable
@MainActor
final class RingPresentationState {
    private(set) var hovered: RingTarget?
    private(set) var pointerInRing: CGPoint?
    /// The wedge whose detail is currently shown; set by the owner of the detail panel.
    var selectedKind: StatKind?
    /// More branch visuals, mirrored from the interaction state by the panel controller.
    private(set) var moreExpanded = false
    private(set) var hoveredMoreKind: StatKind?
    private(set) var selectedMoreKind: StatKind?
    /// Stat under the pointer in a list (favourite row or More row).
    private(set) var hoveredNodeKind: StatKind?
    /// Scroll offset of the side/whole list, so drawing follows the layout's model offset.
    var listOffset: CGFloat = 0

    @ObservationIgnored private var summonPointer: CGPoint?
    @ObservationIgnored private var armed = false

    /// Hover stays off until the pointer actually moves, so clamping a summon under a
    /// stationary pointer cannot highlight a wedge.
    func beginSummon(pointer: CGPoint) {
        summonPointer = pointer
        armed = false
        hovered = nil
        pointerInRing = nil
        selectedKind = nil
        syncExpansion(.collapsed, hovered: nil)
        listOffset = 0
    }

    /// Mirrors the interaction state's open branches into the drawing state.
    func syncExpansion(_ expansion: RingExpansion, hovered node: RingNode?) {
        let wedge = expansion.detail.flatMap { $0.viaMore ? nil : $0.kind }
        let more = expansion.detail.flatMap { $0.viaMore ? $0.kind : nil }
        var hoveredMore: StatKind?
        if case .moreItem(let kind)? = node { hoveredMore = kind }
        if selectedKind != wedge { selectedKind = wedge }
        if selectedMoreKind != more { selectedMoreKind = more }
        let open = expansion.more != nil
        if moreExpanded != open { moreExpanded = open }
        if hoveredMoreKind != hoveredMore { hoveredMoreKind = hoveredMore }
        var listKind: StatKind?
        switch node {
        case .wedge(let kind)?, .moreItem(let kind)?: listKind = kind
        default: break
        }
        if hoveredNodeKind != listKind { hoveredNodeKind = listKind }
    }

    func updatePointer(screenPoint: CGPoint, ringFrame: CGRect, snapshot: RingSnapshot) {
        if !armed {
            guard let start = summonPointer, hypot(screenPoint.x - start.x, screenPoint.y - start.y) >= 2 else { return }
            armed = true
        }
        let local = CGPoint(x: screenPoint.x - ringFrame.minX, y: ringFrame.maxY - screenPoint.y)
        pointerInRing = local
        let target = snapshot.target(at: local)
        let next: RingTarget? = target == .drag ? nil : target
        if next != hovered { hovered = next }
    }

    func reset() {
        hovered = nil
        pointerInRing = nil
        selectedKind = nil
        summonPointer = nil
        armed = false
        syncExpansion(.collapsed, hovered: nil)
        listOffset = 0
    }
}

// MARK: - Fixtures (Debug only)

#if DEBUG
/// The fixed samples behind fixture mode: they seed the disposable store (so the detail cards
/// have data) and feed the wedge gauges through the same mappings real data uses.
enum RingFixtureSamples {
    static let cpu = CPUSample(totalUsagePercent: 42, userPercent: 28, systemPercent: 14, idlePercent: 58)
    static let memory = MemorySample(usedBytes: 19_400_000_000, totalBytes: 34_359_738_368, pressurePercent: 38,
                                     appBytes: 9_000_000_000, wiredBytes: 3_000_000_000, compressedBytes: 2_000_000_000)
    static let disk = DiskSample(usedBytes: 640_000_000_000, freeBytes: 360_000_000_000, totalBytes: 1_000_000_000_000,
                                 readBytesPerSec: 12_000_000, writeBytesPerSec: 3_000_000)
    static let network = NetworkSample(downBytesPerSec: 4_200_000, upBytesPerSec: 300_000,
                                       interfaceName: "Wi-Fi (en0)", localIP: "192.168.1.20")
    static let battery = BatterySample(isPresent: true, percent: 76, isCharging: false, isOnAC: false,
                                       minutesRemaining: 312, healthPercent: 91, cycleCount: 212, temperatureC: 31)
    static let gpu = GPUSample(isAvailable: true, utilizationPercent: 37, deviceName: "Apple GPU")
    static let fan = FanSample(hasFans: true, fans: [FanSample.Fan(current: 1_800, min: 1_200, max: 5_800)])
    static let power = PowerSample(isAvailable: true, cpuWatts: 4.2, gpuWatts: 1.1, aneWatts: 0, dramWatts: 0.6,
                                   loadPercent: 40, systemWatts: 12.5, dcInWatts: 0)
    /// The card's sample has no sensor rows; the gauge needs a valid sensor to draw a fill.
    static let temperature = TemperatureSample(thermalState: .fair, sensors: [])
    static let gaugeTemperature = TemperatureSample(
        thermalState: .fair,
        sensors: [TempReading(label: "CPU", celsius: 64), TempReading(label: "GPU", celsius: 58),
                  TempReading(label: "SSD", celsius: 41)])
    static let load = LoadSample(one: 2.1, five: 1.8, fifteen: 1.5)
    static let uptime = UptimeSample(seconds: 3 * 86_400 + 4 * 3_600)

    /// Gauge for a stat from the fixed samples, with a recent peak where the spec draws one.
    static func gauge(for kind: StatKind, powerCeilingWatts: Double) -> RingGauge {
        switch kind {
        case .cpu: return RingGaugeMapper.cpu(cpu, peak: 0.61)
        case .memory: return RingGaugeMapper.memory(memory)
        case .disk: return RingGaugeMapper.disk(disk)
        case .network: return RingGaugeMapper.network(network, downPeak: 0.62, upPeak: 0.4)
        case .battery: return RingGaugeMapper.battery(battery)
        case .gpu: return RingGaugeMapper.gpu(gpu, peak: 0.55)
        case .fan: return RingGaugeMapper.fans(fan)
        case .power:
            let ceiling = powerCeilingWatts > 0 ? powerCeilingWatts : RingGaugeMapper.defaultPowerCeilingWatts
            return RingGaugeMapper.power(power, ceilingWatts: ceiling, peak: min(1, 14.0 / ceiling))
        case .temps: return RingGaugeMapper.temperature(gaugeTemperature, peak: 0.6)
        case .loadAverage: return RingGaugeMapper.load(load, activeCores: 10)
        case .uptime: return RingGaugeMapper.uptime(uptime)
        }
    }
}

/// Deterministic stress inputs for the ring prototype. Fixture mode never reads or
/// writes stat data, history or defaults: the ring reads `readings`, the detail card
/// reads a store seeded by `StatsStore.seedRingFixture`.
struct RingFixture: Sendable {
    let name: String
    let enabledKinds: [StatKind]
    let readings: [StatKind: RingReading]
    /// Stats left without a seeded sample, so their detail shows the unavailable state.
    let unavailableKinds: Set<StatKind>

    func reading(for kind: StatKind,
                 powerCeilingWatts: Double = RingGaugeMapper.defaultPowerCeilingWatts) -> RingReading {
        if unavailableKinds.contains(kind) { return .unavailable(kind) }
        guard var reading = readings[kind] ?? Self.typical[kind] else { return .unavailable(kind) }
        reading.gauge = RingFixtureSamples.gauge(for: kind, powerCeilingWatts: powerCeilingWatts)
        return reading
    }

    static let names = ["none", "one", "six", "eight", "twelve", "long", "paired", "unavailable"]

    private static let six: [StatKind] = [.cpu, .memory, .disk, .network, .gpu, .temps]
    private static let eight: [StatKind] = [.cpu, .memory, .disk, .network, .battery, .gpu, .power, .temps]

    private static let typical: [StatKind: RingReading] = [
        .cpu: RingReading(value: "42%", widestValue: "100%", band: .calm),
        .memory: RingReading(value: "18,07 GB", widestValue: "888,88 GB", band: .busy),
        .disk: RingReading(value: "341,2 GB", widestValue: "888,88 GB", band: .calm),
        .network: RingReading(value: "\u{2193} 4,2 MB/s", widestValue: "\u{2193} 888 MB/s", band: .calm),
        .battery: RingReading(value: "76%", widestValue: "100%", band: .calm),
        .gpu: RingReading(value: "37%", widestValue: "100%", band: .calm),
        .fan: RingReading(value: "1800 rpm", widestValue: "8888 rpm", band: .calm),
        .power: RingReading(value: "5,9 W", widestValue: "888.8 W", band: .calm),
        .temps: RingReading(value: "Fair", widestValue: "Critical", band: .busy),
        .loadAverage: RingReading(value: "2.10", widestValue: "88.88", band: .calm),
        .uptime: RingReading(value: "3d 4h", widestValue: "88d 88h", band: .calm),
    ]

    private static let paired: [StatKind: RingReading] = [
        .cpu: RingReading(value: "42%", secondary: "61\u{00B0}C", widestValue: "100%",
                          widestSecondary: "888\u{00B0}C"),
        .memory: RingReading(value: "U 18,07 GB", secondary: "F 13,93 GB", widestValue: "U 888,88 GB",
                             widestSecondary: "F 888,88 GB", band: .busy),
        .disk: RingReading(value: "R 12 MB/s", secondary: "W 3 MB/s", widestValue: "R 888 MB/s",
                           widestSecondary: "W 888 MB/s"),
        .network: RingReading(value: "\u{2193} 4,2 MB/s", secondary: "\u{2191} 0,3 MB/s",
                              widestValue: "\u{2193} 888 MB/s", widestSecondary: "\u{2191} 888 MB/s"),
        .battery: RingReading(value: "76%", secondary: "5:12 left", widestValue: "100%",
                              widestSecondary: "888:88 to full"),
        .gpu: RingReading(value: "37%", widestValue: "100%"),
        .temps: RingReading(value: "Fair", widestValue: "Critical", band: .busy),
        .power: RingReading(value: "5,9 W", widestValue: "888.8 W"),
    ]

    /// Every paired reading at its worst-case string, for text-fit review.
    private static let long: [StatKind: RingReading] = Dictionary(uniqueKeysWithValues:
        paired.map { kind, reading in
            (kind, RingReading(value: reading.widestValue, secondary: reading.widestSecondary,
                               widestValue: reading.widestValue, widestSecondary: reading.widestSecondary,
                               band: .hot))
        })

    static func named(_ name: String) -> RingFixture? {
        switch name {
        case "none":
            return RingFixture(name: name, enabledKinds: [], readings: [:], unavailableKinds: [])
        case "one":
            return RingFixture(name: name, enabledKinds: [.cpu], readings: [:], unavailableKinds: [])
        case "six":
            return RingFixture(name: name, enabledKinds: six, readings: [:], unavailableKinds: [])
        case "eight":
            return RingFixture(name: name, enabledKinds: eight, readings: [:], unavailableKinds: [])
        case "twelve":
            return RingFixture(name: name, enabledKinds: StatKind.allCases, readings: [:], unavailableKinds: [])
        case "long":
            return RingFixture(name: name, enabledKinds: eight, readings: long, unavailableKinds: [])
        case "paired":
            return RingFixture(name: name, enabledKinds: six, readings: paired, unavailableKinds: [])
        case "unavailable":
            return RingFixture(name: name, enabledKinds: eight, readings: [:],
                               unavailableKinds: [.battery, .gpu, .power])
        default:
            return nil
        }
    }
}
#endif
