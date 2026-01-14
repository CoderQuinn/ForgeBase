//
//  PacketView.swift
//  NetForge
//
//  Created by MagicianQuinn on 2025/12/19.
//

import ForgeBase
import Network

public enum IPVersion: UInt8 {
    case iPv4 = 4
    case iPv6 = 6
}

public enum TransportProtocol: UInt8 {
    case icmp = 1
    case tcp = 6
    case udp = 17
    case other
}

public struct FBIPPacketView {
    public let buffer: FBPacketBuffer

    public let version: IPVersion
    public let headerLength: Int
    public let totalLength: Int

    public let protocolNumber: TransportProtocol
    public let fragmented: Bool

    public let srcIP: IPv4Address
    public let dstIP: IPv4Address

    public let payloadOffset: Int
    public let payloadLength: Int

    public init?(buffer: FBPacketBuffer) {
        guard buffer.readableBytes >= 20 else { return nil }

        guard let vhl = buffer.loadUInt8(at: 0) else { return nil }
        guard let ver = IPVersion(rawValue: vhl >> 4) else { return nil }
        version = ver
        guard ver == .iPv4 else { return nil }

        let ihl = Int((vhl & 0x0F) * 4)
        guard ihl >= 20, buffer.readableBytes >= ihl else { return nil }
        headerLength = ihl

        guard let totalLen16 = buffer.loadUInt16(at: 2) else { return nil }
        let totalLen = Int(totalLen16)
        guard totalLen >= ihl, totalLen <= buffer.readableBytes else { return nil }
        totalLength = totalLen

        guard let flagsOffset = buffer.loadUInt16(at: 6) else { return nil }
        let mf = (flagsOffset & 0x2000) != 0
        let off = (flagsOffset & 0x1FFF)
        fragmented = mf || off != 0

        guard let protoRaw = buffer.loadUInt8(at: 9)
        else {
            return nil
        }
        let proto: TransportProtocol
        switch protoRaw {
        case 1: proto = .icmp
        case 6: proto = .tcp
        case 17: proto = .udp
        default: proto = .other
        }
        protocolNumber = proto

        guard let src = buffer.loadUInt32(at: 12),
              let dst = buffer.loadUInt32(at: 16),
              let srcAddr = FBIPv4(beValue: src).asNetworkIPv4Address,
              let dstAddr = FBIPv4(beValue: dst).asNetworkIPv4Address
        else {
            return nil
        }
        srcIP = srcAddr
        dstIP = dstAddr

        payloadOffset = ihl
        payloadLength = totalLen - ihl

        self.buffer = buffer
    }
}

public struct FBUDPView {
    public let srcPort: UInt16
    public let dstPort: UInt16
    public let payload: FBPacketBuffer

    public init?(ip: FBIPPacketView) {
        guard ip.protocolNumber == .udp else { return nil }
        guard !ip.fragmented else { return nil }
        guard ip.payloadLength >= 8 else { return nil }

        let base = ip.payloadOffset

        guard let sp = ip.buffer.loadUInt16(at: base),
              let dp = ip.buffer.loadUInt16(at: base + 2),
              let udpLen = ip.buffer.loadUInt16(at: base + 4)
        else {
            return nil
        }

        guard udpLen >= 8 else { return nil }

        let udpTotal = Int(udpLen)
        guard base + udpTotal <= ip.totalLength, udpTotal <= ip.totalLength else { return nil }

        guard let payloadBuf = ip.buffer.slice(from: base + 8, length: udpTotal - 8) else { return nil }

        srcPort = sp
        dstPort = dp
        payload = payloadBuf
    }
}
