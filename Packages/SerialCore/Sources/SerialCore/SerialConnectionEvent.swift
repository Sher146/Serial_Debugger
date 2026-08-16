import Foundation

/// 打开后由底层异步产生的连接事件。
/// 正常 open/close 由调用方发起、不在此流中回显；本流只承载"非调用方发起"的变化。
public enum SerialConnectionEvent: Sendable, Equatable {
    /// 设备被物理拔出或节点消失。发出后 incomingBytes 将以 deviceRemoved 错误终止。
    case deviceRemoved
    /// 底层链路级异常（如帧错误、缓冲溢出）。可恢复性由携带的 SerialError.isRetryable 表达。
    case linkError(SerialError)
}
