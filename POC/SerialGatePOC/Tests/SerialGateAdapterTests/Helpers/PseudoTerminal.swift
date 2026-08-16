import Darwin
import Foundation

/// `openpty(_:_:_:_:_:)` 封装的 PTY 主从对测试工具。
///
/// - 从端路径形如 `/dev/ttysNNN`，适配器像对真实设备一样打开它。
/// - `closeMaster()` 模拟拔出：实测（macOS 26）此后从端 `poll` 得 POLLHUP|POLLIN，
///   `read` 返回 0（EOF），`write` 失败 EIO。
/// - 不依赖宿主 tty，可在 CI 无 TTY 环境运行。
final class PseudoTerminal {
    private(set) var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    let slavePath: String

    init?() {
        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: 128)
        guard openpty(&master, &slave, &name, nil, nil) == 0 else { return nil }
        masterFD = master
        slaveFD = slave
        let pathBytes = name.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        slavePath = String(decoding: pathBytes, as: UTF8.self)
    }

    /// 关闭主端（模拟拔出）。
    func closeMaster() {
        guard masterFD >= 0 else { return }
        close(masterFD)
        masterFD = -1
    }

    /// 关闭从端（测试持有的引用；适配器另有自己打开的 fd）。
    func closeSlave() {
        guard slaveFD >= 0 else { return }
        close(slaveFD)
        slaveFD = -1
    }

    /// 从主端读取（poll 等待，超时返回 nil）。
    func readFromMaster(maxBytes: Int = 4096, timeoutMs: Int32 = 2000) -> Data? {
        guard masterFD >= 0 else { return nil }
        var polled = pollfd(fd: masterFD, events: Int16(POLLIN), revents: 0)
        guard poll(&polled, 1, timeoutMs) > 0,
              polled.revents & Int16(POLLIN) != 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: maxBytes)
        let count = read(masterFD, &buffer, buffer.count)
        guard count > 0 else { return nil }
        return Data(buffer[..<count])
    }

    /// 向主端写入（从端将收到）。
    @discardableResult
    func writeToMaster(_ data: Data) -> Bool {
        guard masterFD >= 0 else { return false }
        return data.withUnsafeBytes { pointer in
            guard let base = pointer.baseAddress else { return false }
            return write(masterFD, base, data.count) == data.count
        }
    }

    /// 读取当前从端 termios（主从共享同一终端设置，读主端即可）。
    func currentTermios() -> termios? {
        guard masterFD >= 0 else { return nil }
        var options = termios()
        guard tcgetattr(masterFD, &options) == 0 else { return nil }
        return options
    }

    deinit {
        closeMaster()
        closeSlave()
    }
}
