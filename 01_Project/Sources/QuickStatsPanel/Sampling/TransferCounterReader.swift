import Foundation
import Darwin
import IOKit

/// Continuous time includes sleep; an invalid boot identity prevents accounting rather than
/// accidentally joining observations from unrelated boots. This performs no persistent I/O.
struct SystemTransferClock: TransferClock {
    private let bootID: String
    private let secondsPerTick: Double

    init() {
        var length = 0
        var identity = ""
        if sysctlbyname("kern.bootsessionuuid", nil, &length, nil, 0) == 0, length > 1, length <= 128 {
            var bytes = [CChar](repeating: 0, count: length)
            if sysctlbyname("kern.bootsessionuuid", &bytes, &length, nil, 0) == 0,
               let end = bytes.firstIndex(of: 0),
               let candidate = String(bytes: bytes[..<end].map { UInt8(bitPattern: $0) }, encoding: .utf8),
               let uuid = UUID(uuidString: candidate) { identity = uuid.uuidString }
        }
        bootID = identity
        var info = mach_timebase_info_data_t()
        if mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 {
            secondsPerTick = Double(info.numer) / Double(info.denom) / 1_000_000_000
        } else { secondsPerTick = .nan }
    }

    func now() -> TransferTimestamp {
        TransferTimestamp(continuousTime: Double(mach_continuous_time()) * secondsPerTick,
                          wallTime: Date(), bootID: bootID)
    }
}

struct NetworkTransferRecord: Sendable {
    let index: UInt32
    let name: String
    let flags: Int32
    let linkIdentity: [UInt8]
    let bytes: TransferBytes
}

enum TransferReaderError: Error { case malformed, unavailable }

/// Reader state is confined to the sampler queue. Interface names/addresses are transient only.
final class NetworkTransferCounterReader: TransferCounterReader, @unchecked Sendable {
    let stat = TransferStat.network
    private struct Link { let name: String; let identity: [UInt8]; let incarnation: UInt64 }
    private var links: [UInt32: Link] = [:]
    private var nextIncarnation: UInt64 = 0

    func read(generation: UUID, sequence: UInt64, timestamp: TransferTimestamp) -> TransferCounterSnapshot {
        do {
            let records = try Self.readRecords()
            return snapshot(records: records, generation: generation, sequence: sequence, timestamp: timestamp)
        } catch {
            links.removeAll()
            return TransferCounterSnapshot(stat: stat, generation: generation, sequence: sequence,
                timestamp: timestamp, enumeration: .failed, sources: [])
        }
    }

    /// Pure parser: the bounded RTAX_IFP sockaddr owns name/index/link identity in the
    /// same counter snapshot. A second if_indextoname call could race hot removal/rename.
    static func parse(_ buffer: [UInt8], count: Int) throws -> [NetworkTransferRecord] {
        guard count >= 0, count <= buffer.count else { throw TransferReaderError.malformed }
        return try buffer.withUnsafeBytes { raw in
            var records: [NetworkTransferRecord] = []
            var offset = 0
            while offset < count {
                guard count - offset >= 4 else { throw TransferReaderError.malformed }
                let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, length <= count - offset, raw[offset + 2] == UInt8(RTM_VERSION) else {
                    throw TransferReaderError.malformed
                }
                if raw[offset + 3] == UInt8(RTM_IFINFO2) {
                    let headerSize = MemoryLayout<if_msghdr2>.size
                    guard length >= headerSize else { throw TransferReaderError.malformed }
                    let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let index = UInt32(header.ifm_index)
                    guard index != 0, (header.ifm_addrs & Int32(RTA_IFP)) != 0 else {
                        throw TransferReaderError.unavailable
                    }
                    // RTAX_IFP supplies link type/address, so index/name reuse can be reseeded.
                    // Darwin route sockaddrs are padded to 32-bit boundaries.
                    var cursor = offset + headerSize
                    var identity = [header.ifm_data.ifi_type]
                    var name: String?
                    for addressIndex in 0..<Int(RTAX_MAX) where (header.ifm_addrs & (1 << addressIndex)) != 0 {
                        guard cursor <= offset + length - 2 else { throw TransferReaderError.malformed }
                        let addressLength = Int(raw[cursor])
                        let stride = addressLength == 0 ? 4 : (addressLength + 3) & ~3
                        guard addressLength >= 2, stride <= offset + length - cursor else { throw TransferReaderError.malformed }
                        if addressIndex == Int(RTAX_IFP) {
                            guard raw[cursor + 1] == UInt8(AF_LINK), addressLength >= 8 else {
                                throw TransferReaderError.malformed
                            }
                            let linkIndex = UInt32(raw.loadUnaligned(fromByteOffset: cursor + 2, as: UInt16.self))
                            guard linkIndex == index else { throw TransferReaderError.malformed }
                            let nameLength = Int(raw[cursor + 5])
                            let linkLength = Int(raw[cursor + 6])
                            let selectorLength = Int(raw[cursor + 7])
                            guard 8 + nameLength + linkLength + selectorLength <= addressLength else {
                                throw TransferReaderError.malformed
                            }
                            let encodedName = Array(raw[(cursor + 8)..<(cursor + 8 + nameLength)])
                            guard nameLength > 0, nameLength < Int(IFNAMSIZ),
                                  encodedName.allSatisfy({ $0 >= 33 && $0 <= 126 }),
                                  let decodedName = String(bytes: encodedName, encoding: .utf8) else {
                                throw TransferReaderError.malformed
                            }
                            name = decodedName
                            let start = cursor + 8 + nameLength
                            identity.append(contentsOf: raw[start..<(start + linkLength)])
                        }
                        cursor += stride
                    }
                    guard let name else { throw TransferReaderError.malformed }
                    records.append(NetworkTransferRecord(index: index, name: name, flags: header.ifm_flags,
                        linkIdentity: identity, bytes: TransferBytes(first: header.ifm_data.ifi_ibytes,
                                                                    second: header.ifm_data.ifi_obytes)))
                }
                offset += length
            }
            return records
        }
    }

    private static func readRecords() throws -> [NetworkTransferRecord] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0,
              length > 0, length <= 16 * 1024 * 1024 else { throw TransferReaderError.unavailable }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { throw TransferReaderError.unavailable }
        return try parse(buffer, count: length)
    }

    func snapshot(records: [NetworkTransferRecord], generation: UUID, sequence: UInt64,
                  timestamp: TransferTimestamp) -> TransferCounterSnapshot {
        var current: [UInt32: Link] = [:]
        var sources: [TransferSourceCounter] = []
        let grouped = Dictionary(grouping: records, by: \.index)
        for index in grouped.keys.sorted() {
            guard let group = grouped[index],
                  let record = group.first(where: { NetworkSampler.shouldCount(interfaceName: $0.name, flags: $0.flags) }) else { continue }
            let duplicate = group.count != 1
            let link: Link
            if !duplicate, let old = links[record.index], old.name == record.name, old.identity == record.linkIdentity {
                link = old
            } else {
                let next = nextIncarnation.addingReportingOverflow(1)
                guard !next.overflow else {
                    links.removeAll()
                    return TransferCounterSnapshot(stat: stat, generation: generation, sequence: sequence,
                        timestamp: timestamp, enumeration: .failed, sources: [])
                }
                nextIncarnation = next.partialValue
                link = Link(name: record.name, identity: record.linkIdentity, incarnation: nextIncarnation)
            }
            if !duplicate { current[record.index] = link }
            sources.append(TransferSourceCounter(id: .network(index: record.index, name: record.name,
                incarnation: link.incarnation), bytes: duplicate ? nil : record.bytes))
        }
        // Observed removal/inactivity forgets the incarnation; reappearance always seeds afresh.
        links = current
        return TransferCounterSnapshot(stat: stat, generation: generation, sequence: sequence,
                                       timestamp: timestamp, enumeration: .complete, sources: sources)
    }
}

struct DiskTransferRecord: Sendable {
    let registryID: UInt64
    let layer: TransferStorageLayer
    let bytes: TransferBytes?
    let blockDriverAncestors: Set<UInt64>?
}

struct DiskTransferCounterReader: TransferCounterReader {
    let stat = TransferStat.disk

    /// Reject unknown providers and unresolved stacked physical drivers; never guess which
    /// layer represents hardware I/O. Healthy independent peers can still contribute.
    static func sources(from records: [DiskTransferRecord]) -> [TransferSourceCounter] {
        let included = records.filter { $0.layer != .excludedVirtual }
        var invalid = Set<UInt64>()
        var seen = Set<UInt64>()
        let ids = Set(included.map(\.registryID))
        for record in included {
            if !seen.insert(record.registryID).inserted { invalid.insert(record.registryID) }
            guard let ancestors = record.blockDriverAncestors else { invalid.insert(record.registryID); continue }
            if !ancestors.isEmpty {
                invalid.insert(record.registryID)
                invalid.formUnion(ancestors.intersection(ids))
            }
        }
        return included.map { record in
            TransferSourceCounter(id: .disk(registryID: record.registryID),
                bytes: record.layer == .physical && !invalid.contains(record.registryID) ? record.bytes : nil)
        }
    }

    static func pairedCounters(_ stats: [String: Any]) -> TransferBytes? {
        func counter(_ key: String) -> UInt64? {
            guard let number = stats[key] as? NSNumber,
                  CFGetTypeID(number) == CFNumberGetTypeID(), CFNumberGetByteSize(number) == 8,
                  !CFNumberIsFloatType(number), number.compare(NSNumber(value: 0)) != .orderedAscending else { return nil }
            return number.uint64Value
        }
        guard let first = counter("Bytes (Read)"), let second = counter("Bytes (Write)") else { return nil }
        return TransferBytes(first: first, second: second)
    }

    private static func properties(_ entry: io_registry_entry_t) -> [String: Any]? {
        var value: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &value, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return value?.takeRetainedValue() as? [String: Any]
    }

    private static func ancestors(_ entry: io_registry_entry_t) -> Set<UInt64>? {
        var current = entry
        var ownsCurrent = false
        defer { if ownsCurrent { IOObjectRelease(current) } }
        var ids = Set<UInt64>()
        for _ in 0..<128 {
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            if result == kIOReturnNoDevice { return ids }
            guard result == KERN_SUCCESS else { return nil }
            if ownsCurrent { IOObjectRelease(current) }
            current = parent; ownsCurrent = true
            if IOObjectConformsTo(current, "IOBlockStorageDriver") != 0 {
                var id: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(current, &id) == KERN_SUCCESS, id != 0,
                      ids.insert(id).inserted else { return nil }
            }
        }
        return nil
    }

    func read(generation: UUID, sequence: UInt64, timestamp: TransferTimestamp) -> TransferCounterSnapshot {
        func snapshot(_ enumeration: TransferEnumeration, _ records: [DiskTransferRecord]) -> TransferCounterSnapshot {
            TransferCounterSnapshot(stat: stat, generation: generation, sequence: sequence, timestamp: timestamp,
                                    enumeration: enumeration, sources: Self.sources(from: records))
        }
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return snapshot(.failed, []) }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return snapshot(.failed, []) }
        defer { IOObjectRelease(iterator) }
        var records: [DiskTransferRecord] = []
        var count = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let ownedEntry = entry
            defer { IOObjectRelease(ownedEntry) }
            count += 1
            var id: UInt64 = 0
            guard count <= 4_096, IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS, id != 0 else {
                return snapshot(.failed, [])
            }
            let props = Self.properties(entry)
            var layer = TransferStorageLayer.unknown
            var provider: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(entry, kIOServicePlane, &provider) == KERN_SUCCESS {
                let characteristics = Self.properties(provider)?["Protocol Characteristics"] as? [String: Any]
                layer = TransferStorageLayer.classify(interconnect: characteristics?["Physical Interconnect"] as? String,
                    location: characteristics?["Physical Interconnect Location"] as? String)
                IOObjectRelease(provider)
            }
            records.append(DiskTransferRecord(registryID: id, layer: layer,
                bytes: (props?["Statistics"] as? [String: Any]).flatMap(Self.pairedCounters),
                blockDriverAncestors: layer == .excludedVirtual ? [] : Self.ancestors(entry)))
            entry = IOIteratorNext(iterator)
        }
        guard IOIteratorIsValid(iterator) != 0 else { return snapshot(.failed, []) }
        return snapshot(.complete, records)
    }
}

/// One owner for timer/lifecycle/read/accounting/reset state. Every callback is delivered in
/// sequence on this queue. stop() is a synchronous barrier, including an in-flight callback.
final class TransferSamplerDriver: @unchecked Sendable {
    let interval: TimeInterval
    private let reader: any TransferCounterReader
    private let clock: any TransferClock
    private let automaticallySchedules: Bool
    private let onEvent: @Sendable (TransferEvent) -> Void
    private let onTick: @Sendable (TransferObservation?, UUID, UInt64) -> Void
    private let onGeneration: @Sendable (UUID) -> Void
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var timer: DispatchSourceTimer?
    private var accounting: TransferAccounting?
    private var runID = UUID()
    private var nextSequence: UInt64 = 0
    private var lastAcceptedTimestamp: TransferTimestamp?
    private var lastResetTime: TimeInterval?
    private var lastResetRequestID: UUID?
    private var running = false

    init(interval: TimeInterval, reader: any TransferCounterReader, clock: any TransferClock,
         automaticallySchedules: Bool, onGeneration: @escaping @Sendable (UUID) -> Void,
         onEvent: @escaping @Sendable (TransferEvent) -> Void,
         onTick: @escaping @Sendable (TransferObservation?, UUID, UInt64) -> Void) {
        self.interval = TransferCadence.effective(interval); self.reader = reader; self.clock = clock
        self.automaticallySchedules = automaticallySchedules; self.onGeneration = onGeneration
        self.onEvent = onEvent; self.onTick = onTick
        queue = DispatchQueue(label: "QuickStatsPanel.TransferSampler.\(reader.stat)")
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit { timer?.cancel() }

    private func confined<T>(_ action: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return action() }
        return queue.sync(execute: action)
    }
    var generation: UUID { confined { runID } }
    var sequence: UInt64 { confined { nextSequence } }

    @discardableResult func start() -> UUID {
        confined {
            guard !running else { return runID }
            runID = UUID(); nextSequence = 0; lastAcceptedTimestamp = nil
            accounting = TransferAccounting(stat: reader.stat, generation: runID, interval: interval)
            running = true
            onGeneration(runID) // Register the generation before the first possible callback.
            if automaticallySchedules, running {
                let expectedRun = runID
                let source = DispatchSource.makeTimerSource(queue: queue)
                source.schedule(deadline: .now(), repeating: interval)
                source.setEventHandler { [weak self] in self?.tick(expectedGeneration: expectedRun) }
                timer = source; source.resume()
            }
            return runID
        }
    }

    func stop() {
        confined {
            running = false
            timer?.setEventHandler {}; timer?.cancel(); timer = nil
            accounting?.invalidateBaselines()
        }
    }
    func invalidate() { confined { accounting?.invalidateBaselines() } }
    func sampleNow(expectedGeneration: UUID? = nil) { confined { tick(expectedGeneration: expectedGeneration ?? runID) } }

    private func advanceSequence() -> UInt64? {
        let next = nextSequence.addingReportingOverflow(1)
        guard !next.overflow else { running = false; timer?.cancel(); timer = nil; return nil }
        nextSequence = next.partialValue
        return nextSequence
    }

    private func tick(expectedGeneration: UUID, timestamp: TransferTimestamp? = nil) {
        guard running, expectedGeneration == runID, let sequence = advanceSequence() else { return }
        let snapshot = reader.read(generation: runID, sequence: sequence, timestamp: timestamp ?? clock.now())
        let observation = accounting?.consume(snapshot)
        if accounting?.lastSequence == sequence { lastAcceptedTimestamp = snapshot.timestamp }
        if observation == nil, accounting?.lastSequence != sequence { accounting?.invalidateBaselines() }
        if let observation { onEvent(.observation(observation)) }
        guard running, runID == expectedGeneration else { return }
        onTick(observation, expectedGeneration, sequence)
    }

    /// A synchronous admission/result API: false means no reset marker was emitted. The reset
    /// marker follows its boundary read even on read failure, retaining an honest missing gap.
    @discardableResult func requestReset(requestID: UUID) -> Bool {
        confined {
            guard running, requestID != lastResetRequestID else { return false }
            let expectedRun = runID
            let timestamp = clock.now()
            guard timestamp.isValid,
                  lastAcceptedTimestamp.map({ timestamp.bootID == $0.bootID && timestamp.continuousTime > $0.continuousTime }) ?? true,
                  lastResetTime.map({ timestamp.continuousTime - $0 >= TransferResourceBudget.minimumResetInterval }) ?? true,
                  nextSequence <= UInt64.max - 2 else { return false }
            lastResetTime = timestamp.continuousTime
            lastResetRequestID = requestID
            tick(expectedGeneration: expectedRun, timestamp: timestamp)
            guard running, runID == expectedRun, let sequence = advanceSequence() else { return false }
            onEvent(.reset(TransferResetMarker(stat: reader.stat, generation: runID, sequence: sequence,
                                              timestamp: timestamp, requestID: requestID)))
            return true
        }
    }
}
