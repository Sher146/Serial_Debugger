import Combine
import Foundation
import AppKit
import SerialCore

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var ports: [SerialPortDescriptor] = []
    @Published private(set) var sessionState: SessionState = .disconnected
    @Published private(set) var visibleRecords: [CommunicationRecord] = []
    @Published private(set) var statistics: RecordStatistics?
    @Published private(set) var logStatus: LogStatus = .inactive
    @Published private(set) var autoSendStatus: AutoSendStatus = .inactive
    @Published private(set) var latestError: SessionError?
    @Published private(set) var presets: [PresetSnapshot] = []
    @Published var configuration = SerialConfiguration(path: "") { didSet { persistPreferences() } }
    @Published var receiveFormat: DisplayFormat = .ascii { didSet { persistPreferences() } }
    @Published var showsTimestamps = true { didSet { persistPreferences() } }
    @Published var followsLatest = true { didSet { persistPreferences() } }
    @Published var showsPresets = true { didSet { persistPreferences() } }
    @Published var isPaused = false
    @Published var sendText = ""
    @Published var sendFormat: DisplayFormat = .ascii { didSet { persistPreferences() } }
    @Published var lineEnding: LineEnding = .crlf { didSet { persistPreferences() } }
    @Published var autoIntervalMilliseconds = 1_000
    @Published var autoRepetitionCountText = ""
    @Published var logFileNamePrefix = "serial-monitor" { didSet { persistPreferences() } }
    @Published private(set) var sendValidationError: ValidationError?

    private let client: any SessionClient
    private let preferencesStore: PreferencesStore
    private let presetStore: PresetStore
    private var subscriptionTask: Task<Void, Never>?
    private var pausedRecordEvents: [CommunicationRecord] = []
    private var activeSecurityScopedDirectory: URL?
    private var activePresetID: UUID?

    init(
        client: any SessionClient,
        preferencesStore: PreferencesStore = PreferencesStore(),
        presetStore: PresetStore = PresetStore()
    ) {
        self.client = client
        self.preferencesStore = preferencesStore
        self.presetStore = presetStore
        let preferences = preferencesStore.load()
        configuration = preferences.defaultConfiguration
        receiveFormat = preferences.receiveFormat
        sendFormat = preferences.sendFormat
        lineEnding = preferences.lineEnding
        showsTimestamps = preferences.showsTimestamps
        followsLatest = preferences.followsLatest
        showsPresets = preferences.showsPresets
        logFileNamePrefix = preferences.logFileNamePrefix
        presets = presetStore.load()
        subscriptionTask = Task { [weak self, client] in
            let stream = await client.subscribe()
            for await event in stream {
                guard !Task.isCancelled else { return }
                self?.consume(event)
            }
        }
    }

    deinit {
        subscriptionTask?.cancel()
        activeSecurityScopedDirectory?.stopAccessingSecurityScopedResource()
    }

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

    var isAutoSending: Bool {
        if case .running = autoSendStatus { return true }
        return false
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

    func shutdown() {
        Task {
            await client.stopAutoSend()
            await client.stopLogging()
            await client.disconnect()
        }
    }

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

    func startEditorAutoSend() {
        do {
            let request = try SendPayloadEncoder.encode(
                text: sendText,
                format: sendFormat,
                lineEnding: lineEnding,
                source: .autoSend
            )
            let schedule = try AutoSendSchedule(
                request: request,
                intervalMilliseconds: autoIntervalMilliseconds,
                repetitionCount: repetitionCount
            )
            sendValidationError = nil
            activePresetID = nil
            Task { await client.startAutoSend(schedule) }
        } catch let error as ValidationError {
            sendValidationError = error
        } catch {
            sendValidationError = .invalidSetting(error.localizedDescription)
        }
    }

    func stopAutoSend() {
        Task { await client.stopAutoSend() }
    }

    func sendPreset(_ preset: PresetSnapshot) {
        do {
            let request = try request(for: preset)
            sendValidationError = nil
            Task { await client.send(request) }
        } catch let error as ValidationError {
            sendValidationError = error
        } catch {
            sendValidationError = .invalidSetting(error.localizedDescription)
        }
    }

    func startPresetAutoSend(_ preset: PresetSnapshot) {
        do {
            let schedule = try AutoSendSchedule(
                request: request(for: preset),
                intervalMilliseconds: autoIntervalMilliseconds,
                repetitionCount: repetitionCount
            )
            sendValidationError = nil
            activePresetID = preset.id
            Task { await client.startAutoSend(schedule) }
        } catch let error as ValidationError {
            sendValidationError = error
        } catch {
            sendValidationError = .invalidSetting(error.localizedDescription)
        }
    }

    func savePreset(id: UUID? = nil, name: String, content: String, format: DisplayFormat, lineEnding: LineEnding) -> ValidationError? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return .invalidSetting("预设名称不能为空") }
        guard !presets.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame }) else {
            return .invalidSetting("预设名称已存在")
        }
        do {
            _ = try SendPayloadEncoder.encode(text: content, format: format, lineEnding: lineEnding)
        } catch let error as ValidationError {
            return error
        } catch {
            return .invalidSetting(error.localizedDescription)
        }
        let preset = PresetSnapshot(id: id ?? UUID(), name: normalizedName, content: content, format: format, lineEnding: lineEnding)
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        presets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        presetStore.save(presets)
        return nil
    }

    func deletePreset(_ preset: PresetSnapshot) {
        if activePresetID == preset.id { stopAutoSend() }
        presets.removeAll { $0.id == preset.id }
        presetStore.save(presets)
    }

    func toggleLogging() {
        if case .recording = logStatus {
            Task { await client.stopLogging() }
            return
        }
        guard let directory = chooseLogDirectory() else { return }
        let configuration = LogConfiguration(directory: directory, fileNamePrefix: logFileNamePrefix)
        Task { await client.startLogging(configuration: configuration) }
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
            if !configuration.path.isEmpty, !ports.contains(where: { $0.path == configuration.path }) {
                configuration.path = ""
            }
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
            if case .inactive = status { stopSecurityScopedDirectoryAccess() }
        case .autoSendStatusChanged(let status):
            autoSendStatus = status
            if case .inactive = status { activePresetID = nil }
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

    private var repetitionCount: Int? {
        let value = autoRepetitionCountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return Int(value)
    }

    private func request(for preset: PresetSnapshot) throws -> SendRequest {
        try SendPayloadEncoder.encode(
            text: preset.content,
            format: preset.format,
            lineEnding: preset.lineEnding,
            source: .preset,
            presetSnapshot: preset
        )
    }

    private func persistPreferences() {
        var preferences = preferencesStore.load()
        preferences.defaultConfiguration = configuration
        preferences.receiveFormat = receiveFormat
        preferences.sendFormat = sendFormat
        preferences.lineEnding = lineEnding
        preferences.showsTimestamps = showsTimestamps
        preferences.followsLatest = followsLatest
        preferences.showsPresets = showsPresets
        preferences.logFileNamePrefix = SafeFileName.sanitize(logFileNamePrefix)
        preferencesStore.save(preferences)
    }

    private func chooseLogDirectory() -> URL? {
        if let existing = resolvedLogDirectory() { return existing }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择日志目录"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        storeLogDirectory(url)
        _ = url.startAccessingSecurityScopedResource()
        activeSecurityScopedDirectory = url
        return url
    }

    private func resolvedLogDirectory() -> URL? {
        let preferences = preferencesStore.load()
        var bookmarkIsStale = false
        if let bookmark = preferences.logDirectoryBookmark,
           let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &bookmarkIsStale) {
            _ = url.startAccessingSecurityScopedResource()
            activeSecurityScopedDirectory = url
            return url
        }
        if let path = preferences.logDirectoryPath {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    private func storeLogDirectory(_ url: URL) {
        var preferences = preferencesStore.load()
        preferences.logDirectoryPath = url.path
        preferences.logDirectoryBookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        preferencesStore.save(preferences)
    }

    private func stopSecurityScopedDirectoryAccess() {
        activeSecurityScopedDirectory?.stopAccessingSecurityScopedResource()
        activeSecurityScopedDirectory = nil
    }
}
