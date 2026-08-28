import Foundation
import XCTest

@testable import ForgeBase

final class ValueSemanticsTests: XCTestCase {
    private func requireHashable<T: Hashable>(_: T.Type) {}

    func testStableValueTypesAreHashable() {
        requireHashable(FBIPv4.self)
        requireHashable(FBDataPacketBuffer.self)
        requireHashable(FBDataSlicePacketBuffer.self)
        requireHashable(IPVersion.self)
        requireHashable(TransportProtocol.self)
        requireHashable(FBUDPIPPacketBuilderError.self)
    }

    func testWholeBuffersCompareAndHashByContent() {
        let first = FBDataPacketBuffer(Data([0x01, 0x02, 0x03]))
        let same = FBDataPacketBuffer(Data([0x01, 0x02, 0x03]))
        let different = FBDataPacketBuffer(Data([0x01, 0x02, 0x04]))

        XCTAssertEqual(first, same)
        XCTAssertNotEqual(first, different)
        XCTAssertEqual(Set([first, same, different]).count, 2)
    }

    func testSlicesIgnoreBackingLocationAndBytesOutsideReadableWindow() {
        let first = FBDataSlicePacketBuffer(
            data: Data([0xAA, 0x01, 0x02, 0xBB]),
            start: 1,
            length: 2
        )
        let same = FBDataSlicePacketBuffer(
            data: Data([0x01, 0x02]),
            start: 0,
            length: 2
        )
        let different = FBDataSlicePacketBuffer(
            data: Data([0xAA, 0x01, 0x03, 0xBB]),
            start: 1,
            length: 2
        )

        XCTAssertEqual(first, same)
        XCTAssertNotEqual(first, different)
        XCTAssertEqual(Set([first, same, different]).count, 2)
    }

    func testRepresentationNeutralComparisonIsExplicitlyMaterialized() {
        let whole = FBDataPacketBuffer(Data([0x01, 0x02]))
        let slice = FBDataSlicePacketBuffer(
            data: Data([0x00, 0x01, 0x02, 0x03]),
            start: 1,
            length: 2
        )

        XCTAssertEqual(whole.materialize(), slice.materialize())
    }
}
