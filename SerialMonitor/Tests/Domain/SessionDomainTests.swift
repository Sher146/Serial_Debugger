import XCTest
import SerialCore
@testable import SerialMonitor

final class SessionDomainTests: XCTestCase {
    func testHexEncoderAcceptsWhitespaceAndSeparators() throws {
        XCTAssertEqual(try HexCodec.decode("55 AA,01:00"), Data([0x55, 0xAA, 0x01, 0x00]))
        XCTAssertThrowsError(try HexCodec.decode("5"))
        XCTAssertThrowsError(try HexCodec.decode("ZZ"))
    }

    func testSendEncoderAppendsLineEndingWithoutChangingRawPayload() throws {
        let request = try SendPayloadEncoder.encode(text: "AT", format: .ascii, lineEnding: .crlf)
        XCTAssertEqual(request.payload, Data([0x41, 0x54, 0x0D, 0x0A]))
        XCTAssertEqual(TextPayloadCodec.decodeForDisplay(Data([0xFF])), "�")
    }

    func testStateMachineRejectsIllegalTransition() {
        var machine = SessionStateMachine()
        XCTAssertFalse(machine.transition(to: .connected(SerialConfiguration(path: "/dev/null"))))
        XCTAssertTrue(machine.transition(to: .opening(SerialConfiguration(path: "/dev/null"))))
        XCTAssertTrue(machine.transition(to: .connected(SerialConfiguration(path: "/dev/null"))))
        XCTAssertFalse(machine.transition(to: .disconnected))
    }

    func testRecordStoreTruncatesButPreservesCountersWhenCleared() async {
        let store = RecordStore(maximumRecords: 2, maximumBytes: 3)
        await store.append(CommunicationRecord(direction: .received, rawBytes: Data([1, 2]), displayFormat: .hex))
        await store.append(CommunicationRecord(direction: .transmitted, rawBytes: Data([3, 4]), displayFormat: .hex))

        let trimmed = await store.statistics()
        XCTAssertEqual(trimmed.recordCount, 1)
        XCTAssertEqual(trimmed.storedByteCount, 2)
        XCTAssertEqual(trimmed.receivedByteCount, 2)
        XCTAssertEqual(trimmed.transmittedByteCount, 2)
        XCTAssertEqual(trimmed.truncationCount, 1)

        await store.clear()
        let cleared = await store.statistics()
        XCTAssertEqual(cleared.recordCount, 0)
        XCTAssertEqual(cleared.storedByteCount, 0)
        XCTAssertEqual(cleared.receivedByteCount, 2)
        XCTAssertEqual(cleared.transmittedByteCount, 2)
    }

    func testSafeFileNameRemovesPathSeparators() {
        XCTAssertEqual(SafeFileName.sanitize(" ../诊断/日志:1 "), "..-诊断-日志-1")
    }
}
