//
//  PacketBuffer.swift
//  NetForge
//
//  Created by MagicianQuinn on 2025/12/19.
//

import Foundation

// MARK: - FBPacketBuffer

public protocol FBPacketBuffer: Sendable {
    var readableBytes: Int { get }

    func loadUInt8(at offset: Int) -> UInt8?
    func loadUInt16(at offset: Int) -> UInt16?
    func loadUInt32(at offset: Int) -> UInt32?

    /// Returns a view (no copy if possible) of [offset, offset+length)
    func slice(from offset: Int, length: Int) -> FBPacketBuffer?

    /// Returns an independently owned snapshot of the readable bytes.
    func materialize() -> Data
}

public enum FBPacketBufferWriterError: Error, Hashable, Sendable {
    case emptyDNSLabel
    case nonASCIIDNSLabel
    case dnsLabelTooLong(actual: Int, maximum: Int)
    case dnsNameTooLong(actual: Int, maximum: Int)
}

@inline(__always)
private func loadUnaligned<T>(
    _: T.Type,
    from data: Data,
    at offset: Int
) -> T {
    let width = MemoryLayout<T>.size
    assert(offset >= 0 && offset <= data.count && width <= data.count - offset)
    return data.withUnsafeBytes {
        $0.loadUnaligned(fromByteOffset: offset, as: T.self)
    }
}

/// Validates a half-open range without evaluating `offset + length`, which
/// could overflow for untrusted integer inputs.
@inline(__always)
private func hasValidPacketRange(offset: Int, length: Int, limit: Int) -> Bool {
    guard offset >= 0, length >= 0, offset <= limit else { return false }
    return length <= limit - offset
}

/// Backing storage: whole Data.
/// Equality and hashing use the readable byte content.
public struct FBDataPacketBuffer: FBPacketBuffer, Hashable {
    public let data: Data
    public init(_ data: Data) { self.data = data }

    public var readableBytes: Int { data.count }

    public func loadUInt8(at offset: Int) -> UInt8? {
        guard hasValidPacketRange(offset: offset, length: 1, limit: data.count) else { return nil }
        return loadUnaligned(UInt8.self, from: data, at: offset)
    }

    public func loadUInt16(at offset: Int) -> UInt16? {
        guard hasValidPacketRange(offset: offset, length: 2, limit: data.count) else { return nil }
        let v: UInt16 = loadUnaligned(UInt16.self, from: data, at: offset)
        return UInt16(bigEndian: v)
    }

    public func loadUInt32(at offset: Int) -> UInt32? {
        guard hasValidPacketRange(offset: offset, length: 4, limit: data.count) else { return nil }
        let v: UInt32 = loadUnaligned(UInt32.self, from: data, at: offset)
        return UInt32(bigEndian: v)
    }

    public func slice(from offset: Int, length: Int) -> FBPacketBuffer? {
        guard hasValidPacketRange(offset: offset, length: length, limit: data.count) else { return nil }
        return FBDataSlicePacketBuffer(data: data, start: offset, length: length)
    }

    public func materialize() -> Data { data }
}

/// Backing storage: Data + range (real view, no subdata copy).
/// Equality and hashing use only the logical readable window, not bytes outside
/// that window or the window's location in the backing storage.
public struct FBDataSlicePacketBuffer: FBPacketBuffer, Hashable {
    public let data: Data
    public let start: Int
    public let length: Int

    @inline(__always)
    static func hasValidRange(dataCount: Int, start: Int, length: Int) -> Bool {
        guard dataCount >= 0, start >= 0, length >= 0, start <= dataCount else {
            return false
        }
        return length <= dataCount - start
    }

    public init(data: Data, start: Int, length: Int) {
        precondition(
            Self.hasValidRange(dataCount: data.count, start: start, length: length),
            "Packet buffer slice is outside the backing Data"
        )
        self.data = data
        self.start = start
        self.length = length
    }

    public var readableBytes: Int { length }

    @inline(__always)
    private func absolute(_ offset: Int) -> Int { start + offset }

    public func loadUInt8(at offset: Int) -> UInt8? {
        guard hasValidPacketRange(offset: offset, length: 1, limit: length) else { return nil }
        let abs = absolute(offset)
        return loadUnaligned(UInt8.self, from: data, at: abs)
    }

    public func loadUInt16(at offset: Int) -> UInt16? {
        guard hasValidPacketRange(offset: offset, length: 2, limit: length) else { return nil }
        let abs = absolute(offset)
        let v: UInt16 = loadUnaligned(UInt16.self, from: data, at: abs)
        return UInt16(bigEndian: v)
    }

    public func loadUInt32(at offset: Int) -> UInt32? {
        guard hasValidPacketRange(offset: offset, length: 4, limit: length) else { return nil }
        let abs = absolute(offset)
        let v: UInt32 = loadUnaligned(UInt32.self, from: data, at: abs)
        return UInt32(bigEndian: v)
    }

    public func slice(from offset: Int, length: Int) -> FBPacketBuffer? {
        guard hasValidPacketRange(offset: offset, length: length, limit: self.length) else { return nil }
        return FBDataSlicePacketBuffer(data: data, start: start + offset, length: length)
    }

    /// Materialize into a standalone Data (copy)
    public func materialize() -> Data {
        let lowerBound = data.index(data.startIndex, offsetBy: start)
        let upperBound = data.index(lowerBound, offsetBy: length)
        return data.subdata(in: lowerBound..<upperBound)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.length == rhs.length else { return false }
        return lhs.materialize() == rhs.materialize()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(materialize())
    }
}

public struct FBPacketBufferWriter: Sendable {
    public private(set) var data: Data
    public private(set) var position: Int = 0

    /// capacity: optional preallocation hint
    public init(capacity: Int = 0) {
        self.data = Data()
        if capacity > 0 {
            self.data.reserveCapacity(capacity)
        }
    }

    @inline(__always)
    public mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
        position += 1
    }

    @inline(__always)
    public mutating func writeUInt16(_ value: UInt16) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
        position += 2
    }

    @inline(__always)
    public mutating func writeUInt32(_ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
        position += 4
    }

    @inline(__always)
    public mutating func raw<T: Collection>(_ bytes: T) where T.Element == UInt8 {
        data.append(contentsOf: bytes)
        position += bytes.count
    }

    @inline(__always)
    public mutating func raw(_ other: Data) {
        data.append(other)
        position += other.count
    }

    @inline(__always)
    public mutating func pointer(to offset: Int) {
        precondition(offset >= 0 && offset <= 0x3FFF, "DNS pointer offset overflow")
        let ptr = UInt16(0xC000) | UInt16(offset)
        writeUInt16(ptr)
    }

    /// Reserve 2 bytes and return offset for later fill
    @inline(__always)
    public mutating func reserve16() -> Int {
        let pos = position
        writeUInt16(0)
        return pos
    }

    @inline(__always)
    public mutating func fillUInt16(at offset: Int, value: UInt16) {
        precondition(
            hasValidPacketRange(offset: offset, length: 2, limit: data.count),
            "Invalid offset for fillUInt16"
        )
        data[offset] = UInt8((value >> 8) & 0xFF)
        data[offset + 1] = UInt8(value & 0xFF)
    }

    /// Writes one DNS QNAME in RFC 1035 wire format.
    ///
    /// The empty string and `.` both encode the root name. A single trailing
    /// dot is accepted for an absolute name. Other empty labels, non-ASCII
    /// presentation bytes, labels longer than 63 bytes, and names whose wire
    /// encoding exceeds 255 bytes are rejected without mutating the writer.
    public mutating func writeDNSName(_ name: String) throws {
        if name.isEmpty || name == "." {
            writeUInt8(0)
            return
        }

        let absolute = name.last == "."
        let presentation = absolute ? String(name.dropLast()) : name
        let labels = presentation.split(
            separator: ".",
            omittingEmptySubsequences: false
        )

        var encoded = Data()
        encoded.reserveCapacity(255)

        for label in labels {
            guard !label.isEmpty else {
                throw FBPacketBufferWriterError.emptyDNSLabel
            }

            let bytes = Array(label.utf8)
            guard bytes.allSatisfy({ $0 < 0x80 }) else {
                throw FBPacketBufferWriterError.nonASCIIDNSLabel
            }
            guard bytes.count <= 63 else {
                throw FBPacketBufferWriterError.dnsLabelTooLong(
                    actual: bytes.count,
                    maximum: 63
                )
            }

            encoded.append(UInt8(bytes.count))
            encoded.append(contentsOf: bytes)
        }
        encoded.append(0)

        guard encoded.count <= 255 else {
            throw FBPacketBufferWriterError.dnsNameTooLong(
                actual: encoded.count,
                maximum: 255
            )
        }

        raw(encoded)
    }

    /// Compatibility entry point for existing packet builders.
    ///
    /// Returns `false` and leaves the writer unchanged when the presentation
    /// name cannot be encoded as a valid DNS QNAME.
    @discardableResult
    public mutating func name(_ name: String) -> Bool {
        do {
            try writeDNSName(name)
            return true
        } catch {
            return false
        }
    }
}
