import Combine
import Foundation
import SerialCore

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var ports: [SerialPortDescriptor] = []
    @Published private(set) var sessionState: SessionState = .disconnected
    @Published private(set) var visibleRecords: [CommunicationRecord] = []
    @Published private(set) var statistics: RecordStatistics?
    @Published private(set) var logStatus: LogStatus = .inactive
    @Published private(set) var latestError: SessionError?
    @Published var configuration = SerialConfiguration(path: "")
    @Published var receiveFormat: DisplayFormat = .ascii
    @Published var showsTimestamps = true
    @Published var followsLatest = true
    @Published var isPaused = false
    @Published var sendText = ""
    @Published var sendFormat: DisplayFormat = .ascii
    @Published var lineEnding: LineEnding = .crlf
    @Published private(set) var sendValidationError: ValidationError?

    private let client: any SessionClient
    private var subscriptionTask: Task<Void, Never>?
    private var pausedRecordEvents: [CommunicationRecord] = []

    init(client: any SessionClient) {
        self.client = client
        subscriptionTask = Task { [weak self, client] in
            let stream = await client.subscribe()
            for await event in stream {
                guard !Task.isCancelled else { return }
                self?.consume(event)
            }
        }
    }

    deinit { subscriptionTask?.cancel() }

    var isConfigurationLocked: Bool {
        switch sessionState {
        case .opening, .connected, .closing: true
        case .disconnected, .error: false
        }
    }

    var isConnected: Bool {
        if case .connected = sessionState { return true }
        return false
    }

    var canSend: Bool {
        guard isConnected else { return false }
        return (try? SendPayloadEncoder.encode(text: sendText, format: sendFormat, lineEnding: lineEnding)) != nil
    }

    var statusTitle: String {
        switch sessionState {
        case .disconnected: L10n.disconnected
        case .opening: L10n.opening
        case .connected: L10n.connected
        case .closing: L10n.closing
        case .error: L10n.connectionError
        }
    }

    func start() { refreshPorts() }

    func refreshPorts() {
        Task { await client.refreshPorts() }
    }

    func connectOrDisconnect() {
        switch sessionState {
        case .connected, .opening, .closing:
            Task { await client.disconnect() }
        case .disconnected, .error:
            guard !configuration.path.isEmpty else {
                latestError = .validation(.invalidSetting(L10n.selectPort))
                return
            }
            Task { await client.connect(configuration: configuration) }
        }
    }

    func sendCurrentText() {
        do {
            let request = try SendPayloadEncoder.encode(text: sendText, format: sendFormat, lineEnding: lineEnding)
            sendValidationError = nil
            Task { await client.send(request) }
        } catch let error as ValidationError {
            sendValidationError = error
        } catch {
            sendValidationError = .invalidSetting(error.localizedDescription)
        }
    }

    func validateSendText() {
        guard !sendText.isEmpty else {
            sendValidationError = nil
            return
        }
        do {
            _ = try SendPayloadEncoder.encode(text: sendText, format: sendFormat, lineEnding: lineEnding)
            sendValidationError = nil
        } catch let error as ValidationError {
            sendValidationError = error
        } catch {
            sendValidationError = .invalidSetting(error.localizedDescription)
        }
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused {
            pausedRecordEvents.forEach(applyRecord)
            pausedRecordEvents.removeAll(keepingCapacity: true)
        }
    }

    func clearRecords() {
        visibleRecords.removeAll(keepingCapacity: true)
        pausedRecordEvents.removeAll(keepingCapacity: true)
        Task { await client.clearRecords() }
    }

    func consume(_ event: SessionEvent) {
        switch event {
        case .portsChanged(let ports):
            self.ports = ports
            if configuration.path.isEmpty, let first = ports.first { configuration.path = first.path }
        case .stateChanged(let state):
            sessionState = state
            if let activeConfiguration = state.configuration { configuration = activeConfiguration }
        case .recordsAppended(let records):
            if isPaused {
                pausedRecordEvents.append(contentsOf: records)
            } else {
                records.forEach(applyRecord)
            }
        case .statisticsChanged(let statistics):
            self.statistics = statistics
        case .logStatusChanged(let status):
            logStatus = status
        case .latestErrorChanged(let error):
            latestError = error
        }
    }

    private func applyRecord(_ record: CommunicationRecord) {
        if let index = visibleRecords.firstIndex(where: { $0.id == record.id }) {
            visibleRecords[index] = record
        } else {
            visibleRecords.append(record)
        }
    }
}
