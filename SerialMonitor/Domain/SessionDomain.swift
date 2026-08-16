import Foundation
import SerialCore

enum RecordDirection: String, Sendable, Codable, Equatable {
    case received = "RX"
    case transmitted = "TX"
}

enum DisplayFormat: String, Sendable, Codable, Equatable, CaseIterable {
    case ascii
    case hex
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

    init(id: UUID = UUID(), name: String, content: String, format: DisplayFormat) {
        self.id = id
        self.name = name
        self.content = content
        self.format = format
    }
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

enum HexCodec {
    static func decode(_ text: String, additionalSeparators: CharacterSet = CharacterSet(charactersIn: ",:;_-|")) throws -> Data {
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

    static func encode(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

enum TextPayloadCodec {
    static func decodeForDisplay(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    static func encode(_ text: String) -> Data {
        Data(text.utf8)
    }
}

enum SendPayloadEncoder {
    static func encode(
        text: String,
        format: DisplayFormat,
        lineEnding: LineEnding,
        source: SendSource = .manual,
        presetSnapshot: PresetSnapshot? = nil
    ) throws -> SendRequest {
        let payload: Data
        switch format {
        case .ascii: payload = TextPayloadCodec.encode(text)
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
    static func string(for record: CommunicationRecord, format: DisplayFormat) -> String {
        switch format {
        case .ascii: TextPayloadCodec.decodeForDisplay(record.rawBytes)
        case .hex: HexCodec.encode(record.rawBytes)
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

    private let maximumRecords: Int
    private let maximumBytes: Int
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
