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

    init(value: String, secondary: String? = nil, widestValue: String,
         widestSecondary: String? = nil, isAvailable: Bool = true, band: Band = .calm) {
        self.value = value
        self.secondary = secondary
        self.widestValue = widestValue
        self.widestSecondary = widestSecondary
        self.isAvailable = isAvailable
        self.band = band
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
                    isAvailable: false, band: .calm)
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

    static var labelFont: NSFont { .systemFont(ofSize: labelSize, weight: .medium) }
    /// Heaviest severity weight (`Theme.weight(for: .hot)`), so a band change never widens a block.
    static var valueFont: NSFont { .monospacedDigitSystemFont(ofSize: valueSize, weight: .heavy) }
    static var secondaryFont: NSFont { .monospacedDigitSystemFont(ofSize: secondarySize, weight: .regular) }

    private static func width(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func height(_ font: NSFont) -> CGFloat {
        ceil((("Ag") as NSString).size(withAttributes: [.font: font]).height)
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
}

// MARK: - Snapshot

/// The summon snapshot: ordered stat identities, their readings at summon, and the
/// frozen geometry. Built once per summon; sample ticks never rebuild it.
struct RingSnapshot: Sendable {
    struct Entry: Equatable, Sendable {
        let kind: StatKind
        let name: String
        let initialReading: RingReading
    }

    /// Identifies this summon for stale-callback checks in later waves.
    let generation: UUID
    let enabledKinds: [StatKind]
    let favourites: [Entry]
    let moreKinds: [StatKind]
    let geometry: RingGeometry
    /// Explains an empty or favourite-less ring; `nil` otherwise.
    let emptyMessage: String?

    /// In this prototype the favourites are the first (up to eight) ordered enabled
    /// stats; everything else is reachable through More.
    static func make(
        enabledKinds: [StatKind],
        reading: (StatKind) -> RingReading,
        measure: (StatKind, RingReading) -> CGSize = { kind, reading in
            RingTypography.blockSize(name: kind.displayName, reading: reading)
        }
    ) -> RingSnapshot {
        let favouriteKinds = Array(enabledKinds.prefix(RingGeometry.maxFavourites))
        let moreKinds = Array(enabledKinds.dropFirst(RingGeometry.maxFavourites))
        let entries = favouriteKinds.map { Entry(kind: $0, name: $0.displayName, initialReading: reading($0)) }
        let geometry = RingGeometry(
            favourites: entries.map { (kind: $0.kind, textSize: measure($0.kind, $0.initialReading)) },
            moreCount: moreKinds.count)
        let message: String? = enabledKinds.isEmpty ? "No stats enabled"
            : (entries.isEmpty ? "No favourites selected" : nil)
        return RingSnapshot(generation: UUID(), enabledKinds: enabledKinds, favourites: entries,
                            moreKinds: moreKinds, geometry: geometry, emptyMessage: message)
    }
}

// MARK: - Pointer state

/// Pointer-derived hover for the ring. The pointer arrives in screen coordinates from
/// the visibility-scoped mouse-moved observation and is evaluated against the frozen
/// geometry, so its position stays known between the ring and the detail panel.
@Observable
@MainActor
final class RingPresentationState {
    private(set) var hovered: RingTarget?
    private(set) var pointerInRing: CGPoint?
    /// The wedge whose detail is currently shown; set by the owner of the detail panel.
    var selectedKind: StatKind?

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
    }

    func updatePointer(screenPoint: CGPoint, ringFrame: CGRect, geometry: RingGeometry) {
        if !armed {
            guard let start = summonPointer, hypot(screenPoint.x - start.x, screenPoint.y - start.y) >= 2 else { return }
            armed = true
        }
        let local = CGPoint(x: screenPoint.x - ringFrame.minX, y: ringFrame.maxY - screenPoint.y)
        pointerInRing = local
        let target = geometry.target(at: local)
        let next: RingTarget? = target == .drag ? nil : target
        if next != hovered { hovered = next }
    }

    func reset() {
        hovered = nil
        pointerInRing = nil
        selectedKind = nil
        summonPointer = nil
        armed = false
    }
}

// MARK: - Fixtures (Debug only)

#if DEBUG
/// Deterministic stress inputs for the ring prototype. Fixture mode never reads or
/// writes stat data, history or defaults: the ring reads `readings`, the detail card
/// reads a store seeded by `StatsStore.seedRingFixture`.
struct RingFixture: Sendable {
    let name: String
    let enabledKinds: [StatKind]
    let readings: [StatKind: RingReading]
    /// Stats left without a seeded sample, so their detail shows the unavailable state.
    let unavailableKinds: Set<StatKind>

    func reading(for kind: StatKind) -> RingReading {
        if unavailableKinds.contains(kind) { return .unavailable(kind) }
        return readings[kind] ?? Self.typical[kind] ?? .unavailable(kind)
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
