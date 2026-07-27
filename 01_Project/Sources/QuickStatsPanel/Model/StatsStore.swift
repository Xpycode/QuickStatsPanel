import Foundation
import Observation
import SwiftUI

/// Owns the live samplers and publishes their latest values to SwiftUI.
///
/// `@Observable` + `@MainActor`: views read `cpu`/`memory` in their body and get
/// automatic updates; all mutation happens on the main actor. Samplers run on
/// background queues and hop back via `Task { @MainActor in … }` (the same
/// pattern StatsWindow's `AppStore` uses — see decision D-005).
@Observable
@MainActor
final class StatsStore {
    var cpu: CPUSample = .empty
    var memory: MemorySample = .empty
    var disk: DiskSample = .empty
    var network: NetworkSample = .empty
    var battery: BatterySample = .empty
    var gpu: GPUSample = .empty
    var fan: FanSample = .empty
    var power: PowerSample = .empty
    var temps: TemperatureSample = .empty
    var loadAverage: LoadSample = .empty
    var uptime: UptimeSample = .empty
    var topProcesses: TopProcessesSample = .empty
    private(set) var isRunning = false

    // MARK: - History (D-025)

    /// How much past to keep for the activity graphs.
    static let historyDuration: TimeInterval = 60

    /// Retained sample count — **derived from the duration and the user's refresh
    /// interval, never a fixed number**. At 0.5 s the buffer holds 120 samples for
    /// the same minute of history; at 5 s it holds 12. A hardcoded count would
    /// silently mean "two minutes" or "five seconds" depending on the slider.
    private static func historyCapacity(interval: TimeInterval) -> Int {
        Int((historyDuration / max(interval, 0.1)).rounded(.up))
    }

    // Whole samples, not extracted numbers, so switching a tile's value mode
    // re-plots the history already collected (see `RingBuffer`).
    private(set) var cpuHistory = RingBuffer<CPUSample>(capacity: 1)
    private(set) var memoryHistory = RingBuffer<MemorySample>(capacity: 1)
    private(set) var diskHistory = RingBuffer<DiskSample>(capacity: 1)
    private(set) var networkHistory = RingBuffer<NetworkSample>(capacity: 1)
    private(set) var gpuHistory = RingBuffer<GPUSample>(capacity: 1)

    /// Per-series peak memory for `.perSeriesPeak` graphs, in the same shape as
    /// `lastBands` below: `@ObservationIgnored` because it is scale bookkeeping
    /// written *during* a body read, and tracking it would risk a render loop.
    @ObservationIgnored private var lastPeaks: [String: Double] = [:]

    /// Resolve the value that maps to a full-height bar for one graph series,
    /// remembering it so `PeakStrategy` can smooth or ratchet across ticks.
    ///
    /// ⚠️ Called from `visibleStats`, which runs in **every** body pass that reads
    /// it — currently the strip *and* the open detail card, so twice per tick, and
    /// more if a view re-renders for an unrelated reason. The two strategies that
    /// are idempotent in `previous` (plain window max, and `max` for a session
    /// peak) are unaffected. A **decaying** peak is not: it would fall once per
    /// render rather than once per sample, so its rate would depend on how many
    /// panels happen to be open. Decay needs a tick counter or a timestamp, not a
    /// per-call step.
    func graphPeak(_ kind: StatKind, series: String, windowMax: Double) -> Double {
        let key = "\(kind.rawValue).\(series)"
        let resolved = PeakStrategy.resolve(windowMax: windowMax,
                                            previous: lastPeaks[key] ?? 0)
        lastPeaks[key] = resolved
        return resolved
    }

    private var cpuSampler: CPUSampler?
    private var memorySampler: MemorySampler?
    private var diskSampler: DiskSampler?
    private var networkSampler: NetworkSampler?
    private var batterySampler: BatterySampler?
    private var gpuSampler: GPUSampler?
    private var fanSampler: FanSampler?
    private var powerSampler: PowerSampler?
    private var temperatureSampler: TemperatureSampler?
    private var loadAverageSampler: LoadAverageSampler?
    private var uptimeSampler: UptimeSampler?
    private var topProcessSampler: TopProcessSampler?

    /// The top-processes sampler spawns `top`, which is costly, so it runs ONLY
    /// while the panel is on screen (set via `setPanelVisible`). The cheap
    /// in-process samplers run continuously; this one is gated.
    private var panelVisible = false

    /// Per-stat last status band, the memory the hysteresis needs (a value
    /// hovering at a boundary holds its band until it crosses by the margin).
    /// `@ObservationIgnored` because it's internal caching, not published state —
    /// it's written while resolving tints inside `visibleStats` (a body read), and
    /// tracking it would risk an observation loop.
    @ObservationIgnored private var lastBands: [StatKind: Band] = [:]

    /// Resolve a stat's status band (with hysteresis vs its previous band) and the
    /// theme color for it, in one call. Reads the *live* theme, so switching preset
    /// recolors immediately on the next body pass; battery passes `reversed: true`
    /// so a low charge reads "hot" — replacing the old `100 - percent` hack.
    func tint(for kind: StatKind, percent: Double, reversed: Bool = false) -> (band: Band, color: Color) {
        let resolved = AppSettings.shared.theme.tint(
            forPercent: percent, reversed: reversed, previous: lastBands[kind])
        lastBands[kind] = resolved.band
        return resolved
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Refresh cadence comes from user settings (read once per run; `restart()`
        // re-reads it after the user changes the interval).
        let interval = AppSettings.shared.interval

        // Rebuild the history buffers for this interval. This also **clears** them,
        // which is the point: `restart()` runs on an interval change, and splicing
        // points sampled 1 s apart onto points sampled 5 s apart would draw a graph
        // whose x-axis silently changes scale partway across.
        let capacity = Self.historyCapacity(interval: interval)
        cpuHistory = RingBuffer(capacity: capacity)
        memoryHistory = RingBuffer(capacity: capacity)
        diskHistory = RingBuffer(capacity: capacity)
        networkHistory = RingBuffer(capacity: capacity)
        gpuHistory = RingBuffer(capacity: capacity)
        lastPeaks.removeAll()   // peaks belong to the discarded time base too

        let cpu = CPUSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in
                self?.cpu = sample
                self?.cpuHistory.append(sample)
            }
        }
        let mem = MemorySampler(interval: interval) { [weak self] sample in
            Task { @MainActor in
                self?.memory = sample
                self?.memoryHistory.append(sample)
            }
        }
        let disk = DiskSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in
                self?.disk = sample
                self?.diskHistory.append(sample)
            }
        }
        let net = NetworkSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in
                self?.network = sample
                self?.networkHistory.append(sample)
            }
        }
        let battery = BatterySampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.battery = sample }
        }
        let gpu = GPUSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in
                self?.gpu = sample
                self?.gpuHistory.append(sample)
            }
        }
        let fan = FanSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.fan = sample }
        }
        let power = PowerSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.power = sample }
        }
        let temps = TemperatureSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.temps = sample }
        }
        let load = LoadAverageSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.loadAverage = sample }
        }
        let uptime = UptimeSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.uptime = sample }
        }
        let topProc = TopProcessSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.topProcesses = sample }
        }
        cpu.start()
        mem.start()
        disk.start()
        net.start()
        battery.start()
        gpu.start()
        fan.start()
        power.start()   // un-gated: IOReport reads are cheap, run continuously like GPU/Fan
        temps.start()   // un-gated: thermalState + IOHID reads are cheap, like Power
        load.start()
        uptime.start()
        if panelVisible { topProc.start() }   // gated; the others run continuously
        self.cpuSampler = cpu
        self.memorySampler = mem
        self.diskSampler = disk
        self.networkSampler = net
        self.batterySampler = battery
        self.gpuSampler = gpu
        self.fanSampler = fan
        self.powerSampler = power
        self.temperatureSampler = temps
        self.loadAverageSampler = load
        self.uptimeSampler = uptime
        self.topProcessSampler = topProc
    }

    func stop() {
        cpuSampler?.stop()
        memorySampler?.stop()
        diskSampler?.stop()
        networkSampler?.stop()
        batterySampler?.stop()
        gpuSampler?.stop()
        fanSampler?.stop()
        powerSampler?.stop()
        temperatureSampler?.stop()
        loadAverageSampler?.stop()
        uptimeSampler?.stop()
        topProcessSampler?.stop()
        cpuSampler = nil
        memorySampler = nil
        diskSampler = nil
        networkSampler = nil
        batterySampler = nil
        gpuSampler = nil
        fanSampler = nil
        powerSampler = nil
        temperatureSampler = nil
        loadAverageSampler = nil
        uptimeSampler = nil
        topProcessSampler = nil
        isRunning = false
    }

    /// Tear down and re-create the samplers so they pick up a new refresh
    /// interval. Wired to `AppSettings.onIntervalChanged`.
    func restart() {
        stop()
        start()
    }

    /// Drive the (costly) top-processes sampler from the panel's visibility: start
    /// it when the panel appears, stop it and clear the stale list when it hides.
    /// Called from `AppDelegate`'s panel visibility hook.
    func setPanelVisible(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        if visible {
            topProcessSampler?.start()
        } else {
            topProcessSampler?.stop()
            topProcesses = .empty   // don't show last session's processes next summon
        }
    }
}
