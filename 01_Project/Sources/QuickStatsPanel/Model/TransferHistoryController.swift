import Foundation

/// All methods of this adapter are called on the history queue. Tests may block or fail the
/// adapter without running hardware, timers, application startup or a production profile.
protocol TransferHistoryStorage: AnyObject {
    func load(now: TransferTimestamp) -> TransferRepositoryLoadResult
    func commit(_ snapshot: TransferTimelineSnapshot) -> TransferPersistenceStatus
}
extension TransferHistoryRepository: TransferHistoryStorage {}

/// One process-lifetime owner. Neither construction nor a public action performs synchronous
/// I/O on its caller. FIFO queue admission keeps callbacks arriving during recovery behind load.
final class TransferHistoryController: @unchecked Sendable {
    typealias Publisher = @Sendable (TransferStat, UInt64, TransferHistoryPeriod, TransferHistoryPresentation) -> Void
    private struct PendingReset {
        let id: UUID
        let generation: UUID
        let completion: @Sendable (String?) -> Void
    }
    private let queue = DispatchQueue(label: "com.sim.QuickStatsPanel.transfer-history", qos: .utility)
    private let clock: any TransferClock
    private let factory: @Sendable () -> any TransferHistoryStorage
    private let automaticallySchedules: Bool
    private let publisher: Publisher
    // Everything below is confined to queue, including repository creation and destruction.
    private var repository: (any TransferHistoryStorage)?
    private var timeline: TransferTimeline?
    private var started = false
    private var timer: DispatchSourceTimer?
    private var selected: [TransferStat: TransferHistoryPeriod] = [.network: .minute, .disk: .minute]
    private var pendingPresentation = Set<TransferStat>()
    private var queryScheduled = false
    private var revision: UInt64 = 0
    private var peaks = TransferGraphPeakCache()
    private var dirtySince: TimeInterval?
    private var lastSaveAttempt: TimeInterval?
    private var saveDeadline: DispatchWorkItem?
    private var lastSaved: Date?
    private var durability: TransferHistorySaveState = .loading
    private var recoveryWarning: String?
    private var pendingReset: [TransferStat: PendingReset] = [:]
    private var lastResetTime: [TransferStat: TimeInterval] = [:]
    private var lastResetID: [TransferStat: UUID] = [:]

    convenience init(root: URL, clock: any TransferClock = SystemTransferClock(),
                     automaticallySchedules: Bool = true, onPresentation: @escaping Publisher) {
        self.init(clock: clock, automaticallySchedules: automaticallySchedules,
                  repositoryFactory: { TransferHistoryRepository(root: root) }, onPresentation: onPresentation)
    }

    init(clock: any TransferClock, automaticallySchedules: Bool = true,
         repositoryFactory: @escaping @Sendable () -> any TransferHistoryStorage,
         onPresentation: @escaping Publisher) {
        self.clock = clock; self.automaticallySchedules = automaticallySchedules
        factory = repositoryFactory; publisher = onPresentation
    }

    deinit { saveDeadline?.cancel(); timer?.setEventHandler {}; timer?.cancel() }

    func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            let store = factory(); repository = store
            let now = clock.now(), loaded = store.load(now: now)
            timeline = loaded.snapshot.map { TransferTimeline(restoring: $0, now: now) } ?? TransferTimeline(now: now)
            lastSaved = loaded.status.savedAt
            if !loaded.status.diagnostics.isEmpty || loaded.status.writeBlocked {
                let message = loaded.status.message ?? "Some saved history is unavailable."
                recoveryWarning = message
                durability = loaded.status.writeBlocked || loaded.status.diagnostics.contains(.storageFailure)
                    ? .failed(lastSaved: lastSaved, message: message) : .recovered(lastSaved: lastSaved, message: message)
            } else if let date = lastSaved { durability = .saved(date) }
            else { durability = .unsaved(lastSaved: nil) }
            pendingPresentation = Set(TransferStat.allCases)
            publishPending()
            if automaticallySchedules {
                let source = DispatchSource.makeTimerSource(queue: queue)
                source.schedule(deadline: .now() + 1, repeating: 1)
                source.setEventHandler { [weak self] in self?.maintain() }
                timer = source; source.resume()
            }
        }
    }

    func admitGeneration(_ generation: UUID, for stat: TransferStat) {
        queue.async { [self] in
            guard let watermark = timeline?.watermark(for: stat), watermark.admission < UInt64.max,
                  timeline?.admitGeneration(generation, for: stat, admission: watermark.admission + 1) == true else { return }
            if let pending = pendingReset.removeValue(forKey: stat) {
                pending.completion("Sampling restarted before the reset boundary was confirmed.")
            }
            markDirty(); requestPresentation(stat)
        }
    }

    func ingest(_ event: TransferEvent) {
        queue.async { [self] in
            let stat: TransferStat
            switch event {
            case .observation(let observation): stat = observation.interval.stat
            case .reset(let marker):
                stat = marker.stat
                guard let pending = pendingReset[stat], pending.id == marker.requestID,
                      pending.generation == marker.generation else { return }
            }
            guard timeline?.ingest(event) == true else {
                if case .reset(let marker) = event,
                   let pending = pendingReset[stat], pending.id == marker.requestID {
                    pendingReset.removeValue(forKey: stat)
                    pending.completion("The reset boundary was stale; totals were kept.")
                }
                return
            }
            markDirty(); requestPresentation(stat)
            if case .reset(let marker) = event, let pending = pendingReset.removeValue(forKey: stat) {
                let error = save()
                let committed = savedWatermarks[stat]
                let confirmed = committed?.generation == marker.generation
                    && committed?.sequence.map { $0 >= marker.sequence } == true
                pending.completion(error ?? (confirmed ? nil : "Reset is unsaved; its durable boundary was not confirmed."))
            }
        }
    }

    func selectPeriod(_ period: TransferHistoryPeriod, for stat: TransferStat) {
        queue.async { [self] in selected[stat] = period; requestPresentation(stat) }
    }

    /// Action runs off-main. Its sampler callback must only enqueue events (never queue.sync).
    /// Success resolves only after the matching ordered marker is included in a durable commit.
    func requestReset(stat: TransferStat, requestID: UUID,
                      performBoundaryReset: @escaping @Sendable (UUID) -> Bool,
                      completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            let now = clock.now()
            guard pendingReset[stat] == nil else { completion("A reset is already pending."); return }
            guard requestID != lastResetID[stat] else { completion("This reset request was already handled."); return }
            guard now.isValid, let generation = timeline?.watermark(for: stat).generation else {
                completion("Sampling is not ready to reset."); return
            }
            guard lastResetTime[stat].map({ now.continuousTime - $0 >= TransferResourceBudget.minimumResetInterval }) ?? true else {
                completion("Wait one second before resetting these totals again."); return
            }
            pendingReset[stat] = PendingReset(id: requestID, generation: generation, completion: completion)
            lastResetID[stat] = requestID
            if performBoundaryReset(requestID) {
                lastResetTime[stat] = now.continuousTime
            } else {
                pendingReset.removeValue(forKey: stat)
                completion("The sampler could not confirm a reset boundary; totals were kept.")
            }
        }
    }

    /// Caller drains its sampler queues before enqueueing this operation. A stalled filesystem
    /// can stall this queue but cannot block MainActor; the application owns its quit deadline.
    func flush(completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in completion(save()) }
    }

    /// A deterministic queue/presentation barrier, also useful after a manual maintenance tick.
    func synchronize(completion: @escaping @Sendable () -> Void) {
        queue.async { [self] in publishPending(); completion() }
    }

    func maintenance() { queue.async { [self] in maintain() } }

    private var savedWatermarks: [TransferStat: TransferTimelineWatermark] = [:]

    private func markDirty() {
        if dirtySince == nil { dirtySince = clock.now().continuousTime }
        // Keep a failed write visible until a later commit actually succeeds.
        if case .failed = durability {} else { durability = .unsaved(lastSaved: lastSaved) }
        scheduleCheckpoint()
    }

    private func scheduleCheckpoint() {
        guard automaticallySchedules, saveDeadline == nil, let dirtySince else { return }
        let delay = max(0, max(dirtySince, lastSaveAttempt ?? dirtySince) + 30 - clock.now().continuousTime)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveDeadline = nil
            if self.dirtySince != nil { _ = self.save() }
        }
        saveDeadline = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func maintain() {
        guard let oldCounts = timeline.map({ t in TransferStat.allCases.map { t.retainedIntervalCount(for: $0) } }) else { return }
        let now = clock.now()
        timeline?.maintenance(now: now)
        let counts = TransferStat.allCases.map { timeline!.retainedIntervalCount(for: $0) }
        if oldCounts != counts { markDirty() }
        for stat in TransferStat.allCases { requestPresentation(stat) }
        if let dirtySince, now.continuousTime - max(dirtySince, lastSaveAttempt ?? dirtySince) >= 30 { _ = save() }
    }

    @discardableResult private func save() -> String? {
        guard let repository, let snapshot = timeline?.snapshot(now: clock.now()) else { return "History is not ready to save." }
        saveDeadline?.cancel(); saveDeadline = nil
        lastSaveAttempt = clock.now().continuousTime
        durability = .saving(lastSaved: lastSaved)
        let status = repository.commit(snapshot)
        savedWatermarks = status.savedWatermarks
        if status.isDurable {
            lastSaved = status.savedAt; dirtySince = nil
            durability = status.savedAt.map { .saved($0) } ?? .unsaved(lastSaved: nil)
        } else {
            if dirtySince == nil { dirtySince = clock.now().continuousTime }
            durability = .failed(lastSaved: lastSaved, message: status.message ?? "History could not be saved.")
        }
        scheduleCheckpoint()
        for stat in TransferStat.allCases { requestPresentation(stat) }
        publishPending()
        return status.isDurable ? nil : "Reset or history is unsaved: \(status.message ?? "storage unavailable")"
    }

    private func requestPresentation(_ stat: TransferStat) {
        pendingPresentation.insert(stat)
        guard !queryScheduled, automaticallySchedules else { return }
        queryScheduled = true
        queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }; self.queryScheduled = false; self.publishPending()
        }
    }

    private func publishPending() {
        guard let timeline, !pendingPresentation.isEmpty else { return }
        let now = clock.now() // One timestamp is shared by every graph, total and coverage query.
        revision &+= 1
        let requested = pendingPresentation; pendingPresentation.removeAll()
        for stat in TransferStat.allCases where requested.contains(stat) {
            let period = selected[stat] ?? .minute
            let result = timeline.query(stat: stat, now: now, duration: period.duration)
            let graph = peaks.graph(result: result, period: period, revision: revision)
            let presentation = TransferHistoryPresentation(result: result, period: period,
                cumulative: timeline.cumulative(for: stat), durability: durability,
                warnings: timeline.warnings, graph: graph, persistenceWarning: recoveryWarning)
            publisher(stat, revision, period, presentation)
        }
    }
}
