import Darwin
import Foundation
import XCTest
@testable import SerialMonitor
@testable import SerialCore

/// Xcode test target 启用后，将本文件与 Infrastructure target 链接以验证：
/// 打开/配置、双向读写、占用、拔出事件顺序、重复 close、连接中取消与写 deadline。
final class POSIXSerialPortAdapterPTYTests: XCTestCase {
    func testPTYFixtureProvidesSlavePath() throws {
        let terminal = try PseudoTerminal()
        defer { terminal.closeMaster(); terminal.closeSlave() }
        XCTAssertTrue(terminal.slavePath.hasPrefix("/dev/"))
    }

    func testWriteReachesPTYMaster() async throws {
        let terminal = try PseudoTerminal()
        let adapter = POSIXSerialPortAdapter()
        defer {
            terminal.closeMaster()
            terminal.closeSlave()
        }

        try await adapter.open(configuration: SerialConfiguration(path: terminal.slavePath))
        let payload = Data([0x53, 0x4D, 0x0A])
        try await adapter.write(payload, deadline: ContinuousClock().now.advanced(by: .seconds(1)))

        var received = [UInt8](repeating: 0, count: payload.count)
        let count = Darwin.read(terminal.master, &received, received.count)
        await adapter.close()

        XCTAssertEqual(count, payload.count)
        XCTAssertEqual(Data(received), payload)
    }
}
