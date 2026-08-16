import Foundation

/// 一个被发现的串口的描述。值类型，可跨 actor 传递。
public struct SerialPortDescriptor: Sendable, Equatable, Identifiable {
    /// 设备路径，macOS 为 /dev/cu.* 调用端口。同时作为 `id`。
    public let path: String
    /// 面向用户的可读名称，如 "USB Serial (FT232R)"；无信息时回退为路径最后一段。
    public let displayName: String
    /// USB Vendor ID（十六进制数值，如 0x1A86 即 CH340）；非 USB 设备为 nil。
    public let usbVendorID: Int?
    /// USB Product ID；非 USB 设备为 nil。
    public let usbProductID: Int?
    /// USB 厂商字符串（如 "QinHeng Electronics"）；不可得为 nil。
    public let usbVendorName: String?
    /// USB 产品字符串（如 "USB2.0-Serial"）；不可得为 nil。
    public let usbProductName: String?

    public init(
        path: String,
        displayName: String,
        usbVendorID: Int? = nil,
        usbProductID: Int? = nil,
        usbVendorName: String? = nil,
        usbProductName: String? = nil
    ) {
        self.path = path
        self.displayName = displayName
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
        self.usbVendorName = usbVendorName
        self.usbProductName = usbProductName
    }

    public var id: String { path }
}
