import Foundation
import SerialCore

protocol SessionClient: Sendable {
    func subscribe() async -> AsyncStream<SessionEvent>
    func refreshPorts() async
    func connect(configuration: SerialConfiguration) async
    func disconnect() async
    func send(_ request: SendRequest) async
    func startAutoSend(_ schedule: AutoSendSchedule) async
    func stopAutoSend() async
    func clearRecords() async
    func updateRecordLimits(maximumRecords: Int, maximumBytes: Int) async
    func startLogging(configuration: LogConfiguration) async
    func stopLogging() async
}
