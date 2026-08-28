import Foundation
import Network
import XCTest

@testable import ForgeBase

final class UDPIPPacketBuilderBoundaryTests: XCTestCase {
    func testEmptyUDPPacketLayoutUsesNetworkByteOrder() throws {
        let packet = try FBUDPIPPacketBuilder.buildUDPIPv4(
            srcIP: IPv4Address("1.2.3.4")!,
            dstIP: IPv4Address("203.0.113.255")!,
            srcPort: 0x1234,
            dstPort: 0xABCD,
            payload: Data(),
            ttl: 255,
            udpChecksumEnabled: false
        )
        let buffer = FBDataPacketBuffer(packet)

        XCTAssertEqual(packet.count, 28)
        XCTAssertEqual(packet[0], 0x45)
        XCTAssertEqual(buffer.loadUInt16(at: 2), 28)
        XCTAssertEqual(packet[8], 255)
        XCTAssertEqual(packet[9], 17)
        XCTAssertEqual(Array(packet[12..<20]), [1, 2, 3, 4, 203, 0, 113, 255])
        XCTAssertEqual(buffer.loadUInt16(at: 20), 0x1234)
        XCTAssertEqual(buffer.loadUInt16(at: 22), 0xABCD)
        XCTAssertEqual(buffer.loadUInt16(at: 24), 8)
        XCTAssertEqual(buffer.loadUInt16(at: 26), 0)
        XCTAssertEqual(ipv4HeaderChecksum(packet), 0)
    }

    func testOddPayloadBuildsParseablePacketWithValidIPChecksum() throws {
        let payload = Data([0x10, 0x20, 0x30, 0x40, 0x50])
        let packet = try FBUDPIPPacketBuilder.buildUDPIPv4(
            srcIP: IPv4Address("10.0.0.1")!,
            dstIP: IPv4Address("10.0.0.2")!,
            srcPort: 65_535,
            dstPort: 1,
            payload: payload,
            ttl: 1
        )
        let ip = FBIPPacketView(buffer: FBDataPacketBuffer(packet))
        let udp = ip.flatMap(FBUDPView.init)

        XCTAssertEqual(packet.count, 33)
        XCTAssertEqual(ip?.totalLength, 33)
        XCTAssertEqual(udp?.srcPort, 65_535)
        XCTAssertEqual(udp?.dstPort, 1)
        XCTAssertEqual(udp?.payload.materialize(), payload)
        XCTAssertEqual(ipv4HeaderChecksum(packet), 0)
    }

    func testMaximumIPv4UDPPayloadFitsSixteenBitLengths() throws {
        let maximumPayloadLength = FBUDPIPPacketBuilder.maximumIPv4UDPPayloadLength
        let payload = Data(repeating: 0xA5, count: maximumPayloadLength)
        let packet = try FBUDPIPPacketBuilder.buildUDPIPv4(
            srcIP: IPv4Address("192.0.2.1")!,
            dstIP: IPv4Address("198.51.100.1")!,
            srcPort: 1,
            dstPort: 2,
            payload: payload
        )
        let buffer = FBDataPacketBuffer(packet)

        XCTAssertEqual(packet.count, Int(UInt16.max))
        XCTAssertEqual(buffer.loadUInt16(at: 2), UInt16.max)
        XCTAssertEqual(buffer.loadUInt16(at: 24), 65_515)
        XCTAssertEqual(packet[28], 0xA5)
        XCTAssertEqual(packet[packet.count - 1], 0xA5)
        XCTAssertEqual(ipv4HeaderChecksum(packet), 0)
    }

    func testOversizedPayloadReturnsStructuredError() {
        let actual = FBUDPIPPacketBuilder.maximumIPv4UDPPayloadLength + 1
        let payload = Data(repeating: 0xA5, count: actual)

        XCTAssertThrowsError(
            try FBUDPIPPacketBuilder.buildUDPIPv4(
                srcIP: IPv4Address("192.0.2.1")!,
                dstIP: IPv4Address("198.51.100.1")!,
                srcPort: 1,
                dstPort: 2,
                payload: payload
            )
        ) { error in
            XCTAssertEqual(
                error as? FBUDPIPPacketBuilderError,
                .payloadTooLarge(actual: actual, maximum: 65_507)
            )
        }
    }

    func testUnsupportedUDPChecksumReturnsStructuredError() {
        XCTAssertThrowsError(
            try FBUDPIPPacketBuilder.buildUDPIPv4(
                srcIP: IPv4Address("192.0.2.1")!,
                dstIP: IPv4Address("198.51.100.1")!,
                srcPort: 1,
                dstPort: 2,
                payload: Data(),
                udpChecksumEnabled: true
            )
        ) { error in
            XCTAssertEqual(
                error as? FBUDPIPPacketBuilderError,
                .udpChecksumUnsupported
            )
        }
    }

    private func ipv4HeaderChecksum(_ packet: Data) -> UInt16 {
        var sum: UInt32 = 0
        for offset in stride(from: 0, to: 20, by: 2) {
            sum += UInt32(packet[offset]) << 8 | UInt32(packet[offset + 1])
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum & 0xFFFF)
    }
}
