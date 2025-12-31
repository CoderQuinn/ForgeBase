//
//  IPv4Types.swift
//  ForgeBase
//

/// IPv4 value type.
/// Convention:
/// - `beValue` is ALWAYS network byte order (big-endian)
/// - Host byte order MUST NOT appear in public APIs
public struct FBIPv4: Equatable, Hashable, Sendable {

    /// Network byte order (big-endian)
    public let beValue: UInt32

    @inline(__always)
    public init(beValue: UInt32) {
        self.beValue = beValue
    }

    @inline(__always)
    public init(a: UInt8, b: UInt8, c: UInt8, d: UInt8) {
        self.beValue =
            UInt32(a) << 24 |
            UInt32(b) << 16 |
            UInt32(c) << 8  |
            UInt32(d)
    }
}

public extension FBIPv4 {

    /// Dotted-decimal string, e.g. "8.8.8.8"
    var dottedDecimalString: String {
        let a = (beValue >> 24) & 0xFF
        let b = (beValue >> 16) & 0xFF
        let c = (beValue >> 8) & 0xFF
        let d = beValue & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
}
