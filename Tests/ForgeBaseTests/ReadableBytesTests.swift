import Foundation
import XCTest

@testable import ForgeBase

/// A legacy conformer using the protocol's additive snapshot fallback.
private struct LegacyBuffer: FBPacketBuffer {
    let storage: FBDataPacketBuffer
    var readableBytes: Int { storage.readableBytes }
    func loadUInt8(at offset: Int) -> UInt8? { storage.loadUInt8(at: offset) }
    func loadUInt16(at offset: Int) -> UInt16? { storage.loadUInt16(at: offset) }
    func loadUInt32(at offset: Int) -> UInt32? { storage.loadUInt32(at: offset) }
    func slice(from offset: Int, length: Int) -> FBPacketBuffer? { storage.slice(from: offset, length: length) }
    func materialize() -> Data { storage.materialize() }
}

final class ReadableBytesTests: XCTestCase {
    private enum ProbeError: Error { case expected }

    func testScopedBorrowWorksThroughExistentialsAndLegacyFallback() throws {
        var storage = Data([99, 1, 2, 3, 4, 88])
        storage.removeFirst()
        XCTAssertNotEqual(storage.startIndex, 0)
        let whole = FBDataPacketBuffer(storage)
        let nested = try XCTUnwrap(whole.slice(from: 1, length: 3)?.slice(from: 1, length: 1))
        let cases: [(FBPacketBuffer, [UInt8])] = [
            (whole, [1, 2, 3, 4, 88]),
            (nested, [3]),
            (LegacyBuffer(storage: whole), [1, 2, 3, 4, 88]),
            (FBDataPacketBuffer(Data()), []),
            (FBDataSlicePacketBuffer(data: Data(), start: 0, length: 0), []),
            (FBDataSlicePacketBuffer(data: storage, start: storage.count, length: 0), []),
        ]
        for (buffer, expected) in cases {
            var calls = 0
            let count = buffer.withUnsafeReadableBytes { bytes in
                calls += 1
                XCTAssertEqual(Array(bytes), expected)
                return bytes.count
            }
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(count, buffer.readableBytes)
            XCTAssertThrowsError(try buffer.withUnsafeReadableBytes { _ -> Void in throw ProbeError.expected }) { error in
                XCTAssertTrue(error is ProbeError)
            }
        }
    }

    func testSliceEqualityAndHashUseOnlyLogicalBytesAcrossStorageLayouts() {
        let bytes = Array(UInt8(0)...UInt8(127))
        var indexed = Data([255] + bytes)
        indexed.removeFirst()
        let original = FBDataSlicePacketBuffer(data: indexed, start: 0, length: bytes.count)
        let equal = FBDataSlicePacketBuffer(data: Data([99] + bytes + [88]), start: 1, length: bytes.count)
        XCTAssertEqual(original, equal)
        XCTAssertEqual(original.hashValue, equal.hashValue)
        for index in [0, bytes.count / 2, bytes.count - 1] {
            var changed = bytes
            changed[index] ^= 0xFF
            XCTAssertNotEqual(original, FBDataSlicePacketBuffer(data: Data(changed), start: 0, length: changed.count))
        }
        XCTAssertNotEqual(original, FBDataSlicePacketBuffer(data: indexed, start: 0, length: bytes.count - 1))
        let empty = FBDataSlicePacketBuffer(data: Data(), start: 0, length: 0)
        let emptyTail = FBDataSlicePacketBuffer(data: indexed, start: indexed.count, length: 0)
        XCTAssertEqual(empty, emptyTail)
        XCTAssertEqual(empty.hashValue, emptyTail.hashValue)
    }

    func testSliceRetainsSnapshotAcrossCallerMutation() throws {
        var source = Data(repeating: 7, count: 4096)
        let slice = try XCTUnwrap(FBDataPacketBuffer(source).slice(from: 1024, length: 16))
        source[1024] = 9
        slice.withUnsafeReadableBytes { XCTAssertEqual(Array($0), Array(repeating: 7, count: 16)) }
        XCTAssertEqual(source[1024], 9)
    }
}
