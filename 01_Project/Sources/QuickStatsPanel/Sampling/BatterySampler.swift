import Foundation
import IOKit
import IOKit.ps

// New sampler (roadmap v1.1). Permission-free: the IOKit Power Sources API
// (IOKit.ps) is the same snapshot the menu-bar battery reads — no entitlement.
// Unlike CPU/Disk/Network this is NOT a delta: each tick reads an absolute state
// (charge %, charging, time remaining). Desktop Macs report no battery at all,
// so `isPresent` gates whether the tile is shown (see StatsStripView).

struct BatterySample: Equatable, Sendable {
    var isPresent: Bool          // false on desktop Macs (no battery)
    var percent: Double          // 0–100 charge
    var isCharging: Bool
    var isOnAC: Bool             // plugged into power (charging or fully charged)
    var minutesRemaining: Int?   // nil = calculating/unknown; means "to full" when charging, else "to empty"

    // Health details from the AppleSmartBattery IORegistry entry (detail card
    // rows, 2026-07-12). nil ⇒ key unreadable on this Mac → row hidden.
    var healthPercent: Double? = nil   // NominalChargeCapacity ÷ DesignCapacity
    var cycleCount: Int? = nil
    var temperatureC: Double? = nil    // registry reports centi-°C (3057 → 30.6 °C)

    static let empty = BatterySample(isPresent: false, percent: 0,
                                     isCharging: false, isOnAC: false, minutesRemaining: nil)

    /// Raw charge as the stat's load figure. Battery is INVERTED vs other stats
    /// (a *low* charge should read "hot"), but that inversion now lives in the
    /// store's tint resolution (`theme.tint(..., reversed: true)`) — not here.
    /// The old `100 - percent` hack is gone: `loadPercent` is just the charge.
    var loadPercent: Double { percent }

    var percentFormatted: String { "\(Int(percent.rounded()))%" }

    /// SF Symbol that mirrors charge level + charging state, like the menu bar.
    /// Charging shows the bolt variant; otherwise the nearest 0/25/50/75/100 fill.
    var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13:  return "battery.0percent"
        case ..<38:  return "battery.25percent"
        case ..<63:  return "battery.50percent"
        case ..<88:  return "battery.75percent"
        default:     return "battery.100percent"
        }
    }

    /// "On battery" / "Charging" / "Charged" — the power state in words.
    var stateLabel: String {
        if isCharging { return "Charging" }
        if isOnAC { return "Charged" }
        return "On battery"
    }

    /// "1:23" hours:minutes, or "—" when unknown/calculating (-1 from IOKit).
    var timeFormatted: String {
        guard let m = minutesRemaining, m > 0 else { return "—" }
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    // Detail rows — nil when the registry key was unreadable (row hidden).
    var healthFormatted: String? { healthPercent.map { "\(Int($0.rounded()))%" } }
    var cyclesFormatted: String? { cycleCount.map(String.init) }
    var temperatureFormatted: String? { temperatureC.map { String(format: "%.0f°C", $0) } }
}

/// Polls IOKit Power Sources on a background timer, reporting an absolute battery
/// snapshot each tick. Same timer skeleton as the other samplers (no delta state).
final class BatterySampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (BatterySample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.BatterySampler")

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (BatterySample) -> Void) {
        self.interval = interval
        self.onSample = onSample
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        self.timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        onSample(Self.readBattery())
    }

    // MARK: - Power Sources (IOKit.ps)

    /// Reads the first internal power source. Returns `.empty` (isPresent: false)
    /// when there is no battery (desktop Macs) or the snapshot can't be read.
    private static func readBattery() -> BatterySample {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else { return .empty }

        // Capacity keys are reported as a percentage on modern macOS, but compute
        // current/max defensively in case max isn't exactly 100.
        let current = (desc[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
        let max = (desc[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
        let percent = max > 0 ? current / max * 100 : 0

        let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        let state = desc[kIOPSPowerSourceStateKey] as? String
        let isOnAC = (state == kIOPSACPowerValue)

        // Time remaining: IOKit uses -1 for "still calculating" → surface as nil.
        // Which value applies depends on whether we're charging.
        let rawTime = (isCharging
                       ? desc[kIOPSTimeToFullChargeKey]
                       : desc[kIOPSTimeToEmptyKey]) as? NSNumber
        let minutes = rawTime.map { $0.intValue }
        let minutesRemaining = (minutes ?? -1) > 0 ? minutes : nil

        let smart = readSmartBattery()
        return BatterySample(isPresent: true, percent: percent,
                             isCharging: isCharging, isOnAC: isOnAC,
                             minutesRemaining: minutesRemaining,
                             healthPercent: smart.health,
                             cycleCount: smart.cycles,
                             temperatureC: smart.tempC)
    }

    /// Health details from the AppleSmartBattery IORegistry entry — the same
    /// numbers System Settings' Battery Health panel derives (permission-free
    /// registry read; keys verified on this M4 Pro 2026-07-12). Any missing key
    /// degrades to nil → its row is hidden, never fabricated.
    ///   • Health % = NominalChargeCapacity ÷ DesignCapacity (both mAh);
    ///     AppleRawMaxCapacity is the fallback numerator on older firmwares.
    ///     (kIOPSMaxCapacityKey is useless here — modern macOS pins it to 100.)
    ///   • Temperature is reported in centi-°C (3057 → 30.6 °C).
    private static func readSmartBattery() -> (health: Double?, cycles: Int?, tempC: Double?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil, nil) }
        defer { IOObjectRelease(service) }

        func number(_ key: String) -> Double? {
            (IORegistryEntryCreateCFProperty(service, key as CFString,
                                             kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber)?.doubleValue
        }

        let cycles = number("CycleCount").map { Int($0) }
        let design = number("DesignCapacity")
        let nominal = number("NominalChargeCapacity") ?? number("AppleRawMaxCapacity")
        let health: Double? = {
            guard let design, design > 0, let nominal else { return nil }
            return nominal / design * 100
        }()
        let tempC = number("Temperature").map { $0 / 100 }
        return (health, cycles, tempC)
    }
}
