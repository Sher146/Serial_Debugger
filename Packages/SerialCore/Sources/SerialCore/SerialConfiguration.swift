import Foundation

public struct SerialConfiguration: Sendable, Codable, Equatable {
    public enum DataBits: Int, Sendable, Codable, CaseIterable {
        case five = 5
        case six = 6
        case seven = 7
        case eight = 8
    }

    public enum Parity: String, Sendable, Codable, CaseIterable {
        case none
        case even
        case odd
    }

    public enum StopBits: Int, Sendable, Codable, CaseIterable {
        case one = 1
        case two = 2
    }

    public enum FlowControl: String, Sendable, Codable, CaseIterable {
        case none
        case hardware
    }

    public var path: String
    public var baudRate: Int
    public var dataBits: DataBits
    public var parity: Parity
    public var stopBits: StopBits
    public var flowControl: FlowControl

    public init(
        path: String,
        baudRate: Int = 115_200,
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
}
