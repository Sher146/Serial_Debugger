import Foundation

public struct SerialPortDescriptor: Sendable, Codable, Equatable, Identifiable {
    public let path: String
    public let displayName: String
    public let usbVendorID: Int?
    public let usbProductID: Int?

    public var id: String { path }

    public init(
        path: String,
        displayName: String? = nil,
        usbVendorID: Int? = nil,
        usbProductID: Int? = nil
    ) {
        self.path = path
        self.displayName = displayName ?? URL(fileURLWithPath: path).lastPathComponent
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
    }
}
