import XCTest
import SerialCore
@testable import SerialMonitor

@MainActor
final class SessionViewModelTests: XCTestCase {
    func testEventProjectionSelectsFirstPortAndUpdatesStatistics() {
        let viewModel = SessionViewModel(client: SessionClientStub())
        let port = SerialPortDescriptor(path: "/dev/cu.mock")
        viewModel.consume(.portsChanged([port]))
        viewModel.consume(.statisticsChanged(RecordStatistics(
            recordCount: 2,
            storedByteCount: 12,
            receivedByteCount: 8,
            transmittedByteCount: 4,
            truncationCount: 0,
            lastTruncatedAt: nil
        )))

        XCTAssertEqual(viewModel.configuration.path, port.path)
        XCTAssertEqual(viewModel.statistics?.receivedByteCount, 8)
    }

    func testPausedDisplayBuffersRecordsUntilResume() {
        let viewModel = SessionViewModel(client: SessionClientStub())
        let first = CommunicationRecord(direction: .received, rawBytes: Data([0x01]), displayFormat: .hex)
        let second = CommunicationRecord(direction: .received, rawBytes: Data([0x02]), displayFormat: .hex)
        viewModel.consume(.recordsAppended([first]))
        viewModel.togglePause()
        viewModel.consume(.recordsAppended([second]))

        XCTAssertEqual(viewModel.visibleRecords.map(\.id), [first.id])
        viewModel.togglePause()
        XCTAssertEqual(viewModel.visibleRecords.map(\.id), [first.id, second.id])
    }

    func testHexDisplayUsesRawUTF8Bytes() {
        let viewModel = SessionViewModel(client: SessionClientStub())
        let record = CommunicationRecord(direction: .received, rawBytes: Data("é".utf8), displayFormat: .ascii)
        viewModel.receiveFormat = .hex
        viewModel.consume(.recordsAppended([record]))

        XCTAssertEqual(RecordFormatter.string(for: viewModel.visibleRecords[0], format: viewModel.receiveFormat), "C3 A9")
    }

    func testConnectionStateLocksParametersAndSendRequiresValidConnectedPayload() {
        let viewModel = SessionViewModel(client: SessionClientStub())
        viewModel.sendText = "0"
        viewModel.sendFormat = .hex
        viewModel.validateSendText()
        XCTAssertFalse(viewModel.canSend)
        XCTAssertNotNil(viewModel.sendValidationError)

        viewModel.consume(.stateChanged(.opening(SerialConfiguration(path: "/dev/cu.mock"))))
        XCTAssertTrue(viewModel.isConfigurationLocked)
        viewModel.consume(.stateChanged(.connected(SerialConfiguration(path: "/dev/cu.mock"))))
        viewModel.sendText = "0A"
        viewModel.validateSendText()

        XCTAssertTrue(viewModel.isConfigurationLocked)
        XCTAssertTrue(viewModel.canSend)
    }
}

private actor SessionClientStub: SessionClient {
    func subscribe() async -> AsyncStream<SessionEvent> {
        let pair = AsyncStream<SessionEvent>.makeStream()
        pair.continuation.finish()
        return pair.stream
    }

    func refreshPorts() async {}
    func connect(configuration: SerialConfiguration) async {}
    func disconnect() async {}
    func send(_ request: SendRequest) async {}
    func startAutoSend(_ schedule: AutoSendSchedule) async {}
    func stopAutoSend() async {}
    func clearRecords() async {}
    func startLogging(configuration: LogConfiguration) async {}
    func stopLogging() async {}
}
