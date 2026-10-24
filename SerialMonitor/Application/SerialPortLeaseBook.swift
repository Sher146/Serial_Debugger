import Foundation

/// 同一进程内对串口路径的独占租约。
///
/// macOS 允许重复 `open` 同一个 `cu.*` callout 设备，第二个窗口照样能“连接成功”，
/// 但内核会把字节流分给两个读者，表现为两边都只收到半截数据。驱动不会报错，
/// 所以在 Application 层显式登记归属：同一路径同一时刻只允许一个会话占用。
actor SerialPortLeaseBook {
    static let shared = SerialPortLeaseBook()

    private var owners: [String: UUID] = [:]

    /// 返回 `false` 表示该路径已被另一个会话占用。
    func acquire(_ path: String, owner: UUID) -> Bool {
        if let current = owners[path], current != owner {
            return false
        }
        owners[path] = owner
        return true
    }

    func release(_ path: String, owner: UUID) {
        guard owners[path] == owner else { return }
        owners.removeValue(forKey: path)
    }
}
