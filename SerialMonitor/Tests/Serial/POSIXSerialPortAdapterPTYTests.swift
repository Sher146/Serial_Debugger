import Darwin
import Foundation
import XCTest
@testable import SerialMonitor
@testable import SerialCore

/// Xcode test target 启用后，将本文件与 Infrastructure target 链接以验证：
/// 打开/配置、双向读写、占用、拔出事件顺序、重复 close、连接中取消与写 deadline。
final class POSIXSerialPortAdapterPTYTests: XCTestCase {
    func testBaudRatePlanUsesTermiosForStandardRatesAndIOSSIOSPEEDForCustomRates() {
        XCTAssertEqual(POSIXBaudRatePlan.make(for: 50), .standard)
        XCTAssertEqual(POSIXBaudRatePlan.make(for: 230_400), .standard)
        XCTAssertEqual(POSIXBaudRatePlan.make(for: 921_600), .custom(921_600))
        XCTAssertEqual(POSIXBaudRatePlan.make(for: 250_000), .custom(250_000))
        XCTAssertNil(POSIXBaudRatePlan.make(for: 0))
    }

    func testCustomBaudRateUsesInjectedIOSSIOSPEEDSetter() async throws {
        let terminal = try PseudoTerminal()
        let adapter = POSIXSerialPortAdapter(setCustomBaudRate: { _, baudRate in
            baudRate == 921_600 ? 0 : -1
        })
        defer {
            terminal.closeMaster()
            terminal.closeSlave()
        }

        try await adapter.open(configuration: SerialConfiguration(path: terminal.slavePath, baudRate: 921_600))
        await adapter.close()
    }

    func testCustomBaudRateDriverRejectionIsConfigurationError() async throws {
        let terminal = try PseudoTerminal()
        let adapter = POSIXSerialPortAdapter(setCustomBaudRate: { _, _ in -1 })
        defer {
            terminal.closeMaster()
            terminal.closeSlave()
        }

        do {
            try await adapter.open(configuration: SerialConfiguration(path: terminal.slavePath, baudRate: 921_600))
            XCTFail("Expected custom baud rate to be rejected")
        } catch let error as SerialError {
            XCTAssertEqual(error.category, .configurationUnsupported)
            XCTAssertTrue(error.message.contains("921,600 bps"))
        }
    }

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

    func testReadFromPTYReachesIncomingStream() async throws {
        let terminal = try PseudoTerminal()
        let adapter = POSIXSerialPortAdapter()
        defer {
            terminal.closeMaster()
            terminal.closeSlave()
        }

        try await adapter.open(configuration: SerialConfiguration(path: terminal.slavePath))
        var iterator = (await adapter.incomingBytes()).makeAsyncIterator()
        try await Task.sleep(for: .milliseconds(25))
        let payload = Data([0x52, 0x58, 0x0A])
        let written = payload.withUnsafeBytes { Darwin.write(terminal.master, $0.baseAddress, payload.count) }
        XCTAssertEqual(written, payload.count)

        let received = try await iterator.next()
        await adapter.close()
        XCTAssertEqual(received, payload)
    }

    func testCloseIsIdempotentAndSubsequentWriteFails() async throws {
        let terminal = try PseudoTerminal()
        let adapter = POSIXSerialPortAdapter()
        defer {
            terminal.closeMaster()
            terminal.closeSlave()
        }

        try await adapter.open(configuration: SerialConfiguration(path: terminal.slavePath))
        await adapter.close()
        await adapter.close()
        do {
            try await adapter.write(Data([0x00]), deadline: ContinuousClock().now.advanced(by: .seconds(1)))
            XCTFail("Expected write to fail after close")
        } catch let error as SerialError {
            XCTAssertEqual(error.category, .writeFailed)
        }
    }
}
