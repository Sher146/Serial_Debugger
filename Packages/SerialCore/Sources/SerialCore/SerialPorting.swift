import Foundation

/// 串口访问抽象。上层（Application/Domain）只依赖本协议，
/// 具体实现（SerialGate 适配器或自研 POSIX/termios + IOKit 适配器）
/// 仅存在于 Infrastructure 层，可整体替换而不影响上层。
///
/// 线程模型约定（实现者必须遵守）：
/// - 协议本身要求 `Sendable`；实现通常是 actor 或内部串行队列封装。
/// - `incomingBytes()` 与 `connectionEvents()` 返回的流在未打开状态下应立即结束
///   （finish），不得挂起等待。
/// - `close()` 必须幂等：重复调用、未打开时调用均不抛错。
/// - 设备拔出时：实现必须先通过 `connectionEvents()` 发出 `.deviceRemoved`，
///   再使 `incomingBytes()` 以 `SerialError(category: .deviceRemoved, ...)` 终止。
public protocol SerialPorting: Sendable {
    /// 枚举当前可用串口。macOS 优先返回 /dev/cu.* 调用端口；
    /// 无 USB 信息的端口（如 PTY）USB 字段为 nil。失败时返回空数组，不抛错。
    func availablePorts() async -> [SerialPortDescriptor]

    /// 按给定配置打开并配置串口。
    /// 失败时抛出 `SerialError`（category 覆盖 notFound/busy/permissionDenied/
    /// configurationUnsupported/openFailed）。重复 open 未先 close 属调用方错误，
    /// 实现应抛 `.openFailed` 而非静默复用。
    func open(configuration: SerialConfiguration) async throws

    /// 关闭串口并释放资源，终止两个流。幂等。
    func close() async

    /// 写入原始字节。仅在已打开状态合法；失败抛 `SerialError(.writeFailed)`，
    /// 设备已拔出时抛 `SerialError(.deviceRemoved)`。
    func write(_ data: Data) async throws

    /// RX 字节流。每次读到的数据块作为一个元素产出（不做任何拆分/合并/转码）。
    /// 发生不可恢复错误时以对应 `SerialError` throw 终止。
    func incomingBytes() -> AsyncThrowingStream<Data, Error>

    /// 连接异步事件流（设备拔出等）。`close()` 后 finish。
    func connectionEvents() -> AsyncStream<SerialConnectionEvent>
}
