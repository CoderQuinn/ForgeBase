//
//  IPv4+Network.swift
//  ForgeBase
//
//  Created by MagicianQuinn on 2025/12/31.
//

import Network
import Foundation

import Network
import Foundation

public extension FBIPv4 {

    @inline(__always)
    init(_ address: IPv4Address) {
        let bytes = address.rawValue
        precondition(bytes.count == 4, "Invalid IPv4Address rawValue length")
        self.init(
            a: bytes[0],
            b: bytes[1],
            c: bytes[2],
            d: bytes[3]
        )
    }

    @inline(__always)
    var asNetworkIPv4Address: IPv4Address? {
        let data = Data([
            UInt8((beValue >> 24) & 0xFF),
            UInt8((beValue >> 16) & 0xFF),
            UInt8((beValue >> 8) & 0xFF),
            UInt8(beValue & 0xFF),
        ])
        return IPv4Address(data)
    }
}

public extension FBIPv4CIDR {

    /// Network.framework convenience wrapper
    @inline(__always)
    static func contains(
        address: IPv4Address,
        networkBE: UInt32,
        prefixLength: Int
    ) -> Bool {
        let fb = FBIPv4(address)
        return contains(
            addressBE: fb.beValue,
            networkBE: networkBE,
            prefixLength: prefixLength
        )
    }
}
