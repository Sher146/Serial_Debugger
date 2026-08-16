import Darwin
import Foundation
import IOKit
import IOKit.serial
import os
import SerialCore
import SerialGate

/// SerialGate → `SerialPorting` 适配器（P0 候选实现）。
///
/// 关键实测事实（SerialGate 4.1.0，commit `8458057`，详见 POC 报告附录）：
/// - `SGPort` 的 init 是 internal：只能通过 `SGPortManager.shared` 枚举获得实例，
///   或直接持有底层 fd 测试注入（`@testable import SerialGate`）。PTY 的
///   `/dev/ttysNNN` 不会出现在管理器枚举中（IOKit 仅列 `cu.*` 节点）。
/// - `SGError` 不携带 errno：notFound/busy/permissionDenied 由本适配器在 open
///   预检（`Darwin.open` 探测 + 进程内占用登记）阶段经 `SerialError.mapErrno` 分类。
/// - `SGPort.read` 对 `read(2)` 返回 0/-1 静默吞掉，且 PTY 无 IOKit 节点，SerialGate
///   的 `portStateStream` 不会对 PTY 拔出发 `.removed`：拔出检测由本适配器用
///   自持 fd `poll(2)`（POLLHUP/POLLERR/POLLNVAL）兜底，`portStateStream` 作为旁路。
/// - `SGPort` 固定 CS8、不提供流控 API：非 8 数据位 / 非 none 流控直接判
///   `.configurationUnsupported`，不调用 SGPort。
public actor SerialGateAdapter: SerialPorting {
    private enum Phase: Sendable {
        case closed, open, removed
    }

    /// 跨 actor 边界共享的流状态（锁保护）。协议方法 `incomingBytes()` /
    /// `connectionEvents()` 是非隔离的，必须借此访问打开状态。
    private struct StreamState: Sendable {
        var isOpen = false
        var byteContinuation: AsyncThrowingStream<Data, Error>.Continuation?
        var eventContinuation: AsyncStream<SerialConnectionEvent>.Continuation?
    }

    private let box = OSAllocatedUnfairLock(initialState: StreamState())

    private var phase: Phase = .closed
    private var port: SGPort?
    /// 测试注入端口（`@testable import SerialGate` 构造的 SGPort，用于 PTY）。
    private let injectedPort: SGPort?
    /// 适配器自持的探测/锁 fd：open 预检时打开并保持，供拔出 poll 使用。
    private var lockFD: Int32 = -1
    private var openedPath: String?
    private var pumpTask: Task<Void, Never>?
    private var portStateTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?

    public init() {
        injectedPort = nil
    }

    /// 仅供测试：注入预先构造的 `SGPort`（生产路径从 SGPortManager 枚举获取）。
    init(injectedPort: SGPort) {
        self.injectedPort = injectedPort
    }

    // MARK: - SerialPorting

    public func availablePorts() async -> [SerialPortDescriptor] {
        // availablePortsStream 是 CurrentValueSubject 桥接，首个元素立即可得。
        guard let ports = await Self.firstValue(of: SGPortManager.shared.availablePortsStream) else {
            return []
        }
        let usbInfo = Self.usbInfoByCalloutPath()
        return ports
            .map { port in
                let info = usbInfo[port.name]
                let fallbackName = (port.name as NSString).lastPathComponent
                return SerialPortDescriptor(
                    path: port.name,
                    displayName: info?.productName ?? fallbackName,
                    usbVendorID: info?.vendorID,
                    usbProductID: info?.productID,
                    usbVendorName: info?.vendorName,
                    usbProductName: info?.productName
                )
            }
            .sorted { lhs, rhs in
                // cu.* 优先，其余按路径字典序。
                let lhsIsCu = lhs.path.hasPrefix("/dev/cu.")
                let rhsIsCu = rhs.path.hasPrefix("/dev/cu.")
                if lhsIsCu != rhsIsCu { return lhsIsCu }
                return lhs.path < rhs.path
            }
    }

    public func open(configuration: SerialConfiguration) async throws {
        guard phase != .open else {
            throw SerialError(category: .openFailed,
                              userMessage: "open failed: port \(configuration.path) is already open",
                              isRetryable: false)
        }
        let path = configuration.path

        // 1) 存在性 + 权限/占用预检：拿到底层 errno 做标准分类。
        let probeFD = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard probeFD >= 0 else {
            throw SerialError.mapErrno(errno, operation: "open", path: path)
        }
        // 2) 进程内占用登记（macOS 实测对 PTY 的二次 open 不返回 EBUSY，
        //    TIOCEXCL 亦不强制互斥；进程内登记保证同进程双开判定确定）。
        guard OpenPathRegistry.shared.insert(path) else {
            Darwin.close(probeFD)
            throw SerialError.mapErrno(EBUSY, operation: "open", path: path)
        }
        // 3) 参数校验：SerialGate 固定 CS8、无流控 API，提前判 configurationUnsupported。
        do {
            try Self.validate(configuration: configuration)
        } catch {
            OpenPathRegistry.shared.remove(path)
            Darwin.close(probeFD)
            throw error
        }
        // 4) 获取 SGPort 实例。
        let sgPort: SGPort
        if let injectedPort, injectedPort.name == path {
            sgPort = injectedPort
        } else {
            guard let found = await Self.findPort(path: path) else {
                OpenPathRegistry.shared.remove(path)
                Darwin.close(probeFD)
                throw SerialError.mapErrno(ENOENT, operation: "open", path: path)
            }
            sgPort = found
        }
        // 5) 预存参数（SGPort.open 内部统一走 cfsetspeed/tcsetattr）。
        do {
            try sgPort.set(baudRate: Int32(clamping: configuration.baudRate))
            try sgPort.set(parity: Self.sgParity(configuration.parity))
            try sgPort.set(stopBits: configuration.stopBits == .two ? 2 : 1)
            try sgPort.open()
        } catch {
            OpenPathRegistry.shared.remove(path)
            Darwin.close(probeFD)
            throw SerialGateErrorMapper.mapOpenError(error, path: path)
        }
        // 6) 打开成功：接管流与监控。
        port = sgPort
        lockFD = probeFD
        openedPath = path
        phase = .open
        box.withLock { $0.isOpen = true }
        startPumps(port: sgPort, lockFD: probeFD)
    }

    public func close() async {
        guard phase != .closed else { return }
        phase = .closed
        monitorTask?.cancel()
        pumpTask?.cancel()
        portStateTask?.cancel()
        monitorTask = nil
        pumpTask = nil
        portStateTask = nil
        try? port?.close()
        port = nil
        if lockFD >= 0 {
            Darwin.close(lockFD)
            lockFD = -1
        }
        if let openedPath {
            OpenPathRegistry.shared.remove(openedPath)
            self.openedPath = nil
        }
        box.withLock { state in
            state.isOpen = false
            state.byteContinuation?.finish()
            state.byteContinuation = nil
            state.eventContinuation?.finish()
            state.eventContinuation = nil
        }
    }

    public func write(_ data: Data) async throws {
        let path = openedPath ?? "<unknown>"
        switch phase {
        case .removed:
            throw SerialError(category: .deviceRemoved,
                              userMessage: "write failed: device at \(path) was removed",
                              isRetryable: true)
        case .closed:
            throw SerialError(category: .writeFailed,
                              userMessage: "write failed: port \(path) is not open",
                              isRetryable: false)
        case .open:
            break
        }
        guard let port else {
            throw SerialError(category: .writeFailed,
                              userMessage: "write failed: port \(path) is not open",
                              isRetryable: false)
        }
        do {
            try port.send(data: data)
        } catch {
            let capturedErrno = errno
            if capturedErrno == EIO {
                handleRemoval()
            }
            throw SerialGateErrorMapper.mapWriteError(error, path: path, fallbackErrno: capturedErrno)
        }
    }

    public nonisolated func incomingBytes() -> AsyncThrowingStream<Data, Error> {
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let registered = box.withLock { state -> Bool in
            guard state.isOpen, state.byteContinuation == nil else { return false }
            state.byteContinuation = continuation
            return true
        }
        if !registered {
            continuation.finish()
        }
        return stream
    }

    public nonisolated func connectionEvents() -> AsyncStream<SerialConnectionEvent> {
        let (stream, continuation) = AsyncStream<SerialConnectionEvent>.makeStream()
        let registered = box.withLock { state -> Bool in
            guard state.isOpen, state.eventContinuation == nil else { return false }
            state.eventContinuation = continuation
            return true
        }
        if !registered {
            continuation.finish()
        }
        return stream
    }

    // MARK: - 内部管线

    private func startPumps(port: SGPort, lockFD: Int32) {
        // RX 数据泵：SGPort.dataStream → AsyncThrowingStream 元素。
        pumpTask = Task { [box] in
            for await result in port.dataStream {
                if case let .success(data) = result {
                    _ = box.withLock { $0.byteContinuation?.yield(data) }
                }
                // .failure 元素（如状态迁移窗口的 portIsNotOpen）为瞬时语义，忽略。
            }
        }
        // 拔出旁路：真实 USB 设备经 SGPortManager 通知（依赖其 RunLoop 存活）。
        portStateTask = Task { [weak self] in
            for await portState in port.portStateStream where portState == .removed {
                await self?.handleRemoval()
            }
        }
        // 拔出兜底：适配器自持 fd 的 poll（PTY 无 IOKit 节点时唯一可靠路径）。
        // 实测（macOS 26）：events 必须非 0 才会报告 POLLHUP，故请求 POLLIN 但
        // 只判 HUP/ERR/NVAL 位（正常数据到达只置 POLLIN，不算拔出）。
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                var polled = pollfd(fd: lockFD, events: Int16(POLLIN), revents: 0)
                let result = poll(&polled, 1, 25)
                if result > 0,
                   polled.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 {
                    await self?.handleRemoval()
                    return
                }
            }
        }
    }

    /// 拔出处理：先 `.deviceRemoved` 事件，后 `incomingBytes` 以 deviceRemoved 终止。
    /// 幂等：poll、portStateStream、write EIO 三条路径可能并发触发。
    private func handleRemoval() {
        guard phase == .open else { return }
        phase = .removed
        let path = openedPath ?? "<unknown>"
        monitorTask?.cancel()
        pumpTask?.cancel()
        let error = SerialError(category: .deviceRemoved, systemCode: Int(EIO),
                                systemDomain: "NSPOSIXErrorDomain",
                                userMessage: "device at \(path) went away",
                                isRetryable: true)
        box.withLock { state in
            state.isOpen = false
            // 顺序契约：先事件、后流终止。
            state.eventContinuation?.yield(.deviceRemoved)
            state.byteContinuation?.finish(throwing: error)
            state.byteContinuation = nil
        }
        // SGPort.close 在死 fd 上会抛错（tcdrain 失败），但其已先取消读定时器，try? 吞掉即可。
        try? port?.close()
        port = nil
        if lockFD >= 0 {
            Darwin.close(lockFD)
            lockFD = -1
        }
        if let openedPath {
            OpenPathRegistry.shared.remove(openedPath)
            self.openedPath = nil
        }
    }

    // MARK: - 静态辅助

    private static func validate(configuration: SerialConfiguration) throws {
        guard configuration.dataBits == .eight else {
            throw SerialError(category: .configurationUnsupported,
                              userMessage: "open failed: SerialGate supports 8 data bits only (requested \(configuration.dataBits.rawValue))",
                              isRetryable: false)
        }
        guard configuration.flowControl == .none else {
            throw SerialError(category: .configurationUnsupported,
                              userMessage: "open failed: SerialGate has no flow control API (requested \(configuration.flowControl.rawValue))",
                              isRetryable: false)
        }
    }

    private static func sgParity(_ parity: SerialConfiguration.Parity) -> SGParity {
        switch parity {
        case .none: return .none
        case .even: return .even
        case .odd: return .odd
        }
    }

    private static func firstValue(of stream: AsyncStream<[SGPort]>) async -> [SGPort]? {
        for await value in stream { return value }
        return nil
    }

    private static func findPort(path: String) async -> SGPort? {
        guard let ports = await firstValue(of: SGPortManager.shared.availablePortsStream) else {
            return nil
        }
        return ports.first { $0.name == path }
    }

    private struct USBInfo {
        var vendorID: Int?
        var productID: Int?
        var vendorName: String?
        var productName: String?
    }

    /// 遍历 IOKit 串口节点，按 callout 路径回溯父链取 USB VID/PID 与名称。
    /// 属适配器内部实现（01 文档 §6.6），不进 SerialCore。
    private static func usbInfoByCalloutPath() -> [String: USBInfo] {
        var result: [String: USBInfo] = [:]
        var iterator: io_iterator_t = .zero
        let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        matchingDict[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            guard let callout = IORegistryEntryCreateCFProperty(
                entry, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String else {
                continue
            }
            var info = USBInfo()
            var current = entry
            while true {
                if info.vendorID == nil,
                   let number = IORegistryEntryCreateCFProperty(
                       current, "idVendor" as CFString, kCFAllocatorDefault, 0
                   )?.takeRetainedValue() as? NSNumber {
                    info.vendorID = number.intValue
                }
                if info.productID == nil,
                   let number = IORegistryEntryCreateCFProperty(
                       current, "idProduct" as CFString, kCFAllocatorDefault, 0
                   )?.takeRetainedValue() as? NSNumber {
                    info.productID = number.intValue
                }
                if info.vendorName == nil,
                   let name = IORegistryEntryCreateCFProperty(
                       current, "USB Vendor Name" as CFString, kCFAllocatorDefault, 0
                   )?.takeRetainedValue() as? String {
                    info.vendorName = name
                }
                if info.productName == nil,
                   let name = IORegistryEntryCreateCFProperty(
                       current, "USB Product Name" as CFString, kCFAllocatorDefault, 0
                   )?.takeRetainedValue() as? String {
                    info.productName = name
                }
                var parent: io_registry_entry_t = .zero
                guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS,
                      parent != IO_OBJECT_NULL else {
                    break
                }
                current = parent
            }
            result[callout] = info
        }
        return result
    }
}

/// 进程内串口路径占用登记（actor 实例间共享）。
/// macOS 实测：PTY/TTY 的二次 `open(2)` 不返回 EBUSY，`TIOCEXCL` 亦不强制互斥，
/// 因此同进程双开判定由本登记表保证确定性；跨进程占用（如 screen）依赖底层 errno。
final class OpenPathRegistry: @unchecked Sendable {
    static let shared = OpenPathRegistry()

    private let lock = OSAllocatedUnfairLock(initialState: Set<String>())

    func insert(_ path: String) -> Bool {
        lock.withLock { $0.insert(path).inserted }
    }

    func remove(_ path: String) {
        lock.withLock { _ = $0.remove(path) }
    }
}
