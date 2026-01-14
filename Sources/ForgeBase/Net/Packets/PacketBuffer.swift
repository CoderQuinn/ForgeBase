//
//  PacketBuffer.swift
//  NetForge
//
//  Created by MagicianQuinn on 2025/12/19.
//

import Foundation

// MARK: - FBPacketBuffer

public protocol FBPacketBuffer {
    var readableBytes: Int { get }

    func loadUInt8(at offset: Int) -> UInt8?
    func loadUInt16(at offset: Int) -> UInt16?
    func loadUInt32(at offset: Int) -> UInt32?

    /// Returns a view (no copy if possible) of [offset, offset+length)
    func slice(from offset: Int, length: Int) -> FBPacketBuffer?
}

@inline(__always)
private func loadUnaligned<T>(
    _: T.Type,
    from data: Data,
    at offset: Int
) -> T {
    assert(offset >= 0 && offset + MemoryLayout<T>.size <= data.count)
    return data.withUnsafeBytes {
        $0.baseAddress!
            .advanced(by: offset)
            .loadUnaligned(as: T.self)
    }
}

/// Backing storage: whole Data
public struct FBDataPacketBuffer: FBPacketBuffer {
    public let data: Data
    public init(_ data: Data) { self.data = data }

    public var readableBytes: Int { data.count }

    public func loadUInt8(at offset: Int) -> UInt8? {
        guard offset >= 0, offset + 1 <= data.count else { return nil }
        return loadUnaligned(UInt8.self, from: data, at: offset)
    }

    public func loadUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        let v: UInt16 = loadUnaligned(UInt16.self, from: data, at: offset)
        return UInt16(bigEndian: v)
    }

    public func loadUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let v: UInt32 = loadUnaligned(UInt32.self, from: data, at: offset)
        return UInt32(bigEndian: v)
    }

    public func slice(from offset: Int, length: Int) -> FBPacketBuffer? {
        guard offset >= 0, length >= 0, offset + length <= data.count else { return nil }
        return FBDataSlicePacketBuffer(data: data, start: offset, length: length)
    }

    public func materialize() -> Data { data }
}

/// Backing storage: Data + range (real view, no subdata copy)
public struct FBDataSlicePacketBuffer: FBPacketBuffer {
    public let data: Data
    public let start: Int
    public let length: Int

    public init(data: Data, start: Int, length: Int) {
        self.data = data
        self.start = start
        self.length = length
    }

    public var readableBytes: Int { length }

    @inline(__always)
    private func absolute(_ offset: Int) -> Int { start + offset }

    public func loadUInt8(at offset: Int) -> UInt8? {
        guard offset >= 0, offset + 1 <= length else { return nil }
        let abs = absolute(offset)
        return loadUnaligned(UInt8.self, from: data, at: abs)
    }

    public func loadUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= length else { return nil }
        let abs = absolute(offset)
        let v: UInt16 = loadUnaligned(UInt16.self, from: data, at: abs)
        return UInt16(bigEndian: v)
    }

    public func loadUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= length else { return nil }
        let abs = absolute(offset)
        let v: UInt32 = loadUnaligned(UInt32.self, from: data, at: abs)
        return UInt32(bigEndian: v)
    }

    public func slice(from offset: Int, length: Int) -> FBPacketBuffer? {
        guard offset >= 0, length >= 0, offset + length <= self.length else { return nil }
        return FBDataSlicePacketBuffer(data: data, start: start + offset, length: length)
    }

    /// Materialize into a standalone Data (copy)
    public func materialize() -> Data {
        data.subdata(in: start ..< start + length)
    }
}

/// FBPacketBuffer is sealed to FBDataPacketBuffer / FBDataSlicePacketBuffer.
/// Adding new conforming types requires updating materialize().
public extension FBPacketBuffer {
    /// IO boundary only. One unavoidable copy.
    func materialize() -> Data {
        if let dataSlice = self as? FBDataSlicePacketBuffer {
            return dataSlice.materialize()
        }

        if let data = self as? FBDataPacketBuffer {
            return data.data
        }
        fatalError("Unknown FBPacketBuffer type")
    }
}

public struct FBPacketBufferWriter {
    public private(set) var data = Data()
    public private(set) var position: Int = 0

    public init() {}

    public mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
        position += 1
    }

    public mutating func writeUInt16(_ value: UInt16) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
        position += 2
    }

    public mutating func writeUInt32(_ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
        position += 4
    }

    public mutating func raw<T: Collection>(_ bytes: T) where T.Element == UInt8 {
        data.append(contentsOf: bytes)
        position += bytes.count
    }

    public mutating func raw(_ data: Data) {
        self.data.append(data)
        position += data.count
    }

    public mutating func pointer(to offset: Int) {
        precondition(offset <= 0x3FFF, "DNS pointer offset overflow")
        let ptr = UInt16(0xC000) | UInt16(offset)
        writeUInt16(ptr)
    }

    public mutating func reserve16() -> Int {
        let pos = position
        writeUInt16(0)
        return pos
    }

    public mutating func fillUInt16(at offset: Int, value: UInt16) {
        precondition(offset >= 0 && offset + 2 <= data.count, "Invalid offset for fillUInt16")
        data[offset] = UInt8((value >> 8) & 0xFF)
        data[offset + 1] = UInt8(value & 0xFF)
    }

    public mutating func name(_ name: String) {
        for label in name.split(separator: ".") {
            let bytes = label.utf8
            writeUInt8(UInt8(bytes.count))
            raw(bytes)
        }
        writeUInt8(0) // null terminator
    }
}
