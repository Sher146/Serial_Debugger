import XCTest
import SerialCore
@testable import SerialMonitor

final class SessionDomainTests: XCTestCase {
    @MainActor
    func testPreferencesMigrateLegacyPayloadWithoutDiscardingValues() throws {
        let defaults = InMemoryKeyValueStore()
        let key = "legacy"
        let legacy = """
        {"defaultConfiguration":{"path":"/dev/cu.legacy","baudRate":57600,"dataBits":8,"parity":"none","stopBits":1,"flowControl":"none"},"receiveFormat":"hex","sendFormat":"ascii","lineEnding":"lf","showsTimestamps":false,"followsLatest":true,"showsPresets":false,"logFileNamePrefix":"legacy-log"}
        """
        defaults.set(Data(legacy.utf8), forKey: key)

        let preferences = PreferencesStore(defaults: defaults, key: key).load()

        XCTAssertEqual(preferences.defaultConfiguration.path, "/dev/cu.legacy")
        XCTAssertEqual(preferences.receiveFormat, .hex)
        XCTAssertEqual(preferences.logFileNamePrefix, "legacy-log")
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertEqual(preferences.maximumRecords, RecordStore.defaultMaximumRecords)
    }

    func testTextEncodingsAndHexPresentationAreApplied() {
        let text = "串口"
        let gbData = TextPayloadCodec.encode(text, encoding: .gb18030)
        XCTAssertEqual(TextPayloadCodec.decodeForDisplay(gbData, encoding: .gb18030), text)
        XCTAssertEqual(HexCodec.encode(Data([0xAB, 0x01]), presentation: HexPresentation(separator: .comma, usesUppercase: false)), "ab,01")
    }

    func testRecordStoreAppliesNewLimitsImmediately() async {
        let store = RecordStore(maximumRecords: 10, maximumBytes: 100)
        await store.append(CommunicationRecord(direction: .received, rawBytes: Data([1]), displayFormat: .hex))
        await store.append(CommunicationRecord(direction: .received, rawBytes: Data([2]), displayFormat: .hex))
        await store.updateLimits(maximumRecords: 1, maximumBytes: 10)

        let records = await store.allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.rawBytes, Data([2]))
    }
    func testBaudRateCatalogContainsAllStandardAndCommonHighSpeedRates() {
        XCTAssertEqual(BaudRateCatalog.standardRates.first, 50)
        XCTAssertEqual(BaudRateCatalog.standardRates.last, 230_400)
        XCTAssertEqual(BaudRateCatalog.highSpeedRates, [
            460_800, 500_000, 576_000, 921_600, 1_000_000,
            1_500_000, 2_000_000, 3_000_000
        ])
        XCTAssertEqual(BaudRateCatalog.rates(including: 115_200), BaudRateCatalog.presetRates)
    }

    func testBaudRateCatalogIncludesAndSortsAnArbitraryCustomRate() {
        let rates = BaudRateCatalog.rates(including: 250_000)
        XCTAssertEqual(rates, rates.sorted())
        XCTAssertTrue(rates.contains(250_000))
        XCTAssertEqual(rates.filter { $0 == 250_000 }.count, 1)
    }

    func testToolbarLayoutUsesWidePortPickerAndLargeIconTargets() {
        XCTAssertEqual(DesignTokens.toolbarPortPickerWidth, 360)
        XCTAssertGreaterThanOrEqual(DesignTokens.toolbarIconTargetSize, 32)
    }

    func testFontScaleMultipliersIncreaseAndScaleMonoSize() {
        let scales: [AppFontScale] = [.xSmall, .small, .standard, .large, .xLarge]
        let multipliers = scales.map(\.multiplier)
        XCTAssertEqual(multipliers, multipliers.sorted())
        XCTAssertEqual(Set(multipliers).count, scales.count)
        XCTAssertEqual(DesignTokens.monoFontSize(scale: .standard), AppFontRole.mono.baseSize)
        XCTAssertGreaterThan(DesignTokens.monoFontSize(scale: .xLarge), DesignTokens.monoFontSize(scale: .xSmall))
    }

    func testHexEncoderAcceptsWhitespaceAndSeparators() throws {
        XCTAssertEqual(try HexCodec.decode("55 AA,01:00"), Data([0x55, 0xAA, 0x01, 0x00]))
        XCTAssertThrowsError(try HexCodec.decode("5"))
        XCTAssertThrowsError(try HexCodec.decode("ZZ"))
    }

    func testHexInputFormatterGroupsPairsAndFiltersNoise() {
        XCTAssertEqual(HexInputFormatter.format("4152"), "41 52")
        XCTAssertEqual(HexInputFormatter.format("41-52:0a"), "41 52 0a")
        XCTAssertEqual(HexInputFormatter.format("4"), "4")
        XCTAssertEqual(HexInputFormatter.format("41 5"), "41 5")
        XCTAssertEqual(HexInputFormatter.format("zz"), "")
        XCTAssertEqual(HexInputFormatter.format(""), "")
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

    @MainActor
    func testPresetAndPreferencesStoresRoundTripLocally() {
        let defaults = InMemoryKeyValueStore()
        let presetStore = PresetStore(defaults: defaults, key: "presets")
        let preferencesStore = PreferencesStore(defaults: defaults, key: "preferences")
        let preset = PresetSnapshot(name: "复位", content: "AT+RST", format: .ascii, lineEnding: .crlf)
        presetStore.save([preset])

        var preferences = AppPreferences()
        preferences.sendFormat = .hex
        preferences.logFileNamePrefix = "session log"
        preferencesStore.save(preferences)

        XCTAssertEqual(presetStore.load(), [preset])
        XCTAssertEqual(preferencesStore.load().sendFormat, .hex)
        XCTAssertEqual(preferencesStore.load().logFileNamePrefix, "session log")
    }

    func testFileLogServiceWritesFinalizedNDJSONRecord() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("serial-monitor-log-test-\(UUID().uuidString)", isDirectory: true)
        let logger = FileLogService()
        await logger.start(configuration: LogConfiguration(directory: directory, fileNamePrefix: "test"))
        await logger.append(CommunicationRecord(
            direction: .transmitted,
            rawBytes: Data([0x41, 0x0D]),
            displayFormat: .ascii,
            source: .manual,
            sendResult: .sent
        ))
        await logger.stop()

        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"rawHex\":\"41 0D\""))
        XCTAssertTrue(contents.contains("\"state\":\"sent\""))
    }

    func testFileLogServiceRotatesUsingIncrementingSuffix() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("serial-monitor-log-rotation-\(UUID().uuidString)", isDirectory: true)
        let logger = FileLogService()
        await logger.start(configuration: LogConfiguration(directory: directory, fileNamePrefix: "rotate", rotationMaximumBytes: 10))
        await logger.append(CommunicationRecord(direction: .received, rawBytes: Data(repeating: 0xAB, count: 20), displayFormat: .hex))
        await logger.append(CommunicationRecord(direction: .received, rawBytes: Data(repeating: 0xCD, count: 20), displayFormat: .hex))
        await logger.stop()

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(names.count, 2)
        XCTAssertTrue(names.contains(where: { $0.contains("-001.ndjson") }))
    }

    @MainActor
    func testCorruptPreferencesAreBackedUpThenFallBackToDefaults() throws {
        let defaults = InMemoryKeyValueStore()
        let backupDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("serial-monitor-recovered-\(UUID().uuidString)", isDirectory: true)
        let key = "preferences"
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: key)

        let store = PreferencesStore(defaults: defaults, key: key, backupDirectory: backupDirectory)
        let preferences = store.load()

        XCTAssertEqual(preferences, AppPreferences())
        let backups = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), corrupt)
    }

    @MainActor
    func testCorruptPresetsAreBackedUpThenFallBackToEmpty() throws {
        let defaults = InMemoryKeyValueStore()
        let backupDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("serial-monitor-recovered-\(UUID().uuidString)", isDirectory: true)
        let key = "presets"
        defaults.set(Data("{broken".utf8), forKey: key)

        let store = PresetStore(defaults: defaults, key: key, backupDirectory: backupDirectory)

        XCTAssertEqual(store.load(), [])
        let backups = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
    }

    func testAutoSendScheduleRejectsSubMinimumIntervalAndZeroRepetition() throws {
        let request = SendRequest(payload: Data([0x41]), displayFormat: .ascii)
        XCTAssertThrowsError(try AutoSendSchedule(request: request, intervalMilliseconds: 9, repetitionCount: nil)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidInterval)
        }
        XCTAssertNoThrow(try AutoSendSchedule(request: request, intervalMilliseconds: 10, repetitionCount: nil))
        XCTAssertThrowsError(try AutoSendSchedule(request: request, intervalMilliseconds: 10, repetitionCount: 0)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidSetting("发送次数必须大于 0"))
        }
    }

    func testSendEncoderAppliesTextEncodingAndLineEndingMatrix() throws {
        let gb = try SendPayloadEncoder.encode(text: "串口", format: .ascii, lineEnding: .lf, textEncoding: .gb18030)
        XCTAssertEqual(gb.payload, TextPayloadCodec.encode("串口", encoding: .gb18030) + Data([0x0A]))
        XCTAssertEqual(gb.displayFormat, .ascii)

        let hex = try SendPayloadEncoder.encode(text: "01 02", format: .hex, lineEnding: .cr, source: .autoSend)
        XCTAssertEqual(hex.payload, Data([0x01, 0x02, 0x0D]))
        XCTAssertEqual(hex.source, .autoSend)

        XCTAssertThrowsError(try SendPayloadEncoder.encode(text: "", format: .ascii, lineEnding: .none)) { error in
            XCTAssertEqual(error as? ValidationError, .emptyPayload)
        }
    }

    func testConsoleProjectionPerformance() {
        let data = Data(repeating: 0xAB, count: 64 * 1_024)
        let record = CommunicationRecord(direction: .received, rawBytes: data, displayFormat: .hex)
        measure {
            _ = HexCodec.encode(data)
            _ = try? HexCodec.decode(HexCodec.encode(data))
            _ = RecordFormatter.string(for: record, format: .ascii)
        }
    }

    func testFileLogServiceIsolatesAppendFailureFromCaller() async throws {
        let blocker = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("serial-monitor-log-blocker-\(UUID().uuidString)")
        try Data("block".utf8).write(to: blocker)
        let logger = FileLogService()

        await logger.start(configuration: LogConfiguration(directory: blocker, fileNamePrefix: "test"))
        guard case .failed = await logger.currentStatus() else {
            return XCTFail("Expected logging to fail when the directory is a regular file")
        }

        await logger.append(CommunicationRecord(direction: .received, rawBytes: Data([0x01]), displayFormat: .hex))
        guard case .failed = await logger.currentStatus() else {
            return XCTFail("Append failure must not recover or crash the logger")
        }
        await logger.stop()
    }
}
