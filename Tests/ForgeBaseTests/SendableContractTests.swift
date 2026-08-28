import Foundation
import Network
import XCTest

@testable import ForgeBase

private struct ForwardingPacketBuffer: FBPacketBuffer {
    let storage: FBDataPacketBuffer

    var readableBytes: Int { storage.readableBytes }

    func loadUInt8(at offset: Int) -> UInt8? {
        storage.loadUInt8(at: offset)
    }

    func loadUInt16(at offset: Int) -> UInt16? {
        storage.loadUInt16(at: offset)
    }

    func loadUInt32(at offset: Int) -> UInt32? {
        storage.loadUInt32(at: offset)
    }

    func slice(from offset: Int, length: Int) -> FBPacketBuffer? {
        storage.slice(from: offset, length: length)
    }

    func materialize() -> Data {
        storage.materialize()
    }
}

final class SendableContractTests: XCTestCase {
    private func requireSendable<T: Sendable>(_: T.Type) {}

    func testPublicPacketValuesAreSendable() {
        requireSendable((any FBPacketBuffer).self)
        requireSendable(FBDataPacketBuffer.self)
        requireSendable(FBDataSlicePacketBuffer.self)
        requireSendable(FBPacketBufferWriter.self)
        requireSendable(IPVersion.self)
        requireSendable(TransportProtocol.self)
        requireSendable(FBIPPacketView.self)
        requireSendable(FBUDPView.self)
    }

    func testCustomConformerOwnsMaterializationBehavior() async {
        let buffer: any FBPacketBuffer = ForwardingPacketBuffer(
            storage: FBDataPacketBuffer(Data([0x01, 0x02, 0x03]))
        )

        let materialized = await Task.detached {
            buffer.materialize()
        }.value

        XCTAssertEqual(materialized, Data([0x01, 0x02, 0x03]))
    }
}
