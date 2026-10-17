import Darwin
import Foundation
import SerialCore

typealias CustomBaudRateSetter = @Sendable (Int32, UInt64) -> Int32

@_silgen_name("serial_monitor_set_custom_baud_rate")
private func serialMonitorSetCustomBaudRate(_ fileDescriptor: Int32, _ baudRate: UInt64) -> Int32

enum POSIXBaudRatePlan: Equatable {
    case standard
    case custom(UInt64)

    static func make(for baudRate: Int) -> Self? {
        guard baudRate > 0 else { return nil }
        if BaudRateCatalog.isStandard(baudRate) {
            return .standard
        }
        return .custom(UInt64(baudRate))
    }
}

/// 基于 POSIX/termios 的 P0 实现。它不依赖第三方库，生产采用与否由 P0 实机矩阵决定。
public actor POSIXSerialPortAdapter: SerialPorting {
    private let clock = ContinuousClock()
    private var fileDescriptor: Int32 = -1
    private var activePath: String?
    private var incomingContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var incomingStream: AsyncThrowingStream<Data, Error>?
    private var eventContinuation: AsyncStream<SerialConnectionEvent>.Continuation?
    private var eventStream: AsyncStream<SerialConnectionEvent>?
    private var readerTask: Task<Void, Never>?
    private let setCustomBaudRate: CustomBaudRateSetter

    public init() {
        setCustomBaudRate = serialMonitorSetCustomBaudRate
    }

    init(setCustomBaudRate: @escaping CustomBaudRateSetter) {
        self.setCustomBaudRate = setCustomBaudRate
    }

    deinit {
        readerTask?.cancel()
        if fileDescriptor >= 0 { Darwin.close(fileDescriptor) }
    }

    public func availablePorts() async -> [SerialPortDescriptor] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else { return [] }
        return names
            .filter { $0.hasPrefix("cu.") }
            .sorted()
            .map { SerialPortDescriptor(path: "/dev/\($0)") }
    }

    public func open(configuration: SerialConfiguration) async throws {
        guard fileDescriptor < 0 else {
            throw SerialError(
                category: .openFailed,
                operation: "open",
                path: configuration.path,
                message: "A serial port is already open"
            )
        }

        let descriptor = Darwin.open(configuration.path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw SerialError.fromErrno(errno, operation: "open", path: configuration.path)
        }

        do {
            try configure(descriptor, with: configuration)
        } catch {
            Darwin.close(descriptor)
            throw error
        }

        fileDescriptor = descriptor
        activePath = configuration.path
        makeStreams()
        startReader()
    }

    public func close() async {
        readerTask?.cancel()
        readerTask = nil

        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
        activePath = nil
        incomingContinuation?.finish()
        eventContinuation?.finish()
        incomingContinuation = nil
        eventContinuation = nil
        incomingStream = nil
        eventStream = nil
    }

    public func write(_ data: Data, deadline: ContinuousClock.Instant) async throws {
        guard fileDescriptor >= 0 else {
            throw SerialError(category: .writeFailed, operation: "write", path: activePath, message: "Port is not open")
        }

        var offset = 0
        while offset < data.count {
            try Task.checkCancellation()
            guard clock.now < deadline else {
                throw SerialError(category: .timeout, operation: "write", path: activePath, message: "Write deadline expired")
            }

            let written = data.withUnsafeBytes { buffer in
                Darwin.write(fileDescriptor, buffer.baseAddress!.advanced(by: offset), data.count - offset)
            }
            if written > 0 {
                offset += written
                continue
            }

            if written == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                try await Task.sleep(for: .milliseconds(1))
                continue
            }
            throw SerialError.fromErrno(errno, operation: "write", path: activePath)
        }
    }

    public func incomingBytes() async -> AsyncThrowingStream<Data, Error> {
        incomingStream ?? AsyncThrowingStream { $0.finish() }
    }

    public func connectionEvents() async -> AsyncStream<SerialConnectionEvent> {
        eventStream ?? AsyncStream { $0.finish() }
    }

    private func makeStreams() {
        let incomingPair = AsyncThrowingStream<Data, Error>.makeStream()
        incomingStream = incomingPair.stream
        incomingContinuation = incomingPair.continuation

        let eventPair = AsyncStream<SerialConnectionEvent>.makeStream()
        eventStream = eventPair.stream
        eventContinuation = eventPair.continuation
    }

    private func startReader() {
        readerTask?.cancel()
        readerTask = Task { [weak self] in
            guard let self else { return }
            await self.readLoop()
        }
    }

    private func readLoop() async {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while !Task.isCancelled, fileDescriptor >= 0 {
            let count = Darwin.read(fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                incomingContinuation?.yield(Data(buffer.prefix(Int(count))))
                continue
            }
            if count == 0 || (count == -1 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                try? await Task.sleep(for: .milliseconds(5))
                continue
            }

            let error = SerialError.fromErrno(errno, operation: "read", path: activePath)
            if error.category == .deviceRemoved {
                eventContinuation?.yield(.deviceRemoved)
            } else {
                eventContinuation?.yield(.driverError(error.message))
            }
            incomingContinuation?.finish(throwing: error)
            return
        }
    }

    private func configure(_ descriptor: Int32, with configuration: SerialConfiguration) throws {
        guard let baudRatePlan = POSIXBaudRatePlan.make(for: configuration.baudRate),
              let speed = termiosBaudRate(configuration.baudRate, plan: baudRatePlan) else {
            throw SerialError(category: .configurationUnsupported, operation: "configure", path: configuration.path, message: "Unsupported baud rate \(configuration.baudRate)")
        }

        var options = termios()
        guard tcgetattr(descriptor, &options) == 0 else {
            throw SerialError.fromErrno(errno, operation: "configure", path: configuration.path)
        }
        cfmakeraw(&options)
        options.c_cflag &= ~tcflag_t(CSIZE)
        options.c_cflag |= dataBitsFlag(configuration.dataBits)

        switch configuration.parity {
        case .none:
            options.c_cflag &= ~tcflag_t(PARENB)
        case .even:
            options.c_cflag |= tcflag_t(PARENB)
            options.c_cflag &= ~tcflag_t(PARODD)
        case .odd:
            options.c_cflag |= tcflag_t(PARENB | PARODD)
        }

        if configuration.stopBits == .two {
            options.c_cflag |= tcflag_t(CSTOPB)
        } else {
            options.c_cflag &= ~tcflag_t(CSTOPB)
        }

        if configuration.flowControl == .hardware {
            options.c_cflag |= tcflag_t(CRTS_IFLOW | CCTS_OFLOW)
        } else {
            options.c_cflag &= ~tcflag_t(CRTS_IFLOW | CCTS_OFLOW)
        }

        guard cfsetispeed(&options, speed) == 0, cfsetospeed(&options, speed) == 0, tcsetattr(descriptor, TCSANOW, &options) == 0 else {
            throw SerialError.fromErrno(errno, operation: "configure", path: configuration.path)
        }

        if case .custom(let baudRate) = baudRatePlan, setCustomBaudRate(descriptor, baudRate) != 0 {
            throw SerialError(
                category: .configurationUnsupported,
                operation: "configure",
                path: configuration.path,
                message: "当前串口驱动不支持 \(BaudRateCatalog.label(for: configuration.baudRate)) bps"
            )
        }
    }

    private func dataBitsFlag(_ value: SerialConfiguration.DataBits) -> tcflag_t {
        switch value {
        case .five: return tcflag_t(CS5)
        case .six: return tcflag_t(CS6)
        case .seven: return tcflag_t(CS7)
        case .eight: return tcflag_t(CS8)
        }
    }

    private func termiosBaudRate(_ value: Int, plan: POSIXBaudRatePlan) -> speed_t? {
        if case .custom = plan {
            // A baseline speed is required before IOSSIOSPEED applies the final
            // arbitrary rate. Failure is surfaced instead of retaining B9600.
            return speed_t(B9600)
        }

        switch value {
        case 50: return speed_t(B50)
        case 75: return speed_t(B75)
        case 110: return speed_t(B110)
        case 134: return speed_t(B134)
        case 150: return speed_t(B150)
        case 200: return speed_t(B200)
        case 300: return speed_t(B300)
        case 600: return speed_t(B600)
        case 1_200: return speed_t(B1200)
        case 1_800: return speed_t(B1800)
        case 2_400: return speed_t(B2400)
        case 4_800: return speed_t(B4800)
        case 7_200: return speed_t(B7200)
        case 9_600: return speed_t(B9600)
        case 14_400: return speed_t(B14400)
        case 19_200: return speed_t(B19200)
        case 28_800: return speed_t(B28800)
        case 38_400: return speed_t(B38400)
        case 57_600: return speed_t(B57600)
        case 76_800: return speed_t(B76800)
        case 115_200: return speed_t(B115200)
        case 230_400: return speed_t(B230400)
        default: return nil
        }
    }
}
