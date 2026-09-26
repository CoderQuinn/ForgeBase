import Foundation
import XCTest

@testable import ForgeBase

final class PacketBufferBoundaryTests: XCTestCase {
    func testWholeBufferReadsNetworkByteOrderAndRejectsBounds() {
        let data = Data([0x01, 0x23, 0x45, 0x67, 0x89])
        let buffer = FBDataPacketBuffer(data)

        XCTAssertEqual(buffer.loadUInt8(at: 4), 0x89)
        XCTAssertEqual(buffer.loadUInt16(at: 1), 0x2345)
        XCTAssertEqual(buffer.loadUInt32(at: 1), 0x2345_6789)
        XCTAssertNil(buffer.loadUInt8(at: -1))
        XCTAssertNil(buffer.loadUInt8(at: data.count))
        XCTAssertNil(buffer.loadUInt16(at: data.count - 1))
        XCTAssertNil(buffer.loadUInt32(at: data.count - 3))

        let existential: FBPacketBuffer = buffer
        XCTAssertEqual(existential.materialize(), data)
    }

    func testSliceReadsNestedSlicesAndRejectsInvalidRanges() {
        let buffer = FBDataPacketBuffer(Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55]))
        let slice = buffer.slice(from: 1, length: 5) as? FBDataSlicePacketBuffer

        XCTAssertEqual(slice?.loadUInt8(at: 0), 0x11)
        XCTAssertEqual(slice?.loadUInt16(at: 1), 0x2233)
        XCTAssertEqual(slice?.loadUInt32(at: 1), 0x2233_4455)
        XCTAssertNil(slice?.loadUInt8(at: -1))
        XCTAssertNil(slice?.loadUInt8(at: 5))
        XCTAssertNil(slice?.loadUInt16(at: 4))
        XCTAssertNil(slice?.loadUInt32(at: 2))

        let nested = slice?.slice(from: 1, length: 3)
        XCTAssertEqual(nested?.materialize(), Data([0x22, 0x33, 0x44]))
        XCTAssertNil(slice?.slice(from: -1, length: 1))
        XCTAssertNil(slice?.slice(from: 0, length: -1))
        XCTAssertNil(slice?.slice(from: 4, length: 2))

        XCTAssertNil(buffer.slice(from: -1, length: 1))
        XCTAssertNil(buffer.slice(from: 0, length: -1))
        XCTAssertNil(buffer.slice(from: 5, length: 2))
    }

    func testEmptySlicesAtReadableBoundaryAreValid() {
        let data = Data([0xAA, 0xBB])
        let whole = FBDataPacketBuffer(data)
        let empty = whole.slice(from: data.count, length: 0)
        let direct = FBDataSlicePacketBuffer(data: data, start: 0, length: data.count)

        XCTAssertEqual(empty?.readableBytes, 0)
        XCTAssertEqual(empty?.materialize(), Data())
        XCTAssertEqual(direct.materialize(), data)
    }

    func testWriterRawDataPointersAndCapacityPreserveByteOrder() {
        var writer = FBPacketBufferWriter(capacity: 32)
        writer.raw([0x01, 0x02])
        writer.raw(Data([0x03, 0x04]))
        writer.pointer(to: 0)
        writer.pointer(to: 0x3FFF)

        XCTAssertEqual(
            writer.data,
            Data([0x01, 0x02, 0x03, 0x04, 0xC0, 0x00, 0xFF, 0xFF])
        )
        XCTAssertEqual(writer.position, 8)
    }

    func testWriterEncodesRootAndAbsoluteDNSNames() throws {
        var root = FBPacketBufferWriter()
        XCTAssertTrue(root.name(""))
        XCTAssertEqual(root.data, Data([0]))

        var absoluteRoot = FBPacketBufferWriter()
        try absoluteRoot.writeDNSName(".")
        XCTAssertEqual(absoluteRoot.data, Data([0]))

        var domain = FBPacketBufferWriter()
        XCTAssertTrue(domain.name("www.example.com."))
        XCTAssertEqual(
            domain.data,
            Data([
                3, 0x77, 0x77, 0x77,
                7, 0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65,
                3, 0x63, 0x6F, 0x6D,
                0,
            ])
        )
        XCTAssertEqual(domain.position, domain.data.count)
    }

    func testWriterRejectsMalformedDNSNamesWithoutMutation() {
        let invalidNames = [
            ".example.com",
            "example..com",
            "example.com..",
            "café.example",
            String(repeating: "a", count: 64) + ".example",
        ]

        for invalidName in invalidNames {
            var writer = FBPacketBufferWriter()
            writer.raw([0xAA, 0xBB])

            XCTAssertFalse(writer.name(invalidName), invalidName)
            XCTAssertEqual(writer.data, Data([0xAA, 0xBB]), invalidName)
            XCTAssertEqual(writer.position, 2, invalidName)
        }
    }

    func testWriterEnforcesDNSWireLengthBoundary() throws {
        let maximumName = [63, 63, 63, 61]
            .map { String(repeating: "a", count: $0) }
            .joined(separator: ".")
        let oversizedName = [63, 63, 63, 62]
            .map { String(repeating: "a", count: $0) }
            .joined(separator: ".")

        var maximumWriter = FBPacketBufferWriter()
        try maximumWriter.writeDNSName(maximumName)
        XCTAssertEqual(maximumWriter.data.count, 255)
        XCTAssertEqual(maximumWriter.position, 255)

        var oversizedWriter = FBPacketBufferWriter()
        XCTAssertThrowsError(try oversizedWriter.writeDNSName(oversizedName)) { error in
            XCTAssertEqual(
                error as? FBPacketBufferWriterError,
                .dnsNameTooLong(actual: 256, maximum: 255)
            )
        }
        XCTAssertTrue(oversizedWriter.data.isEmpty)
        XCTAssertEqual(oversizedWriter.position, 0)
    }

    func testWriterReportsDNSValidationFailures() {
        var writer = FBPacketBufferWriter()

        XCTAssertThrowsError(try writer.writeDNSName("a..b")) { error in
            XCTAssertEqual(error as? FBPacketBufferWriterError, .emptyDNSLabel)
        }
        XCTAssertThrowsError(try writer.writeDNSName("café.example")) { error in
            XCTAssertEqual(error as? FBPacketBufferWriterError, .nonASCIIDNSLabel)
        }
        XCTAssertThrowsError(
            try writer.writeDNSName(String(repeating: "a", count: 64))
        ) { error in
            XCTAssertEqual(
                error as? FBPacketBufferWriterError,
                .dnsLabelTooLong(actual: 64, maximum: 63)
            )
        }
        XCTAssertTrue(writer.data.isEmpty)
        XCTAssertEqual(writer.position, 0)
    }
}
