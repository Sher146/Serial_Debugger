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
