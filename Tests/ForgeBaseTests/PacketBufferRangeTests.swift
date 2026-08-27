import Foundation
import XCTest

@testable import ForgeBase

final class PacketBufferRangeTests: XCTestCase {
    func testWholeBufferRejectsOverflowingPublicRanges() {
        let buffer = FBDataPacketBuffer(Data([0x01, 0x02, 0x03, 0x04]))

        for offset in [Int.min, -1, 4, Int.max] {
            XCTAssertNil(buffer.loadUInt8(at: offset), "offset: \(offset)")
            XCTAssertNil(buffer.loadUInt16(at: offset), "offset: \(offset)")
            XCTAssertNil(buffer.loadUInt32(at: offset), "offset: \(offset)")
        }

        XCTAssertNil(buffer.slice(from: Int.max, length: 1))
        XCTAssertNil(buffer.slice(from: 1, length: Int.max))
        XCTAssertNil(buffer.slice(from: Int.min, length: Int.max))
    }

    func testSliceBufferRejectsOverflowingPublicRanges() {
        let buffer = FBDataSlicePacketBuffer(
            data: Data([0x00, 0x01, 0x02, 0x03, 0x04]),
            start: 1,
            length: 3
        )

        for offset in [Int.min, -1, 3, Int.max] {
            XCTAssertNil(buffer.loadUInt8(at: offset), "offset: \(offset)")
            XCTAssertNil(buffer.loadUInt16(at: offset), "offset: \(offset)")
            XCTAssertNil(buffer.loadUInt32(at: offset), "offset: \(offset)")
        }

        XCTAssertNil(buffer.slice(from: Int.max, length: 1))
        XCTAssertNil(buffer.slice(from: 1, length: Int.max))
        XCTAssertNil(buffer.slice(from: Int.min, length: Int.max))
    }

    func testSliceValidityMatchesHalfOpenRangeModelAtBoundaries() {
        let buffer = FBDataPacketBuffer(Data([0x00, 0x01, 0x02, 0x03]))
        let values = [Int.min, -1, 0, 1, 3, 4, 5, Int.max]

        for offset in values {
            for length in values {
                let expected =
                    offset >= 0 && length >= 0 && offset <= buffer.readableBytes
                    && length <= buffer.readableBytes - offset
                XCTAssertEqual(
                    buffer.slice(from: offset, length: length) != nil,
                    expected,
                    "offset: \(offset), length: \(length)"
                )
            }
        }
    }
}
