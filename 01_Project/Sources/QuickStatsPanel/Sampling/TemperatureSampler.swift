import Foundation

// New sampler (D-018). The Temperatures tile has two layers:
//   • Headline = ProcessInfo.thermalState — public, guaranteed, permission-free, so
//     the tile is ALWAYS visible (its descriptor never returns nil). This is the
//     project's first always-on *optional* tile.
//   • Detail card = best-effort per-role °C from IOHIDTemperatureReader (private but
//     un-entitled IOHID SPI; see TemperatureReader.swift). Degrades to a single
//     `Pressure: <state>` row when no sensors enumerate (Intel / VM / renamed chip).
//
// thermalState is POLLED each tick, NOT observed via thermalStateDidChangeNotification
// — that posts on a background queue and needs a priming read to seed the first value;
// every other sampler here polls, so we match them (D-018 locked decision). Reads are
// cheap in-process calls, so the sampler runs continuously with no visibility gating.

struct TemperatureSample: Equatable, Sendable {
    /// System thermal pressure — the always-visible headline. Public API, never fails.
    var thermalState: ProcessInfo.ThermalState
    /// Best-effort per-role °C (already averaged per cluster by the reader). Empty on
    /// hardware where IOHID enumerates no usable sensor → drives the fallback row.
    var sensors: [TempReading]

    static let empty = TemperatureSample(thermalState: .nominal, sensors: [])

    /// Strip headline: the thermal-pressure word. The fixed-width template is the
    /// widest word, "Critical" (descriptor's `widestValue`), so the tile never jitters
    /// as the state changes (Penumbra pattern, AC-6).
    var headlineFormatted: String { Self.word(for: thermalState) }

    /// Feeds the shared calm→hot tint + font-weight pipeline (reversed:false, so hotter
    /// reads worse). Locked mapping (D-018): nominal 0 / fair 40 / serious 75 / critical 100.
    var loadPercent: Double {
        switch thermalState {
        case .nominal:    return 0
        case .fair:       return 40
        case .serious:    return 75
        case .critical:   return 100
        @unknown default: return 0
        }
    }

    /// Detail-card rows: one per present sensor role ("CPU" → "62°C"), or a single
    /// `Pressure: <state>` row when no sensors enumerated. The always-visible guarantee
    /// means this is never empty — the card always has at least the pressure word (AC-5).
    var detailRows: [(String, String)] {
        guard !sensors.isEmpty else { return [("Pressure", headlineFormatted)] }
        return sensors.map { ($0.label, String(format: "%.0f°C", $0.celsius)) }
    }

    /// ThermalState → display word. No built-in description on the enum, so map it here;
    /// "Critical" is the widest, which `StatDescriptor.widestValue` reserves space for.
    private static func word(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:    return "Nominal"
        case .fair:       return "Fair"
        case .serious:    return "Serious"
        case .critical:   return "Critical"
        @unknown default: return "Nominal"
        }
    }
}

/// Polls thermalState + the IOHID reader on a background timer, emitting one
/// TemperatureSample per tick. Timer skeleton mirrors GPUSampler; the owned, non-Sendable
/// reader (created in `start()`, dropped in `stop()`) mirrors PowerSampler's IOReportPower.
///
/// Thread-safety: `IOHIDTemperatureReader` is non-Sendable and must stay confined to one
/// serial queue. It is created in `start()` and only `read()` from `tick()` on `queue`;
/// `stop()` cancels the timer before niling the reader, so no in-flight `tick()` can race
/// the release. Only the value-type `TemperatureSample: Sendable` escapes. Same confinement
/// FanSampler/PowerSampler use for their hardware handles.
final class TemperatureSampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (TemperatureSample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.TemperatureSampler")
    private var reader: IOHIDTemperatureReader?

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (TemperatureSample) -> Void) {
        self.interval = interval
        self.onSample = onSample
    }

    func start() {
        reader = IOHIDTemperatureReader()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        reader = nil   // last strong ref drops → IOHIDTemperatureReader releases its CF state
    }

    private func tick() {   // runs on `queue`
        let sensors = reader?.read() ?? []
        onSample(TemperatureSample(thermalState: ProcessInfo.processInfo.thermalState,
                                   sensors: sensors))
    }
}

#if DEBUG
extension TemperatureSampler {
    /// De-risk dump (D-018 Wave 2 / T2.1): drives an IOHIDTemperatureReader synchronously
    /// and prints the headline word + loadPercent + clustered rows, exercising the same
    /// `TemperatureSample` mapping `tick()` builds. Throwaway; not wired into the app.
    static func debugDump(ticks: Int = 5, interval: TimeInterval = 1.0) {
        let reader = IOHIDTemperatureReader()
        print("[TemperatureSampler] reader.isAvailable = \(reader.isAvailable)")
        for i in 0..<ticks {
            Thread.sleep(forTimeInterval: interval)
            let sample = TemperatureSample(thermalState: ProcessInfo.processInfo.thermalState,
                                           sensors: reader.read())
            let rows = sample.detailRows.map { "\($0.0)=\($0.1)" }.joined(separator: "  ")
            print(String(format: "[TemperatureSampler] tick %d  headline \"%@\"  load %d  [%@]",
                         i, sample.headlineFormatted, Int(sample.loadPercent), rows))
        }
    }
}
#endif
