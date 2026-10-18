import XCTest
import SerialCore
@testable import SerialMonitor

final class SessionCoordinatorTests: XCTestCase {
    func testFiftyInterleavedSendsRemainFIFO() async throws {
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial)
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))

        for value in 0..<50 {
            await coordinator.send(SendRequest(payload: Data([UInt8(value)]), displayFormat: .hex))
        }
        try await waitUntil { await serial.writes().count == 50 }
        let writes = await serial.writes()
        XCTAssertEqual(writes, (0..<50).map { Data([UInt8($0)]) })
    }

    func testDisconnectDuringOpeningCannotReconnectStaleAttempt() async throws {
        let serial = MockSerialPort()
        await serial.configure(openDelay: .milliseconds(80))
        let coordinator = SessionCoordinator(serialPort: serial)
        let task = Task { await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock")) }
        try await Task.sleep(for: .milliseconds(10))
        await coordinator.disconnect()
        _ = await task.value
        try await Task.sleep(for: .milliseconds(100))
        let state = await coordinator.currentState()
        XCTAssertEqual(state, .disconnected)
    }

    func testDeviceRemovalTransitionsToError() async throws {
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial)
        let configuration = SerialConfiguration(path: "/dev/cu.mock")
        await coordinator.connect(configuration: configuration)
        await serial.emitEvent(.deviceRemoved)
        try await waitUntil {
            if case .error = await coordinator.currentState() { return true }
            return false
        }

        await coordinator.connect(configuration: configuration)
        let recoveredState = await coordinator.currentState()
        XCTAssertEqual(recoveredState, .connected(configuration))
    }

    func testIncomingBytesCreateReceivedRecordAndUpdateStatistics() async throws {
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial)
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        await serial.emitIncoming(Data([0x52, 0x58]))

        try await waitUntil { await coordinator.recordsSnapshot().count == 1 }
        let records = await coordinator.recordsSnapshot()
        let statistics = await coordinator.statisticsSnapshot()
        XCTAssertEqual(records.first?.direction, .received)
        XCTAssertEqual(records.first?.rawBytes, Data([0x52, 0x58]))
        XCTAssertEqual(statistics.receivedByteCount, 2)
    }

    func testClearRecordsResetsTrafficCounters() async throws {
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial)
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        await coordinator.send(SendRequest(payload: Data([0x01, 0x02]), displayFormat: .hex))
        try await waitUntil { await coordinator.recordsSnapshot().count == 1 }

        await coordinator.clearRecords()
        let statistics = await coordinator.statisticsSnapshot()
        XCTAssertEqual(statistics.recordCount, 0)
        XCTAssertEqual(statistics.storedByteCount, 0)
        XCTAssertEqual(statistics.transmittedByteCount, 0)
    }

    func testUpdatingRecordLimitsTrimsExistingRecordsAndPublishesStatistics() async throws {
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial)
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        await serial.emitIncoming(Data([0x01]))
        await serial.emitIncoming(Data([0x02]))
        try await waitUntil { await coordinator.recordsSnapshot().count == 2 }

        await coordinator.updateRecordLimits(maximumRecords: 1, maximumBytes: 1024)

        let records = await coordinator.recordsSnapshot()
        let statistics = await coordinator.statisticsSnapshot()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.rawBytes, Data([0x02]))
        XCTAssertEqual(statistics.recordCount, 1)
    }

    func testEachSubscriberReceivesAnIndependentInitialSnapshot() async {
        let coordinator = SessionCoordinator(serialPort: MockSerialPort())
        var firstIterator = (await coordinator.subscribe()).makeAsyncIterator()
        var secondIterator = (await coordinator.subscribe()).makeAsyncIterator()

        let firstEvent = await firstIterator.next()
        let secondEvent = await secondIterator.next()
        XCTAssertEqual(firstEvent, .portsChanged([]))
        XCTAssertEqual(secondEvent, .portsChanged([]))
    }

    func testWriteTimeoutFailsSessionAndMarksRecord() async throws {
        let serial = MockSerialPort()
        await serial.configure(writeError: SerialError(category: .timeout, operation: "write", message: "deadline"))
        let coordinator = SessionCoordinator(serialPort: serial)
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        await coordinator.send(SendRequest(payload: Data([0x01]), displayFormat: .hex))
        try await waitUntil {
            if case .error = await coordinator.currentState() { return true }
            return false
        }
        let records = await coordinator.recordsSnapshot()
        XCTAssertEqual(records.last?.sendResult, .failed(.serial(SerialError(category: .timeout, operation: "write", message: "deadline"))))

        await serial.configure()
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        let recoveredState = await coordinator.currentState()
        XCTAssertEqual(recoveredState, .connected(SerialConfiguration(path: "/dev/cu.mock")))
    }

    func testFiniteAutoSendWaitsForEachCompletionAndStops() async throws {
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial)
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        let schedule = try AutoSendSchedule(
            request: SendRequest(payload: Data([0x41]), displayFormat: .ascii, source: .autoSend),
            intervalMilliseconds: 10,
            repetitionCount: 3
        )
        await coordinator.startAutoSend(schedule)

        try await waitUntil(timeout: .seconds(2)) { await serial.writes().count == 3 }
        try await waitUntil(timeout: .seconds(1)) { await coordinator.currentAutoSendStatus() == .inactive }
        let writes = await serial.writes()
        XCTAssertEqual(writes, [Data([0x41]), Data([0x41]), Data([0x41])])
    }

    func testCoordinatorLogsIncomingAndFinalizedOutgoingRecords() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("serial-monitor-coordinator-log-\(UUID().uuidString)", isDirectory: true)
        let logger = FileLogService()
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial, logService: logger)
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        await coordinator.startLogging(configuration: LogConfiguration(directory: directory, fileNamePrefix: "session"))
        await coordinator.send(SendRequest(payload: Data([0x41]), displayFormat: .ascii))
        try await waitUntil { await serial.writes().count == 1 }
        try await waitUntil {
            let records = await coordinator.recordsSnapshot()
            return records.last?.sendResult == .sent
        }
        await coordinator.stopLogging()

        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("\"direction\":\"TX\""))
        XCTAssertTrue(lines[0].contains("\"state\":\"sent\""))
    }

    func testStartingPresetLoopReplacesEditorLoop() async throws {
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial)
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        let editor = try AutoSendSchedule(
            request: SendRequest(payload: Data([0x41]), displayFormat: .hex, source: .autoSend),
            intervalMilliseconds: 1_000,
            repetitionCount: nil
        )
        await coordinator.startAutoSend(editor)
        try await waitUntil { await serial.writes().count == 1 }

        let preset = try AutoSendSchedule(
            request: SendRequest(payload: Data([0x42]), displayFormat: .hex, source: .preset),
            intervalMilliseconds: 10,
            repetitionCount: 1
        )
        await coordinator.startAutoSend(preset)

        try await waitUntil(timeout: .seconds(2)) { await coordinator.currentAutoSendStatus() == .inactive }
        try await waitUntil { await serial.writes().count == 2 }
        let writesAfterReplacement = await serial.writes()
        XCTAssertEqual(writesAfterReplacement.last, Data([0x42]))

        try await Task.sleep(for: .milliseconds(50))
        let settledWrites = await serial.writes()
        XCTAssertEqual(settledWrites.count, 2, "The replaced editor loop must not continue writing")
    }

    func testDisconnectStopsAutoSendLoop() async throws {
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial)
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        let schedule = try AutoSendSchedule(
            request: SendRequest(payload: Data([0x41]), displayFormat: .hex, source: .autoSend),
            intervalMilliseconds: 10,
            repetitionCount: nil
        )
        await coordinator.startAutoSend(schedule)
        try await waitUntil { await serial.writes().count >= 2 }

        await coordinator.disconnect()

        try await waitUntil { await coordinator.currentAutoSendStatus() == .inactive }
        let frozen = await serial.writes().count
        try await Task.sleep(for: .milliseconds(80))
        let afterDisconnect = await serial.writes().count
        XCTAssertEqual(afterDisconnect, frozen)
    }

    func testWriteFailureStopsAutoSendAndEntersError() async throws {
        let serial = MockSerialPort()
        await serial.configure(writeError: SerialError(category: .writeFailed, operation: "write", message: "boom"))
        let coordinator = SessionCoordinator(serialPort: serial)
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        let schedule = try AutoSendSchedule(
            request: SendRequest(payload: Data([0x41]), displayFormat: .hex, source: .autoSend),
            intervalMilliseconds: 10,
            repetitionCount: nil
        )
        await coordinator.startAutoSend(schedule)

        try await waitUntil {
            if case .error = await coordinator.currentState() { return true }
            return false
        }
        try await waitUntil { await coordinator.currentAutoSendStatus() == .inactive }
    }

    func testLoggingFailureIsIsolatedFromSession() async throws {
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial, logService: FailingLogService())
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        await coordinator.send(SendRequest(payload: Data([0x41]), displayFormat: .hex))
        try await waitUntil { await serial.writes().count == 1 }

        let isolatedState = await coordinator.currentState()
        XCTAssertEqual(isolatedState, .connected(SerialConfiguration(path: "/dev/cu.mock")))
        await serial.emitIncoming(Data([0x52]))
        try await waitUntil { await coordinator.recordsSnapshot().count == 2 }
    }

    func testShutdownStopsLoopAndDisconnects() async throws {
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial)
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        let schedule = try AutoSendSchedule(
            request: SendRequest(payload: Data([0x41]), displayFormat: .hex, source: .autoSend),
            intervalMilliseconds: 10,
            repetitionCount: nil
        )
        await coordinator.startAutoSend(schedule)
        try await waitUntil { await serial.writes().count >= 1 }

        await coordinator.shutdown()

        let shutdownState = await coordinator.currentState()
        let shutdownAutoSend = await coordinator.currentAutoSendStatus()
        XCTAssertEqual(shutdownState, .disconnected)
        XCTAssertEqual(shutdownAutoSend, .inactive)
    }

    func testPortMonitorPublishesWhenPortsChange() async throws {
        let serial = MockSerialPort()
        let coordinator = SessionCoordinator(serialPort: serial, portPollInterval: .milliseconds(20))
        await coordinator.refreshPorts()

        await serial.setPorts([SerialPortDescriptor(path: "/dev/cu.hotplugged")])

        try await waitUntil(timeout: .seconds(2)) {
            await coordinator.portsSnapshot().contains { $0.path == "/dev/cu.hotplugged" }
        }
        await coordinator.shutdown()
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private actor FailingLogService: LogServicing {
    func start(configuration: LogConfiguration) async {}
    func append(_ record: CommunicationRecord) async {}
    func stop() async {}
    func flushAndClose() async {}
    func currentStatus() async -> LogStatus { .failed("disk full") }
}
