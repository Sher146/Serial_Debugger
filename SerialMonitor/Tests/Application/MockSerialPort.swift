import Foundation
import SerialCore
@testable import SerialMonitor

actor MockSerialPort: SerialPorting {
    private var ports = [SerialPortDescriptor(path: "/dev/cu.mock")]
    private var writesStorage: [Data] = []
    private var openDelay: Duration?
    private var writeError: Error?
    private var isOpen = false
    private let incomingPair = AsyncThrowingStream<Data, Error>.makeStream()
    private let eventPair = AsyncStream<SerialConnectionEvent>.makeStream()

    func availablePorts() async -> [SerialPortDescriptor] { ports }

    func open(configuration: SerialConfiguration) async throws {
        if let openDelay { try await Task.sleep(for: openDelay) }
        isOpen = true
    }

    func close() async { isOpen = false }

    func write(_ data: Data, deadline: ContinuousClock.Instant) async throws {
        guard isOpen else {
            throw SerialError(category: .writeFailed, operation: "write", message: "not open")
        }
        if let writeError { throw writeError }
        writesStorage.append(data)
    }

    func incomingBytes() async -> AsyncThrowingStream<Data, Error> { incomingPair.stream }
    func connectionEvents() async -> AsyncStream<SerialConnectionEvent> { eventPair.stream }

    func configure(openDelay: Duration? = nil, writeError: Error? = nil) {
        self.openDelay = openDelay
        self.writeError = writeError
    }

    func emitIncoming(_ data: Data) { incomingPair.continuation.yield(data) }
    func emitEvent(_ event: SerialConnectionEvent) { eventPair.continuation.yield(event) }
    func writes() -> [Data] { writesStorage }
}
