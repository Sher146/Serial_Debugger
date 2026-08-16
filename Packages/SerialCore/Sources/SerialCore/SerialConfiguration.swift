import Foundation

/// 串口通信参数。Codable 用于设置持久化（需求 §7.1 串口默认值），
/// Equatable 用于"连接过程中锁定参数"的变更检测（需求 §5.1）。
public struct SerialConfiguration: Sendable, Codable, Equatable {
    /// 目标端口路径，对应 SerialPortDescriptor.path。
    public var path: String
    /// 波特率（bps）。常用值见 `CommonBaudRates`；自定义值是否生效取决于驱动，
    /// 本层不校验合法性，由 open 时底层判定并可能抛 configurationUnsupported。
    public var baudRate: Int
    public var dataBits: DataBits
    public var parity: Parity
    public var stopBits: StopBits
    public var flowControl: FlowControl

    public init(
        path: String,
        baudRate: Int = 115200,
        dataBits: DataBits = .eight,
        parity: Parity = .none,
        stopBits: StopBits = .one,
        flowControl: FlowControl = .none
    ) {
        self.path = path
        self.baudRate = baudRate
        self.dataBits = dataBits
        self.parity = parity
        self.stopBits = stopBits
        self.flowControl = flowControl
    }

    public enum DataBits: Int, Sendable, Codable, Equatable, CaseIterable {
        case five = 5, six = 6, seven = 7, eight = 8
    }

    public enum Parity: String, Sendable, Codable, Equatable, CaseIterable {
        case none, even, odd
    }

    public enum StopBits: String, Sendable, Codable, Equatable, CaseIterable {
        case one, two
    }

    public enum FlowControl: String, Sendable, Codable, Equatable, CaseIterable {
        /// 无流控（默认）。
        case none
        /// RTS/CTS 硬件流控。
        case rtsCts
        /// XON/XOFF 软件流控。
        case xonXoff
    }

    /// 常用波特率，供 UI 下拉与测试引用；不构成合法值白名单。
    public static let commonBaudRates: [Int] = [
        300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600,
    ]
}
