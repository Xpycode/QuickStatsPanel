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
}
