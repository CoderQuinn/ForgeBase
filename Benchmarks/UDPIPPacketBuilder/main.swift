import Baseline
import CryptoKit
import ForgeBase
import Foundation
import Network

// These counters observe adapter calls in correctness probes only. They do not
// measure allocations and are deliberately absent from the timed workload.
final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var counts = ["borrow": 0, "materialize": 0]
    func record(_ key: String) {
        lock.lock()
        counts[key, default: 0] += 1
        lock.unlock()
    }
    func count(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[key, default: 0]
    }
}
struct BorrowProbe: FBPacketBuffer {
    let base: any FBPacketBuffer
    let calls: Calls
    var readableBytes: Int { base.readableBytes }
    func loadUInt8(at offset: Int) -> UInt8? { base.loadUInt8(at: offset) }
    func loadUInt16(at offset: Int) -> UInt16? { base.loadUInt16(at: offset) }
    func loadUInt32(at offset: Int) -> UInt32? { base.loadUInt32(at: offset) }
    func slice(from offset: Int, length: Int) -> (any FBPacketBuffer)? { base.slice(from: offset, length: length) }
    func materialize() -> Data {
        calls.record("materialize")
        return base.materialize()
    }
    func withUnsafeReadableBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        calls.record("borrow")
        return try base.withUnsafeReadableBytes(body)
    }
}
struct LegacyBuffer: FBPacketBuffer {
    let base: any FBPacketBuffer
    let calls: Calls?
    var readableBytes: Int { base.readableBytes }
    func loadUInt8(at offset: Int) -> UInt8? { base.loadUInt8(at: offset) }
    func loadUInt16(at offset: Int) -> UInt16? { base.loadUInt16(at: offset) }
    func loadUInt32(at offset: Int) -> UInt32? { base.loadUInt32(at: offset) }
    func slice(from offset: Int, length: Int) -> (any FBPacketBuffer)? { base.slice(from: offset, length: length) }
    func materialize() -> Data {
        calls?.record("materialize")
        return base.materialize()
    }
    // Intentionally uses the protocol's materializing scoped-byte default.
}
enum HarnessError: Error { case invalid(String) }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw HarnessError.invalid(message) }
}

// Independent reference encoder: fixed synthetic addresses, explicit wire
// fields, and a one's-complement sum. No production builder/checksum helpers.
func referencePacket(_ payload: Data, port: UInt16) -> Data {
    func word(_ value: Int) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 255)] }
    var header: [UInt8] =
        [0x45, 0] + word(payload.count + 28) + [0, 0, 0, 0, 64, 17, 0, 0]
        + [192, 0, 2, 1, 198, 51, 100, 2]
    var sum = stride(from: 0, to: 20, by: 2).reduce(0) { $0 + Int(header[$1]) * 256 + Int(header[$1 + 1]) }
    sum = (sum & 65535) + (sum >> 16)
    sum = (sum & 65535) + (sum >> 16)
    header.replaceSubrange(10..<12, with: word(65535 - sum))
    return Data(header + word(Int(port)) + word(443) + word(payload.count + 8) + [0, 0]) + payload
}
func validate(_ packet: Data, payload: Data, port: UInt16) throws {
    try require(packet == referencePacket(payload, port: port), "independent IPv4/UDP oracle mismatch")
}
struct Round: Encodable {
    let order: String
    let baselineBatchNs: UInt64
    let candidateBatchNs: UInt64
}
struct Workload: Encodable {
    let payloadSize: Int
    let path: String
    let iterations: Int
    let rounds: [Round]
}
struct Observation: Encodable {
    let payloadSize: Int
    let path: String
    let scopedBorrowOverrideCalls: Int
    let materializeCalls: Int
    let ownedOutputPayloadBytes: Int
    let method: String
}
struct Result: Encodable {
    let oraclePassed: Bool
    let timingStatus: String
    let fixtureSha256: String
    let observations: [Observation]
    let workloads: [Workload]
    let sink: UInt64
}

@main enum Benchmark {
    static func main() throws {
        let arguments = Set(CommandLine.arguments.dropFirst())
        try require(arguments.isSubset(of: ["--measure", "--smoke", "--self-test", "--profile-check"]), "unknown benchmark option")
        let profile = arguments.contains("--profile-check")
        let measure = arguments.contains("--measure") || profile
        let smoke = arguments.contains("--smoke") || profile
        let selfTest = arguments.contains("--self-test") || profile
        guard let src = IPv4Address("192.0.2.1"), let dst = IPv4Address("198.51.100.2") else {
            throw HarnessError.invalid("invalid synthetic address")
        }
        func baseline(_ payload: Data, _ port: UInt16) throws -> Data {
            try BaselineUDPIPPacketBuilder.buildUDPIPv4(srcIP: src, dstIP: dst, srcPort: port, dstPort: 443, payload: payload)
        }
        func build(_ payload: Data, _ buffer: (any FBPacketBuffer)?, _ port: UInt16) throws -> Data {
            if let buffer {
                return try FBUDPIPPacketBuilder.buildUDPIPv4(srcIP: src, dstIP: dst, srcPort: port, dstPort: 443, payloadBuffer: buffer)
            }
            return try FBUDPIPPacketBuilder.buildUDPIPv4(srcIP: src, dstIP: dst, srcPort: port, dstPort: 443, payload: payload)
        }
        var sink: UInt64 = 0
        func batch(_ iterations: Int, _ operation: (UInt16) throws -> Data) rethrows -> UInt64 {
            let start = DispatchTime.now().uptimeNanoseconds
            for index in 0..<iterations {
                let packet = try operation(UInt16(truncatingIfNeeded: index))
                sink &+= UInt64(packet[10]) + UInt64(packet[packet.count - 1]) + UInt64(packet.count)
            }
            return DispatchTime.now().uptimeNanoseconds - start
        }
        let payloads = [0, 64, 1472, 4096, 65507].map { size in Data((0..<size).map { UInt8(truncatingIfNeeded: $0) }) }
        var observations: [Observation] = []
        var fixtures: [(Data, String, (any FBPacketBuffer)?)] = []
        for payload in payloads {
            let whole = FBDataPacketBuffer(payload)
            // Data retains a nonzero startIndex; then two logical slice levels
            // hide prefix/suffix sentinels from the builder.
            let backing = (Data([0xEE, 0xDD, 0xCC]) + payload + Data([0xBB, 0xAA])).dropFirst()
            guard let outer = FBDataPacketBuffer(backing).slice(from: 1, length: payload.count + 2),
                let nested = outer.slice(from: 1, length: payload.count)
            else { throw HarnessError.invalid("invalid synthetic window") }
            for path in ["data", "borrowed", "nested_slice", "legacy_fallback"] {
                let calls = Calls()
                let base: any FBPacketBuffer = path == "nested_slice" ? nested : whole
                let probe: (any FBPacketBuffer)? =
                    path == "data" ? nil : (path == "legacy_fallback" ? (LegacyBuffer(base: base, calls: calls) as any FBPacketBuffer) : BorrowProbe(base: base, calls: calls))
                for port: UInt16 in [0, 1234, 65535] {
                    try validate(baseline(payload, port), payload: payload, port: port)
                    try validate(build(payload, probe, port), payload: payload, port: port)
                }
                try require(calls.count("borrow") == (["borrowed", "nested_slice"].contains(path) ? 3 : 0), "borrow path changed")
                try require(calls.count("materialize") == (path == "legacy_fallback" ? 3 : 0), "materialize path changed")
                observations.append(
                    Observation(
                        payloadSize: payload.count, path: path, scopedBorrowOverrideCalls: calls.count("borrow"), materializeCalls: calls.count("materialize"),
                        ownedOutputPayloadBytes: payload.count,
                        method: "adapter calls counted outside timing; owned copy bytes inferred from validated size/source contract; allocations unmeasured"))
                if selfTest, let probe {
                    try require(probe.loadUInt8(at: 0) == payload.first, "probe byte read mismatch")
                    try require(probe.loadUInt16(at: 0) == (payload.count >= 2 ? 1 : nil), "probe word read mismatch")
                    try require(probe.loadUInt32(at: 0) == (payload.count >= 4 ? 66051 : nil), "probe dword read mismatch")
                    try require(probe.slice(from: 0, length: payload.count)?.materialize() == payload, "probe slice mismatch")
                    try require(probe.materialize() == payload, "probe materialize mismatch")
                }
                let timed: (any FBPacketBuffer)? = path == "data" ? nil : (path == "legacy_fallback" ? LegacyBuffer(base: whole, calls: nil) : base)
                fixtures.append((payload, path, timed))
            }
            if selfTest {
                let expected = referencePacket(payload, port: 1234)
                for index in expected.indices {
                    var corrupt = expected
                    corrupt[index] ^= 1
                    do {
                        try validate(corrupt, payload: payload, port: 1234)
                        throw HarnessError.invalid("oracle accepted corrupted byte \(index)")
                    } catch HarnessError.invalid(let reason) {
                        try require(reason == "independent IPv4/UDP oracle mismatch", reason)
                    }
                }
            }
        }
        // Anchor the reference encoder to a manually checked empty datagram.
        try require(
            referencePacket(Data(), port: 1234) == Data([69, 0, 0, 28, 0, 0, 0, 0, 64, 17, 142, 154, 192, 0, 2, 1, 198, 51, 100, 2, 4, 210, 1, 187, 0, 8, 0, 0]),
            "reference fixture mismatch")
        do {
            _ = try build(Data(count: 65508), nil, 1234)
            throw HarnessError.invalid("oversized payload accepted")
        } catch FBUDPIPPacketBuilderError.payloadTooLarge(let actual, let maximum) {
            try require(actual == 65508 && maximum == 65507, "incorrect oversized error")
        }
        // All baseline and candidate fixtures have passed before timing begins.
        var workloads: [Workload] = []
        for (payload, path, buffer) in fixtures {
            let iterations = measure ? (smoke ? 10 : (payload.count > 4096 ? 2000 : 20000)) : 0
            var rounds: [Round] = []
            if measure {
                _ = try batch(smoke ? 2 : 100) { try baseline(payload, $0) }
                _ = try batch(smoke ? 2 : 100) { try build(payload, buffer, $0) }
                for round in 0..<(smoke ? 2 : 7) {
                    let a: UInt64
                    let b: UInt64
                    if round.isMultiple(of: 2) {
                        a = try batch(iterations) { try baseline(payload, $0) }
                        b = try batch(iterations) { try build(payload, buffer, $0) }
                    } else {
                        b = try batch(iterations) { try build(payload, buffer, $0) }
                        a = try batch(iterations) { try baseline(payload, $0) }
                    }
                    rounds.append(Round(order: round.isMultiple(of: 2) ? "AB" : "BA", baselineBatchNs: a, candidateBatchNs: b))
                }
            }
            workloads.append(Workload(payloadSize: payload.count, path: path, iterations: iterations, rounds: rounds))
        }
        let fixturesData = payloads.reduce(into: Data()) { $0.append($1) }
        let fixtureDigest = SHA256.hash(data: fixturesData).map { String(format: "%02x", $0) }.joined()
        let result = Result(
            oraclePassed: true, timingStatus: profile ? "instrumented_correctness" : (measure ? "measured" : "not_run"), fixtureSha256: fixtureDigest,
            observations: observations, workloads: workloads, sink: sink)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        print(String(decoding: try encoder.encode(result), as: UTF8.self))
    }
}
