import Foundation
import Network
import XCTest

@testable import ForgeBase

final class PacketViewBoundaryTests: XCTestCase {
    func testIPViewRejectsEmptyTruncatedAndMalformedHeaders() {
        let valid = makePacket(payload: Data([0xAA]))

        XCTAssertNil(FBIPPacketView(buffer: FBDataPacketBuffer(Data())))
        XCTAssertNil(FBIPPacketView(buffer: FBDataPacketBuffer(Data(valid.prefix(19)))))
        XCTAssertNil(FBIPPacketView(buffer: FBDataPacketBuffer(Data(valid.dropLast()))))

        var unknownVersion = valid
        unknownVersion[0] = 0x55
        XCTAssertNil(FBIPPacketView(buffer: FBDataPacketBuffer(unknownVersion)))

        var ipv6 = valid
        ipv6[0] = 0x65
        XCTAssertNil(FBIPPacketView(buffer: FBDataPacketBuffer(ipv6)))

        var shortHeader = valid
        shortHeader[0] = 0x44
        XCTAssertNil(FBIPPacketView(buffer: FBDataPacketBuffer(shortHeader)))

        var unavailableOptions = Data(repeating: 0, count: 20)
        unavailableOptions[0] = 0x46
        XCTAssertNil(FBIPPacketView(buffer: FBDataPacketBuffer(unavailableOptions)))

        var totalShorterThanHeader = valid
        totalShorterThanHeader.setUInt16BE(19, at: 2)
        XCTAssertNil(FBIPPacketView(buffer: FBDataPacketBuffer(totalShorterThanHeader)))

        var totalLongerThanBuffer = valid
        totalLongerThanBuffer.setUInt16BE(UInt16(valid.count + 1), at: 2)
        XCTAssertNil(FBIPPacketView(buffer: FBDataPacketBuffer(totalLongerThanBuffer)))
    }

    func testIPViewParsesOptionsAndLocatesUDPPayload() {
        let payload = Data([0xDE, 0xAD])
        var packet = makePacket(payload: payload)
        packet.insert(contentsOf: [0x01, 0x01, 0x00, 0x00], at: 20)
        packet[0] = 0x46
        packet.setUInt16BE(UInt16(packet.count), at: 2)

        let ip = FBIPPacketView(buffer: FBDataPacketBuffer(packet))
        let udp = ip.flatMap(FBUDPView.init)

        XCTAssertEqual(ip?.headerLength, 24)
        XCTAssertEqual(ip?.payloadOffset, 24)
        XCTAssertEqual(ip?.payloadLength, 10)
        XCTAssertEqual(udp?.srcPort, 12_345)
        XCTAssertEqual(udp?.dstPort, 53)
        XCTAssertEqual(udp?.payload.materialize(), payload)
    }

    func testIPViewClassifiesTransportProtocols() {
        let expected: [(UInt8, TransportProtocol)] = [
            (1, .icmp),
            (6, .tcp),
            (17, .udp),
            (255, .other),
        ]

        for (rawValue, protocolNumber) in expected {
            var packet = makePacket()
            packet[9] = rawValue
            let view = FBIPPacketView(buffer: FBDataPacketBuffer(packet))
            XCTAssertEqual(view?.protocolNumber, protocolNumber)
        }
    }

    func testUDPViewRejectsFragmentsAndNonUDPProtocols() {
        var moreFragments = makePacket()
        moreFragments.setUInt16BE(0x2000, at: 6)
        let mfView = FBIPPacketView(buffer: FBDataPacketBuffer(moreFragments))
        XCTAssertEqual(mfView?.fragmented, true)
        XCTAssertNil(mfView.flatMap(FBUDPView.init))

        var fragmentOffset = makePacket()
        fragmentOffset.setUInt16BE(0x0001, at: 6)
        let offsetView = FBIPPacketView(buffer: FBDataPacketBuffer(fragmentOffset))
        XCTAssertEqual(offsetView?.fragmented, true)
        XCTAssertNil(offsetView.flatMap(FBUDPView.init))

        var tcp = makePacket()
        tcp[9] = 6
        let tcpView = FBIPPacketView(buffer: FBDataPacketBuffer(tcp))
        XCTAssertNil(tcpView.flatMap(FBUDPView.init))
    }

    func testUDPViewRejectsShortAndInconsistentLengths() {
        var noUDPHeader = makePacket()
        noUDPHeader.setUInt16BE(27, at: 2)
        let noHeaderView = FBIPPacketView(buffer: FBDataPacketBuffer(noUDPHeader))
        XCTAssertEqual(noHeaderView?.payloadLength, 7)
        XCTAssertNil(noHeaderView.flatMap(FBUDPView.init))

        var lengthBelowHeader = makePacket()
        lengthBelowHeader.setUInt16BE(7, at: 24)
        let belowHeaderView = FBIPPacketView(buffer: FBDataPacketBuffer(lengthBelowHeader))
        XCTAssertNil(belowHeaderView.flatMap(FBUDPView.init))

        var lengthBeyondIPPacket = makePacket()
        lengthBeyondIPPacket.setUInt16BE(0xFFFF, at: 24)
        let beyondView = FBIPPacketView(buffer: FBDataPacketBuffer(lengthBeyondIPPacket))
        XCTAssertNil(beyondView.flatMap(FBUDPView.init))
    }

    func testUDPViewAcceptsEmptyPayload() {
        let packet = makePacket(payload: Data())
        let ip = FBIPPacketView(buffer: FBDataPacketBuffer(packet))
        let udp = ip.flatMap(FBUDPView.init)

        XCTAssertEqual(ip?.totalLength, 28)
        XCTAssertEqual(udp?.payload.readableBytes, 0)
        XCTAssertEqual(udp?.payload.materialize(), Data())
    }

    private func makePacket(payload: Data = Data([0x01, 0x02])) -> Data {
        FBUDPIPPacketBuilder.buildUDPIPv4(
            srcIP: IPv4Address("192.0.2.1")!,
            dstIP: IPv4Address("198.51.100.2")!,
            srcPort: 12_345,
            dstPort: 53,
            payload: payload
        )
    }
}

extension Data {
    fileprivate mutating func setUInt16BE(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8((value >> 8) & 0xFF)
        self[offset + 1] = UInt8(value & 0xFF)
    }
}
