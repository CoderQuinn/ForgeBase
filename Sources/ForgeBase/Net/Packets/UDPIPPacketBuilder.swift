//
//  UDPIPPacketBuilder.swift
//  NetForge
//
//  Created by MagicianQuinn on 2025/12/26.
//

import Foundation
import Network

public enum FBUDPIPPacketBuilderError: Error, Hashable, Sendable {
    case invalidPayloadLength(actual: Int)
    case payloadLengthMismatch(declared: Int, actual: Int)
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
        try buildUDPIPv4(
            srcIP: srcIP, dstIP: dstIP, srcPort: srcPort, dstPort: dstPort,
            payloadBuffer: FBDataPacketBuffer(payload), ttl: ttl, udpChecksumEnabled: udpChecksumEnabled
        )
    }

    /// Builds from the buffer's logical window without first materializing it.
    /// Legacy conformers may materialize in the default scoped-byte fallback.
    /// The result owns a copy of the payload; no borrowed pointer escapes.
    /// Validation order is declared length, checksum support, then borrowed length.
    public static func buildUDPIPv4(
        srcIP: IPv4Address,
        dstIP: IPv4Address,
        srcPort: UInt16,
        dstPort: UInt16,
        payloadBuffer: FBPacketBuffer,
        ttl: UInt8 = 64,
        udpChecksumEnabled: Bool = false
    ) throws -> Data {
        let length = payloadBuffer.readableBytes
        guard length >= 0 else {
            throw FBUDPIPPacketBuilderError.invalidPayloadLength(actual: length)
        }
        guard length <= maximumIPv4UDPPayloadLength else {
            throw FBUDPIPPacketBuilderError.payloadTooLarge(
                actual: length,
                maximum: maximumIPv4UDPPayloadLength
            )
        }
        guard !udpChecksumEnabled else {
            throw FBUDPIPPacketBuilderError.udpChecksumUnsupported
        }
        return try payloadBuffer.withUnsafeReadableBytes { payload in
            guard payload.count == length else {
                throw FBUDPIPPacketBuilderError.payloadLengthMismatch(declared: length, actual: payload.count)
            }
            return assembleUDPIPv4(
                srcIP: srcIP, dstIP: dstIP, srcPort: srcPort, dstPort: dstPort, payload: payload, ttl: ttl
            )
        }
    }

    private static func assembleUDPIPv4(
        srcIP: IPv4Address,
        dstIP: IPv4Address,
        srcPort: UInt16,
        dstPort: UInt16,
        payload: UnsafeRawBufferPointer,
        ttl: UInt8
    ) -> Data {
        // Lengths were validated before entering the borrow. Write into one
        // final-sized owned buffer; only the payload copy crosses ownership.
        let udpLen = UInt16(8 + payload.count)
        let totalLen = 20 + Int(udpLen)
        var packet = Data(count: totalLen)
        packet.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            // Zero initialization supplies DSCP, ID, flags and checksum fields.
            bytes[0] = 0x45
            writeUInt16BE(UInt16(totalLen), into: bytes, at: 2)
            bytes[8] = ttl
            bytes[9] = 17
            srcIP.rawValue.withUnsafeBytes {
                UnsafeMutableRawBufferPointer(rebasing: bytes[12..<16]).copyMemory(from: $0)
            }
            dstIP.rawValue.withUnsafeBytes {
                UnsafeMutableRawBufferPointer(rebasing: bytes[16..<20]).copyMemory(from: $0)
            }
            let checksum = ipv4HeaderChecksum(ipHeader20: UnsafeRawBufferPointer(rebasing: bytes[..<20]))
            writeUInt16BE(checksum, into: bytes, at: 10)
            writeUInt16BE(srcPort, into: bytes, at: 20)
            writeUInt16BE(dstPort, into: bytes, at: 22)
            writeUInt16BE(udpLen, into: bytes, at: 24)
            // A zero UDP checksum is valid for IPv4. Empty buffers are valid.
            UnsafeMutableRawBufferPointer(rebasing: bytes[28...]).copyMemory(from: payload)
        }
        return packet
    }

    // MARK: - IPv4 checksum

    private static func ipv4HeaderChecksum(ipHeader20: UnsafeRawBufferPointer) -> UInt16 {
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
    private static func writeUInt16BE(_ value: UInt16, into bytes: UnsafeMutableRawBufferPointer, at offset: Int) {
        bytes[offset] = UInt8(value >> 8)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }
}
