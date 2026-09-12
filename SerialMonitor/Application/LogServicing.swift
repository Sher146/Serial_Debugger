import Foundation

struct LogConfiguration: Sendable, Equatable {
    let directory: URL
    let fileNamePrefix: String

    init(directory: URL, fileNamePrefix: String = "serial-monitor") {
        self.directory = directory
        self.fileNamePrefix = SafeFileName.sanitize(fileNamePrefix)
    }
}

protocol LogServicing: Sendable {
    func start(configuration: LogConfiguration) async
    func append(_ record: CommunicationRecord) async
    func stop() async
    func flushAndClose() async
    func currentStatus() async -> LogStatus
}

actor NullLogService: LogServicing {
    func start(configuration: LogConfiguration) async {}
    func append(_ record: CommunicationRecord) async {}
    func stop() async {}
    func flushAndClose() async {}
    func currentStatus() async -> LogStatus { .inactive }
}

/// Append-only newline-delimited JSON logger. A log failure is isolated to the
/// logger and is surfaced through `currentStatus`; it never fails the session.
actor FileLogService: LogServicing {
    private var handle: FileHandle?
    private var status: LogStatus = .inactive

    func start(configuration: LogConfiguration) async {
        await flushAndClose()
        do {
            try FileManager.default.createDirectory(at: configuration.directory, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = configuration.directory.appendingPathComponent("\(configuration.fileNamePrefix)-\(stamp).ndjson")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            status = .recording
        } catch {
            handle = nil
            status = .failed(error.localizedDescription)
        }
    }

    func append(_ record: CommunicationRecord) async {
        guard let handle else { return }
        do {
            let entry = NDJSONLogEntry(record: record)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry) + Data([0x0A])
            try handle.write(contentsOf: data)
        } catch {
            try? handle.close()
            self.handle = nil
            status = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        await flushAndClose()
        if case .recording = status { status = .inactive }
    }

    func flushAndClose() async {
        guard let handle else { return }
        try? handle.synchronize()
        try? handle.close()
        self.handle = nil
    }

    func currentStatus() async -> LogStatus { status }
}

private struct NDJSONLogEntry: Encodable {
    let timestamp: Date
    let direction: String
    let rawHex: String
    let displayFormat: String
    let source: String?
    let preset: PresetLogEntry?
    let sendResult: SendResultLogEntry?

    init(record: CommunicationRecord) {
        timestamp = record.timestamp
        direction = record.direction.rawValue
        rawHex = HexCodec.encode(record.rawBytes)
        displayFormat = record.displayFormat.rawValue
        source = record.source?.rawValue
        preset = record.presetSnapshot.map(PresetLogEntry.init)
        sendResult = record.sendResult.map(SendResultLogEntry.init)
    }
}

private struct PresetLogEntry: Encodable {
    let id: UUID
    let name: String
    let content: String
    let format: String
    let lineEnding: String

    init(_ preset: PresetSnapshot) {
        id = preset.id
        name = preset.name
        content = preset.content
        format = preset.format.rawValue
        lineEnding = preset.lineEnding.rawValue
    }
}

private struct SendResultLogEntry: Encodable {
    let state: String
    let error: String?

    init(_ result: SendResult) {
        switch result {
        case .pending: state = "pending"; error = nil
        case .sent: state = "sent"; error = nil
        case .failed(let sessionError): state = "failed"; error = sessionError.localizedDescription
        }
    }
}
