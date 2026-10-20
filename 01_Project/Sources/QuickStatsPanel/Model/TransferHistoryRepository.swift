import Foundation
import Darwin

enum TransferPersistenceDiagnostic: String, Sendable, Hashable {
    case missingCumulative, corruptCheckpoint, corruptSegment, staleCheckpoint
    case unsupportedVersion, storageFailure, resourceLimit
}

enum TransferCommitStage: CaseIterable {
    case segmentsSealed, checkpointPrepared, priorReplaced, currentReplaced, garbageCollected
}

struct TransferPersistenceStatus: Sendable {
    var savedAt: Date?
    var savedWatermarks: [TransferStat: TransferTimelineWatermark] = [:]
    var diagnostics: Set<TransferPersistenceDiagnostic> = []
    /// True only after file synchronization, atomic replacement and directory synchronization.
    var isDurable = false
    var writeBlocked = false
    var checkpointBytes = 0
    var message: String?
}

struct TransferRepositoryLoadResult: Sendable {
    var snapshot: TransferTimelineSnapshot?
    var status: TransferPersistenceStatus
}

/// Synchronous by design: construct/use exclusively on the controller's dedicated serial history
/// queue, never MainActor. No default root, singleton, timers, preferences or hardware access.
/// FileHandle synchronizes payloads; rename + directory fsync order their durable publication.
/// These system calls cannot bound a stalled filesystem; the controller bounds its quit wait.
final class TransferHistoryRepository {
    static let formatVersion: UInt32 = 1
    static let maximumCheckpointBytes = 256 * 1024
    static let maximumSegmentBytes = 32 + TransferResourceBudget.maximumRecordsPerSegmentPerStat * TransferInterval.packedSize
    static let maximumFiles = 1_200
    let root: URL
    private let faultInjector: ((TransferCommitStage) throws -> Void)?
    private var status = TransferPersistenceStatus()
    private var loaded = false
    private var committed: Data?
    private var currentReferences = Set<String>()
    private var priorReferences = Set<String>()
    private var knownFiles = Set<String>()
    private var rootBytes = 0
    private var rootFiles = 0
    private let fm = FileManager.default

    init(root: URL, faultInjector: ((TransferCommitStage) throws -> Void)? = nil) {
        self.root = root; self.faultInjector = faultInjector
    }

    func load(now: TransferTimestamp) -> TransferRepositoryLoadResult {
        loaded = true
        status = TransferPersistenceStatus()
        committed = nil; currentReferences.removeAll(); priorReferences.removeAll(); knownFiles.removeAll()
        do {
            guard fm.fileExists(atPath: root.path) else { return TransferRepositoryLoadResult(snapshot: nil, status: status) }
            var inventoryLimited = false
            do { try inventory() } catch Failure.limit {
                inventoryLimited = true; status.diagnostics.insert(.resourceLimit)
            }
            // Inspect both versions before any mutation; future-format evidence is never cleaned up.
            for name in ["checkpoint", "prior"] where fm.fileExists(atPath: url(name).path) {
                do {
                    if let version = try headerVersion(name), version != Self.formatVersion { throw Failure.unsupported }
                } catch Failure.unsupported { throw Failure.unsupported }
                catch {
                    // An uninspectable current may hide a future format. Recover the readable
                    // prior, but preserve both files until a subsequent load can inspect them.
                    status.writeBlocked = true; status.diagnostics.insert(.storageFailure)
                }
            }
            var candidate: Manifest?
            var candidateData: Data?
            for name in ["checkpoint", "prior"] where fm.fileExists(atPath: url(name).path) {
                do {
                    let data = try boundedRead(name, maximum: Self.maximumCheckpointBytes)
                    let manifest = try decodeManifest(data)
                    if candidate == nil {
                        candidate = manifest; candidateData = data
                        if name == "prior" { status.diagnostics.insert(.staleCheckpoint) }
                    } else { priorReferences = Set(manifest.references) }
                } catch Failure.unsupported { throw Failure.unsupported }
                catch { status.diagnostics.insert(.corruptCheckpoint) }
            }
            guard let manifest = candidate, let data = candidateData else {
                status.diagnostics.insert(.missingCumulative)
                status.message = "Saved totals could not be recovered; a new cumulative epoch is required."
                quarantineOne()
                return TransferRepositoryLoadResult(snapshot: nil, status: status)
            }
            committed = data; currentReferences = Set(manifest.references)
            var snapshot = manifest.snapshot
            for i in snapshot.stats.indices {
                var segments: [TransferTimelineSegment] = []
                var previousEnd: Double?
                for reference in manifest.sealed[i] where !inventoryLimited {
                    do {
                        let segment = try autoreleasepool {
                            try decodeSegment(try boundedRead(reference.name, maximum: Self.maximumSegmentBytes), reference: reference)
                        }
                        var candidateEnd = previousEnd
                        guard segment.records.allSatisfy({ raw in
                            let record = segment.placed(raw)
                            let valid = record.isValid && record.end <= snapshot.anchor.timelineTime
                                && (candidateEnd.map { record.start >= $0 } ?? true)
                                && (snapshot.stats[i].watermark.lastEventTime.map { record.end <= $0 } ?? false)
                            if valid { candidateEnd = record.end }; return valid
                        }) else { throw Failure.invalid("History segment times are invalid.") }
                        previousEnd = candidateEnd
                        segments.append(segment); knownFiles.insert(reference.name)
                    } catch Failure.unsupported { throw Failure.unsupported }
                    catch { status.diagnostics.insert(.corruptSegment) }
                }
                for active in snapshot.stats[i].segments {
                    if let first = active.records.first, let previousEnd, active.placed(first).start < previousEnd {
                        status.diagnostics.insert(.corruptSegment)
                    } else { segments.append(active) }
                }
                snapshot.stats[i].segments = segments
            }
            if inventoryLimited { snapshot.warnings.insert(.resourceLimit) }
            status.savedAt = manifest.savedAt
            status.savedWatermarks = Dictionary(uniqueKeysWithValues: snapshot.stats.map { ($0.stat, $0.watermark) })
            status.checkpointBytes = data.count
            status.isDurable = true
            if status.diagnostics.contains(.staleCheckpoint) {
                status.message = "Recovered an older checkpoint; observations after its saved time may be lost."
            } else if inventoryLimited {
                status.message = "Saved cumulative totals were recovered; history storage exceeds its safety limit."
            } else if status.diagnostics.contains(.corruptSegment) {
                status.message = "Some saved history is unreadable and appears as gaps; saved cumulative totals are retained."
            }
            return TransferRepositoryLoadResult(snapshot: snapshot, status: status)
        } catch { fail(error) }
        return TransferRepositoryLoadResult(snapshot: nil, status: status)
    }

    @discardableResult func commit(_ snapshot: TransferTimelineSnapshot) -> TransferPersistenceStatus {
        guard loaded else { fail(Failure.invalid("Load history before saving.")); return status }
        status.isDurable = false
        guard !status.writeBlocked else { return status }
        do {
            try validate(snapshot)
            try ensureRootDurable()
            try inventory()
            let manifest = try makeManifest(snapshot)
            // Only newly sealed/pruned chunks are encoded. Existing immutable chunks are shared by
            // both checkpoints. Snapshot ArraySlices never materialize a full-day copy.
            for i in snapshot.stats.indices {
                for segment in snapshot.stats[i].segments where segment.isSealed {
                    let reference = referenceFor(segment)
                    if !knownFiles.contains(reference.name) {
                        try autoreleasepool {
                            let data = try encodeSegment(segment)
                            try atomicWrite(data, name: reference.name)
                        }
                        knownFiles.insert(reference.name)
                    }
                }
            }
            try faultInjector?(.segmentsSealed)
            let data = try encodeManifest(manifest)
            try writePending(data)
            try faultInjector?(.checkpointPrepared)
            if let committed { try atomicWrite(committed, name: "prior") }
            try faultInjector?(.priorReplaced)
            try publishPending(as: "checkpoint")
            // At this point recovery sees the new commit, even if subsequent cleanup fails.
            priorReferences = currentReferences; currentReferences = Set(manifest.references)
            committed = data
            status.savedAt = manifest.savedAt
            status.savedWatermarks = Dictionary(uniqueKeysWithValues: snapshot.stats.map { ($0.stat, $0.watermark) })
            status.checkpointBytes = data.count
            status.isDurable = true
            status.diagnostics.remove(.storageFailure); status.diagnostics.remove(.resourceLimit)
            status.message = nil
            try faultInjector?(.currentReplaced)
            try garbageCollect()
            try faultInjector?(.garbageCollected)
        } catch {
            let published = status.isDurable
            fail(error)
            if published { status.isDurable = true; status.message = "History was saved; storage cleanup could not finish." }
        }
        return status
    }

    /// Only committed current/prior reference sets authorize removal. Does not prune live values;
    /// the timeline performs retention before snapshotting. Future formats disable this operation.
    @discardableResult func prune() -> TransferPersistenceStatus {
        guard loaded, !status.writeBlocked else { return status }
        do { try inventory(); try garbageCollect() } catch {
            let durable = status.isDurable; fail(error); status.isDurable = durable
        }
        return status
    }

    private struct Reference {
        var name: String
        var id: UUID
        var stat: TransferStat
        var count: Int
        var offset: Double
    }
    private struct Manifest {
        var savedAt: Date
        var snapshot: TransferTimelineSnapshot
        var sealed: [[Reference]]
        var references: [String] { sealed.flatMap { $0.map(\.name) } }
    }
    private enum Failure: Error { case invalid(String), unsupported, limit, io(Int32) }
    private func url(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: false) }
    private func fail(_ error: Error) {
        status.isDurable = false
        switch error {
        case Failure.unsupported:
            status.writeBlocked = true; status.diagnostics.insert(.unsupportedVersion)
            status.message = "A newer history format was preserved; saving is disabled."
        case Failure.limit:
            status.diagnostics.insert(.resourceLimit); status.message = "History storage exceeded its safety limit; changes remain unsaved."
        case Failure.invalid(let message):
            status.diagnostics.insert(.storageFailure); status.message = message
        default:
            status.diagnostics.insert(.storageFailure); status.message = "History could not be saved or read; live collection can continue."
        }
    }
    private func headerVersion(_ name: String) throws -> UInt32? {
        let values = try url(name).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        let handle = try FileHandle(forReadingFrom: url(name)); defer { try? handle.close() }
        guard let bytes = try handle.read(upToCount: 12), bytes.count == 12 else { return nil }
        return try? version(of: bytes)
    }
    private func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw Failure.io(errno) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw Failure.io(errno) }
    }
    private func ensureRootDurable() throws {
        var missing: [URL] = [], cursor = root
        while !fm.fileExists(atPath: cursor.path) {
            missing.append(cursor); let parent = cursor.deletingLastPathComponent()
            guard parent != cursor else { throw Failure.invalid("History directory is unavailable.") }
            cursor = parent
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for directory in missing.reversed() { try synchronizeDirectory(directory.deletingLastPathComponent()) }
    }
    private func inventory() throws {
        rootBytes = 0; rootFiles = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let entries = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsSubdirectoryDescendants]) else { throw Failure.invalid("History directory is unavailable.") }
        for case let entry as URL in entries {
            rootFiles += 1
            guard rootFiles <= Self.maximumFiles else { throw Failure.limit }
            let values = try entry.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size >= 0 else { throw Failure.invalid("History directory contains an unsupported entry.") }
            guard size <= TransferResourceBudget.maximumBytes - rootBytes else { throw Failure.limit }
            rootBytes += size
        }
    }
    private func boundedRead(_ name: String, maximum: Int) throws -> Data {
        let values = try url(name).resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
              size >= 20, size <= maximum else { throw Failure.invalid("History record has an invalid size.") }
        let handle = try FileHandle(forReadingFrom: url(name)); defer { try? handle.close() }
        guard let data = try handle.read(upToCount: maximum + 1), data.count == size else { throw Failure.invalid("History record was truncated.") }
        return data
    }
    private func writePending(_ data: Data, name: String = "pending") throws {
        guard data.count <= Self.maximumCheckpointBytes,
              rootBytes + data.count <= TransferResourceBudget.maximumBytes,
              rootFiles + 1 <= Self.maximumFiles else { throw Failure.limit }
        let path = url(name)
        if fm.fileExists(atPath: path.path) { try fm.removeItem(at: path) }
        guard fm.createFile(atPath: path.path, contents: nil) else { throw Failure.invalid("History temporary file could not be created.") }
        let handle = try FileHandle(forWritingTo: path)
        do { try handle.write(contentsOf: data); try handle.synchronize()
            // macOS fsync alone may leave drive caches unflushed after power loss.
            guard fcntl(handle.fileDescriptor, F_FULLFSYNC) == 0 else { throw Failure.io(errno) }
            try handle.close() }
        catch { try? handle.close(); throw error }
        rootBytes += data.count; rootFiles += 1
    }
    private func atomicWrite(_ data: Data, name: String) throws {
        try writePending(data, name: "temporary"); try publishPending(as: name, from: "temporary")
    }
    private func publishPending(as name: String, from temporary: String = "pending") throws {
        let oldSize = (try? url(name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard rename(url(temporary).path, url(name).path) == 0 else { throw Failure.io(errno) }
        rootBytes -= oldSize
        if oldSize > 0 { rootFiles -= 1 }
        try synchronizeDirectory(root)
        // Flush the rename and preceding directory fsync as well as the payload. This barrier
        // completes the transaction on supported local macOS filesystems; failure is unsaved.
        let handle = try FileHandle(forReadingFrom: url(name)); defer { try? handle.close() }
        guard fcntl(handle.fileDescriptor, F_FULLFSYNC) == 0 else { throw Failure.io(errno) }
    }
    private func garbageCollect() throws {
        let protected = currentReferences.union(priorReferences)
        guard let entries = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]) else { return }
        var count = 0
        for case let entry as URL in entries {
            count += 1; guard count <= Self.maximumFiles else { throw Failure.limit }
            let name = entry.lastPathComponent
            if (name.hasPrefix("segment-") && name.hasSuffix(".bin") && !protected.contains(name)) || name == "pending" || name == "temporary" {
                try fm.removeItem(at: entry); knownFiles.remove(name)
            }
        }
        try inventory()
    }
    private func quarantineOne() {
        // At most one bounded artifact. The original checkpoint stays available for diagnosis;
        // no whole-day segment or repeated timestamped quarantine copies can accumulate.
        guard !status.writeBlocked, !fm.fileExists(atPath: url("quarantine").path),
              let bytes = try? boundedRead("checkpoint", maximum: Self.maximumCheckpointBytes),
              rootBytes + bytes.count <= TransferResourceBudget.maximumBytes else { return }
        try? atomicWrite(bytes, name: "quarantine")
    }
    private func referenceFor(_ segment: TransferTimelineSegment) -> Reference {
        // ID guarantees immutable raw backing records. Slice bounds distinguish retention pruning;
        // timestamps survive normalized ArraySlice indices after a load. Offset stays in the reference.
        let first = segment.records.first!.start.bitPattern, last = segment.records.last!.end.bitPattern
        let name = "segment-\(segment.id.uuidString)-\(first)-\(last)-\(segment.records.count).bin"
        return Reference(name: name, id: segment.id, stat: segment.stat, count: segment.records.count, offset: segment.timeOffset)
    }
    private func makeManifest(_ snapshot: TransferTimelineSnapshot) throws -> Manifest {
        var active = snapshot
        var references = [[Reference]]()
        for i in snapshot.stats.indices {
            references.append(snapshot.stats[i].segments.filter(\.isSealed).map(referenceFor))
            active.stats[i].segments = snapshot.stats[i].segments.filter { !$0.isSealed }
        }
        return Manifest(savedAt: snapshot.anchor.wallTime, snapshot: active, sealed: references)
    }
    private func validate(_ snapshot: TransferTimelineSnapshot) throws {
        guard snapshot.stats.count == 2, snapshot.stats[0].stat == .network, snapshot.stats[1].stat == .disk,
              snapshot.anchor.continuousTime.isFinite, snapshot.anchor.continuousTime >= 0,
              snapshot.anchor.timelineTime.isFinite, snapshot.anchor.timelineTime >= snapshot.anchor.continuousTime,
              snapshot.anchor.wallTime.timeIntervalSince1970.isFinite,
              !snapshot.anchor.bootID.isEmpty, snapshot.anchor.bootID.utf8.count <= 128 else { throw Failure.invalid("History snapshot is invalid.") }
        var ids = Set<UUID>()
        for state in snapshot.stats {
            guard state.cumulative.startedAt.timeIntervalSince1970.isFinite,
                  state.segments.count <= TransferTimeline.maximumSegmentsPerStat,
                  state.segments.reduce(0, { $0 + $1.records.count }) <= TransferResourceBudget.maximumIntervalsPerStat,
                  state.segments.filter({ !$0.isSealed }).count <= 1,
                  state.watermark.sequence == nil || state.watermark.generation != nil,
                  state.watermark.lastEventTime.map({ $0.isFinite && $0 >= 0 && $0 <= snapshot.anchor.timelineTime }) ?? true else { throw Failure.invalid("History counts or watermarks are invalid.") }
            var previous: Double?
            for segment in state.segments {
                guard segment.stat == state.stat, !segment.records.isEmpty,
                      segment.records.count <= TransferResourceBudget.maximumRecordsPerSegmentPerStat,
                      segment.timeOffset.isFinite, ids.insert(segment.id).inserted else { throw Failure.limit }
                for raw in segment.records {
                    let record = segment.placed(raw)
                    guard raw.isValid, record.isValid, record.stat == state.stat,
                          record.end <= snapshot.anchor.timelineTime,
                          previous.map({ record.start >= $0 }) ?? true else { throw Failure.invalid("History intervals are invalid.") }
                    previous = record.end
                }
            }
            if let previous {
                guard state.watermark.lastEventTime.map({ $0 >= previous }) ?? false else { throw Failure.invalid("History watermark precedes its intervals.") }
            }
        }
    }

    // Binary envelope: magic UInt64, version UInt32, payload size UInt32, payload, FNV-1a UInt64.
    // The checksum detects accidental corruption, not malicious tampering; files stay local.
    private static let checkpointMagic: UInt64 = 0x51535043484B5031
    private static let segmentMagic: UInt64 = 0x5153505345474D31
    private func envelope(_ payload: Data, magic: UInt64) -> Data {
        var w = Writer(); w.u64(magic); w.u32(Self.formatVersion); w.u32(UInt32(payload.count)); w.data.append(payload)
        w.u64(Self.checksum(w.data)); return w.data
    }
    private func version(of data: Data) throws -> UInt32 {
        var r = Reader(data: data); let magic = try r.u64()
        guard magic == Self.checkpointMagic || magic == Self.segmentMagic else { throw Failure.invalid("History header is invalid.") }
        return try r.u32()
    }
    private func payload(_ data: Data, magic: UInt64) throws -> Reader {
        var r = Reader(data: data)
        guard try r.u64() == magic else { throw Failure.invalid("History header is invalid.") }
        guard try r.u32() == Self.formatVersion else { throw Failure.unsupported }
        let size = Int(try r.u32())
        guard size == data.count - 24 else { throw Failure.invalid("History length is invalid.") }
        var checksumReader = Reader(data: data, offset: data.count - 8)
        guard try checksumReader.u64() == Self.checksum(data.prefix(data.count - 8)) else { throw Failure.invalid("History checksum failed.") }
        return Reader(data: data, offset: 16, end: data.count - 8)
    }
    private static func checksum<T: Sequence>(_ bytes: T) -> UInt64 where T.Element == UInt8 {
        bytes.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
    private func encodeSegment(_ segment: TransferTimelineSegment) throws -> Data {
        var w = Writer(); w.u32(UInt32(segment.records.count)); w.u32(0)
        for record in segment.records { w.interval(record) }
        return envelope(w.data, magic: Self.segmentMagic)
    }
    private func decodeSegment(_ data: Data, reference: Reference) throws -> TransferTimelineSegment {
        var r = try payload(data, magic: Self.segmentMagic)
        let count = Int(try r.u32()); guard try r.u32() == 0, count == reference.count,
            count > 0, count <= TransferResourceBudget.maximumRecordsPerSegmentPerStat,
            r.remaining == count * TransferInterval.packedSize else { throw Failure.limit }
        var records: [TransferInterval] = []; records.reserveCapacity(count)
        for _ in 0..<count { records.append(try r.interval(stat: reference.stat)) }
        return TransferTimelineSegment(id: reference.id, stat: reference.stat, records: records[...], isSealed: true, timeOffset: reference.offset)
    }
    private func encodeManifest(_ manifest: Manifest) throws -> Data {
        let snapshot = manifest.snapshot
        var w = Writer(); w.double(manifest.savedAt.timeIntervalSince1970)
        w.double(snapshot.anchor.continuousTime); w.double(snapshot.anchor.timelineTime); w.double(snapshot.anchor.wallTime.timeIntervalSince1970)
        try w.string(snapshot.anchor.bootID, maximum: 128)
        var flags: UInt32 = 0
        for (index, warning) in [TransferTimelineWarning.invalidHistory, .historyClockAmbiguous, .resourceLimit, .accountingOverflow].enumerated() where snapshot.warnings.contains(warning) { flags |= 1 << index }
        w.u32(flags)
        for i in 0..<2 {
            let state = snapshot.stats[i]
            w.u64(state.cumulative.bytes.first); w.u64(state.cumulative.bytes.second)
            w.double(state.cumulative.startedAt.timeIntervalSince1970); w.u8(state.cumulative.accountingOverflow ? 1 : 0)
            w.u8(state.watermark.generation == nil ? 0 : 1)
            if let id = state.watermark.generation { w.uuid(id) }
            w.u64(state.watermark.admission)
            w.u8(state.watermark.sequence == nil ? 0 : 1); if let sequence = state.watermark.sequence { w.u64(sequence) }
            w.u8(state.watermark.lastEventTime == nil ? 0 : 1); if let time = state.watermark.lastEventTime { w.double(time) }
            w.u32(UInt32(manifest.sealed[i].count))
            for reference in manifest.sealed[i] {
                try w.string(reference.name, maximum: 160); w.uuid(reference.id); w.u32(UInt32(reference.count)); w.double(reference.offset)
            }
            w.u8(UInt8(state.segments.count))
            for segment in state.segments {
                w.uuid(segment.id); w.double(segment.timeOffset); w.u32(UInt32(segment.records.count))
                for record in segment.records { w.interval(record) }
            }
        }
        let result = envelope(w.data, magic: Self.checkpointMagic)
        guard result.count <= Self.maximumCheckpointBytes else { throw Failure.limit }
        return result
    }
    private func decodeManifest(_ data: Data) throws -> Manifest {
        var r = try payload(data, magic: Self.checkpointMagic)
        let savedAt = Date(timeIntervalSince1970: try r.double())
        let anchor = TransferTimelineAnchor(continuousTime: try r.double(), timelineTime: try r.double(), wallTime: Date(timeIntervalSince1970: try r.double()), bootID: try r.string(maximum: 128))
        let flags = try r.u32(); guard flags < 16 else { throw Failure.invalid("History flags are invalid.") }
        var warnings = Set<TransferTimelineWarning>()
        for (index, warning) in [TransferTimelineWarning.invalidHistory, .historyClockAmbiguous, .resourceLimit, .accountingOverflow].enumerated() where flags & (1 << index) != 0 { warnings.insert(warning) }
        var stats: [TransferTimelineStatSnapshot] = [], references = [[Reference]]()
        var ids = Set<UUID>(), names = Set<String>()
        for stat in TransferStat.allCases {
            let cumulative = TransferCumulativeEpoch(bytes: TransferBytes(first: try r.u64(), second: try r.u64()), startedAt: Date(timeIntervalSince1970: try r.double()), accountingOverflow: try r.boolean())
            let generation = try r.boolean() ? try r.uuid() : nil
            let admission = try r.u64(), sequence = try r.boolean() ? try r.u64() : nil
            let time = try r.boolean() ? try r.double() : nil
            let watermark = TransferTimelineWatermark(generation: generation, admission: admission, sequence: sequence, lastEventTime: time)
            let count = Int(try r.u32()); guard count <= TransferTimeline.maximumSegmentsPerStat, r.remaining >= count * 38 else { throw Failure.limit }
            var sealed: [Reference] = []; var total = 0
            for _ in 0..<count {
                let name = try r.string(maximum: 160), id = try r.uuid(), records = Int(try r.u32()), offset = try r.double()
                guard name.hasPrefix("segment-"), name.hasSuffix(".bin"), !name.contains("/"), !name.contains(".."),
                      names.insert(name).inserted, ids.insert(id).inserted, offset.isFinite,
                      records > 0, records <= TransferResourceBudget.maximumRecordsPerSegmentPerStat else { throw Failure.limit }
                total += records; guard total <= TransferResourceBudget.maximumIntervalsPerStat else { throw Failure.limit }
                sealed.append(Reference(name: name, id: id, stat: stat, count: records, offset: offset))
            }
            let activeCount = Int(try r.u8()); guard activeCount <= 1, count + activeCount <= TransferTimeline.maximumSegmentsPerStat else { throw Failure.limit }
            var active: [TransferTimelineSegment] = []
            for _ in 0..<activeCount {
                let id = try r.uuid(), offset = try r.double(), recordCount = Int(try r.u32())
                guard ids.insert(id).inserted, offset.isFinite, recordCount > 0,
                      recordCount <= TransferResourceBudget.maximumRecordsPerSegmentPerStat,
                      total + recordCount <= TransferResourceBudget.maximumIntervalsPerStat,
                      r.remaining >= recordCount * TransferInterval.packedSize else { throw Failure.limit }
                var records: [TransferInterval] = []; records.reserveCapacity(recordCount)
                for _ in 0..<recordCount { records.append(try r.interval(stat: stat)) }
                active.append(TransferTimelineSegment(id: id, stat: stat, records: records[...], isSealed: false, timeOffset: offset))
            }
            stats.append(TransferTimelineStatSnapshot(stat: stat, cumulative: cumulative, watermark: watermark, segments: active)); references.append(sealed)
        }
        guard r.remaining == 0, savedAt.timeIntervalSince1970.isFinite else { throw Failure.invalid("History checkpoint is invalid.") }
        let snapshot = TransferTimelineSnapshot(anchor: anchor, stats: stats, warnings: warnings)
        try validate(snapshot)
        return Manifest(savedAt: savedAt, snapshot: snapshot, sealed: references)
    }
    private struct Writer {
        var data = Data()
        mutating func u8(_ v: UInt8) { data.append(v) }
        mutating func u32(_ v: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { u8(UInt8(truncatingIfNeeded: v >> shift)) } }
        mutating func u64(_ v: UInt64) { for shift in stride(from: 0, to: 64, by: 8) { u8(UInt8(truncatingIfNeeded: v >> shift)) } }
        mutating func double(_ v: Double) { u64(v.bitPattern) }
        mutating func string(_ v: String, maximum: Int) throws {
            let bytes = Array(v.utf8); guard bytes.count <= maximum else { throw Failure.limit }
            u32(UInt32(bytes.count)); data.append(contentsOf: bytes)
        }
        mutating func uuid(_ v: UUID) { var value = v.uuid; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        mutating func interval(_ v: TransferInterval) {
            double(v.start); double(v.end); u64(v.bytes.first); u64(v.bytes.second)
            u8(v.stat.rawValue); u8(v.coverage.rawValue); for _ in 0..<6 { u8(0) }
        }
    }
    private struct Reader {
        let data: Data
        var offset = 0
        var end: Int?
        var remaining: Int { (end ?? data.count) - offset }
        mutating func u8() throws -> UInt8 { guard remaining >= 1 else { throw Failure.invalid("History was truncated.") }; defer { offset += 1 }; return data[offset] }
        mutating func u32() throws -> UInt32 { var v: UInt32 = 0; for shift in stride(from: 0, to: 32, by: 8) { v |= UInt32(try u8()) << shift }; return v }
        mutating func u64() throws -> UInt64 { var v: UInt64 = 0; for shift in stride(from: 0, to: 64, by: 8) { v |= UInt64(try u8()) << shift }; return v }
        mutating func double() throws -> Double { Double(bitPattern: try u64()) }
        mutating func boolean() throws -> Bool { let v = try u8(); guard v <= 1 else { throw Failure.invalid("History flag is invalid.") }; return v == 1 }
        mutating func string(maximum: Int) throws -> String {
            let count = Int(try u32()); guard count <= maximum, remaining >= count else { throw Failure.limit }
            let bytes = data[offset..<(offset + count)]; offset += count
            guard let value = String(data: bytes, encoding: .utf8) else { throw Failure.invalid("History text is invalid.") }; return value
        }
        mutating func uuid() throws -> UUID {
            let bytes = try (0..<16).map { _ in try u8() }
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        }
        mutating func interval(stat: TransferStat) throws -> TransferInterval {
            let start = try double(), end = try double(), first = try u64(), second = try u64()
            guard try u8() == stat.rawValue, let coverage = TransferCoverage(rawValue: try u8()) else { throw Failure.invalid("History interval kind is invalid.") }
            for _ in 0..<6 { guard try u8() == 0 else { throw Failure.invalid("History reserved bytes are invalid.") } }
            let result = TransferInterval(start: start, end: end, bytes: TransferBytes(first: first, second: second), stat: stat, coverage: coverage)
            guard result.isValid else { throw Failure.invalid("History interval is invalid.") }; return result
        }
    }
}
