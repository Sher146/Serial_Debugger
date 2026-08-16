import Foundation

struct QueuedSend: Sendable, Equatable {
    let recordID: UUID
    let request: SendRequest
}

actor TXSendQueue {
    private var pending: [QueuedSend] = []

    func enqueue(_ item: QueuedSend) {
        pending.append(item)
    }

    func dequeue() -> QueuedSend? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    func cancelAll() -> [QueuedSend] {
        defer { pending.removeAll(keepingCapacity: true) }
        return pending
    }
}
