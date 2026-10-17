import Foundation
import SerialCore

actor SessionPreviewClient: SessionClient {
    private let initialEvents: [SessionEvent]

    init(state: SessionState, records: [CommunicationRecord] = []) {
        let configuration = state.configuration ?? SerialConfiguration(path: "/dev/cu.usbserial-demo")
        initialEvents = [
            .portsChanged([SerialPortDescriptor(path: configuration.path, displayName: "演示串口")]),
            .stateChanged(state),
            .recordsAppended(records),
            .statisticsChanged(RecordStatistics(
                recordCount: records.count,
                storedByteCount: records.reduce(0) { $0 + $1.rawBytes.count },
                receivedByteCount: records.filter { $0.direction == .received }.reduce(0) { $0 + $1.rawBytes.count },
                transmittedByteCount: records.filter { $0.direction == .transmitted }.reduce(0) { $0 + $1.rawBytes.count },
                truncationCount: 0,
                lastTruncatedAt: nil
            )),
            .logStatusChanged(.inactive),
            .autoSendStatusChanged(.inactive),
            .latestErrorChanged(nil)
        ]
    }

    func subscribe() async -> AsyncStream<SessionEvent> {
        let pair = AsyncStream<SessionEvent>.makeStream()
        for event in initialEvents {
            pair.continuation.yield(event)
        }
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
    func updateRecordLimits(maximumRecords: Int, maximumBytes: Int) async {}
    func startLogging(configuration: LogConfiguration) async {}
    func stopLogging() async {}
}

/// Only selected by an explicit UI-test launch argument. Production launches always
/// create `SessionCoordinator` with the POSIX adapter in `SerialMonitorApp`.
enum SessionUITestScenario: String, Sendable {
    case echo
    case opening
    case writeFailure = "write-failure"
    case deviceRemoval = "device-removal"
    case burst
    case autoSendLoop = "auto-send"

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-ui-testing-scenario"),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }
        self.init(rawValue: arguments[arguments.index(after: index)])
    }
}

/// Deterministic serial-session substitute for XCUITest. It intentionally mirrors
/// the `SessionClient` event contract instead of exposing test-only UI controls.
actor SessionScenarioClient: SessionClient {
    private let scenario: SessionUITestScenario
    private let eventHub = SessionEventHub()
    private let ports = [SerialPortDescriptor(path: "/dev/cu.ui-test", displayName: "cu.Bluetooth-Incoming-Port")]
    private var state: SessionState = .disconnected
    private var records: [CommunicationRecord] = []
    private var receivedByteCount = 0
    private var transmittedByteCount = 0
    private var latestError: SessionError?
    private var attemptID = UUID()

    init(scenario: SessionUITestScenario) {
        self.scenario = scenario
    }

    func subscribe() async -> AsyncStream<SessionEvent> {
        await eventHub.subscribe(initialEvents: [
            .portsChanged(ports),
            .stateChanged(state),
            .statisticsChanged(statistics),
            .logStatusChanged(.inactive),
            .autoSendStatusChanged(.inactive),
            .latestErrorChanged(latestError)
        ])
    }

    func refreshPorts() async {
        await eventHub.publish(.portsChanged(ports))
    }

    func connect(configuration: SerialConfiguration) async {
        let attempt = UUID()
        attemptID = attempt
        latestError = nil
        state = .opening(configuration)
        await eventHub.publish(.latestErrorChanged(nil))
        await eventHub.publish(.stateChanged(state))

        if scenario == .opening {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                await self?.completeConnection(configuration: configuration, attempt: attempt)
            }
        } else {
            await completeConnection(configuration: configuration, attempt: attempt)
        }
    }

    func disconnect() async {
        attemptID = UUID()
        latestError = nil
        state = .disconnected
        await eventHub.publish(.latestErrorChanged(nil))
        await eventHub.publish(.stateChanged(state))
    }

    func send(_ request: SendRequest) async {
        guard case .connected = state else {
            latestError = .notConnected
            await eventHub.publish(.latestErrorChanged(latestError))
            return
        }

        switch scenario {
        case .writeFailure:
            let error = SessionError.serial(SerialError(category: .writeFailed, operation: "write", message: "UI test write failure"))
            await append(CommunicationRecord(
                direction: .transmitted,
                rawBytes: request.payload,
                displayFormat: request.displayFormat,
                source: request.source,
                presetSnapshot: request.presetSnapshot,
                sendResult: .failed(error)
            ))
            latestError = error
            state = .error(error)
            await eventHub.publish(.latestErrorChanged(error))
            await eventHub.publish(.stateChanged(state))
        default:
            await append(CommunicationRecord(
                direction: .transmitted,
                rawBytes: request.payload,
                displayFormat: request.displayFormat,
                source: request.source,
                presetSnapshot: request.presetSnapshot,
                sendResult: .sent
            ))
            await append(CommunicationRecord(direction: .received, rawBytes: request.payload, displayFormat: .ascii))
        }
    }

    func clearRecords() async {
        records.removeAll(keepingCapacity: true)
        await eventHub.publish(.statisticsChanged(statistics))
    }

    func updateRecordLimits(maximumRecords: Int, maximumBytes: Int) async {}

    func startAutoSend(_ schedule: AutoSendSchedule) async {
        await eventHub.publish(.autoSendStatusChanged(.running(source: schedule.request.source, remainingCount: schedule.repetitionCount)))
        await send(schedule.request)
        // The loop scenario keeps reporting "running" so the UI can be observed
        // and stopped deterministically; other scenarios complete immediately.
        guard scenario == .autoSendLoop else {
            await eventHub.publish(.autoSendStatusChanged(.inactive))
            return
        }
        await eventHub.publish(.autoSendStatusChanged(.running(source: schedule.request.source, remainingCount: nil)))
    }

    func stopAutoSend() async {
        await eventHub.publish(.autoSendStatusChanged(.inactive))
    }

    func startLogging(configuration: LogConfiguration) async {
        await eventHub.publish(.logStatusChanged(.recording))
    }

    func stopLogging() async {
        await eventHub.publish(.logStatusChanged(.inactive))
    }

    private func completeConnection(configuration: SerialConfiguration, attempt: UUID) async {
        guard attemptID == attempt else { return }
        state = .connected(configuration)
        await eventHub.publish(.stateChanged(state))

        switch scenario {
        case .burst:
            await append(CommunicationRecord(direction: .received, rawBytes: Data("FIRST".utf8), displayFormat: .ascii))
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                await self?.appendBurstTail(attempt: attempt)
            }
        case .deviceRemoval:
            Task { [weak self] in
                // Give the UI test enough time to observe the connected state before
                // exercising the asynchronous removal/error transition.
                try? await Task.sleep(for: .seconds(2))
                await self?.removeDevice(attempt: attempt)
            }
        default:
            break
        }
    }

    private func appendBurstTail(attempt: UUID) async {
        guard attemptID == attempt, case .connected = state else { return }
        await append(CommunicationRecord(direction: .received, rawBytes: Data("SECOND".utf8), displayFormat: .ascii))
    }

    private func removeDevice(attempt: UUID) async {
        guard attemptID == attempt, case .connected = state else { return }
        let error = SessionError.serial(SerialError(category: .deviceRemoved, operation: "read", message: "UI test device removed"))
        latestError = error
        state = .error(error)
        await eventHub.publish(.latestErrorChanged(error))
        await eventHub.publish(.stateChanged(state))
    }

    private func append(_ record: CommunicationRecord) async {
        records.append(record)
        switch record.direction {
        case .received: receivedByteCount += record.rawBytes.count
        case .transmitted: transmittedByteCount += record.rawBytes.count
        }
        await eventHub.publish(.recordsAppended([record]))
        await eventHub.publish(.statisticsChanged(statistics))
    }

    private var statistics: RecordStatistics {
        RecordStatistics(
            recordCount: records.count,
            storedByteCount: records.reduce(0) { $0 + $1.rawBytes.count },
            receivedByteCount: receivedByteCount,
            transmittedByteCount: transmittedByteCount,
            truncationCount: 0,
            lastTruncatedAt: nil
        )
    }
}
