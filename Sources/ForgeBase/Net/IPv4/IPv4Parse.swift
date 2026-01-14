//
//  IPv4Parse.swift
//  ForgeBase
//

import Foundation

/// IPv4 parsing utilities (no Network.framework dependency).
/// Convention:
/// - All UInt32 values are NETWORK BYTE ORDER (big-endian)
public enum FBIPv4Parse {
    // MARK: - Dotted decimal parsing

    /// Parse dotted-decimal IPv4 string, e.g. "192.168.1.1"
    /// Strict rules:
    /// - Exactly 4 octets
    /// - Each octet: 0...255
    /// - Decimal only (no hex / octal)
    public static func parseDottedDecimal(
        _ s: Substring
    ) -> FBIPv4? {
        var octets: [UInt8] = []
        octets.reserveCapacity(4)

        var current = 0
        var hasDigit = false

        for ch in s.utf8 {
            if ch >= 48, ch <= 57 { // '0'...'9'
                hasDigit = true
                current = current * 10 + Int(ch - 48)
                if current > 255 { return nil }
            } else if ch == 46 { // '.'
                guard hasDigit else { return nil }
                octets.append(UInt8(current))
                if octets.count > 3 { return nil }
                current = 0
                hasDigit = false
            } else {
                return nil
            }
        }

        guard hasDigit else { return nil }
        octets.append(UInt8(current))
        guard octets.count == 4 else { return nil }

        return FBIPv4(
            a: octets[0],
            b: octets[1],
            c: octets[2],
            d: octets[3]
        )
    }

    // MARK: - CIDR parsing

    /// Parse CIDR string, e.g. "192.168.1.0/24"
    ///
    /// Returns:
    /// - networkBE: UInt32 (network byte order)
    /// - prefixLength: Int
    ///
    /// Note:
    /// - The returned networkBE is already normalized
    ///   (address & netmask).
    public static func parseCIDR(
        _ cidr: String
    ) -> (networkBE: UInt32, prefixLength: Int)? {
        let trimmed = cidr.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(
            separator: "/",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )

        guard parts.count == 2 else { return nil }

        let ipPart = parts[0]
        let prefixPart = parts[1]

        guard let prefixLength = Int(prefixPart),
              (0 ... 32).contains(prefixLength)
        else {
            return nil
        }

        guard let ip = parseDottedDecimal(ipPart) else {
            return nil
        }

        guard let networkBE = FBIPv4CIDR.networkBaseBE(
            addressBE: ip.beValue,
            prefixLength: prefixLength
        ) else {
            return nil
        }

        return (networkBE, prefixLength)
    }

    /// Convenience: parse CIDR to dotted-decimal strings
    /// e.g. "192.168.1.0/24" -> ("192.168.1.0", "255.255.255.0")
    public static func parseCIDRToStrings(
        _ cidr: String
    ) -> (ip: String, mask: String)? {
        guard let parsed = parseCIDR(cidr),
              let maskBE = FBIPv4CIDR.netmaskBE(
                  prefixLength: parsed.prefixLength
              )
        else {
            return nil
        }

        let ip = FBIPv4(beValue: parsed.networkBE).dottedDecimalString
        let mask = FBIPv4(beValue: maskBE).dottedDecimalString
        return (ip, mask)
    }
}
