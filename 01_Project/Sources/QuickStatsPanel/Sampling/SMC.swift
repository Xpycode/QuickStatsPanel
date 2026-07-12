import Foundation
import IOKit

// Permission-free READ-ONLY AppleSMC reader. No writes, ever. Consumers:
// FanSampler (fan rpm), TemperatureReader (named-core °C via the ported
// SMCTemperatureTable — added 2026-07-12; D-018 originally went IOHID-only
// because the Apple-Silicon temp keys were undocumented, until exelban/stats'
// crowd-sourced key map closed that gap), and PowerSampler (System/DC In watts).
//
// Load-bearing facts:
//   • Field order in SMCKeyData_t MUST match the kernel ABI exactly — the struct
//     is passed by value through IOConnectCallStructMethod and the kernel reads
//     specific byte offsets. Do not reorder fields.
//   • Integer types (ui8, ui16, ui32, sp78, fpe2) are big-endian in the SMC wire
//     format. The "flt " type is IEEE-754 single-precision in native little-endian
//     byte order on Apple Silicon. Older readers that treat "flt " as big-endian
//     will produce garbage rpm values (e.g. 6e9) on M-series Macs.
//   • kIOMainPortDefault is correct for macOS 12+. kIOMasterPortDefault is
//     deprecated and must not be used here.

private enum SMCKeys: UInt8 {
    case kernelIndex  = 2   // selector for IOConnectCallStructMethod (kSMCHandleYPCEvent)
    case readBytes    = 5   // SMC_CMD_READ_BYTES   → goes in input.data8
    case readKeyInfo  = 9   // SMC_CMD_READ_KEYINFO → goes in input.data8
}

private struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    struct vers_t {
        var major: CUnsignedChar = 0, minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0, reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }
    struct LimitData_t {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
    }
    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0
    }
    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0        // ← command byte goes HERE
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
                             0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0)
}

private struct SMCVal_t {
    var key: String
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)
    init(_ key: String) { self.key = key }
}

private extension FourCharCode {
    init(fromString str: String) {
        precondition(str.count == 4)
        self = str.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
    func toString() -> String {
        String(UnicodeScalar(self >> 24 & 0xff)!) +
        String(UnicodeScalar(self >> 16 & 0xff)!) +
        String(UnicodeScalar(self >>  8 & 0xff)!) +
        String(UnicodeScalar(self        & 0xff)!)
    }
}

final class SMC {
    private var conn: io_connect_t = 0

    init() {
        var iterator: io_iterator_t = 0
        let match = IOServiceMatching("AppleSMC")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == kIOReturnSuccess
        else { return }
        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else { return }
        let r = IOServiceOpen(device, mach_task_self_, 0, &conn)
        IOObjectRelease(device)
        if r != kIOReturnSuccess { conn = 0 }
    }

    deinit { close() }

    func close() {
        guard conn != 0 else { return }
        IOServiceClose(conn)
        conn = 0
    }

    /// Decodes the value at `key` to a Double by dispatching on its SMC dataType.
    /// Returns nil if the key is absent, empty, or an unsupported type.
    func value(forKey key: String) -> Double? {
        guard conn != 0 else { return nil }
        var val = SMCVal_t(key)
        guard read(&val) == kIOReturnSuccess, val.dataSize > 0 else { return nil }
        let b = val.bytes
        switch val.dataType {
        case "ui8 ": return Double(b[0])
        case "ui16": return Double(UInt16(b[0]) << 8 | UInt16(b[1]))            // big-endian
        case "ui32": return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16
                                 | UInt32(b[2]) << 8  | UInt32(b[3]))           // big-endian
        case "flt ": return Double(b.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Float.self) }) // IEEE-754 native LE
        case "fpe2": return Double((Int(b[0]) << 6) + (Int(b[1]) >> 2))
        case "sp78": return Double(Int(b[0]) << 8 | Int(b[1])) / 256
        default:     return nil
        }
    }

    private func read(_ value: inout SMCVal_t) -> kern_return_t {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = FourCharCode(fromString: value.key)
        input.data8 = SMCKeys.readKeyInfo.rawValue
        var r = call(input: &input, output: &output)
        if r != kIOReturnSuccess { return r }
        value.dataSize = UInt32(output.keyInfo.dataSize)
        value.dataType = output.keyInfo.dataType.toString()
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCKeys.readBytes.rawValue
        r = call(input: &input, output: &output)
        if r != kIOReturnSuccess { return r }
        _ = withUnsafePointer(to: &output.bytes) { src in
            value.bytes.withUnsafeMutableBytes { dst in
                memcpy(dst.baseAddress!, src, min(Int(value.dataSize), 32))
            }
        }
        return kIOReturnSuccess
    }

    private func call(input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride   // reset every call
        return IOConnectCallStructMethod(conn, UInt32(SMCKeys.kernelIndex.rawValue),
                                         &input, inputSize, &output, &outputSize)
    }

    // MARK: - Fan convenience (used by FanSampler)

    /// Number of fans reported by the SMC ("FNum" key).
    var fanCount: Int { Int(value(forKey: "FNum") ?? 0) }

    /// Current fan speed in rpm for the given fan index (F0Ac, F1Ac, …).
    func fanSpeed(_ id: Int) -> Double? { value(forKey: "F\(id)Ac") }

    /// Minimum rated speed in rpm for the given fan index (F0Mn, F1Mn, …).
    func fanMin(_ id: Int)   -> Double? { value(forKey: "F\(id)Mn") }

    /// Maximum rated speed in rpm for the given fan index (F0Mx, F1Mx, …).
    func fanMax(_ id: Int)   -> Double? { value(forKey: "F\(id)Mx") }
}
