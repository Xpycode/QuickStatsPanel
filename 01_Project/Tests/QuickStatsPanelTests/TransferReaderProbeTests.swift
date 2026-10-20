import XCTest
import Darwin
import IOKit

/// Bounded, permission-free hardware gate. These tests do not start samplers/apps, generate
/// traffic, change devices or write profiles. A skip means feasibility was NOT established.
/// Fixture accounting tests alone never satisfy this gate.
final class TransferReaderProbeTests: XCTestCase {
    private enum ProbeError: Error { case unavailable(String), malformed(String) }

    private func parseRoute(_ buffer: [UInt8], count: Int) throws -> [if_msghdr2] {
        guard count >= 0 && count <= buffer.count else { throw ProbeError.malformed("route count") }
        return try buffer.withUnsafeBytes { raw in
            var result: [if_msghdr2] = []
            var offset = 0
            while offset < count {
                guard count - offset >= 4 else { throw ProbeError.malformed("route prefix") }
                let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4 && length <= count - offset else { throw ProbeError.malformed("route length") }
                guard raw[offset + 2] == UInt8(RTM_VERSION) else { throw ProbeError.malformed("route version") }
                if raw[offset + 3] == UInt8(RTM_IFINFO2) {
                    guard length >= MemoryLayout<if_msghdr2>.size else { throw ProbeError.malformed("ifinfo2 size") }
                    result.append(raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self))
                }
                offset += length
            }
            return result
        }
    }

    func testCurrentRouteSnapshotExposesBounded64BitPhysicalCounters() throws {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0 else {
            throw XCTSkip("Hardware gate unavailable: NET_RT_IFLIST2 sizing failed")
        }
        XCTAssertGreaterThan(length, 0)
        XCTAssertLessThanOrEqual(length, 16 * 1024 * 1024)
        guard length > 0 && length <= 16 * 1024 * 1024 else { return }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            throw XCTSkip("Hardware gate unavailable: route enumeration raced/failed")
        }
        let messages = try parseRoute(buffer, count: length)
        XCTAssertFalse(messages.isEmpty)
        var counted = 0
        var indices = Set<UInt16>()
        for message in messages {
            XCTAssertTrue(indices.insert(message.ifm_index).inserted, "Duplicate route interface identity")
            XCTAssertEqual(MemoryLayout.size(ofValue: message.ifm_data.ifi_ibytes), 8)
            XCTAssertEqual(MemoryLayout.size(ofValue: message.ifm_data.ifi_obytes), 8)
            var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
            guard if_indextoname(UInt32(message.ifm_index), &name) != nil else {
                throw XCTSkip("Hardware gate unavailable: interface disappeared during bounded probe")
            }
            if NetworkSampler.shouldCount(interfaceName: String(cString: name), flags: message.ifm_flags) { counted += 1 }
        }
        guard counted > 0 else { throw XCTSkip("Hardware gate unavailable: no current active physical network interface") }
        print("Transfer hardware gate: validated \(messages.count) route records, \(counted) physical links, paired 64-bit counters")
    }

    func testRouteParserRejectsTruncatedZeroLengthAndWrongVersionMessages() {
        XCTAssertThrowsError(try parseRoute([0, 0, UInt8(RTM_VERSION), UInt8(RTM_IFINFO2)], count: 4))
        XCTAssertThrowsError(try parseRoute([160, 0, UInt8(RTM_VERSION), UInt8(RTM_IFINFO2)], count: 4))
        XCTAssertThrowsError(try parseRoute([4, 0, 0, UInt8(RTM_IFINFO2)], count: 4))
        XCTAssertThrowsError(try parseRoute([4, 0, UInt8(RTM_VERSION)], count: 3))
        XCTAssertThrowsError(try parseRoute([], count: 1))
    }

    private func properties(_ entry: io_registry_entry_t) throws -> [String: Any] {
        var value: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &value, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let result = value?.takeRetainedValue() as? [String: Any] else {
            throw ProbeError.unavailable("registry properties")
        }
        return result
    }

    private func pairedCounters(_ stats: [String: Any]) throws -> TransferBytes {
        guard let first = stats["Bytes (Read)"] as? NSNumber,
              let second = stats["Bytes (Write)"] as? NSNumber,
              CFGetTypeID(first) == CFNumberGetTypeID(), CFGetTypeID(second) == CFNumberGetTypeID(),
              CFNumberGetByteSize(first) == 8, CFNumberGetByteSize(second) == 8,
              first.compare(NSNumber(value: 0)) != .orderedAscending,
              second.compare(NSNumber(value: 0)) != .orderedAscending else {
            throw ProbeError.malformed("unpaired/non-64-bit block counters")
        }
        return TransferBytes(first: first.uint64Value, second: second.uint64Value)
    }

    func testCurrentPhysicalBlockDriversHaveDistinctPaired64BitCountersWithoutAncestorDuplication() throws {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else {
            throw XCTSkip("Hardware gate unavailable: block storage matching")
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            throw XCTSkip("Hardware gate unavailable: block storage enumeration")
        }
        defer { IOObjectRelease(iterator) }
        var ids = Set<UInt64>()
        var physical = 0
        var virtual = 0
        var unknown = 0
        var count = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let ownedEntry = entry
            defer { IOObjectRelease(ownedEntry) }
            count += 1
            guard count <= 4_096 else { throw ProbeError.malformed("excessive driver count") }
            var id: UInt64 = 0
            XCTAssertEqual(IORegistryEntryGetRegistryEntryID(entry, &id), KERN_SUCCESS)
            XCTAssertNotEqual(id, 0)
            XCTAssertTrue(ids.insert(id).inserted, "Duplicate registry identity must not count twice")
            let props = try properties(entry)
            let counters = try pairedCounters(try XCTUnwrap(props["Statistics"] as? [String: Any]))
            // Real values are read and validated but hardware IDs and paths are never logged.
            _ = counters
            var provider: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &provider) == KERN_SUCCESS else {
                throw ProbeError.unavailable("block provider")
            }
            let protocolProperties: [String: Any]
            do { protocolProperties = try properties(provider)["Protocol Characteristics"] as? [String: Any] ?? [:] }
            catch { IOObjectRelease(provider); throw error }
            IOObjectRelease(provider)
            let layer = TransferStorageLayer.classify(interconnect: protocolProperties["Physical Interconnect"] as? String,
                location: protocolProperties["Physical Interconnect Location"] as? String)
            switch layer {
            case .excludedVirtual: virtual += 1
            case .unknown: unknown += 1
            case .physical:
                physical += 1
                // Public registry ancestry detects stacked driver nodes. This does not establish
                // unobserved RAID/multipath correctness; those are explicit hardware limitations.
                var current = entry
                var ownsCurrent = false
                var depth = 0
                var parent: io_registry_entry_t = 0
                while IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS {
                    if ownsCurrent { IOObjectRelease(current) }
                    current = parent; ownsCurrent = true; depth += 1
                    XCTAssertEqual(IOObjectConformsTo(current, "IOBlockStorageDriver"), 0,
                        "Physical driver stacking requires topology resolution before counting")
                    if depth >= 128 { break }
                }
                if ownsCurrent { IOObjectRelease(current) }
                XCTAssertLessThan(depth, 128)
            }
            entry = IOIteratorNext(iterator)
        }
        guard physical > 0 else { throw XCTSkip("Hardware gate unavailable: no positively classified physical block driver") }
        XCTAssertEqual(unknown, 0, "Hardware gate unresolved: unknown provider classification")
        print("Transfer hardware gate: \(physical) distinct physical drivers with paired 64-bit counters; \(virtual) virtual layers excluded; no physical ancestor stacking")
    }
}
