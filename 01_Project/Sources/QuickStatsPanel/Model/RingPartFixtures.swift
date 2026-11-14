import Foundation

#if DEBUG

// Debug-only part fixture sets for `--ring-parts=` (typical, dense, minimal). Parent readings
// are derived from the parts, so parent and parts agree by construction (AC-34). Values are
// deterministic formulas, not random.

enum RingPartFixtureName: String, CaseIterable, Sendable {
    case typical, dense, minimal
}

struct RingPartFixtureSet: Sendable {
    let name: RingPartFixtureName
    let cpuParts: RingPartList
    let diskParts: RingPartList
    let networkParts: RingPartList
    let temperatureParts: RingPartList

    /// Parent readings derived from the parts.
    let cpu: CPUSample
    let disk: DiskSample
    let network: NetworkSample
    let temperature: TemperatureSample
}

enum RingPartFixtures {

    static func make(_ name: RingPartFixtureName) -> RingPartFixtureSet {
        let cores: [RingCoreInput]
        let volumes: [RingVolumeInput]
        let interfaces: [RingInterfaceInput]
        let sensors: [RingSensorInput]
        switch name {
        case .typical:
            cores = coreInputs([("Efficiency", 2), ("Performance", 8)])
            volumes = volumeInputs(count: 4)
            interfaces = interfaceInputs(count: 3)
            sensors = sensorInputs([("CPU", 12), ("GPU", 6), ("SoC", 5), ("SSD", 3), ("Battery", 3)])
        case .dense:
            cores = coreInputs([("Efficiency", 4), ("Performance", 20), ("Super", 8)])
            volumes = volumeInputs(count: 4)
            interfaces = interfaceInputs(count: 3)
            sensors = sensorInputs([("CPU", 20), ("GPU", 8), ("SoC", 6), ("SSD", 3), ("Battery", 3)])
        case .minimal:
            cores = coreInputs([("Efficiency", 2), ("Performance", 8)])
            volumes = volumeInputs(count: 1)
            interfaces = interfaceInputs(count: 1)
            // Two invalid readings only: both are dropped, so no sensor remains.
            sensors = [RingSensorInput(group: "CPU", name: "CPU die", celsius: 130),
                       RingSensorInput(group: "SoC", name: "SoC probe", celsius: -5)]
        }

        let cpuParts = RingPartBuilder.cpu(cores: cores)
        let diskParts = RingPartBuilder.disk(volumes: volumes)
        let networkParts = RingPartBuilder.network(interfaces: interfaces)
        let temperatureParts = RingPartBuilder.temperature(sensors: sensors)

        let total = cores.map(\.usagePercent).reduce(0, +) / Double(cores.count)
        let user = total * 0.62
        let system = total * 0.30
        let cpu = CPUSample(totalUsagePercent: total, userPercent: user, systemPercent: system,
                            idlePercent: 100 - total)

        let boot = volumes.first { $0.isBoot } ?? volumes[0]
        let disk = DiskSample(usedBytes: boot.usedBytes, freeBytes: boot.totalBytes - boot.usedBytes,
                              totalBytes: boot.totalBytes, readBytesPerSec: 18_000_000,
                              writeBytesPerSec: 6_000_000)

        let network = NetworkSample(downBytesPerSec: interfaces.reduce(0) { $0 + $1.downBytesPerSec },
                                    upBytesPerSec: interfaces.reduce(0) { $0 + $1.upBytesPerSec },
                                    interfaceName: interfaces.first?.name, localIP: nil)

        // One reading per sensor so the Temperature gauge sees the same hottest sensor as the
        // parts; invalid inputs stay in so the mapper's own filter is exercised.
        let temperature = TemperatureSample(thermalState: .nominal,
                                            sensors: sensors.map { TempReading(label: $0.name, celsius: $0.celsius) })

        return RingPartFixtureSet(name: name, cpuParts: cpuParts, diskParts: diskParts,
                                  networkParts: networkParts, temperatureParts: temperatureParts,
                                  cpu: cpu, disk: disk, network: network, temperature: temperature)
    }

    // MARK: Inputs

    private static func coreInputs(_ classes: [(String, Int)]) -> [RingCoreInput] {
        var out: [RingCoreInput] = []
        var n = 0
        for (group, count) in classes {
            for i in 0..<count {
                let prefix = String(group.prefix(1))
                out.append(RingCoreInput(id: "cpu\(n)", name: "\(prefix)\(i + 1)", group: group,
                                         usagePercent: Double(8 + (n * 17) % 71)))
                n += 1
            }
        }
        return out
    }

    private static let volumeNames = ["Macintosh HD", "Archive", "Backup", "Scratch"]

    private static func volumeInputs(count: Int) -> [RingVolumeInput] {
        let gib: UInt64 = 1_073_741_824
        return (0..<count).map { i in
            let total = [994, 2000, 4000, 500][i % 4] * gib
            let used = total / 100 * UInt64([62, 35, 81, 12][i % 4])
            return RingVolumeInput(id: "vol\(i)", name: volumeNames[i % volumeNames.count],
                                   usedBytes: used, totalBytes: total, isBoot: i == 0)
        }
    }

    private static let interfaceNames = ["Wi-Fi", "Ethernet", "iPhone USB"]

    private static func interfaceInputs(count: Int) -> [RingInterfaceInput] {
        (0..<count).map { i in
            RingInterfaceInput(id: "en\(i)", name: interfaceNames[i % interfaceNames.count],
                               downBytesPerSec: [4_500_000, 250_000, 12_000][i % 3],
                               upBytesPerSec: [600_000, 40_000, 800][i % 3])
        }
    }

    private static func sensorInputs(_ roles: [(String, Int)]) -> [RingSensorInput] {
        var out: [RingSensorInput] = []
        var n = 0
        for (role, count) in roles {
            for i in 0..<count {
                out.append(RingSensorInput(group: role, name: "\(role) sensor \(i + 1)",
                                           celsius: Double(38 + (n * 7) % 37) + 0.5))
                n += 1
            }
        }
        return out
    }
}

#endif
