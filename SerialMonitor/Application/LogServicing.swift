import Foundation

struct LogConfiguration: Sendable, Equatable {
    let directory: URL
    let fileNamePrefix: String
    let rotationMaximumBytes: Int?

    init(directory: URL, fileNamePrefix: String = "serial-monitor", rotationMaximumBytes: Int? = nil) {
        self.directory = directory
        self.fileNamePrefix = SafeFileName.sanitize(fileNamePrefix)
        self.rotationMaximumBytes = rotationMaximumBytes
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
    private var configuration: LogConfiguration?
    private var fileStem = ""
    private var rotationIndex = 0
    private var currentFileBytes = 0

    func start(configuration: LogConfiguration) async {
        await flushAndClose()
        self.configuration = configuration
        rotationIndex = 0
        do {
            try FileManager.default.createDirectory(at: configuration.directory, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            fileStem = "\(configuration.fileNamePrefix)-\(stamp)"
            try openNextFile()
            status = .recording
        } catch {
            handle = nil
            self.configuration = nil
            status = .failed(error.localizedDescription)
        }
    }

    func append(_ record: CommunicationRecord) async {
        guard handle != nil else { return }
        do {
            let entry = NDJSONLogEntry(record: record)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry) + Data([0x0A])
            if let limit = configuration?.rotationMaximumBytes,
               currentFileBytes > 0,
               currentFileBytes + data.count > limit {
                if let activeHandle = self.handle {
                    try activeHandle.close()
                }
                self.handle = nil
                rotationIndex += 1
                try openNextFile()
            }
            if let activeHandle = self.handle {
                try activeHandle.write(contentsOf: data)
            }
            currentFileBytes += data.count
        } catch {
            if let activeHandle = self.handle {
                try? activeHandle.close()
            }
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
        currentFileBytes = 0
    }

    func currentStatus() async -> LogStatus { status }

    private func openNextFile() throws {
        guard let configuration else { return }
        let suffix = rotationIndex == 0 ? "" : String(format: "-%03d", rotationIndex)
        let url = configuration.directory.appendingPathComponent("\(fileStem)\(suffix).ndjson")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        currentFileBytes = 0
    }
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
