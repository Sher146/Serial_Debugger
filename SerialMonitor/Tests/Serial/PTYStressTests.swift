import Darwin
import Foundation
import XCTest
@testable import SerialMonitor
@testable import SerialCore

/// Opt-in long-running test. `run-automated-tests.zsh --stress` supplies the
/// compile-time switch; normal local test runs exclude this class.
final class PTYStressTests: XCTestCase {
    func testSustains115200bpsForConfiguredDuration() async throws {
        let durationSeconds: Int
        #if PTY_STRESS
        durationSeconds = 1_800
        #elseif PTY_STRESS_SMOKE
        durationSeconds = 2
        #else
        throw XCTSkip("Run Scripts/run-automated-tests.zsh --stress to enable the PTY stress test")
        #endif

        let terminal = try PseudoTerminal()
        let adapter = POSIXSerialPortAdapter()
        defer {
            terminal.closeMaster()
            terminal.closeSlave()
        }

        let coordinator = SessionCoordinator(serialPort: adapter)
        await coordinator.connect(configuration: SerialConfiguration(path: terminal.slavePath, baudRate: 115_200))
        try await Task.sleep(for: .milliseconds(25))

        // 1,024 bytes every 88 ms is approximately 116 kbit/s including serial framing.
        let payload = Data(repeating: 0x55, count: 1_024)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(durationSeconds))
        var sentByteCount = 0

        while clock.now < deadline {
            let written = payload.withUnsafeBytes { buffer in
                Darwin.write(terminal.master, buffer.baseAddress, payload.count)
            }
            guard written == payload.count else {
                XCTFail("PTY writer only accepted \(written) of \(payload.count) bytes")
                break
            }
            sentByteCount += written
            try await Task.sleep(for: .milliseconds(88))
        }

        let expectedByteCount = sentByteCount
        try await waitUntil(timeout: .seconds(10)) {
            await coordinator.statisticsSnapshot().receivedByteCount == expectedByteCount
        }
        let statistics = await coordinator.statisticsSnapshot()
        XCTAssertEqual(statistics.receivedByteCount, expectedByteCount)
        XCTAssertLessThanOrEqual(statistics.storedByteCount, RecordStore.defaultMaximumBytes)
        if expectedByteCount > RecordStore.defaultMaximumBytes {
            XCTAssertGreaterThan(statistics.truncationCount, 0)
        }
        await coordinator.disconnect()
    }

    private func waitUntil(
        timeout: Duration,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for PTY receiver to drain")
    }
}
