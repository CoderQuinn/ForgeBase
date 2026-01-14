import Foundation
import Network
import XCTest
@testable import ForgeBase

final class ForgeBaseTests: XCTestCase {
    func testParseDottedDecimal_valid() {
        let ip = FBIPv4Parse.parseDottedDecimal("8.8.8.8")
        XCTAssertNotNil(ip)
        XCTAssertEqual(ip?.dottedDecimalString, "8.8.8.8")
    }

    func testParseDottedDecimal_invalidInputs() {
        let invalid = [
            "", "1.2.3", "256.0.0.1", "1.2.3.4.5", "a.b.c.d"
        ]
        for value in invalid {
            XCTAssertNil(
                FBIPv4Parse.parseDottedDecimal(Substring(value)),
                "Expected nil for \(value)"
            )
        }
    }

    func testParseCIDR_normalizesNetwork() {
        let parsed = FBIPv4Parse.parseCIDR("192.168.1.42/24")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.prefixLength, 24)
        XCTAssertEqual(
            FBIPv4(beValue: parsed!.networkBE).dottedDecimalString,
            "192.168.1.0"
        )
    }

    func testCIDRContainment() {
        guard let (networkBE, prefix) = FBIPv4Parse.parseCIDR("10.0.0.0/8") else {
            XCTFail("Failed to parse CIDR")
            return
        }

        let inside = FBIPv4(a: 10, b: 1, c: 2, d: 3).beValue
        let outside = FBIPv4(a: 11, b: 0, c: 0, d: 1).beValue

        XCTAssertTrue(
            FBIPv4CIDR.contains(
                addressBE: inside,
                networkBE: networkBE,
                prefixLength: prefix
            )
        )

        XCTAssertFalse(
            FBIPv4CIDR.contains(
                addressBE: outside,
                networkBE: networkBE,
                prefixLength: prefix
            )
        )
    }

    func testNetmaskEdges() {
        XCTAssertEqual(FBIPv4CIDR.netmaskBE(prefixLength: 0), 0)
        XCTAssertEqual(
            FBIPv4CIDR.netmaskBE(prefixLength: 32),
            UInt32.max
        )
        XCTAssertNil(FBIPv4CIDR.netmaskBE(prefixLength: -1))
        XCTAssertNil(FBIPv4CIDR.netmaskBE(prefixLength: 33))
    }

    func testPacketBufferLoadsAndSlices() {
        let bytes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05]
        let data = Data(bytes)
        let buf = FBDataPacketBuffer(data)

        XCTAssertEqual(buf.readableBytes, 5)
        XCTAssertEqual(buf.loadUInt8(at: 0), 0x01)
        XCTAssertEqual(buf.loadUInt16(at: 0), 0x0102)
        XCTAssertEqual(buf.loadUInt32(at: 0), 0x01020304)
        XCTAssertNil(buf.loadUInt32(at: 2))

        let slice = buf.slice(from: 1, length: 3) as? FBDataSlicePacketBuffer
        XCTAssertNotNil(slice)
        XCTAssertEqual(slice?.readableBytes, 3)
        XCTAssertEqual(slice?.loadUInt16(at: 0), 0x0203)
        XCTAssertEqual(slice?.materialize(), Data([0x02, 0x03, 0x04]))
    }

    func testPacketBufferWriter() {
        var writer = FBPacketBufferWriter()
        let offset = writer.reserve16() // placeholder
        writer.writeUInt8(0xAA)
        writer.writeUInt16(0x0102)
        writer.writeUInt32(0x0A0B0C0D)
        writer.fillUInt16(at: offset, value: 0xBEEF)

        let expected = Data([
            0xBE, 0xEF, // filled
            0xAA,
            0x01, 0x02,
            0x0A, 0x0B, 0x0C, 0x0D,
        ])
        XCTAssertEqual(writer.data, expected)
        XCTAssertEqual(writer.position, expected.count)
    }

    func testUDPIPv4BuildAndParse() {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let srcIP = IPv4Address("10.0.0.1")!
        let dstIP = IPv4Address("10.0.0.2")!

        let packet = FBUDPIPPacketBuilder.buildUDPIPv4(
            srcIP: srcIP,
            dstIP: dstIP,
            srcPort: 12345,
            dstPort: 80,
            payload: payload,
            ttl: 32
        )

        let buffer = FBDataPacketBuffer(packet)
        guard let ipView = FBIPPacketView(buffer: buffer) else {
            XCTFail("Failed to parse IPv4 packet")
            return
        }

        XCTAssertEqual(ipView.version, .iPv4)
        XCTAssertEqual(ipView.headerLength, 20)
        XCTAssertEqual(ipView.totalLength, packet.count)
        XCTAssertEqual(ipView.protocolNumber, .udp)
        XCTAssertFalse(ipView.fragmented)
        XCTAssertEqual(ipView.srcIP, srcIP)
        XCTAssertEqual(ipView.dstIP, dstIP)

        guard let udpView = FBUDPView(ip: ipView) else {
            XCTFail("Failed to parse UDP view")
            return
        }

        XCTAssertEqual(udpView.srcPort, 12345)
        XCTAssertEqual(udpView.dstPort, 80)
        XCTAssertEqual(udpView.payload.materialize(), payload)

        // Validate IPv4 header checksum (ones-complement sum should be 0xFFFF)
        let header = packet.prefix(20)
        var sum: UInt32 = 0
        for i in stride(from: 0, to: 20, by: 2) {
            sum &+= UInt32(header[i]) << 8 | UInt32(header[i + 1])
        }
        while (sum >> 16) != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        XCTAssertEqual(UInt16(~sum & 0xFFFF), 0)
    }
}
