import Foundation
import Observation

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
    var loadAverage: LoadSample = .empty
    var uptime: UptimeSample = .empty
    var topProcesses: TopProcessesSample = .empty
    private(set) var isRunning = false

    private var cpuSampler: CPUSampler?
    private var memorySampler: MemorySampler?
    private var diskSampler: DiskSampler?
    private var networkSampler: NetworkSampler?
    private var batterySampler: BatterySampler?
    private var loadAverageSampler: LoadAverageSampler?
    private var uptimeSampler: UptimeSampler?
    private var topProcessSampler: TopProcessSampler?

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Refresh cadence comes from user settings (read once per run; `restart()`
        // re-reads it after the user changes the interval).
        let interval = AppSettings.shared.interval

        let cpu = CPUSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.cpu = sample }
        }
        let mem = MemorySampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.memory = sample }
        }
        let disk = DiskSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.disk = sample }
        }
        let net = NetworkSampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.network = sample }
        }
        let battery = BatterySampler(interval: interval) { [weak self] sample in
            Task { @MainActor in self?.battery = sample }
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
        load.start()
        uptime.start()
        topProc.start()
        self.cpuSampler = cpu
        self.memorySampler = mem
        self.diskSampler = disk
        self.networkSampler = net
        self.batterySampler = battery
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
        loadAverageSampler?.stop()
        uptimeSampler?.stop()
        topProcessSampler?.stop()
        cpuSampler = nil
        memorySampler = nil
        diskSampler = nil
        networkSampler = nil
        batterySampler = nil
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
}
