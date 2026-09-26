import Foundation
import Network
import XCTest

@testable import ForgeBase

private final class BorrowProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var counts = (borrow: 0, materialize: 0)
    func record(borrow: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if borrow { counts.borrow += 1 } else { counts.materialize += 1 }
    }
    var snapshot: (borrow: Int, materialize: Int) {
        lock.lock()
        defer { lock.unlock() }
        return counts
    }
}

private struct LegacyPayload: FBPacketBuffer {
    let data: Data
    let readableBytes: Int
    let probe: BorrowProbe
    func loadUInt8(at offset: Int) -> UInt8? { FBDataPacketBuffer(data).loadUInt8(at: offset) }
    func loadUInt16(at offset: Int) -> UInt16? { FBDataPacketBuffer(data).loadUInt16(at: offset) }
    func loadUInt32(at offset: Int) -> UInt32? { FBDataPacketBuffer(data).loadUInt32(at: offset) }
    func slice(from offset: Int, length: Int) -> FBPacketBuffer? {
        FBDataPacketBuffer(data).slice(from: offset, length: length)
    }
    func materialize() -> Data {
        probe.record(borrow: false)
        return data
    }
}

private struct ContiguousPayload: FBPacketBuffer {
    let legacy: LegacyPayload
    var readableBytes: Int { legacy.readableBytes }
    func loadUInt8(at offset: Int) -> UInt8? { legacy.loadUInt8(at: offset) }
    func loadUInt16(at offset: Int) -> UInt16? { legacy.loadUInt16(at: offset) }
    func loadUInt32(at offset: Int) -> UInt32? { legacy.loadUInt32(at: offset) }
    func slice(from offset: Int, length: Int) -> FBPacketBuffer? { legacy.slice(from: offset, length: length) }
    func materialize() -> Data { legacy.materialize() }
    func withUnsafeReadableBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        legacy.probe.record(borrow: true)
        return try legacy.data.withUnsafeBytes(body)
    }
}

final class UDPIPPacketBufferTests: XCTestCase {
    private let src = IPv4Address("192.0.2.1")!
    private let dst = IPv4Address("198.51.100.2")!

    private func build(_ buffer: FBPacketBuffer, ttl: UInt8 = 64, checksum: Bool = false) throws -> Data {
        try FBUDPIPPacketBuilder.buildUDPIPv4(
            srcIP: src, dstIP: dst, srcPort: 0, dstPort: 65_535,
            payloadBuffer: buffer, ttl: ttl, udpChecksumEnabled: checksum
        )
    }

    func testLogicalWindowsMatchDataAPIAndIndependentChecksumOracle() throws {
        for size in [0, 1, 2, 63, 512, 1472, 4096, 65_507] {
            let expected = Data((0..<size).map { UInt8(truncatingIfNeeded: $0) })
            var indexedPayload = Data([99]) + expected
            indexedPayload.removeFirst()
            var indexed = Data([99, 88]) + expected + Data([77])
            indexed.removeFirst()
            XCTAssertNotEqual(indexed.startIndex, 0)
            let nested = try XCTUnwrap(
                FBDataPacketBuffer(indexed).slice(from: 1, length: size + 1)?.slice(from: 0, length: size)
            )
            let buffers: [FBPacketBuffer] = [
                FBDataPacketBuffer(expected), FBDataPacketBuffer(indexedPayload), nested,
                FBDataSlicePacketBuffer(data: indexed, start: 1, length: size),
            ]
            for ttl: UInt8 in [0, 1, 64, 255] {
                let reference = try FBUDPIPPacketBuilder.buildUDPIPv4(
                    srcIP: src, dstIP: dst, srcPort: 0, dstPort: 65_535, payload: expected, ttl: ttl
                )
                for buffer in buffers {
                    let packet = try build(buffer, ttl: ttl)
                    XCTAssertEqual(packet, reference)
                    XCTAssertEqual(Data(packet.dropFirst(28)), expected)
                    XCTAssertEqual(packet.count, size + 28)
                    XCTAssertEqual(packet[8], ttl)
                    XCTAssertEqual(FBDataPacketBuffer(packet).loadUInt16(at: 2), UInt16(size + 28))
                    XCTAssertEqual(FBDataPacketBuffer(packet).loadUInt16(at: 24), UInt16(size + 8))
                    XCTAssertEqual(Array(packet[20..<24]), [0, 0, 255, 255])
                    XCTAssertEqual(Array(packet[26..<28]), [0, 0])
                    // Independent end-around-carry oracle, including the emitted checksum.
                    var sum = 0
                    for offset in stride(from: 0, to: 20, by: 2) {
                        sum += Int(packet[offset]) * 256 + Int(packet[offset + 1])
                        if sum > 65_535 { sum -= 65_535 }
                    }
                    XCTAssertEqual(sum, 65_535)
                }
            }
        }
        let emptyTail = FBDataSlicePacketBuffer(data: Data([1]), start: 1, length: 0)
        XCTAssertEqual(try build(emptyTail), try build(FBDataPacketBuffer(Data())))
    }

    func testContiguousBorrowAndLegacyFallbackDispatchAndOwnedOutput() throws {
        for size in [0, 1, 4096, 65_507] {
            var data = Data(repeating: 7, count: size)
            let probe = BorrowProbe()
            let legacy = LegacyPayload(data: data, readableBytes: size, probe: probe)
            var packet = try build(ContiguousPayload(legacy: legacy))
            XCTAssertEqual(probe.snapshot.borrow, 1)
            XCTAssertEqual(probe.snapshot.materialize, 0)
            XCTAssertEqual(try build(legacy), packet)
            XCTAssertEqual(probe.snapshot.materialize, 1)
            if size > 0 {
                data[0] = 9
                XCTAssertEqual(packet[28], 7)
                packet[28] = 8
                XCTAssertEqual(legacy.data[0], 7)
                XCTAssertEqual(data[0], 9)
            }
        }
    }

    func testInvalidDeclarationsAndErrorOrderAvoidBorrowing() {
        for checksum in [false, true] {
            for length in [Int.min, -1, 65_508, Int.max] {
                let probe = BorrowProbe()
                let payload = ContiguousPayload(legacy: LegacyPayload(data: Data(), readableBytes: length, probe: probe))
                let expected: FBUDPIPPacketBuilderError =
                    length < 0
                    ? .invalidPayloadLength(actual: length)
                    : .payloadTooLarge(actual: length, maximum: 65_507)
                XCTAssertThrowsError(try build(payload, checksum: checksum)) {
                    XCTAssertEqual($0 as? FBUDPIPPacketBuilderError, expected)
                }
                XCTAssertEqual(probe.snapshot.borrow, 0)
                XCTAssertEqual(probe.snapshot.materialize, 0)
            }
        }
        let probe = BorrowProbe()
        let mismatch = ContiguousPayload(legacy: LegacyPayload(data: Data([1]), readableBytes: 0, probe: probe))
        XCTAssertThrowsError(try build(mismatch, checksum: true)) {
            XCTAssertEqual($0 as? FBUDPIPPacketBuilderError, .udpChecksumUnsupported)
        }
        XCTAssertEqual(probe.snapshot.borrow, 0)
        XCTAssertThrowsError(
            try FBUDPIPPacketBuilder.buildUDPIPv4(
                srcIP: src, dstIP: dst, srcPort: 0, dstPort: 0,
                payload: Data(repeating: 0, count: 65_508), udpChecksumEnabled: true
            )
        ) {
            XCTAssertEqual($0 as? FBUDPIPPacketBuilderError, .payloadTooLarge(actual: 65_508, maximum: 65_507))
        }
    }

    func testBorrowedLengthMismatchIsRejectedForBothDispatchPaths() {
        for (declared, actual) in [(0, 1), (1, 0), (1, 2), (2, 1), (65_507, 65_508)] {
            let probe = BorrowProbe()
            let legacy = LegacyPayload(data: Data(repeating: 7, count: actual), readableBytes: declared, probe: probe)
            for buffer: FBPacketBuffer in [legacy, ContiguousPayload(legacy: legacy)] {
                XCTAssertThrowsError(try build(buffer)) {
                    XCTAssertEqual(
                        $0 as? FBUDPIPPacketBuilderError, .payloadLengthMismatch(declared: declared, actual: actual)
                    )
                }
            }
            XCTAssertEqual(probe.snapshot.borrow, 1)
            XCTAssertEqual(probe.snapshot.materialize, 1)
        }
    }
}
