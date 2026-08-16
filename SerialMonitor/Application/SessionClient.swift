import Foundation
import SerialCore

protocol SessionClient: Sendable {
    func subscribe() async -> AsyncStream<SessionEvent>
    func refreshPorts() async
    func connect(configuration: SerialConfiguration) async
    func disconnect() async
    func send(_ request: SendRequest) async
    func clearRecords() async
}
