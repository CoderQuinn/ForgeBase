//
//  IPv4CIDR.swift
//  ForgeBase
//

/// IPv4 CIDR / prefix utilities.
/// All UInt32 values are NETWORK BYTE ORDER.
public enum FBIPv4CIDR {
    /// prefixLength → netmask (UInt32, network byte order)
    @inline(__always)
    public static func netmaskBE(prefixLength: Int) -> UInt32? {
        guard (0 ... 32).contains(prefixLength) else { return nil }
        guard prefixLength > 0 else { return 0 }
        return UInt32.max << (32 - prefixLength)
    }

    /// addressBE & maskBE → network base (UInt32BE)
    @inline(__always)
    public static func networkBaseBE(
        addressBE: UInt32,
        prefixLength: Int
    ) -> UInt32? {
        guard let mask = netmaskBE(prefixLength: prefixLength) else {
            return nil
        }
        return addressBE & mask
    }

    /// Check if address (UInt32BE) is inside CIDR
    @inline(__always)
    public static func contains(
        addressBE: UInt32,
        networkBE: UInt32,
        prefixLength: Int
    ) -> Bool {
        guard let mask = netmaskBE(prefixLength: prefixLength) else {
            return false
        }
        return (addressBE & mask) == networkBE
    }
}
