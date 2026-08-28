//
//  UDPIPPacketBuilder.swift
//  NetForge
//
//  Created by MagicianQuinn on 2025/12/26.
//

import Foundation
import Network

public enum FBUDPIPPacketBuilderError: Error, Equatable, Sendable {
    case payloadTooLarge(actual: Int, maximum: Int)
    case udpChecksumUnsupported
}

public enum FBUDPIPPacketBuilder {
    /// Maximum payload that fits in one IPv4 packet with 20-byte IPv4 and
    /// 8-byte UDP headers.
    public static let maximumIPv4UDPPayloadLength = Int(UInt16.max) - 20 - 8

    /// Builds one unfragmented UDP/IPv4 packet.
    ///
    /// - Throws: `FBUDPIPPacketBuilderError.payloadTooLarge` when the payload
    ///   cannot fit in one IPv4 packet, or `.udpChecksumUnsupported` when UDP
    ///   checksum generation is requested.
    public static func buildUDPIPv4(
        srcIP: IPv4Address,
        dstIP: IPv4Address,
        srcPort: UInt16,
        dstPort: UInt16,
        payload: Data,
        ttl: UInt8 = 64,
        udpChecksumEnabled: Bool = false
    ) throws -> Data {
        guard payload.count <= maximumIPv4UDPPayloadLength else {
            throw FBUDPIPPacketBuilderError.payloadTooLarge(
                actual: payload.count,
                maximum: maximumIPv4UDPPayloadLength
            )
        }
        guard !udpChecksumEnabled else {
            throw FBUDPIPPacketBuilderError.udpChecksumUnsupported
        }

        // ---- UDP header (8 bytes) ----
        // srcPort(2) dstPort(2) length(2) checksum(2)
        let udpLen = UInt16(8 + payload.count)

        var udp = Data()
        udp.reserveCapacity(Int(udpLen))

        udp.appendUInt16BE(srcPort)
        udp.appendUInt16BE(dstPort)
        udp.appendUInt16BE(udpLen)

        // A zero UDP checksum is valid for IPv4.
        udp.appendUInt16BE(0)

        udp.append(payload)

        // ---- IPv4 header (20 bytes, no options) ----
        let totalLen = UInt16(20 + udp.count)

        var ip = Data()
        ip.reserveCapacity(20 + udp.count)

        // Version(4) + IHL(4) => 0x45
        ip.append(0x45)
        // DSCP/ECN
        ip.append(0)

        ip.appendUInt16BE(totalLen)

        // Identification
        ip.appendUInt16BE(0)
        // Flags/Fragment offset
        ip.appendUInt16BE(0)

        // TTL
        ip.append(ttl)
        // Protocol UDP = 17
        ip.append(17)

        // Header checksum (placeholder)
        ip.appendUInt16BE(0)

        // src/dst IP
        ip.append(srcIP.rawValue)
        ip.append(dstIP.rawValue)

        // Compute IPv4 header checksum
        let csum = ipv4HeaderChecksum(ipHeader20: ip)
        ip.replaceSubrange(10..<12, with: [UInt8(csum >> 8), UInt8(csum & 0xFF)])

        // payload
        ip.append(udp)
        return ip
    }

    // MARK: - IPv4 checksum

    private static func ipv4HeaderChecksum(ipHeader20: Data) -> UInt16 {
        precondition(ipHeader20.count >= 20)

        var sum: UInt32 = 0
        // 20 bytes header, checksum field assumed already 0 when summing
        for i in stride(from: 0, to: 20, by: 2) {
            let hi = UInt16(ipHeader20[i])
            let lo = UInt16(ipHeader20[i + 1])
            sum += UInt32((hi << 8) | lo)
        }

        // fold
        while (sum >> 16) != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }

        return ~UInt16(sum & 0xFFFF)
    }
}

// MARK: - Data helpers

extension Data {
    fileprivate mutating func appendUInt16BE(_ v: UInt16) {
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8(v & 0xFF))
    }
}
