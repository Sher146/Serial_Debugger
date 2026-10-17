import XCTest
import SerialCore
@testable import SerialMonitor

@MainActor
final class SessionViewModelTests: XCTestCase {
    func testSettingsDraftDoesNotChangeLivePreferencesUntilApplied() {
        let defaults = InMemoryKeyValueStore()
        let store = PreferencesStore(defaults: defaults, key: "preferences")
        let viewModel = SessionViewModel(client: SessionClientStub(), preferencesStore: store)
        var draft = viewModel.settingsDraft()
        draft.appearance = .dark
        draft.maximumRecords = 10_000

        XCTAssertEqual(viewModel.appearance, .system)
        XCTAssertEqual(store.load().appearance, .system)
        XCTAssertEqual(store.load().maximumRecords, RecordStore.defaultMaximumRecords)

        viewModel.applySettings(draft)

        XCTAssertEqual(viewModel.appearance, .dark)
        XCTAssertEqual(viewModel.maximumRecords, 10_000)
        XCTAssertEqual(store.load().appearance, .dark)
        XCTAssertEqual(store.load().maximumRecords, 10_000)
    }

    func testDefaultSettingsRequireApplyBeforeTheyAffectTheModel() {
        let defaults = InMemoryKeyValueStore()
        let store = PreferencesStore(defaults: defaults, key: "preferences")
        var persisted = AppPreferences()
        persisted.appearance = .dark
        persisted.consoleFontSize = 18
        store.save(persisted)
        let viewModel = SessionViewModel(client: SessionClientStub(), preferencesStore: store)
        let defaultDraft = AppPreferences()

        XCTAssertEqual(viewModel.appearance, .dark)
        XCTAssertEqual(viewModel.consoleFontSize, 18)

        viewModel.applySettings(defaultDraft)

        XCTAssertEqual(viewModel.appearance, .system)
        XCTAssertEqual(viewModel.consoleFontSize, 12)
        XCTAssertEqual(store.load().appearance, .system)
    }

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

    func testSavePresetValidatesAndPersistsLocally() {
        let (preferences, presets) = makeStores()
        let viewModel = SessionViewModel(client: SessionClientStub(), preferencesStore: preferences, presetStore: presets)

        XCTAssertNil(viewModel.savePreset(name: "  复位  ", content: "AT+RST", format: .ascii, lineEnding: .crlf))
        XCTAssertEqual(viewModel.presets.count, 1)
        XCTAssertEqual(viewModel.presets.first?.name, "复位")
        XCTAssertEqual(presets.load().first?.name, "复位")
    }

    func testSavePresetRejectsEmptyDuplicateAndInvalidHex() {
        let (preferences, presets) = makeStores()
        let viewModel = SessionViewModel(client: SessionClientStub(), preferencesStore: preferences, presetStore: presets)

        XCTAssertNil(viewModel.savePreset(name: "A", content: "01", format: .hex, lineEnding: .none))
        XCTAssertNotNil(viewModel.savePreset(name: "  ", content: "01", format: .hex, lineEnding: .none))
        XCTAssertNotNil(viewModel.savePreset(name: "a", content: "02", format: .hex, lineEnding: .none))
        XCTAssertNotNil(viewModel.savePreset(name: "B", content: "ZZ", format: .hex, lineEnding: .none))
        XCTAssertEqual(viewModel.presets.count, 1)
    }

    func testDeletePresetStopsAnyActivePresetLoop() async {
        let client = RecordingSessionClient()
        let (preferences, presets) = makeStores()
        let viewModel = SessionViewModel(client: client, preferencesStore: preferences, presetStore: presets)
        _ = viewModel.savePreset(name: "P", content: "41", format: .hex, lineEnding: .none)

        viewModel.startPresetAutoSend(viewModel.presets[0])
        await eventually { await client.autoSendSchedules.count == 1 }

        viewModel.deletePreset(viewModel.presets[0])

        await eventually { await client.stopAutoSendCount >= 1 }
        XCTAssertTrue(viewModel.presets.isEmpty)
    }

    func testEditorAutoSendBuildsScheduleWithParsedRepetition() async {
        let client = RecordingSessionClient()
        let (preferences, presets) = makeStores()
        let viewModel = SessionViewModel(client: client, preferencesStore: preferences, presetStore: presets)
        viewModel.sendText = "41"
        viewModel.sendFormat = .hex
        viewModel.autoIntervalMilliseconds = 250
        viewModel.autoRepetitionCountText = "5"

        viewModel.startEditorAutoSend()

        await eventually { await client.autoSendSchedules.count == 1 }
        let schedule = await client.autoSendSchedules.first
        XCTAssertEqual(schedule?.repetitionCount, 5)
        XCTAssertEqual(schedule?.interval, .milliseconds(250))
        XCTAssertEqual(schedule?.request.source, .autoSend)
        XCTAssertNil(viewModel.sendValidationError)
    }

    func testEditorAutoSendRejectsInvalidIntervalAndCount() async {
        let client = RecordingSessionClient()
        let (preferences, presets) = makeStores()
        let viewModel = SessionViewModel(client: client, preferencesStore: preferences, presetStore: presets)
        viewModel.sendText = "41"
        viewModel.sendFormat = .hex

        viewModel.autoIntervalMilliseconds = 5
        viewModel.startEditorAutoSend()
        XCTAssertEqual(viewModel.sendValidationError, .invalidInterval)

        viewModel.autoIntervalMilliseconds = 100
        viewModel.autoRepetitionCountText = "0"
        viewModel.startEditorAutoSend()
        XCTAssertEqual(viewModel.sendValidationError, .invalidSetting("发送次数必须大于 0"))

        let schedules = await client.autoSendSchedules
        XCTAssertTrue(schedules.isEmpty)
    }

    func testPresetAutoSendUsesPresetSnapshotAsSource() async {
        let client = RecordingSessionClient()
        let (preferences, presets) = makeStores()
        let viewModel = SessionViewModel(client: client, preferencesStore: preferences, presetStore: presets)
        _ = viewModel.savePreset(name: "P", content: "41", format: .hex, lineEnding: .none)
        let preset = viewModel.presets[0]

        viewModel.startPresetAutoSend(preset)

        await eventually { await client.autoSendSchedules.count == 1 }
        let schedule = await client.autoSendSchedules.first
        XCTAssertEqual(schedule?.request.source, .preset)
        XCTAssertEqual(schedule?.request.presetSnapshot, preset)
        XCTAssertEqual(schedule?.request.payload, Data([0x41]))
    }

    func testCanSendRequiresConnectedSession() {
        let viewModel = SessionViewModel(client: SessionClientStub())
        viewModel.sendText = "41"
        viewModel.sendFormat = .hex

        XCTAssertFalse(viewModel.canSend)
        viewModel.consume(.stateChanged(.connected(SerialConfiguration(path: "/dev/cu.mock"))))
        XCTAssertTrue(viewModel.canSend)
    }

    func testToggleLoggingStartsThenStopsWithStoredDirectory() async {
        let client = RecordingSessionClient()
        let (preferences, presets) = makeStores()
        var stored = preferences.load()
        stored.logDirectoryPath = NSTemporaryDirectory()
        preferences.save(stored)
        let viewModel = SessionViewModel(client: client, preferencesStore: preferences, presetStore: presets)

        viewModel.toggleLogging()
        await eventually { await client.logConfigurations.count == 1 }
        let prefix = await client.logConfigurations.first?.fileNamePrefix
        XCTAssertEqual(prefix, "serial-monitor")

        viewModel.consume(.logStatusChanged(.recording))
        viewModel.toggleLogging()
        await eventually { await client.stopLoggingCount == 1 }
    }

    func testAutoStartLoggingOnConnectUsesStoredDirectory() async {
        let client = RecordingSessionClient()
        let (preferences, presets) = makeStores()
        var stored = preferences.load()
        stored.autoStartLogging = true
        stored.logDirectoryPath = NSTemporaryDirectory()
        preferences.save(stored)
        let viewModel = SessionViewModel(client: client, preferencesStore: preferences, presetStore: presets)

        viewModel.consume(.stateChanged(.connected(SerialConfiguration(path: "/dev/cu.mock"))))

        await eventually { await client.logConfigurations.count == 1 }
    }

    func testAutoStartLoggingWithoutDirectorySurfacesValidationError() async {
        let client = RecordingSessionClient()
        let (preferences, presets) = makeStores()
        var stored = preferences.load()
        stored.autoStartLogging = true
        stored.logDirectoryPath = nil
        preferences.save(stored)
        let viewModel = SessionViewModel(client: client, preferencesStore: preferences, presetStore: presets)

        viewModel.consume(.stateChanged(.connected(SerialConfiguration(path: "/dev/cu.mock"))))

        await eventually { viewModel.latestError != nil }
        XCTAssertEqual(viewModel.latestError, .validation(.invalidSetting("已开启自动记录，请先在设置中选择日志目录")))
        let configurations = await client.logConfigurations
        XCTAssertTrue(configurations.isEmpty)
    }

    private func makeStores() -> (PreferencesStore, PresetStore) {
        let defaults = InMemoryKeyValueStore()
        return (
            PreferencesStore(defaults: defaults, key: "preferences"),
            PresetStore(defaults: defaults, key: "presets")
        )
    }

    private func eventually(_ condition: () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition was not satisfied in time")
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
    func updateRecordLimits(maximumRecords: Int, maximumBytes: Int) async {}
    func startLogging(configuration: LogConfiguration) async {}
    func stopLogging() async {}
}

private actor RecordingSessionClient: SessionClient {
    private(set) var autoSendSchedules: [AutoSendSchedule] = []
    private(set) var stopAutoSendCount = 0
    private(set) var logConfigurations: [LogConfiguration] = []
    private(set) var stopLoggingCount = 0

    func subscribe() async -> AsyncStream<SessionEvent> {
        let pair = AsyncStream<SessionEvent>.makeStream()
        pair.continuation.finish()
        return pair.stream
    }

    func refreshPorts() async {}
    func connect(configuration: SerialConfiguration) async {}
    func disconnect() async {}
    func send(_ request: SendRequest) async {}
    func startAutoSend(_ schedule: AutoSendSchedule) async { autoSendSchedules.append(schedule) }
    func stopAutoSend() async { stopAutoSendCount += 1 }
    func clearRecords() async {}
    func updateRecordLimits(maximumRecords: Int, maximumBytes: Int) async {}
    func startLogging(configuration: LogConfiguration) async { logConfigurations.append(configuration) }
    func stopLogging() async { stopLoggingCount += 1 }
}
