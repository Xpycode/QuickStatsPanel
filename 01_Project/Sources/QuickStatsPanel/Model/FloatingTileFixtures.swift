import Foundation

#if DEBUG

/// Fixture sets of the floating-tile prototype (`--floating-tiles-fixture=`).
///
///     cpu-network, network-cpu   the two-stat interaction journey (Wave 1)
///     all                        every stat, in declaration order, typical readings
///     all-reversed               every stat in reverse saved order (Uptime is the large tile)
///     all-hot                    every stat, with high usage on the percentage stats
///     all-live                   every stat; readings keep changing (digit widths included)
///     subset                     five stats in a non-default saved order
///     one                        Memory only
///     empty                      no enabled stats
///     unavailable                every stat enabled; Battery, GPU, Fans and Power have no reading
enum FloatingTileFixtureName: String, CaseIterable, Sendable {
    case cpuNetwork = "cpu-network"
    case networkCPU = "network-cpu"
    case all
    case allReversed = "all-reversed"
    case allHot = "all-hot"
    case allLive = "all-live"
    case subset
    case one
    case empty
    case unavailable

    /// Saved order of the enabled stats; the first is the large tile.
    var enabledKinds: [StatKind] {
        switch self {
        case .cpuNetwork: return [.cpu, .network]
        case .networkCPU: return [.network, .cpu]
        case .all, .allHot, .allLive, .unavailable: return StatKind.allCases
        case .allReversed: return StatKind.allCases.reversed()
        case .subset: return [.disk, .battery, .uptime, .memory, .temps]
        case .one: return [.memory]
        case .empty: return []
        }
    }

    /// Full saved order: the enabled stats first, the rest after them (disabled).
    var statOrder: [StatKind] {
        enabledKinds + StatKind.allCases.filter { !enabledKinds.contains($0) }
    }

    /// Stats that keep their identity but have no reading.
    var unavailableKinds: Set<StatKind> {
        self == .unavailable ? [.battery, .gpu, .fan, .power] : []
    }

    /// True when the percentage stats are seeded high (amber/red coverage).
    var isHot: Bool { self == .allHot }

    /// True when a disposable timer keeps changing the readings.
    var drifts: Bool { self == .allLive }
}

/// Builds the prototype's isolated launch state. Nothing here touches the standard defaults
/// domain or the retained history location.
enum FloatingTileFixtures {

    /// A fresh isolated defaults suite seeded with the fixture's stat choices. Any earlier content
    /// under the same (per-launch unique) name is discarded first. Returns nil only if the suite
    /// cannot be created, in which case the caller must not fall back to standard defaults.
    static func isolatedDefaults(for options: FloatingTilePrototypeOptions) -> UserDefaults? {
        guard let defaults = UserDefaults(suiteName: options.defaultsSuiteName) else { return nil }
        defaults.removePersistentDomain(forName: options.defaultsSuiteName)
        AppSettings.seedPrototypeDefaults(defaults, statOrder: options.fixture.statOrder,
                                          enabled: options.fixture.enabledKinds, anchor: .screenCenter)
        return defaults
    }

    /// Removes the isolated defaults suite (called once the app no longer writes settings).
    static func removeIsolatedDefaults(for options: FloatingTilePrototypeOptions) {
        UserDefaults(suiteName: options.defaultsSuiteName)?.removePersistentDomain(forName: options.defaultsSuiteName)
        do { try FileManager.default.removeItem(at: options.defaultsFile) }
        catch CocoaError.fileNoSuchFile {}
        catch { NSLog("Isolated prototype defaults not removed: %@", error.localizedDescription) }
    }

    /// Disposable store: no samplers, deterministic readings, a transfer-history root of its own
    /// that is removed after the termination flush, and history period queries that publish on
    /// selection although automatic scheduling is off.
    @MainActor
    static func makeStore(options: FloatingTilePrototypeOptions) -> StatsStore {
        let root = options.historyRoot
        let transfers = FloatingTileFixtureTransfers()
        let store = StatsStore(transferHistoryRoot: root, transferHistoryAutomaticallySchedules: false,
                               transferBoundaryReset: { stat, id in transfers.reset(stat, requestID: id) },
                               publishesTransferQueriesOnSelection: true)
        store.disposableTransferHistoryRoot = root
        store.seedRingFixture(unavailable: options.fixture.unavailableKinds)
        if options.fixture.isHot { applyHotReadings(to: store) }
        store.startTransferHistory()
        if let controller = store.transferHistoryController { transfers.attach(controller) }
        if options.fixture.drifts { FloatingTileFixtureDrift.start(store) }
        return store
    }

    /// High usage on the percentage stats, covering both band edges: CPU 91 (high), Memory 85
    /// (high), Disk 79.9 (elevated, the boundary), GPU 50 (elevated, the boundary) and Battery at
    /// 12% charge (88 drained: high).
    @MainActor
    static func applyHotReadings(to store: StatsStore) {
        store.cpu.totalUsagePercent = 91
        store.cpu.userPercent = 70
        store.cpu.systemPercent = 21
        store.cpu.idlePercent = 9
        store.memory.usedBytes = UInt64(Double(store.memory.totalBytes) * 0.85)
        store.disk.usedBytes = UInt64(Double(store.disk.totalBytes) * 0.799)
        store.disk.freeBytes = store.disk.totalBytes - store.disk.usedBytes
        if store.gpu.isAvailable { store.gpu.utilizationPercent = 50 }
        if store.battery.isPresent { store.battery.percent = 12 }
    }
}

/// Disposable transfer history for the fixture store: one fixture generation per stat, a seeded
/// minute of observed activity (so totals, graph and "Since reset" are non-empty), and a
/// boundary-reset hook standing in for the samplers the fixture never starts. Everything goes
/// into the store's temporary history root; nothing reads a hardware counter.
///
/// `reset` is called on the history controller's queue and only enqueues events, as the real
/// sampler callback must.
final class FloatingTileFixtureTransfers: @unchecked Sendable {
    private struct Stream { let generation: UUID; var sequence: UInt64; var last: TransferTimestamp }

    /// Seeded history: `seedSteps` observations of `seedStep` seconds ending now.
    static let seedSteps = 12
    static let seedStep: TimeInterval = 5

    private let lock = NSLock()
    private let clock: any TransferClock
    private var controller: TransferHistoryController?
    private var streams: [TransferStat: Stream] = [:]

    init(clock: any TransferClock = SystemTransferClock()) { self.clock = clock }

    /// Admits one generation per stat and seeds a minute of varied activity. Without a valid boot
    /// identity the timeline rejects the events and the card simply shows no history.
    func attach(_ controller: TransferHistoryController) {
        let now = clock.now()
        lock.withLock {
            self.controller = controller
            for (index, stat) in TransferStat.allCases.enumerated() {
                let generation = UUID()
                controller.admitGeneration(generation, for: stat)
                var stream = Stream(generation: generation, sequence: 0, last: Self.timestamp(now, offset: -Double(Self.seedSteps) * Self.seedStep))
                for step in 0..<Self.seedSteps {
                    let end = Self.timestamp(now, offset: -Double(Self.seedSteps - 1 - step) * Self.seedStep)
                    let scale = UInt64([3, 8, 21, 5, 13, 34, 2, 55, 9, 17, 4, 26][step % 12])
                    let bytes = TransferBytes(first: scale * 1_400_000 * UInt64(index + 1), second: scale * 260_000)
                    stream.sequence += 1
                    controller.ingest(.observation(Self.observation(stat, stream, end: end, bytes: bytes)))
                    stream.last = end
                }
                streams[stat] = stream
            }
        }
    }

    /// The boundary reset the real sampler would perform: an observation up to now, then the
    /// marker at a higher sequence. Returns false when no fixture stream exists.
    func reset(_ stat: TransferStat, requestID: UUID) -> Bool {
        lock.withLock {
            guard let controller, var stream = streams[stat] else { return false }
            let now = clock.now()
            guard now.continuousTime > stream.last.continuousTime else { return false }
            stream.sequence += 1
            controller.ingest(.observation(Self.observation(stat, stream, end: now, bytes: .zero)))
            stream.sequence += 1
            controller.ingest(.reset(TransferResetMarker(stat: stat, generation: stream.generation,
                                                         sequence: stream.sequence, timestamp: now, requestID: requestID)))
            stream.last = now
            streams[stat] = stream
            return true
        }
    }

    private static func observation(_ stat: TransferStat, _ stream: Stream, end: TransferTimestamp,
                                    bytes: TransferBytes) -> TransferObservation {
        TransferObservation(generation: stream.generation, sequence: stream.sequence, timestamp: end,
                            interval: TransferInterval(start: stream.last.continuousTime, end: end.continuousTime,
                                                       bytes: bytes, stat: stat, coverage: .complete),
                            accountingOverflow: false)
    }

    private static func timestamp(_ now: TransferTimestamp, offset: TimeInterval) -> TransferTimestamp {
        TransferTimestamp(continuousTime: now.continuousTime + offset, wallTime: now.wallTime.addingTimeInterval(offset),
                          bootID: now.bootID)
    }
}

/// Changes a disposable store's readings on a timer, so value changes (including digit-count
/// changes: 9% to 100%, KB/s to MB/s) can be checked against frozen tile frames. It only writes
/// fixture values to the store; no sampler runs.
@MainActor
final class FloatingTileFixtureDrift {
    private static var running: [FloatingTileFixtureDrift] = []
    private weak var store: StatsStore?
    private var step = 0
    private var timer: Timer?

    static func start(_ store: StatsStore) {
        let drift = FloatingTileFixtureDrift(store)
        running.append(drift)
        drift.timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            MainActor.assumeIsolated { drift.tick() }
        }
    }

    private init(_ store: StatsStore) { self.store = store }

    private func tick() {
        guard let store else { timer?.invalidate(); return }
        step += 1
        let cpuSteps: [Double] = [9, 42, 100, 7, 63, 88, 100, 5]
        let rates: [Double] = [120_000, 4_200_000, 88_000_000, 900, 25_000_000, 640_000_000]
        store.cpu.totalUsagePercent = cpuSteps[step % cpuSteps.count]
        store.memory.usedBytes = UInt64(Double(store.memory.totalBytes) * [0.31, 0.56, 0.84, 0.49][step % 4])
        store.network.downBytesPerSec = rates[step % rates.count]
        store.network.upBytesPerSec = rates[(step + 3) % rates.count] / 8
        store.disk.readBytesPerSec = rates[(step + 1) % rates.count]
        store.disk.writeBytesPerSec = rates[(step + 4) % rates.count] / 4
        if store.gpu.isAvailable { store.gpu.utilizationPercent = cpuSteps[(step + 3) % cpuSteps.count] }
        if store.battery.isPresent { store.battery.percent = [76, 49.9, 12, 100][step % 4] }
    }
}

#endif
