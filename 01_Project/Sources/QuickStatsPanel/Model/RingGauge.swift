import Foundation

// Gauge content for the ring (D-035). Pure values: nothing here reads StatsStore, draws, or
// samples. Each mapping takes sample values and returns a `RingGauge` whose fractions are
// presentation values (0...1) for the radial fill; they never replace the status band's input.

// MARK: - Components and marks

/// One stacked fill component. The stacking order is the declaration order within a stat's
/// list: CPU user, system, nice; Memory app, wired, compressed, other used; Power CPU, GPU,
/// Neural Engine, DRAM, rest of system. Single-fill stats use `.level`.
enum RingComponent: String, Equatable, Hashable, Sendable {
    case level
    case user, system, nice
    case app, wired, compressed, otherUsed
    case cpu, gpu, neuralEngine, dram, restOfSystem
}

/// A fill component with its own share of the full scale (not cumulative).
struct RingFillComponent: Equatable, Sendable {
    let component: RingComponent
    let fraction: Double
}

/// Marks drawn on a wedge. Network rate marks sit on the log scale; Battery power marks follow
/// the spec's four cases (bolt, amber plug, plug, none on battery power).
enum RingMark: Equatable, Sendable {
    case rate(fraction: Double, bytesPerSecond: Double)
    case chargingBolt
    case pluggedNotCharging
    case pluggedFull
}

/// macOS thermal state as presentation; the wedge tints from `fair` upward.
enum RingThermalState: Int, Equatable, Comparable, Sendable {
    case nominal, fair, serious, critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:  self = .nominal
        case .fair:     self = .fair
        case .serious:  self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }

    var tintsWedge: Bool { self >= .fair }

    static func < (lhs: RingThermalState, rhs: RingThermalState) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum RingBadge: Equatable, Sendable {
    case thermalState(RingThermalState)
}

/// Network's split wedge: download on the left half, upload on the right half.
struct RingHalves: Equatable, Sendable {
    let left: Double
    let right: Double
    let leftPeak: Double?
    let rightPeak: Double?
}

// MARK: - RingGauge

struct RingGauge: Equatable, Sendable {
    let stat: StatKind
    /// False for absent hardware or an empty sample. An unavailable gauge has no components,
    /// halves, rim, peak, marks or heat flag: it must draw the empty track, never a zero fill.
    let isAvailable: Bool
    /// Ordered stack, innermost first. Each fraction is the component's own share; the sum is
    /// clamped to at most 1 at construction. Empty for halves, no-fill and unavailable gauges.
    let components: [RingFillComponent]
    let halves: RingHalves?
    /// Disk I/O rim brightness 0...1 (read + write on the log rate scale). Never changes the fill.
    let rim: Double?
    /// 60-second peak as a fraction of the same scale as the fill.
    let peak: Double?
    let marks: [RingMark]
    let badge: RingBadge?
    /// True when the fill colour is the heat ramp fixed to radius (Temperature).
    let usesHeatRamp: Bool
    /// Names the fill basis where it can differ from the configured text reading.
    let basisNote: String?

    init(stat: StatKind,
         isAvailable: Bool = true,
         components: [RingFillComponent] = [],
         halves: RingHalves? = nil,
         rim: Double? = nil,
         peak: Double? = nil,
         marks: [RingMark] = [],
         badge: RingBadge? = nil,
         usesHeatRamp: Bool = false,
         basisNote: String? = nil) {
        self.stat = stat
        self.isAvailable = isAvailable
        self.components = Self.normalized(components)
        self.halves = halves
        self.rim = rim
        self.peak = peak
        self.marks = marks
        self.badge = badge
        self.usesHeatRamp = usesHeatRamp
        self.basisNote = basisNote
    }

    /// Neutral track with an unavailable indication.
    static func unavailable(_ stat: StatKind, badge: RingBadge? = nil, basisNote: String? = nil) -> RingGauge {
        RingGauge(stat: stat, isAvailable: false, badge: badge, basisNote: basisNote)
    }

    /// Cumulative outer reach of the stack, 0...1. Equals the sum of component fractions.
    var totalFraction: Double { components.reduce(0) { $0 + $1.fraction } }

    /// Cumulative fraction at the outer edge of each component, in stack order.
    var cumulativeFractions: [Double] {
        var running = 0.0
        return components.map { running += $0.fraction; return Swift.min(running, 1) }
    }

    /// True when the wedge draws any fill (stack, halves non-zero).
    var hasFill: Bool {
        if let h = halves, h.left > 0 || h.right > 0 { return true }
        return totalFraction > 0
    }

    private static func normalized(_ input: [RingFillComponent]) -> [RingFillComponent] {
        // Only negatives and NaN are clamped before scaling, so an over-full stack keeps its
        // proportions instead of flattening the largest components first.
        let cleaned = input.map { RingFillComponent(component: $0.component, fraction: $0.fraction.isNaN ? 0 : Swift.max($0.fraction, 0)) }
        let sum = cleaned.reduce(0) { $0 + $1.fraction }
        guard sum > 1, sum.isFinite else {
            return sum.isFinite ? cleaned : cleaned.map { RingFillComponent(component: $0.component, fraction: $0.fraction.isInfinite ? 1 : 0) }
        }
        return cleaned.map { RingFillComponent(component: $0.component, fraction: $0.fraction / sum) }
    }
}

enum RingGaugeMath {
    /// NaN and negative values clamp to 0; values above 1 clamp to 1.
    static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return value == .infinity ? 1 : 0 }
        return Swift.min(Swift.max(value, 0), 1)
    }
}

// MARK: - Rate scale

/// Fixed log rate scale: 1 KB/s to 1 GB/s mapped onto 0...1. It never rescales by itself.
enum RingRateScale {
    static let floorBytesPerSecond = 1_000.0
    static let ceilingBytesPerSecond = 1_000_000_000.0
    /// Marks drawn on the Network wedge.
    static let markBytesPerSecond: [Double] = [100_000, 10_000_000]

    /// `(log10(bytes per second) - 3) / 6`, clamped. Zero, negative, NaN and sub-KB/s map to 0.
    static func fraction(bytesPerSecond: Double) -> Double {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return bytesPerSecond == .infinity ? 1 : 0 }
        return RingGaugeMath.clamp01((log10(bytesPerSecond) - 3) / 6)
    }

    static func bytesPerSecond(forFraction fraction: Double) -> Double {
        pow(10, RingGaugeMath.clamp01(fraction) * 6 + 3)
    }
}

// MARK: - Peak window

/// Rolling maximum over a fixed window. Timestamps are injected (no wall clock inside), so
/// tests and the live caller choose the time base; it only needs to be monotonic.
struct RingPeakWindow: Sendable {
    static let defaultWindow: TimeInterval = 60

    let window: TimeInterval
    private var entries: [(time: TimeInterval, value: Double)] = []

    init(window: TimeInterval = RingPeakWindow.defaultWindow) {
        self.window = window
    }

    /// Records a value and returns the peak over `(time - window, time]`.
    @discardableResult
    mutating func record(_ value: Double, at time: TimeInterval) -> Double? {
        if value.isFinite, time.isFinite {
            // Monotonic deque: a newer, larger value makes older smaller ones irrelevant.
            while let last = entries.last, last.value <= value { entries.removeLast() }
            entries.append((time, value))
        }
        return peak(at: time)
    }

    /// Peak over samples strictly younger than `window` seconds at `time`; nil when none.
    mutating func peak(at time: TimeInterval) -> Double? {
        while let first = entries.first, time - first.time >= window { entries.removeFirst() }
        return entries.first?.value
    }

    mutating func reset() { entries.removeAll() }
}

// MARK: - Mappings

/// One pure mapping per stat. Fractions use existing sample fields only. A nil sample, absent
/// hardware or an empty sample returns an unavailable gauge (AC-28), never a zero fill.
enum RingGaugeMapper {

    /// Provisional Power ceiling in watts; a per-Mac setting later.
    static let defaultPowerCeilingWatts = 30.0

    /// Battery counts as full on power at or above this charge.
    static let batteryFullPercent = 99.5

    // CPU: user, system and nice stacked, 0-100 % of all cores.
    static func cpu(_ sample: CPUSample?, peak: Double? = nil) -> RingGauge {
        guard let s = sample, s != .empty else { return .unavailable(.cpu) }
        let user = Swift.max(s.userPercent, 0)
        let system = Swift.max(s.systemPercent, 0)
        let nice = Swift.max(s.totalUsagePercent - user - system, 0)
        return RingGauge(stat: .cpu,
                         components: [
                            RingFillComponent(component: .user, fraction: user / 100),
                            RingFillComponent(component: .system, fraction: system / 100),
                            RingFillComponent(component: .nice, fraction: nice / 100)],
                         peak: peak)
    }

    // Memory: app, wired, compressed, other used against installed memory; empty is free.
    static func memory(_ sample: MemorySample?) -> RingGauge {
        let note = "Fill shows memory in use against installed memory; the text may show free memory."
        guard let s = sample, s.totalBytes > 0 else { return .unavailable(.memory, basisNote: note) }
        let total = Double(s.totalBytes)
        let app = Double(s.appBytes)
        let wired = Double(s.wiredBytes)
        let compressed = Double(s.compressedBytes)
        let other = Swift.max(Double(s.usedBytes) - app - wired - compressed, 0)
        return RingGauge(stat: .memory,
                         components: [
                            RingFillComponent(component: .app, fraction: app / total),
                            RingFillComponent(component: .wired, fraction: wired / total),
                            RingFillComponent(component: .compressed, fraction: compressed / total),
                            RingFillComponent(component: .otherUsed, fraction: other / total)],
                         basisNote: note)
    }

    // Disk: used capacity of the boot volume; thin outer rim follows read + write on the log
    // rate scale and never changes the fill.
    static func disk(_ sample: DiskSample?) -> RingGauge {
        let note = "Fill shows used capacity of the boot volume; the text may show free space."
        guard let s = sample, s.totalBytes > 0 else { return .unavailable(.disk, basisNote: note) }
        let used = Double(s.usedBytes) / Double(s.totalBytes)
        let rim = RingRateScale.fraction(bytesPerSecond: Swift.max(s.readBytesPerSec, 0) + Swift.max(s.writeBytesPerSec, 0))
        return RingGauge(stat: .disk,
                         components: [RingFillComponent(component: .level, fraction: used)],
                         rim: rim,
                         basisNote: note)
    }

    // Network: download left half, upload right half, log scale, marks at 100 KB/s and 10 MB/s.
    static func network(_ sample: NetworkSample?, downPeak: Double? = nil, upPeak: Double? = nil) -> RingGauge {
        guard let s = sample, s != .empty else { return .unavailable(.network) }
        let marks = RingRateScale.markBytesPerSecond.map {
            RingMark.rate(fraction: RingRateScale.fraction(bytesPerSecond: $0), bytesPerSecond: $0)
        }
        return RingGauge(stat: .network,
                         halves: RingHalves(left: RingRateScale.fraction(bytesPerSecond: s.downBytesPerSec),
                                            right: RingRateScale.fraction(bytesPerSecond: s.upBytesPerSec),
                                            leftPeak: downPeak,
                                            rightPeak: upPeak),
                         marks: marks)
    }

    // Battery: charge 0-100 %. Bolt while charging, amber plug when plugged in but not
    // charging, plug when full on power, no mark on battery power.
    static func battery(_ sample: BatterySample?) -> RingGauge {
        guard let s = sample, s.isPresent else { return .unavailable(.battery) }
        var marks: [RingMark] = []
        if s.isCharging {
            marks = [.chargingBolt]
        } else if s.isOnAC {
            marks = [s.percent >= batteryFullPercent ? .pluggedFull : .pluggedNotCharging]
        }
        return RingGauge(stat: .battery,
                         components: [RingFillComponent(component: .level, fraction: s.percent / 100)],
                         marks: marks)
    }

    // GPU: utilisation 0-100 %.
    static func gpu(_ sample: GPUSample?, peak: Double? = nil) -> RingGauge {
        guard let s = sample, s.isAvailable else { return .unavailable(.gpu) }
        return RingGauge(stat: .gpu,
                         components: [RingFillComponent(component: .level, fraction: s.utilizationPercent / 100)],
                         peak: peak)
    }

    // Power: CPU, GPU, Neural Engine, DRAM and rest of system (system watts minus components)
    // stacked against a fixed ceiling. A ceiling at or below zero falls back to the default.
    static func power(_ sample: PowerSample?,
                      ceilingWatts: Double = RingGaugeMapper.defaultPowerCeilingWatts,
                      peak: Double? = nil) -> RingGauge {
        guard let s = sample, s.isAvailable else { return .unavailable(.power) }
        let ceiling = (ceilingWatts.isFinite && ceilingWatts > 0) ? ceilingWatts : defaultPowerCeilingWatts
        let rest = s.systemWatts.map { Swift.max($0 - s.totalWatts, 0) } ?? 0
        func share(_ watts: Double) -> Double { Swift.max(watts, 0) / ceiling }
        return RingGauge(stat: .power,
                         components: [
                            RingFillComponent(component: .cpu, fraction: share(s.cpuWatts)),
                            RingFillComponent(component: .gpu, fraction: share(s.gpuWatts)),
                            RingFillComponent(component: .neuralEngine, fraction: share(s.aneWatts)),
                            RingFillComponent(component: .dram, fraction: share(s.dramWatts)),
                            RingFillComponent(component: .restOfSystem, fraction: share(rest))],
                         peak: peak,
                         basisNote: "Fill is measured against a fixed \(Int(ceiling.rounded())) W ceiling.")
    }

    /// Sensor readings the gauge and the parts both accept.
    static let validTemperatureRange: ClosedRange<Double> = 0...110
    static let temperatureScaleRange: ClosedRange<Double> = 30...100

    static func isValidTemperature(_ celsius: Double) -> Bool {
        celsius.isFinite && validTemperatureRange.contains(celsius)
    }

    static func temperatureFraction(celsius: Double) -> Double {
        let lo = temperatureScaleRange.lowerBound, hi = temperatureScaleRange.upperBound
        return RingGaugeMath.clamp01((celsius - lo) / (hi - lo))
    }

    // Temperature: hottest valid sensor on 30-100 degrees C, heat ramp fixed to radius; thermal
    // state as a badge (tint from Fair upward). No valid sensor is unavailable; the thermal
    // state stays because it is always readable.
    static func temperature(_ sample: TemperatureSample?, peak: Double? = nil) -> RingGauge {
        let note = "Fill shows the hottest valid sensor; the text may show another reading."
        guard let s = sample else { return .unavailable(.temps, basisNote: note) }
        let badge = RingBadge.thermalState(RingThermalState(s.thermalState))
        guard let hottest = s.sensors.map(\.celsius).filter(isValidTemperature).max() else {
            return .unavailable(.temps, badge: badge, basisNote: note)
        }
        return RingGauge(stat: .temps,
                         components: [RingFillComponent(component: .level, fraction: temperatureFraction(celsius: hottest))],
                         peak: peak,
                         badge: badge,
                         usesHeatRamp: true,
                         basisNote: note)
    }

    // Fans: fastest fan between its own minimum and maximum speed. A missing or zeroed rated
    // range is unavailable, never a falsely idle fan.
    static func fans(_ sample: FanSample?) -> RingGauge {
        guard let s = sample, s.hasFans, let fan = s.fastest, fan.max > fan.min else { return .unavailable(.fan) }
        return RingGauge(stat: .fan,
                         components: [RingFillComponent(component: .level,
                                                        fraction: (fan.current - fan.min) / (fan.max - fan.min))],
                         basisNote: "Fill shows the fastest fan between its minimum and maximum speed.")
    }

    enum LoadWindow: Equatable, Sendable { case one, five, fifteen }

    // Load: selected average divided by active core count, 0 to 1.0 per core, clamped.
    static func load(_ sample: LoadSample?, window: LoadWindow = .one, activeCores: Int) -> RingGauge {
        let note = "Fill shows load per active core, clamped at 1.0."
        guard let s = sample, s != .empty, activeCores > 0 else { return .unavailable(.loadAverage, basisNote: note) }
        let average: Double
        switch window {
        case .one: average = s.one
        case .five: average = s.five
        case .fifteen: average = s.fifteen
        }
        return RingGauge(stat: .loadAverage,
                         components: [RingFillComponent(component: .level, fraction: average / Double(activeCores))],
                         basisNote: note)
    }

    // Uptime: text on the plain track, no fill. Available once a boot time has been read.
    static func uptime(_ sample: UptimeSample?) -> RingGauge {
        guard let s = sample, s.seconds > 0 else { return .unavailable(.uptime) }
        return RingGauge(stat: .uptime)
    }
}
