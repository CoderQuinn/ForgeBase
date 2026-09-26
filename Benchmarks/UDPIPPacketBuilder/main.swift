import Foundation
import Network
import ForgeBase
import Baseline

let src = IPv4Address("192.0.2.1")!
let dst = IPv4Address("198.51.100.2")!
@inline(never) func build(_ old: Bool, _ payload: Data, _ port: UInt16) throws -> Data {
    if old {
        return try BaselineUDPIPPacketBuilder.buildUDPIPv4(srcIP: src, dstIP: dst, srcPort: port, dstPort: 443, payload: payload)
    }
    return try FBUDPIPPacketBuilder.buildUDPIPv4(srcIP: src, dstIP: dst, srcPort: port, dstPort: 443, payload: payload)
}
var sink: UInt64 = 0
func measure(_ old: Bool, _ payload: Data, _ iterations: Int) throws -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    for i in 0..<iterations {
        let packet = try build(old, payload, UInt16(truncatingIfNeeded: i))
        sink &+= UInt64(packet[10]) + UInt64(packet.last!) + UInt64(packet.count)
    }
    return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations)
}
for size in [0, 64, 1472, 4096, 65507] {
    let payload = Data((0..<size).map { UInt8(truncatingIfNeeded: $0) })
    let expected = try build(true, payload, 1234)
    let actual = try build(false, payload, 1234)
    precondition(expected == actual)
    let iterations = size > 4096 ? 2000 : 20000
    _ = try measure(true, payload, 100)
    _ = try measure(false, payload, 100)
    var old: [Double] = [], current: [Double] = []
    for round in 0..<7 {
        if round.isMultiple(of: 2) {
            old.append(try measure(true, payload, iterations))
            current.append(try measure(false, payload, iterations))
        } else {
            current.append(try measure(false, payload, iterations))
            old.append(try measure(true, payload, iterations))
        }
    }
    let a = old.sorted()[3], b = current.sorted()[3]
    print("payload=\(size) baseline_ns=\(Int(a)) candidate_ns=\(Int(b)) ratio=\(b/a)")
}
print("observable_sink=\(sink)")
