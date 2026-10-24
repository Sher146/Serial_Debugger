import Foundation
import CoreFoundation
import SerialCore

enum RecordDirection: String, Sendable, Codable, Equatable {
    case received = "RX"
    case transmitted = "TX"
}

enum DisplayFormat: String, Sendable, Codable, Equatable, CaseIterable {
    case ascii
    case hex
}

enum AppAppearance: String, Sendable, Codable, CaseIterable, Equatable {
    case system, light, dark
}

enum AppFontScale: String, Sendable, Codable, CaseIterable, Equatable {
    case xSmall = "xsmall"
    case small
    case standard
    case large
    case xLarge = "xlarge"

    var multiplier: CGFloat {
        switch self {
        case .xSmall: 0.85
        case .small: 0.925
        case .standard: 1
        case .large: 1.1
        case .xLarge: 1.2
        }
    }
}

enum ConsoleLineSpacing: String, Sendable, Codable, CaseIterable, Equatable {
    case compact, standard, relaxed

    var points: CGFloat {
        switch self {
        case .compact: 0
        case .standard: 2
        case .relaxed: 4
        }
    }
}

enum TextEncodingPreference: String, Sendable, Codable, CaseIterable, Equatable {
    case utf8, gb18030

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8: .utf8
        case .gb18030:
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        }
    }
}

enum HexSeparator: String, Sendable, Codable, CaseIterable, Equatable {
    case space, none, comma

    var value: String {
        switch self {
        case .space: " "
        case .none: ""
        case .comma: ","
        }
    }
}

struct HexPresentation: Sendable, Codable, Equatable {
    var separator: HexSeparator = .space
    var usesUppercase = true
}

enum SendSource: String, Sendable, Codable, Equatable {
    case manual
    case autoSend
    case preset
}

enum LineEnding: String, Sendable, Codable, Equatable, CaseIterable {
    case none
    case cr
    case lf
    case crlf

    var bytes: Data {
        switch self {
        case .none: Data()
        case .cr: Data([0x0D])
        case .lf: Data([0x0A])
        case .crlf: Data([0x0D, 0x0A])
        }
    }
}

struct PresetSnapshot: Sendable, Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let content: String
    let format: DisplayFormat
    let lineEnding: LineEnding

    init(id: UUID = UUID(), name: String, content: String, format: DisplayFormat, lineEnding: LineEnding = .crlf) {
        self.id = id
        self.name = name
        self.content = content
        self.format = format
        self.lineEnding = lineEnding
    }
}

struct AutoSendSchedule: Sendable, Equatable {
    let request: SendRequest
    let interval: Duration
    /// `nil` means repeat until explicitly stopped or the session fails.
    let repetitionCount: Int?

    init(request: SendRequest, intervalMilliseconds: Int, repetitionCount: Int?) throws {
        guard intervalMilliseconds >= 10 else { throw ValidationError.invalidInterval }
        guard repetitionCount == nil || repetitionCount! > 0 else {
            throw ValidationError.invalidSetting("发送次数必须大于 0")
        }
        self.request = request
        self.interval = .milliseconds(intervalMilliseconds)
        self.repetitionCount = repetitionCount
    }
}

enum AutoSendStatus: Sendable, Equatable {
    case inactive
    case running(source: SendSource, remainingCount: Int?)
}

enum SessionError: Error, Sendable, Equatable, LocalizedError {
    case serial(SerialError)
    case cancelled
    case notConnected
    case validation(ValidationError)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .serial(let error): error.message
        case .cancelled: "操作已取消"
        case .notConnected: "串口尚未连接"
        case .validation(let error): error.errorDescription
        case .unexpected(let message): message
        }
    }

    static func map(_ error: Error) -> SessionError {
        if let error = error as? SessionError { return error }
        if let error = error as? SerialError { return .serial(error) }
        if error is CancellationError { return .cancelled }
        return .unexpected(error.localizedDescription)
    }
}

enum SendResult: Sendable, Equatable {
    case pending
    case sent
    case failed(SessionError)
}

struct CommunicationRecord: Sendable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let direction: RecordDirection
    let rawBytes: Data
    let displayFormat: DisplayFormat
    let source: SendSource?
    let presetSnapshot: PresetSnapshot?
    var sendResult: SendResult?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        direction: RecordDirection,
        rawBytes: Data,
        displayFormat: DisplayFormat,
        source: SendSource? = nil,
        presetSnapshot: PresetSnapshot? = nil,
        sendResult: SendResult? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.rawBytes = rawBytes
        self.displayFormat = displayFormat
        self.source = source
        self.presetSnapshot = presetSnapshot
        self.sendResult = sendResult
    }
}

struct SendRequest: Sendable, Equatable {
    let payload: Data
    let displayFormat: DisplayFormat
    let source: SendSource
    let presetSnapshot: PresetSnapshot?

    init(payload: Data, displayFormat: DisplayFormat, source: SendSource = .manual, presetSnapshot: PresetSnapshot? = nil) {
        self.payload = payload
        self.displayFormat = displayFormat
        self.source = source
        self.presetSnapshot = presetSnapshot
    }
}

enum ValidationError: Error, Sendable, Equatable, LocalizedError {
    case invalidHex(String)
    case emptyPayload
    case invalidInterval
    case notConnected
    case invalidSetting(String)

    var errorDescription: String? {
        switch self {
        case .invalidHex(let reason): "HEX 格式无效：\(reason)"
        case .emptyPayload: "发送内容不能为空"
        case .invalidInterval: "发送间隔必须不小于 10 ms"
        case .notConnected: "请先连接串口"
        case .invalidSetting(let reason): "设置无效：\(reason)"
        }
    }
}

/// Formats free-form hex input into space-separated byte pairs so typing or
/// pasting "41 52" / "4152" / "41-52" all normalise to "41 52".
enum HexInputFormatter {
    static func format(_ text: String) -> String {
        var digits: [Character] = []
        for scalar in text.unicodeScalars where isHexDigit(scalar) {
            digits.append(Character(scalar))
        }
        var result = ""
        var index = 0
        while index < digits.count {
            if index > 0 { result.append(" ") }
            let end = min(index + 2, digits.count)
            result.append(contentsOf: digits[index..<end])
            index = end
        }
        return result
    }

    static func isHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
    }
}

enum HexCodec {    static func decode(_ text: String, additionalSeparators: CharacterSet = CharacterSet(charactersIn: ",:;_-|")) throws -> Data {
        var digits = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || additionalSeparators.contains(scalar) {
                continue
            }
            guard CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar) else {
                throw ValidationError.invalidHex("包含非法字符“\(String(scalar))”")
            }
            digits.unicodeScalars.append(scalar)
        }
        guard !digits.isEmpty else { throw ValidationError.emptyPayload }
        guard digits.count.isMultiple(of: 2) else { throw ValidationError.invalidHex("十六进制字符数量必须为偶数") }

        var result = Data()
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else {
                throw ValidationError.invalidHex("无法解析字节")
            }
            result.append(byte)
            index = next
        }
        return result
    }

    static func encode(_ data: Data, presentation: HexPresentation = HexPresentation()) -> String {
        let format = presentation.usesUppercase ? "%02X" : "%02x"
        return data.map { String(format: format, $0) }.joined(separator: presentation.separator.value)
    }
}

enum TextPayloadCodec {
    static func decodeForDisplay(_ data: Data, encoding: TextEncodingPreference = .utf8) -> String {
        if encoding == .utf8 {
            // 逐非法子序列替换：单个坏字节只损失自己，不会把整行可读文本变成等长的替换符。
            return String(decoding: data, as: UTF8.self)
        }
        return String(data: data, encoding: encoding.stringEncoding) ?? String(repeating: "\u{FFFD}", count: max(1, data.count))
    }

    static func encode(_ text: String, encoding: TextEncodingPreference = .utf8) -> Data {
        text.data(using: encoding.stringEncoding, allowLossyConversion: false) ?? Data()
    }
}

enum SendPayloadEncoder {
    static func encode(
        text: String,
        format: DisplayFormat,
        lineEnding: LineEnding,
        textEncoding: TextEncodingPreference = .utf8,
        source: SendSource = .manual,
        presetSnapshot: PresetSnapshot? = nil
    ) throws -> SendRequest {
        let payload: Data
        switch format {
        case .ascii:
            payload = TextPayloadCodec.encode(text, encoding: textEncoding)
            guard !payload.isEmpty || text.isEmpty else {
                throw ValidationError.invalidSetting("内容无法按所选文本编码发送")
            }
        case .hex: payload = try HexCodec.decode(text)
        }
        guard !payload.isEmpty else { throw ValidationError.emptyPayload }
        return SendRequest(
            payload: payload + lineEnding.bytes,
            displayFormat: format,
            source: source,
            presetSnapshot: presetSnapshot
        )
    }
}

enum RecordFormatter {
    static func string(
        for record: CommunicationRecord,
        format: DisplayFormat,
        textEncoding: TextEncodingPreference = .utf8,
        hexPresentation: HexPresentation = HexPresentation()
    ) -> String {
        switch format {
        case .ascii: TextPayloadCodec.decodeForDisplay(record.rawBytes, encoding: textEncoding)
        case .hex: HexCodec.encode(record.rawBytes, presentation: hexPresentation)
        }
    }
}

enum SessionState: Sendable, Equatable {
    case disconnected
    case opening(SerialConfiguration)
    case connected(SerialConfiguration)
    case closing
    case error(SessionError)

    var configuration: SerialConfiguration? {
        switch self {
        case .opening(let configuration), .connected(let configuration): configuration
        case .disconnected, .closing, .error: nil
        }
    }
}

struct SessionStateMachine: Sendable {
    private(set) var state: SessionState = .disconnected

    mutating func transition(to next: SessionState) -> Bool {
        guard Self.isValid(from: state, to: next) else { return false }
        state = next
        return true
    }

    static func isValid(from current: SessionState, to next: SessionState) -> Bool {
        switch (current, next) {
        case (.disconnected, .opening), (.opening, .connected), (.opening, .error),
             (.opening, .closing), (.connected, .closing), (.connected, .error),
             (.closing, .disconnected), (.closing, .error), (.error, .opening),
             (.error, .closing):
            true
        default:
            false
        }
    }
}

struct RecordStatistics: Sendable, Equatable {
    let recordCount: Int
    let storedByteCount: Int
    let receivedByteCount: Int
    let transmittedByteCount: Int
    let truncationCount: Int
    let lastTruncatedAt: Date?
}

actor RecordStore {
    static let defaultMaximumRecords = 50_000
    static let defaultMaximumBytes = 16 * 1_024 * 1_024

    private var maximumRecords: Int
    private var maximumBytes: Int
    private var records: [CommunicationRecord] = []
    private var storedByteCount = 0
    private var receivedByteCount = 0
    private var transmittedByteCount = 0
    private var truncationCount = 0
    private var lastTruncatedAt: Date?

    init(maximumRecords: Int = RecordStore.defaultMaximumRecords, maximumBytes: Int = RecordStore.defaultMaximumBytes) {
        self.maximumRecords = max(1, maximumRecords)
        self.maximumBytes = max(1, maximumBytes)
    }

    func append(_ record: CommunicationRecord) {
        records.append(record)
        storedByteCount += record.rawBytes.count
        switch record.direction {
        case .received: receivedByteCount += record.rawBytes.count
        case .transmitted: transmittedByteCount += record.rawBytes.count
        }
        trimIfNeeded()
    }

    func updateSendResult(recordID: UUID, result: SendResult) -> CommunicationRecord? {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return nil }
        records[index].sendResult = result
        return records[index]
    }

    func allRecords() -> [CommunicationRecord] { records }

    func clear() {
        records.removeAll(keepingCapacity: true)
        storedByteCount = 0
        receivedByteCount = 0
        transmittedByteCount = 0
    }

    func updateLimits(maximumRecords: Int, maximumBytes: Int) {
        self.maximumRecords = max(1, maximumRecords)
        self.maximumBytes = max(1, maximumBytes)
        trimIfNeeded()
    }

    func statistics() -> RecordStatistics {
        RecordStatistics(
            recordCount: records.count,
            storedByteCount: storedByteCount,
            receivedByteCount: receivedByteCount,
            transmittedByteCount: transmittedByteCount,
            truncationCount: truncationCount,
            lastTruncatedAt: lastTruncatedAt
        )
    }

    private func trimIfNeeded() {
        var removed = false
        while records.count > maximumRecords || storedByteCount > maximumBytes {
            let removedRecord = records.removeFirst()
            storedByteCount -= removedRecord.rawBytes.count
            removed = true
        }
        if removed {
            truncationCount += 1
            lastTruncatedAt = Date()
        }
    }
}

enum SafeFileName {
    static func sanitize(_ value: String, fallback: String = "serial-monitor") -> String {
        let prohibited = CharacterSet(charactersIn: "/\\:\u{0}")
        let result = value.unicodeScalars.map { prohibited.contains($0) ? "-" : String($0) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? fallback : String(result.prefix(80))
    }
}

struct AppPreferences: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion = currentSchemaVersion
    var defaultConfiguration = SerialConfiguration(path: "")
    var receiveFormat: DisplayFormat = .ascii
    var sendFormat: DisplayFormat = .ascii
    var lineEnding: LineEnding = .crlf
    var showsTimestamps = true
    var followsLatest = true
    var showsPresets = true
    var logDirectoryPath: String?
    var logDirectoryBookmark: Data?
    var logFileNamePrefix = "serial-monitor"
    var appearance: AppAppearance = .system
    var fontScale: AppFontScale = .standard
    var consoleLineSpacing: ConsoleLineSpacing = .standard
    var textEncoding: TextEncodingPreference = .utf8
    var hexPresentation = HexPresentation()
    var maximumRecords = RecordStore.defaultMaximumRecords
    var maximumBytes = RecordStore.defaultMaximumBytes
    var autoStartLogging = false
    /// `nil` disables rotation; non-nil values are byte thresholds.
    var logRotationMaximumBytes: Int?
    var restoresLastConfiguration = true
    var restoresSendDraft = true
    var sendDraft = ""
    var autoIntervalMilliseconds = 1_000
    var autoRepetitionCountText = ""

    enum CodingKeys: String, CodingKey {
        case schemaVersion, defaultConfiguration, receiveFormat, sendFormat, lineEnding
        case showsTimestamps, followsLatest, showsPresets, logDirectoryPath, logDirectoryBookmark, logFileNamePrefix
        case appearance, fontScale, consoleLineSpacing, textEncoding, hexPresentation
        case maximumRecords, maximumBytes, autoStartLogging, logRotationMaximumBytes
        case restoresLastConfiguration, restoresSendDraft, sendDraft, autoIntervalMilliseconds, autoRepetitionCountText
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func decoded<T: Decodable>(_ type: T.Type, _ key: CodingKeys, default fallback: T) -> T {
            (try? values.decodeIfPresent(type, forKey: key)) ?? fallback
        }
        schemaVersion = decoded(Int.self, .schemaVersion, default: 1)
        defaultConfiguration = decoded(SerialConfiguration.self, .defaultConfiguration, default: SerialConfiguration(path: ""))
        receiveFormat = decoded(DisplayFormat.self, .receiveFormat, default: .ascii)
        sendFormat = decoded(DisplayFormat.self, .sendFormat, default: .ascii)
        lineEnding = decoded(LineEnding.self, .lineEnding, default: .crlf)
        showsTimestamps = decoded(Bool.self, .showsTimestamps, default: true)
        followsLatest = decoded(Bool.self, .followsLatest, default: true)
        showsPresets = decoded(Bool.self, .showsPresets, default: true)
        logDirectoryPath = try? values.decodeIfPresent(String.self, forKey: .logDirectoryPath)
        logDirectoryBookmark = try? values.decodeIfPresent(Data.self, forKey: .logDirectoryBookmark)
        logFileNamePrefix = decoded(String.self, .logFileNamePrefix, default: "serial-monitor")
        appearance = decoded(AppAppearance.self, .appearance, default: .system)
        fontScale = decoded(AppFontScale.self, .fontScale, default: .standard)
        consoleLineSpacing = decoded(ConsoleLineSpacing.self, .consoleLineSpacing, default: .standard)
        textEncoding = decoded(TextEncodingPreference.self, .textEncoding, default: .utf8)
        hexPresentation = decoded(HexPresentation.self, .hexPresentation, default: HexPresentation())
        maximumRecords = decoded(Int.self, .maximumRecords, default: RecordStore.defaultMaximumRecords)
        maximumBytes = decoded(Int.self, .maximumBytes, default: RecordStore.defaultMaximumBytes)
        autoStartLogging = decoded(Bool.self, .autoStartLogging, default: false)
        logRotationMaximumBytes = try? values.decodeIfPresent(Int.self, forKey: .logRotationMaximumBytes)
        restoresLastConfiguration = decoded(Bool.self, .restoresLastConfiguration, default: true)
        restoresSendDraft = decoded(Bool.self, .restoresSendDraft, default: true)
        sendDraft = decoded(String.self, .sendDraft, default: "")
        autoIntervalMilliseconds = decoded(Int.self, .autoIntervalMilliseconds, default: 1_000)
        autoRepetitionCountText = decoded(String.self, .autoRepetitionCountText, default: "")
        normalize()
    }

    mutating func normalize() {
        schemaVersion = Self.currentSchemaVersion
        maximumRecords = [10_000, 50_000, 100_000, 200_000].min(by: { abs($0 - maximumRecords) < abs($1 - maximumRecords) }) ?? 50_000
        maximumBytes = [4, 16, 64, 128].map { $0 * 1_024 * 1_024 }.min(by: { abs($0 - maximumBytes) < abs($1 - maximumBytes) }) ?? RecordStore.defaultMaximumBytes
        if let limit = logRotationMaximumBytes, ![5, 20, 100].map({ $0 * 1_024 * 1_024 }).contains(limit) {
            logRotationMaximumBytes = nil
        }
    }
}

struct LogDirectorySelection: Equatable {
    let path: String
    let bookmark: Data?
}

/// Minimal key/value surface used by the persistence stores. `UserDefaults`
/// satisfies it in production; tests inject an in-memory implementation so they
/// never create `~/Library/Preferences` plists.
protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStore {}

@MainActor
final class PreferencesStore {
    private let defaults: KeyValueStore
    private let key: String
    private let backupDirectory: URL?
    private let fileManager: FileManager

    static var defaultBackupDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SerialMonitor/Recovered", isDirectory: true)
    }

    init(
        defaults: KeyValueStore = UserDefaults.standard,
        key: String = "serial-monitor.preferences.v1",
        backupDirectory: URL? = PreferencesStore.defaultBackupDirectory,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.key = key
        self.backupDirectory = backupDirectory
        self.fileManager = fileManager
    }

    func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key) else { return AppPreferences() }
        guard let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            backUpCorruptData(data)
            return AppPreferences()
        }
        return preferences
    }

    private func backUpCorruptData(_ data: Data) {
        guard let backupDirectory else { return }
        try? fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        let name = "\(SafeFileName.sanitize(key))-\(stamp).json"
        try? data.write(to: backupDirectory.appendingPathComponent(name))
    }

    func save(_ preferences: AppPreferences) {
        var normalized = preferences
        normalized.normalize()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
final class PresetStore {
    private let defaults: KeyValueStore
    private let key: String
    private let backupDirectory: URL?
    private let fileManager: FileManager

    static var defaultBackupDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SerialMonitor/Recovered", isDirectory: true)
    }

    init(
        defaults: KeyValueStore = UserDefaults.standard,
        key: String = "serial-monitor.presets.v1",
        backupDirectory: URL? = PresetStore.defaultBackupDirectory,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.key = key
        self.backupDirectory = backupDirectory
        self.fileManager = fileManager
    }

    func load() -> [PresetSnapshot] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let presets = try? JSONDecoder().decode([PresetSnapshot].self, from: data) else {
            backUpCorruptData(data)
            return []
        }
        return presets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func backUpCorruptData(_ data: Data) {
        guard let backupDirectory else { return }
        try? fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        let name = "\(SafeFileName.sanitize(key))-\(stamp).json"
        try? data.write(to: backupDirectory.appendingPathComponent(name))
    }

    func save(_ presets: [PresetSnapshot]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: key)
    }
}
