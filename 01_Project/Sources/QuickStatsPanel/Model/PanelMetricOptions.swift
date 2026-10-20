import Foundation

/// Explicit headline choices keep unlike power measurements distinguishable.
enum PowerDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case system, chipTotal, cpu, gpu, cpuAndGPU, dcIn
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Whole system"
        case .chipTotal: return "Chip total"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .cpuAndGPU: return "CPU + GPU"
        case .dcIn: return "Charger input"
        }
    }

    /// Reserve a stable width within each selected mode, including three-digit watts.
    var widestValue: String {
        self == .cpuAndGPU ? "CPU 888.8 W · GPU 888.8 W" : "888.8 W"
    }
}

enum LoadDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case oneMinute, fiveMinutes, fifteenMinutes, relativeToCores
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneMinute: return "1-minute average"
        case .fiveMinutes: return "5-minute average"
        case .fifteenMinutes: return "15-minute average"
        case .relativeToCores: return "1-minute average / cores"
        }
    }

    var widestValue: String {
        self == .relativeToCores ? "888.8 / 888 cores" : "888.88"
    }
}

enum TemperatureDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case status, cpu, gpu, statusAndCPU, statusAndGPU
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .status: return "Thermal status"
        case .cpu: return "CPU temperature"
        case .gpu: return "GPU temperature"
        case .statusAndCPU: return "Status + CPU temperature"
        case .statusAndGPU: return "Status + GPU temperature"
        }
    }

    func widestValue(unit: TemperatureUnit) -> String {
        switch self {
        case .status: return "Critical"
        case .cpu, .gpu: return "888°\(unit.symbol)"
        case .statusAndCPU: return "Critical · CPU 888°\(unit.symbol)"
        case .statusAndGPU: return "Critical · GPU 888°\(unit.symbol)"
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var symbol: String { self == .celsius ? "C" : "F" }
    var displayName: String { self == .celsius ? "Celsius (°C)" : "Fahrenheit (°F)" }

    /// Samples stay in Celsius; conversion happens only at the presentation boundary.
    func formatted(celsius: Double?) -> String {
        guard let celsius, celsius.isFinite else { return "—°\(symbol)" }
        let value = self == .celsius ? celsius : celsius * 9 / 5 + 32
        return String(format: "%.0f°%@", value, symbol)
    }
}

enum DiskDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case capacity, activity
    var id: String { rawValue }
    var displayName: String { self == .capacity ? "Capacity" : "Read/write activity" }
    var valuePair: (first: String, second: String) {
        self == .capacity ? ("Free", "Used") : ("Read", "Write")
    }
}

extension TemperatureSample {
    func headline(for mode: TemperatureDisplayMode, unit: TemperatureUnit) -> String {
        let role: String
        switch mode {
        case .status: return headlineFormatted
        case .cpu, .statusAndCPU: role = "CPU"
        case .gpu, .statusAndGPU: role = "GPU"
        }
        let reading = unit.formatted(celsius: sensors.first { $0.label == role }?.celsius)
        switch mode {
        case .statusAndCPU, .statusAndGPU: return "\(headlineFormatted) · \(role) \(reading)"
        default: return reading
        }
    }

    func detailRows(unit: TemperatureUnit) -> [(String, String)] {
        guard !sensors.isEmpty else { return [("Pressure", headlineFormatted)] }
        return sensors.map { ($0.label, unit.formatted(celsius: $0.celsius)) }
    }
}

extension StatKind {
    /// Labels are stable persistence IDs as well as the detail-card labels.
    var configurableDetailRows: [String] {
        switch self {
        case .cpu: return ["User", "System", "Idle", "Temp"]
        case .memory: return ["Used", "Free", "App", "Wired", "Compressed", "Total", "Pressure"]
        case .disk: return ["Used", "Free", "Total", "Read", "Write"]
        case .network: return ["Down", "Up", "Interface", "Local IP"]
        case .battery: return ["Charge", "State", "Time", "Health", "Cycles", "Temp"]
        case .gpu: return ["Utilization", "Device", "Temp"]
        case .fan: return ["Fan"]
        case .temps: return ["CPU", "GPU", "SSD", "Battery", "Pressure"]
        case .uptime: return ["Uptime", "Booted"]
        case .power: return ["CPU", "GPU", "ANE", "DRAM", "Total", "System", "DC In"]
        case .loadAverage: return ["1 min", "5 min", "15 min", "Cores"]
        }
    }
}

extension PowerSample {
    func headline(for mode: PowerDisplayMode) -> String {
        switch mode {
        case .system: return systemFormatted ?? "— W"
        case .chipTotal: return totalFormatted
        case .cpu: return cpuFormatted
        case .gpu: return gpuFormatted
        case .cpuAndGPU: return "CPU \(cpuFormatted) · GPU \(gpuFormatted)"
        case .dcIn: return dcInFormatted ?? "— W"
        }
    }
}

extension LoadSample {
    func headline(for mode: LoadDisplayMode, cores: Int) -> String {
        switch mode {
        case .oneMinute: return oneFormatted
        case .fiveMinutes: return fiveFormatted
        case .fifteenMinutes: return fifteenFormatted
        case .relativeToCores: return String(format: "%.1f / %d cores", one, max(1, cores))
        }
    }

    func saturationPercent(for mode: LoadDisplayMode, cores: Int) -> Double {
        let value: Double
        switch mode {
        case .oneMinute, .relativeToCores: value = one
        case .fiveMinutes: value = five
        case .fifteenMinutes: value = fifteen
        }
        return min(100, max(0, value) / Double(max(1, cores)) * 100)
    }
}
