import Foundation
import SerialCore

actor SessionCoordinator: SessionClient {
    private let serialPort: any SerialPorting
    private let recordStore: RecordStore
    private let logService: any LogServicing
    private let eventHub = SessionEventHub()
    private let txQueue = TXSendQueue()
    private let clock = ContinuousClock()
    private let writeTimeout: Duration
    private let portPollInterval: Duration

    private var stateMachine = SessionStateMachine()
    private var ports: [SerialPortDescriptor] = []
    private var latestError: SessionError?
    private var connectionAttemptID = UUID()
    private var receiveTask: Task<Void, Never>?
    private var connectionEventTask: Task<Void, Never>?
    private var txPumpTask: Task<Void, Never>?
    private var autoSendTask: Task<Void, Never>?
    private var portMonitorTask: Task<Void, Never>?
    private var autoSendID = UUID()
    private var autoSendStatus: AutoSendStatus = .inactive
    private var sendContinuations: [UUID: CheckedContinuation<SendResult, Never>] = [:]
    private var pendingRecordEvents: [CommunicationRecord] = []
    private var recordBatchTask: Task<Void, Never>?

    init(
        serialPort: any SerialPorting,
        recordStore: RecordStore = RecordStore(),
        logService: any LogServicing = NullLogService(),
        writeTimeout: Duration = .seconds(2),
        portPollInterval: Duration = .milliseconds(1_200)
    ) {
        self.serialPort = serialPort
        self.recordStore = recordStore
        self.logService = logService
        self.writeTimeout = writeTimeout
        self.portPollInterval = portPollInterval
    }

    func subscribe() async -> AsyncStream<SessionEvent> {
        let statistics = await recordStore.statistics()
        let logStatus = await logService.currentStatus()
        return await eventHub.subscribe(initialEvents: [
            .portsChanged(ports),
            .stateChanged(stateMachine.state),
            .statisticsChanged(statistics),
            .logStatusChanged(logStatus),
            .autoSendStatusChanged(autoSendStatus),
            .latestErrorChanged(latestError)
        ])
    }

    func refreshPorts() async {
        ports = await serialPort.availablePorts()
        await eventHub.publish(.portsChanged(ports))
        startPortMonitoringIfNeeded()
    }

    private func startPortMonitoringIfNeeded() {
        guard portMonitorTask == nil else { return }
        portMonitorTask = Task { [weak self, portPollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: portPollInterval)
                guard !Task.isCancelled else { return }
                await self?.pollPortsOnce()
            }
        }
    }

    private func pollPortsOnce() async {
        let latest = await serialPort.availablePorts()
        guard latest != ports else { return }
        ports = latest
        await eventHub.publish(.portsChanged(latest))
    }

    func connect(configuration: SerialConfiguration) async {
        await disconnectCurrentSession(publishDisconnected: false)
        let attempt = UUID()
        connectionAttemptID = attempt
        latestError = nil
        await transition(to: .opening(configuration))
        await eventHub.publish(.latestErrorChanged(nil))

        do {
            try await serialPort.open(configuration: configuration)
            guard connectionAttemptID == attempt else {
                await serialPort.close()
                return
            }
            await transition(to: .connected(configuration))
            startReceiveTasks(for: attempt)
        } catch {
            guard connectionAttemptID == attempt else { return }
            await fail(SessionError.map(error), attempt: attempt)
        }
    }

    func disconnect() async {
        connectionAttemptID = UUID()
        await disconnectCurrentSession(publishDisconnected: true)
    }

    func send(_ request: SendRequest) async {
        _ = await enqueueSend(request, waitForCompletion: false)
    }

    func startAutoSend(_ schedule: AutoSendSchedule) async {
        await stopAutoSend()
        guard case .connected = stateMachine.state else {
            latestError = .notConnected
            await eventHub.publish(.latestErrorChanged(latestError))
            return
        }
        let identifier = UUID()
        autoSendID = identifier
        autoSendStatus = .running(source: schedule.request.source, remainingCount: schedule.repetitionCount)
        await eventHub.publish(.autoSendStatusChanged(autoSendStatus))
        autoSendTask = Task { [weak self] in
            await self?.runAutoSend(schedule, identifier: identifier)
        }
    }

    func stopAutoSend() async {
        autoSendID = UUID()
        autoSendTask?.cancel()
        autoSendTask = nil
        guard autoSendStatus != .inactive else { return }
        autoSendStatus = .inactive
        await eventHub.publish(.autoSendStatusChanged(.inactive))
    }

    func startLogging(configuration: LogConfiguration) async {
        await logService.start(configuration: configuration)
        await eventHub.publish(.logStatusChanged(await logService.currentStatus()))
    }

    func stopLogging() async {
        await logService.stop()
        await eventHub.publish(.logStatusChanged(await logService.currentStatus()))
    }

    private func enqueueSend(_ request: SendRequest, waitForCompletion: Bool) async -> SendResult? {
        guard case .connected = stateMachine.state else {
            latestError = .notConnected
            await eventHub.publish(.latestErrorChanged(latestError))
            return .failed(.notConnected)
        }
        guard !request.payload.isEmpty else {
            latestError = .validation(.emptyPayload)
            await eventHub.publish(.latestErrorChanged(latestError))
            return .failed(.validation(.emptyPayload))
        }

        let record = CommunicationRecord(
            direction: .transmitted,
            rawBytes: request.payload,
            displayFormat: request.displayFormat,
            source: request.source,
            presetSnapshot: request.presetSnapshot,
            sendResult: .pending
        )
        await appendRecord(record)
        await txQueue.enqueue(QueuedSend(recordID: record.id, request: request))
        guard waitForCompletion else {
            startTXPumpIfNeeded()
            return nil
        }
        return await withCheckedContinuation { continuation in
            sendContinuations[record.id] = continuation
            startTXPumpIfNeeded()
        }
    }

    func clearRecords() async {
        await flushPendingRecordEvents()
        await recordStore.clear()
        await eventHub.publish(.statisticsChanged(await recordStore.statistics()))
    }

    func updateRecordLimits(maximumRecords: Int, maximumBytes: Int) async {
        await recordStore.updateLimits(maximumRecords: maximumRecords, maximumBytes: maximumBytes)
        await eventHub.publish(.statisticsChanged(await recordStore.statistics()))
    }

    func shutdown() async {
        portMonitorTask?.cancel()
        portMonitorTask = nil
        await disconnect()
    }

    func currentState() -> SessionState { stateMachine.state }

    func portsSnapshot() -> [SerialPortDescriptor] { ports }

    func recordsSnapshot() async -> [CommunicationRecord] { await recordStore.allRecords() }

    func statisticsSnapshot() async -> RecordStatistics { await recordStore.statistics() }

    func currentAutoSendStatus() -> AutoSendStatus { autoSendStatus }

    private func transition(to state: SessionState) async {
        guard stateMachine.transition(to: state) else { return }
        await eventHub.publish(.stateChanged(state))
    }

    private func startReceiveTasks(for attempt: UUID) {
        receiveTask?.cancel()
        connectionEventTask?.cancel()
        receiveTask = Task { [weak self, serialPort] in
            let stream = await serialPort.incomingBytes()
            do {
                for try await bytes in stream {
                    guard !Task.isCancelled else { return }
                    await self?.receive(bytes, attempt: attempt)
                }
            } catch {
                await self?.receiveFailed(error, attempt: attempt)
            }
        }
        connectionEventTask = Task { [weak self, serialPort] in
            let stream = await serialPort.connectionEvents()
            for await event in stream {
                guard !Task.isCancelled else { return }
                await self?.handleConnectionEvent(event, attempt: attempt)
            }
        }
    }

    private func receive(_ bytes: Data, attempt: UUID) async {
        guard connectionAttemptID == attempt, case .connected = stateMachine.state else { return }
        await appendRecord(CommunicationRecord(
            direction: .received,
            rawBytes: bytes,
            displayFormat: .ascii
        ))
    }

    private func receiveFailed(_ error: Error, attempt: UUID) async {
        guard !Task.isCancelled, connectionAttemptID == attempt else { return }
        await fail(SessionError.map(error), attempt: attempt)
    }

    private func handleConnectionEvent(_ event: SerialConnectionEvent, attempt: UUID) async {
        guard connectionAttemptID == attempt else { return }
        switch event {
        case .deviceRemoved:
            await fail(.serial(SerialError(category: .deviceRemoved, operation: "connection", message: "串口设备已断开")), attempt: attempt)
        case .driverError(let message):
            await fail(.unexpected(message), attempt: attempt)
        }
    }

    private func startTXPumpIfNeeded() {
        guard txPumpTask == nil else { return }
        txPumpTask = Task { [weak self] in
            await self?.drainTXQueue()
        }
    }

    private func drainTXQueue() async {
        defer { txPumpTask = nil }
        while !Task.isCancelled, let queued = await txQueue.dequeue() {
            guard case .connected = stateMachine.state else {
                await completeSend(queued.recordID, result: .failed(.notConnected))
                continue
            }
            do {
                try await serialPort.write(queued.request.payload, deadline: clock.now.advanced(by: writeTimeout))
                await completeSend(queued.recordID, result: .sent)
            } catch {
                let sessionError = SessionError.map(error)
                await completeSend(queued.recordID, result: .failed(sessionError))
                await fail(sessionError, attempt: connectionAttemptID)
                return
            }
        }
    }

    private func completeSend(_ recordID: UUID, result: SendResult) async {
        guard let record = await recordStore.updateSendResult(recordID: recordID, result: result) else { return }
        await logService.append(record)
        await queueRecordEvent(record)
        sendContinuations.removeValue(forKey: recordID)?.resume(returning: result)
        await eventHub.publish(.logStatusChanged(await logService.currentStatus()))
    }

    private func appendRecord(_ record: CommunicationRecord) async {
        await recordStore.append(record)
        if record.direction == .received {
            await logService.append(record)
        }
        await queueRecordEvent(record)
        await eventHub.publish(.statisticsChanged(await recordStore.statistics()))
        await eventHub.publish(.logStatusChanged(await logService.currentStatus()))
    }

    private func queueRecordEvent(_ record: CommunicationRecord) async {
        pendingRecordEvents.append(record)
        guard recordBatchTask == nil else { return }
        recordBatchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(25))
            await self?.flushPendingRecordEvents()
        }
    }

    private func flushPendingRecordEvents() async {
        recordBatchTask?.cancel()
        recordBatchTask = nil
        guard !pendingRecordEvents.isEmpty else { return }
        let records = pendingRecordEvents
        pendingRecordEvents.removeAll(keepingCapacity: true)
        await eventHub.publish(.recordsAppended(records))
    }

    private func fail(_ error: SessionError, attempt: UUID) async {
        guard connectionAttemptID == attempt else { return }
        switch stateMachine.state {
        case .opening, .connected:
            break
        case .disconnected, .closing, .error:
            return
        }
        receiveTask?.cancel()
        connectionEventTask?.cancel()
        txPumpTask?.cancel()
        await stopAutoSend()
        let cancelled = await txQueue.cancelAll()
        for queued in cancelled {
            await completeSend(queued.recordID, result: .failed(error))
        }
        await flushPendingRecordEvents()
        await logService.stop()
        await logService.flushAndClose()
        await serialPort.close()
        latestError = error
        await transition(to: .error(error))
        await eventHub.publish(.latestErrorChanged(error))
        await eventHub.publish(.logStatusChanged(await logService.currentStatus()))
    }

    private func disconnectCurrentSession(publishDisconnected: Bool) async {
        let wasActive: Bool
        switch stateMachine.state {
        case .disconnected: wasActive = false
        default: wasActive = true
        }
        if wasActive { await transition(to: .closing) }
        receiveTask?.cancel()
        connectionEventTask?.cancel()
        txPumpTask?.cancel()
        await stopAutoSend()
        let cancelled = await txQueue.cancelAll()
        for queued in cancelled {
            await completeSend(queued.recordID, result: .failed(.cancelled))
        }
        await flushPendingRecordEvents()
        if wasActive || publishDisconnected {
            await logService.stop()
            await logService.flushAndClose()
        }
        await serialPort.close()
        if wasActive {
            await transition(to: .disconnected)
        } else if publishDisconnected {
            await eventHub.publish(.stateChanged(.disconnected))
        }
        await eventHub.publish(.logStatusChanged(await logService.currentStatus()))
    }

    private func runAutoSend(_ schedule: AutoSendSchedule, identifier: UUID) async {
        var remaining = schedule.repetitionCount
        while !Task.isCancelled, autoSendID == identifier {
            guard let result = await enqueueSend(schedule.request, waitForCompletion: true) else { return }
            guard autoSendID == identifier, !Task.isCancelled else { return }
            guard result == .sent else {
                await stopAutoSendIfCurrent(identifier)
                return
            }
            if let count = remaining {
                let nextCount = count - 1
                remaining = nextCount
                if nextCount == 0 {
                    await stopAutoSendIfCurrent(identifier)
                    return
                }
            }
            autoSendStatus = .running(source: schedule.request.source, remainingCount: remaining)
            await eventHub.publish(.autoSendStatusChanged(autoSendStatus))
            do {
                try await Task.sleep(for: schedule.interval)
            } catch {
                return
            }
        }
    }

    private func stopAutoSendIfCurrent(_ identifier: UUID) async {
        guard autoSendID == identifier else { return }
        autoSendTask = nil
        autoSendStatus = .inactive
        await eventHub.publish(.autoSendStatusChanged(.inactive))
    }
}
