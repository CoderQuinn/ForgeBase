import Foundation
import Network
import XCTest

@testable import ForgeBase

final class IPv4BoundaryTests: XCTestCase {
    func testDottedDecimalOctetBoundariesAndByteOrder() {
        let zero = FBIPv4Parse.parseDottedDecimal("0.0.0.0")
        let maximum = FBIPv4Parse.parseDottedDecimal("255.255.255.255")
        let ordered = FBIPv4Parse.parseDottedDecimal("1.2.3.4")

        XCTAssertEqual(zero?.beValue, 0x0000_0000)
        XCTAssertEqual(maximum?.beValue, 0xFFFF_FFFF)
        XCTAssertEqual(ordered?.beValue, 0x0102_0304)
        XCTAssertEqual(ordered?.dottedDecimalString, "1.2.3.4")
    }

    func testDottedDecimalRejectsEmptyOctetsAndOverflow() {
        let invalid = [
            ".1.2.3",
            "1..2.3",
            "1.2.3.",
            "1.2.3.4.",
            "1.2.3.256",
            "999999999999999999999.0.0.1",
            "1.2.3.-1",
            "1.2.3.4\n",
        ]

        for input in invalid {
            XCTAssertNil(
                FBIPv4Parse.parseDottedDecimal(Substring(input)),
                "Expected invalid IPv4 input: \(input)"
            )
        }
    }

    func testCIDRParsingCoversZeroHostAndPrefixBoundaries() {
        let allAddresses = FBIPv4Parse.parseCIDR(" 203.0.113.7/0\n")
        let singleAddress = FBIPv4Parse.parseCIDR("203.0.113.7/32")
        let strings = FBIPv4Parse.parseCIDRToStrings("192.168.50.199/24")

        XCTAssertEqual(allAddresses?.networkBE, 0)
        XCTAssertEqual(allAddresses?.prefixLength, 0)
        XCTAssertEqual(singleAddress?.networkBE, 0xCB00_7107)
        XCTAssertEqual(singleAddress?.prefixLength, 32)
        XCTAssertEqual(strings?.ip, "192.168.50.0")
        XCTAssertEqual(strings?.mask, "255.255.255.0")
    }

    func testCIDRParsingRejectsMalformedAndOverflowingPrefixes() {
        let invalid = [
            "203.0.113.7",
            "203.0.113.7/",
            "/24",
            "203.0.113.7/-1",
            "203.0.113.7/33",
            "203.0.113.7/999999999999999999999",
            "999.0.0.1/24",
            "203.0.113.7/24/extra",
        ]

        for input in invalid {
            XCTAssertNil(FBIPv4Parse.parseCIDR(input), "Expected invalid CIDR: \(input)")
            XCTAssertNil(
                FBIPv4Parse.parseCIDRToStrings(input),
                "Expected invalid CIDR strings input: \(input)"
            )
        }
    }

    func testCIDRUtilitiesHandleInvalidPrefixesAndNetworkFrameworkBridge() {
        let address = IPv4Address("10.20.30.40")!
        let network = FBIPv4(a: 10, b: 0, c: 0, d: 0).beValue

        XCTAssertNil(
            FBIPv4CIDR.networkBaseBE(
                addressBE: FBIPv4(address).beValue,
                prefixLength: 33
            )
        )
        XCTAssertFalse(
            FBIPv4CIDR.contains(
                addressBE: FBIPv4(address).beValue,
                networkBE: network,
                prefixLength: -1
            )
        )
        XCTAssertTrue(
            FBIPv4CIDR.contains(
                address: address,
                networkBE: network,
                prefixLength: 8
            )
        )
    }

    func testNetworkFrameworkRoundTripPreservesOctets() {
        let networkAddress = IPv4Address("198.51.100.42")!
        let value = FBIPv4(networkAddress)

        XCTAssertEqual(value.beValue, 0xC633_642A)
        XCTAssertEqual(value.dottedDecimalString, "198.51.100.42")
        XCTAssertEqual(value.asNetworkIPv4Address, networkAddress)
        XCTAssertEqual(Array(value.asNetworkIPv4Address!.rawValue), [198, 51, 100, 42])
    }
}
