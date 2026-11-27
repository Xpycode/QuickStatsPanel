import Foundation

#if DEBUG

/// Usage band of a floating-tile reading (spec "Usage semantics"): below 50% is low, from 50% to
/// below 80% elevated, from 80% high. These thresholds belong to the tile spec and are
/// deliberately independent of the user's theme zones, so the prototype's bands are stable.
enum FloatingTileUsageBand: Equatable, Sendable {
    case low, elevated, high

    static let elevatedThreshold = 50.0
    static let highThreshold = 80.0

    static func band(forPercent percent: Double) -> FloatingTileUsageBand {
        if percent >= highThreshold { return .high }
        if percent >= elevatedThreshold { return .elevated }
        return .low
    }

    /// The word that carries the band without colour.
    var word: String {
        switch self {
        case .low: return "Normal"
        case .elevated: return "Elevated"
        case .high: return "High"
        }
    }

    /// The existing theme band: drives the status hue (neutral under Mono) and the weight ramp.
    var themeBand: Band {
        switch self {
        case .low: return .calm
        case .elevated: return .busy
        case .high: return .hot
        }
    }
}

/// What a reading's usage percentage measures. Only the first four are meaningful fractions;
/// everything else stays neutral rather than borrowing an arbitrary ceiling.
enum FloatingTileUsageBasis: Equatable, Sendable {
    case cpuUtilization
    case gpuUtilization
    case memoryUsedOfTotal
    case diskUsedOfTotal
    /// Battery: 100 minus charge, so a low charge reads "high".
    case batteryDrained
    /// Missing fraction or unknown scale (network, fans, power, temperature, load, uptime).
    case neutral(String)

    var isMeaningfulFraction: Bool {
        if case .neutral = self { return false }
        return true
    }

    static func basis(for kind: StatKind) -> FloatingTileUsageBasis {
        switch kind {
        case .cpu: return .cpuUtilization
        case .gpu: return .gpuUtilization
        case .memory: return .memoryUsedOfTotal
        case .disk: return .diskUsedOfTotal
        case .battery: return .batteryDrained
        case .network: return .neutral("Transfer rate")
        case .fan: return .neutral("Fan speed")
        case .power: return .neutral("Power draw")
        case .temps: return .neutral("Thermal state")
        case .loadAverage: return .neutral("Load average")
        case .uptime: return .neutral("Since restart")
        }
    }
}

/// A render-ready overview-tile reading: the stat's configured primary/paired text (with the
/// widest strings used to reserve widths) plus an explicit, optional usage basis. Pure value type.
struct FloatingTileReading: Equatable, Sendable {
    let kind: StatKind
    let isAvailable: Bool
    let primary: String
    let widestPrimary: String
    let secondary: String?
    let widestSecondary: String?
    let basis: FloatingTileUsageBasis
    /// 0...100 on the basis, or nil when the stat has no meaningful fraction (or no measurement).
    let usagePercent: Double?
    let band: FloatingTileUsageBand?

    /// Short basis line under the value, e.g. "56% of total". The percentage is truncated, never
    /// rounded up, so the label can never read "50%" while the band is still below 50.
    var caption: String {
        guard isAvailable else { return "No reading" }
        switch basis {
        case .neutral(let text): return text
        case .cpuUtilization, .gpuUtilization: return percentText(suffix: "utilization")
        case .memoryUsedOfTotal: return percentText(suffix: "of total")
        case .diskUsedOfTotal: return percentText(suffix: "of capacity")
        case .batteryDrained: return percentText(suffix: "drained")
        }
    }

    /// The full basis sentence, for tooltips and accessibility.
    var explanation: String {
        guard isAvailable else { return "\(kind.displayName) is unavailable on this Mac." }
        let measure: String
        switch basis {
        case .cpuUtilization: measure = "CPU utilization"
        case .gpuUtilization: measure = "GPU utilization"
        case .memoryUsedOfTotal: measure = "memory used as a share of total"
        case .diskUsedOfTotal: measure = "disk capacity used"
        case .batteryDrained: measure = "battery drained (100 minus charge)"
        case .neutral(let text):
            return "\(text); no usage scale, so no status colour."
        }
        guard let usagePercent, let band else { return "\(measure.capitalizedFirst): not measured." }
        return "\(measure.capitalizedFirst): \(Self.truncatedPercent(usagePercent))%, \(band.word.lowercased())."
    }

    /// Spoken/read form: name, the shown readings, then the basis and band.
    var accessibilityText: String {
        guard isAvailable else { return "\(kind.displayName), unavailable" }
        var parts = [kind.displayName, primary]
        if let secondary { parts.append(secondary) }
        parts.append(explanation)
        return parts.joined(separator: ", ")
    }

    /// Accessibility value of the tile control (its label already names the stat): the shown
    /// readings, then the basis and band.
    var accessibilityValue: String {
        guard isAvailable else { return "Unavailable" }
        return ([primary] + (secondary.map { [$0] } ?? []) + [explanation]).joined(separator: ", ")
    }

    private func percentText(suffix: String) -> String {
        guard let usagePercent else { return "Not measured" }
        return "\(Self.truncatedPercent(usagePercent))% \(suffix)"
    }

    static func truncatedPercent(_ percent: Double) -> Int { Int(min(max(percent, 0), 100).rounded(.down)) }

    // MARK: Construction

    static func unavailable(_ kind: StatKind) -> FloatingTileReading {
        FloatingTileReading(kind: kind, isAvailable: false, primary: "Unavailable", widestPrimary: "Unavailable",
                            secondary: nil, widestSecondary: nil, basis: .basis(for: kind),
                            usagePercent: nil, band: nil)
    }

    /// The band for a basis and raw percentage; nil for neutral bases or unusable numbers.
    static func band(for basis: FloatingTileUsageBasis, percent: Double?) -> FloatingTileUsageBand? {
        guard basis.isMeaningfulFraction, let percent, percent.isFinite else { return nil }
        return .band(forPercent: min(max(percent, 0), 100))
    }

    /// Builds a reading from the existing display text. `rawPercent` is the percentage *on the
    /// basis* (battery: the charge; it is reversed here).
    init(descriptorKind kind: StatKind, value: String, widestValue: String,
         secondary: String?, widestSecondary: String?, rawPercent: Double?) {
        let basis = FloatingTileUsageBasis.basis(for: kind)
        var percent = rawPercent.flatMap { $0.isFinite ? min(max($0, 0), 100) : nil }
        if basis == .batteryDrained { percent = percent.map { 100 - $0 } }
        if !basis.isMeaningfulFraction { percent = nil }
        self.kind = kind
        self.isAvailable = true
        self.primary = value
        self.widestPrimary = widestValue
        self.secondary = secondary
        self.widestSecondary = secondary == nil ? nil : (widestSecondary ?? secondary)
        self.basis = basis
        self.usagePercent = percent
        self.band = Self.band(for: basis, percent: percent)
    }

    private init(kind: StatKind, isAvailable: Bool, primary: String, widestPrimary: String,
                 secondary: String?, widestSecondary: String?, basis: FloatingTileUsageBasis,
                 usagePercent: Double?, band: FloatingTileUsageBand?) {
        self.kind = kind
        self.isAvailable = isAvailable
        self.primary = primary
        self.widestPrimary = widestPrimary
        self.secondary = secondary
        self.widestSecondary = widestSecondary
        self.basis = basis
        self.usagePercent = usagePercent
        self.band = band
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension StatsStore {
    /// The overview reading for `kind`. The configured primary/secondary text comes from the
    /// existing descriptor; the usage percentage is taken from the samples on the explicit basis
    /// (not the descriptor's activity/pressure figure, which has other meanings).
    func floatingTileReading(for kind: StatKind, settings: AppSettings = AppSettings.shared) -> FloatingTileReading {
        guard let descriptor = descriptor(for: kind, settings: settings) else { return .unavailable(kind) }
        return FloatingTileReading(descriptorKind: kind, value: descriptor.value, widestValue: descriptor.widestValue,
                                   secondary: descriptor.secondaryValue,
                                   widestSecondary: descriptor.widestSecondaryValue,
                                   rawPercent: usageBasisPercent(for: kind))
    }

    /// Percentage on the basis (battery: charge, reversed by the reading); nil when not
    /// meaningful or not measurable (for example a total of zero bytes).
    func usageBasisPercent(for kind: StatKind) -> Double? {
        switch kind {
        case .cpu: return cpu.totalUsagePercent
        case .gpu: return gpu.isAvailable ? gpu.utilizationPercent : nil
        case .memory: return memory.totalBytes > 0 ? Double(memory.usedBytes) / Double(memory.totalBytes) * 100 : nil
        case .disk: return disk.totalBytes > 0 ? Double(disk.usedBytes) / Double(disk.totalBytes) * 100 : nil
        case .battery: return battery.isPresent ? battery.percent : nil
        case .network, .fan, .power, .temps, .loadAverage, .uptime: return nil
        }
    }
}

#endif
