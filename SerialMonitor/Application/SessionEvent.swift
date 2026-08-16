import Foundation
import SerialCore

enum LogStatus: Sendable, Equatable {
    case inactive
    case recording
    case failed(String)
}

enum SessionEvent: Sendable, Equatable {
    case portsChanged([SerialPortDescriptor])
    case stateChanged(SessionState)
    case recordsAppended([CommunicationRecord])
    case statisticsChanged(RecordStatistics)
    case logStatusChanged(LogStatus)
    case latestErrorChanged(SessionError?)
}

actor SessionEventHub {
    private var continuations: [UUID: AsyncStream<SessionEvent>.Continuation] = [:]

    func subscribe(initialEvents: [SessionEvent]) -> AsyncStream<SessionEvent> {
        let token = UUID()
        let pair = AsyncStream<SessionEvent>.makeStream()
        continuations[token] = pair.continuation
        initialEvents.forEach { pair.continuation.yield($0) }
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(token) }
        }
        return pair.stream
    }

    func publish(_ event: SessionEvent) {
        continuations.values.forEach { $0.yield(event) }
    }

    private func remove(_ token: UUID) {
        continuations[token] = nil
    }
}
