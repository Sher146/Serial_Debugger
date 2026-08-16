import Foundation
import SerialCore

actor SessionPreviewClient: SessionClient {
    private let initialEvents: [SessionEvent]

    init(state: SessionState, records: [CommunicationRecord] = []) {
        let configuration = state.configuration ?? SerialConfiguration(path: "/dev/cu.usbserial-demo")
        initialEvents = [
            .portsChanged([SerialPortDescriptor(path: configuration.path, displayName: "演示串口")]),
            .stateChanged(state),
            .recordsAppended(records),
            .statisticsChanged(RecordStatistics(
                recordCount: records.count,
                storedByteCount: records.reduce(0) { $0 + $1.rawBytes.count },
                receivedByteCount: records.filter { $0.direction == .received }.reduce(0) { $0 + $1.rawBytes.count },
                transmittedByteCount: records.filter { $0.direction == .transmitted }.reduce(0) { $0 + $1.rawBytes.count },
                truncationCount: 0,
                lastTruncatedAt: nil
            )),
            .logStatusChanged(.inactive),
            .latestErrorChanged(nil)
        ]
    }

    func subscribe() async -> AsyncStream<SessionEvent> {
        let pair = AsyncStream<SessionEvent>.makeStream()
        for event in initialEvents {
            pair.continuation.yield(event)
        }
        pair.continuation.finish()
        return pair.stream
    }

    func refreshPorts() async {}
    func connect(configuration: SerialConfiguration) async {}
    func disconnect() async {}
    func send(_ request: SendRequest) async {}
    func clearRecords() async {}
}
