import XCTest

final class NetworkSamplerTests: XCTestCase {
    private let active = Int32(IFF_UP | IFF_RUNNING)

    func testCountsActivePhysicalInterfaces() {
        XCTAssertTrue(NetworkSampler.shouldCount(interfaceName: "en0", flags: active))
        XCTAssertTrue(NetworkSampler.shouldCount(interfaceName: "en7", flags: active))
    }

    func testExcludesLoopbackTunnelsAndInactiveLinks() {
        XCTAssertFalse(NetworkSampler.shouldCount(
            interfaceName: "lo0", flags: active | Int32(IFF_LOOPBACK)))
        XCTAssertFalse(NetworkSampler.shouldCount(interfaceName: "utun4", flags: active))
        XCTAssertFalse(NetworkSampler.shouldCount(interfaceName: "awdl0", flags: active))
        XCTAssertFalse(NetworkSampler.shouldCount(interfaceName: "en0", flags: Int32(IFF_UP)))
    }

    private func routeMessage(index: UInt16 = 1, first: UInt64 = 5_000_000_000,
                              second: UInt64 = 6_000_000_000, interfaceName: String = "en0") -> [UInt8] {
        var header = if_msghdr2()
        let name: [UInt8] = Array(interfaceName.utf8)
        let address: [UInt8] = [1, 2, 3, 4, 5, 6]
        var sockaddr: [UInt8] = [UInt8(8 + name.count + address.count), UInt8(AF_LINK), UInt8(truncatingIfNeeded: index), UInt8(truncatingIfNeeded: index >> 8), 6,
                                  UInt8(name.count), UInt8(address.count), 0] + name + address
        while sockaddr.count % 4 != 0 { sockaddr.append(0) }
        header.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size + sockaddr.count)
        header.ifm_version = UInt8(RTM_VERSION)
        header.ifm_type = UInt8(RTM_IFINFO2)
        header.ifm_addrs = Int32(RTA_IFP)
        header.ifm_flags = active
        header.ifm_index = index
        header.ifm_data.ifi_type = 6
        header.ifm_data.ifi_ibytes = first
        header.ifm_data.ifi_obytes = second
        return withUnsafeBytes(of: &header) { Array($0) } + sockaddr
    }

    func testRouteParserReadsPaired64BitCountersAndBoundedLinkIdentity() throws {
        let bytes = routeMessage()
        let records = try NetworkTransferCounterReader.parse(bytes, count: bytes.count)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.index, 1)
        XCTAssertEqual(records.first?.bytes, TransferBytes(first: 5_000_000_000, second: 6_000_000_000))
        XCTAssertEqual(records.first?.linkIdentity, [6, 1, 2, 3, 4, 5, 6])
        let second = routeMessage(index: 2, interfaceName: "en1")
        XCTAssertEqual(try NetworkTransferCounterReader.parse(bytes + second, count: bytes.count + second.count).count, 2)
    }

    func testRouteParserRejectsInvalidLengthsVersionsLinkAddressesAndMissingName() {
        let valid = routeMessage()
        XCTAssertThrowsError(try NetworkTransferCounterReader.parse(valid, count: valid.count + 1))
        XCTAssertThrowsError(try NetworkTransferCounterReader.parse(Array(valid.dropLast()), count: valid.count - 1))
        var invalid = valid; invalid[0] = 0; invalid[1] = 0
        XCTAssertThrowsError(try NetworkTransferCounterReader.parse(invalid, count: invalid.count))
        invalid = valid; invalid[2] = 0
        XCTAssertThrowsError(try NetworkTransferCounterReader.parse(invalid, count: invalid.count))
        invalid = valid; invalid[MemoryLayout<if_msghdr2>.size + 6] = 255
        XCTAssertThrowsError(try NetworkTransferCounterReader.parse(invalid, count: invalid.count))
        invalid = valid; invalid[MemoryLayout<if_msghdr2>.size] = 255
        XCTAssertThrowsError(try NetworkTransferCounterReader.parse(invalid, count: invalid.count))
        invalid = valid; invalid[MemoryLayout<if_msghdr2>.size + 1] = UInt8(AF_INET)
        XCTAssertThrowsError(try NetworkTransferCounterReader.parse(invalid, count: invalid.count))
        invalid = valid; invalid[MemoryLayout<if_msghdr2>.size + 2] = 99
        XCTAssertThrowsError(try NetworkTransferCounterReader.parse(invalid, count: invalid.count))
        invalid = valid; invalid[MemoryLayout<if_msghdr2>.size + 5] = 0
        XCTAssertThrowsError(try NetworkTransferCounterReader.parse(invalid, count: invalid.count))
        invalid = valid; invalid[MemoryLayout<if_msghdr2>.size + 8] = 0
        XCTAssertThrowsError(try NetworkTransferCounterReader.parse(invalid, count: invalid.count))
    }

    func testRouteSnapshotNameWorksWithoutAnySecondaryInterfaceLookup() throws {
        // No resolver exists in the parser API. A renamed/disappeared interface cannot make
        // another API return nil and discard healthy peers from this captured route snapshot.
        let message = routeMessage(index: 42, interfaceName: "en41")
        let record = try XCTUnwrap(NetworkTransferCounterReader.parse(message, count: message.count).first)
        XCTAssertEqual(record.index, 42)
        XCTAssertEqual(record.name, "en41")
    }

    func testReaderIncarnationChangesOnlyAfterIdentityChangeOrObservedRemoval() throws {
        let reader = NetworkTransferCounterReader()
        let generation = UUID()
        func snapshot(_ records: [NetworkTransferRecord], _ sequence: UInt64) -> TransferCounterSnapshot {
            reader.snapshot(records: records, generation: generation, sequence: sequence,
                timestamp: TransferTimestamp(continuousTime: Double(sequence), wallTime: Date(), bootID: "fixture"))
        }
        func record(_ name: String = "en0", identity: [UInt8] = [1], value: UInt64 = 100) -> NetworkTransferRecord {
            NetworkTransferRecord(index: 1, name: name, flags: active, linkIdentity: identity,
                bytes: TransferBytes(first: value, second: value))
        }
        let first = try XCTUnwrap(snapshot([record()], 1).sources.first?.id)
        XCTAssertEqual(snapshot([record(value: 200)], 2).sources.first?.id, first)
        let changedLink = try XCTUnwrap(snapshot([record(identity: [2])], 3).sources.first?.id)
        XCTAssertNotEqual(changedLink, first)
        let changedName = try XCTUnwrap(snapshot([record("en1", identity: [2])], 4).sources.first?.id)
        XCTAssertNotEqual(changedName, changedLink)
        XCTAssertTrue(snapshot([], 5).sources.isEmpty)
        XCTAssertNotEqual(snapshot([record("en1", identity: [2])], 6).sources.first?.id, changedName)
    }

    func testDuplicateRawInterfaceIndexCannotEscapeViaConflictingIncarnations() throws {
        let reader = NetworkTransferCounterReader(); let generation = UUID()
        func snapshot(_ records: [NetworkTransferRecord], _ sequence: UInt64) -> TransferCounterSnapshot {
            reader.snapshot(records: records, generation: generation, sequence: sequence,
                timestamp: TransferTimestamp(continuousTime: Double(sequence), wallTime: Date(), bootID: "fixture"))
        }
        let normal = NetworkTransferRecord(index: 1, name: "en0", flags: active, linkIdentity: [1], bytes: TransferBytes(first: 100, second: 100))
        let conflicting = NetworkTransferRecord(index: 1, name: "en1", flags: active, linkIdentity: [2], bytes: TransferBytes(first: 1_000_000, second: 1_000_000))
        let healthy = NetworkTransferRecord(index: 2, name: "en2", flags: active, linkIdentity: [3], bytes: TransferBytes(first: 200, second: 200))
        let original = try XCTUnwrap(snapshot([normal, healthy], 1).sources.first?.id)
        let duplicated = snapshot([normal, conflicting, healthy], 2)
        XCTAssertEqual(duplicated.sources.count, 2)
        XCTAssertEqual(duplicated.sources.filter { $0.bytes == nil }.count, 1)
        let recovered = try XCTUnwrap(snapshot([normal, healthy], 3).sources.first?.id)
        XCTAssertNotEqual(recovered, original, "Duplicate index invalidates its incarnation before recovery")
    }

    func testRateFormattersAcceptExtremeAndNonfiniteValuesWithoutIntegerTrap() {
        for value in [Double(UInt64.max) / 0.25, Double.infinity, -Double.infinity, Double.nan, -1, 0] {
            XCTAssertFalse(NetworkSample.rate(value).isEmpty)
            XCTAssertFalse(DiskSample.rate(value).isEmpty)
        }
        let sample = DiskSample(usedBytes: .max, freeBytes: .max, totalBytes: .max, readBytesPerSec: 0, writeBytesPerSec: 0)
        XCTAssertFalse(sample.totalFormatted.isEmpty)
    }
}
