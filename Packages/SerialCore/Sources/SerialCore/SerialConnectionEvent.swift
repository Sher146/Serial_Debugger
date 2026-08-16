import Foundation

public enum SerialConnectionEvent: Sendable, Equatable {
    case deviceRemoved
    case driverError(String)
}
