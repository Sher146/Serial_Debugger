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
        await coordinator.connect(configuration: SerialConfiguration(path: "/dev/cu.mock"))
        await serial.emitEvent(.deviceRemoved)
        try await waitUntil {
            if case .error = await coordinator.currentState() { return true }
            return false
        }
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
