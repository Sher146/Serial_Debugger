import Darwin
import Foundation

/// P0 PTY 验证基础设施；测试结束时必须关闭主从端，避免泄漏描述符。
struct PseudoTerminal {
    let master: Int32
    let slave: Int32
    let slavePath: String

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard openpty(&master, &slave, &name, nil, nil) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        self.master = master
        self.slave = slave
        let terminator = name.firstIndex(of: 0) ?? name.endIndex
        self.slavePath = String(decoding: name[..<terminator].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func closeMaster() { Darwin.close(master) }
    func closeSlave() { Darwin.close(slave) }
}
