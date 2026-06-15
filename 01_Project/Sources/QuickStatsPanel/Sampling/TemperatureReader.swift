import Foundation

// Permission-free per-sensor temperature reader (D-018). Wraps Apple's PRIVATE,
// un-entitled **IOHIDEventSystemClient** SPI: the temperature sensors on the
// AppleVendor HID page (PrimaryUsagePage 0xff00 / PrimaryUsage 5), read as IEEE
// floats in °C via `kIOHIDEventTypeTemperature`. C prototypes live in
// QuickStatsPanel-Bridging-Header.h; the symbols link via `-framework IOKit`.
// No root, no entitlement, no prompt — same trust level as IOReport (D-019) and
// the AppleSMC fan reader (D-017). This feeds ONLY the Temperatures detail card;
// the tile's always-visible headline is the public `ProcessInfo.thermalState`.
//
// Wave-1 de-risk finding (M4 Pro, un-elevated): page 0xff00/5 returns 77 services.
// The named CPU/GPU "MTR Temp Sensor" sensors the reference tools list on some
// chips DO NOT appear here — instead: ~14 × `PMU tdie<N>` SoC-die sensors (~37 °C),
// `gas gauge battery` (31 °C), `NAND CH<N> temp` (33 °C), plus `PMU tcal`
// (calibration ref) and `PMU tdev<N>` (sentinel ≈ −9200 °C, garbage). So sensor
// *names drift per SoC* (exactly D-018's documented fragility): `role(for:)` maps
// names→roles defensively — it yields CPU/GPU rows on a chip that exposes them and
// falls back to a single SoC row from the die sensors otherwise, dropping
// calibration/sentinel/out-of-range readings.
//
// Thread-safety: the client, service handles, and CF objects are non-Sendable and
// MUST stay confined to one serial queue. This type is NOT Sendable; its owner
// (TemperatureSampler) creates it in `start()` and only calls `read()` from its own
// serial timer queue — exactly how FanSampler confines its SMC handle.

/// One averaged temperature reading for a role label, already in °C.
struct TempReading: Equatable, Sendable {
    let label: String
    let celsius: Double
}

private let kIOHIDEventTypeTemperature: Int64 = 15   // IOHIDEventGetFloatValue field = type << 16

final class IOHIDTemperatureReader {

    /// Display order for the detail-card rows (only those actually present render).
    static let roleOrder = ["CPU", "GPU", "SoC", "SSD", "Battery"]

    /// Borrowed-then-retained service handles paired with the role they map to,
    /// resolved once at init. Holding the `IOHIDServiceClient` instances in this
    /// array retains them (CF objects bridge as classes), so they outlive the
    /// `CopyServices` array. Empty ⇒ no usable sensors on this hardware.
    private var sensors: [(service: IOHIDServiceClient, role: String)] = []

    /// True when ≥1 sensor mapped to a role at init. Drives the detail card's
    /// sensor-rows-vs-`Pressure` fallback — NOT the tile's visibility (the tile is
    /// always shown via the thermalState headline; D-018).
    var isAvailable: Bool { !sensors.isEmpty }

    init() {
        let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault).takeRetainedValue()
        IOHIDEventSystemClientSetMatching(
            client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)

        guard let services = IOHIDEventSystemClientCopyServices(client) else { return }
        for i in 0..<CFArrayGetCount(services) {
            guard let raw = CFArrayGetValueAtIndex(services, i) else { continue }
            let service = Unmanaged<IOHIDServiceClient>.fromOpaque(raw).takeUnretainedValue()
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  let role = Self.role(for: name)
            else { continue }   // skip unnamed / calibration / sentinel sensors
            sensors.append((service, role))
        }
    }

    /// Map a raw IOHID `"Product"` sensor name → a friendly role label, or nil to
    /// exclude it. Ordered most-specific first. Grounded in the Wave-1 dump but
    /// chip-agnostic: role-named sensors (pACC/eACC/GPU MTR) win when present;
    /// otherwise the numbered `PMU tdie` dies collapse into a single "SoC" row.
    /// `PMU tcal` (calibration) and `PMU tdev` (sentinel ≈ −9200) match nothing → dropped.
    static func role(for name: String) -> String? {
        let n = name.lowercased()
        if n.contains("battery")                                   { return "Battery" }
        if n.hasPrefix("nand")                                     { return "SSD" }
        if n.contains("gpu")                                       { return "GPU" }
        if n.hasPrefix("pacc") || n.hasPrefix("eacc") || n.contains("cpu") { return "CPU" }
        if n.contains("tdie") || n.contains("soc") || n.contains("mtr temp") { return "SoC" }
        return nil
    }

    /// One averaged reading per present role, in `roleOrder`. Empty when no sensors
    /// enumerated. Drops non-finite / ≤0 / >130 °C readings (the `PMU tdev` sentinel
    /// and any momentary garbage). MUST be called on the owner's serial queue.
    func read() -> [TempReading] {
        guard !sensors.isEmpty else { return [] }
        let field = Int32(truncatingIfNeeded: kIOHIDEventTypeTemperature << 16)

        var sums: [String: (total: Double, count: Int)] = [:]
        for (service, role) in sensors {
            guard let event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let c = IOHIDEventGetFloatValue(event.takeRetainedValue(), field)
            guard c.isFinite, c > 0, c < 130 else { continue }   // drop sentinel/garbage
            let cur = sums[role] ?? (0, 0)
            sums[role] = (cur.total + c, cur.count + 1)
        }

        return Self.roleOrder.compactMap { role in
            guard let s = sums[role], s.count > 0 else { return nil }
            return TempReading(label: role, celsius: s.total / Double(s.count))
        }
    }
}

#if DEBUG
extension IOHIDTemperatureReader {
    /// De-risk spike (D-018 Wave 1): print the live per-role °C once per second,
    /// **un-elevated**, to validate the IOHID path + name→role mapping before the
    /// sampler and tile are built on top. Throwaway; not wired into the shipping app.
    static func debugDump(ticks: Int = 5, interval: TimeInterval = 1.0) {
        let reader = IOHIDTemperatureReader()
        print("[IOHIDTemperatureReader] isAvailable = \(reader.isAvailable)  mappedSensors = \(reader.sensors.count)")
        for i in 0..<ticks {
            Thread.sleep(forTimeInterval: interval)
            let rows = reader.read().map { String(format: "%@ %.1f°C", $0.label, $0.celsius) }
            print("[IOHIDTemperatureReader] tick \(i)  \(rows.joined(separator: "  "))")
        }
    }
}
#endif
