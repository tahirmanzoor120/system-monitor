import Foundation
import IOKit

/// Minimal AppleSMC reader (works on Apple Silicon for flt/ui/sp keys).
final class SMC {
    private var conn: io_connect_t = 0

    // Layout must match the kernel's SMCParamStruct (80 bytes).
    private struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0, pad: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0, p1: UInt8 = 0, p2: UInt8 = 0, p3: UInt8 = 0 }
    private struct Param {
        var key: UInt32 = 0
        var vers = Vers()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    init?() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
    }
    deinit { if conn != 0 { IOServiceClose(conn) } }

    private func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    private func str(_ v: UInt32) -> String {
        String(bytes: [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)], encoding: .ascii) ?? "????"
    }

    private func call(_ input: inout Param) -> Param? {
        var out = Param()
        var size = MemoryLayout<Param>.stride
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<Param>.stride, &out, &size)
        return r == KERN_SUCCESS && out.result == 0 ? out : nil
    }

    /// Returns (type, raw bytes) for a key.
    func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        var p = Param()
        p.key = fourCC(key)
        p.data8 = 9  // read key info
        guard let info = call(&p) else { return nil }
        var q = Param()
        q.key = p.key
        q.keyInfo.dataSize = info.keyInfo.dataSize
        q.data8 = 5  // read bytes
        guard let out = call(&q) else { return nil }
        let n = Int(info.keyInfo.dataSize)
        let all = withUnsafeBytes(of: out.bytes) { Array($0) }
        return (str(info.keyInfo.dataType), Array(all.prefix(n)))
    }

    func double(_ key: String) -> Double? {
        guard let (t, b) = read(key) else { return nil }
        switch t.trimmingCharacters(in: .whitespaces) {
        case "flt":
            guard b.count == 4 else { return nil }
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "ui8": return b.first.map(Double.init)
        case "ui16": return b.count == 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) : nil
        case "fpe2": return b.count == 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4 : nil
        case "sp78": return b.count == 2 ? Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256 : nil
        default: return nil
        }
    }

    /// Key at index (for discovery).
    func key(at i: UInt32) -> String? {
        var p = Param()
        p.data8 = 8
        p.data32 = i
        return call(&p).map { str($0.key) }
    }
}
