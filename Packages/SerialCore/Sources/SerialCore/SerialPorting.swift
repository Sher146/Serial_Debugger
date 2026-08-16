import Foundation

/// Infrastructure 层的唯一串口边界。实现必须保证 close 幂等、写入有界，
/// 并在设备移除时先发 connection event、后结束接收流。
public protocol SerialPorting: Sendable {
    func availablePorts() async -> [SerialPortDescriptor]
    func open(configuration: SerialConfiguration) async throws
    func close() async
    func write(_ data: Data, deadline: ContinuousClock.Instant) async throws
    func incomingBytes() async -> AsyncThrowingStream<Data, Error>
    func connectionEvents() async -> AsyncStream<SerialConnectionEvent>
}
