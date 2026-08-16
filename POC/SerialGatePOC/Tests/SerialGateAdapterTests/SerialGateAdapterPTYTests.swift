import Foundation
import SerialCore
import XCTest
@testable import SerialGate
@testable import SerialGateAdapter

final class SerialGateAdapterPTYTests: XCTestCase {
    private struct Timeout: Error {}

    /// SGPort init 为 internal，经 `@testable import SerialGate` 构造注入适配器。
    /// 生产路径下实例由 SGPortManager 枚举获得（见 POC 报告附录）。
    private func makeAdapter(on pty: PseudoTerminal) -> SerialGateAdapter {
        SerialGateAdapter(injectedPort: SGPort(pty.slavePath))
    }

    private func withTimeout<T: Sendable>(
        _ seconds: UInt64 = 5,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw Timeout()
            }
            guard let value = try await group.next() else { throw Timeout() }
            group.cancelAll()
            return value
        }
    }

    // 1. 发现：SerialGate 经 IOKit 仅枚举 cu.* 节点，PTY 从端预计不在列表中。
    //    若不在则跳过并记录（01 文档步骤 5 允许的豁免，已记入 POC 报告）。
    func testAvailablePortsContainsPTYSlave() async throws {
        let pty = try XCTUnwrap(PseudoTerminal())
        let adapter = SerialGateAdapter()
        let ports = await adapter.availablePorts()
        guard ports.contains(where: { $0.path == pty.slavePath }) else {
            throw XCTSkip("SerialGate 不枚举 PTY /dev/ttys 节点（IOKit 仅 cu.*），已记录 POC 报告")
        }
    }

    // 2. 打开后从端 tcgetattr 的输入波特率与配置一致（9600 与 115200 两档）。
    func testOpenConfiguresBaudRate() async throws {
        let pty = try XCTUnwrap(PseudoTerminal())
        let adapter = makeAdapter(on: pty)
        try await adapter.open(configuration: SerialConfiguration(path: pty.slavePath, baudRate: 9600))
        var options = try XCTUnwrap(pty.currentTermios())
        XCTAssertEqual(cfgetispeed(&options), speed_t(B9600))
        await adapter.close()

        let adapter2 = SerialGateAdapter(injectedPort: SGPort(pty.slavePath))
        try await adapter2.open(configuration: SerialConfiguration(path: pty.slavePath, baudRate: 115200))
        options = try XCTUnwrap(pty.currentTermios())
        XCTAssertEqual(cfgetispeed(&options), speed_t(B115200))
        await adapter2.close()
    }

    // 3. write 的字节到达主端。
    func testWriteBytesArriveAtMaster() async throws {
        let pty = try XCTUnwrap(PseudoTerminal())
        let adapter = makeAdapter(on: pty)
        try await adapter.open(configuration: SerialConfiguration(path: pty.slavePath, baudRate: 115200))
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF])
        try await adapter.write(payload)
        let received = pty.readFromMaster(timeoutMs: 2000)
        XCTAssertEqual(received, payload)
        await adapter.close()
    }

    // 4. 主端写入的字节经 incomingBytes() 产出（内容一致，不做拆分/合并假设，
    //    仅断言收到的拼接结果与原数据相等）。
    func testIncomingBytesFromMaster() async throws {
        let pty = try XCTUnwrap(PseudoTerminal())
        let adapter = makeAdapter(on: pty)
        try await adapter.open(configuration: SerialConfiguration(path: pty.slavePath, baudRate: 115200))
        let stream = adapter.incomingBytes()
        let payload = Data("hello-serial".utf8)
        XCTAssertTrue(pty.writeToMaster(payload))
        var collected = Data()
        try await withTimeout {
            for try await chunk in stream {
                collected.append(chunk)
                if collected.count >= payload.count { break }
            }
        }
        XCTAssertEqual(collected, payload)
        await adapter.close()
    }

    // 5. 拔出（关闭主端）：先 .deviceRemoved 事件，后 incomingBytes 以
    //    SerialError(.deviceRemoved) 终止。
    func testMasterCloseTerminatesStreamWithDeviceRemoved() async throws {
        let pty = try XCTUnwrap(PseudoTerminal())
        let adapter = makeAdapter(on: pty)
        try await adapter.open(configuration: SerialConfiguration(path: pty.slavePath, baudRate: 115200))
        let events = adapter.connectionEvents()
        let bytes = adapter.incomingBytes()
        pty.closeMaster()

        // 顺序断言：先收事件。
        let firstEvent = try await withTimeout { await events.first { _ in true } }
        XCTAssertEqual(firstEvent, .deviceRemoved)

        // 后收流终止。
        do {
            for try await _ in bytes {}
            XCTFail("incomingBytes 应以 deviceRemoved 终止而非正常结束")
        } catch let error as SerialError {
            XCTAssertEqual(error.category, .deviceRemoved)
        }
        await adapter.close()
    }

    // 6. 占用冲突：同一路径第二个适配器打开应抛 .portBusy。
    //    （macOS 实测 PTY 二次 open 不返 EBUSY，由适配器进程内登记保证，见 POC 报告）
    func testOpenBusyPortThrowsPortBusy() async throws {
        let pty = try XCTUnwrap(PseudoTerminal())
        let adapter1 = makeAdapter(on: pty)
        try await adapter1.open(configuration: SerialConfiguration(path: pty.slavePath, baudRate: 115200))
        let adapter2 = SerialGateAdapter(injectedPort: SGPort(pty.slavePath))
        do {
            try await adapter2.open(configuration: SerialConfiguration(path: pty.slavePath, baudRate: 115200))
            XCTFail("第二次打开同一路径应抛 .portBusy")
        } catch let error as SerialError {
            XCTAssertEqual(error.category, .portBusy)
            XCTAssertTrue(error.isRetryable)
        }
        await adapter1.close()
    }

    // 7. close 幂等：重复调用、未打开时调用均不抛错。
    func testCloseIsIdempotent() async throws {
        let pty = try XCTUnwrap(PseudoTerminal())
        let adapter = makeAdapter(on: pty)
        await adapter.close() // 未打开时调用
        try await adapter.open(configuration: SerialConfiguration(path: pty.slavePath, baudRate: 115200))
        await adapter.close()
        await adapter.close()
    }

    // 8. close 后 write 抛 .writeFailed。
    func testWriteAfterCloseThrows() async throws {
        let pty = try XCTUnwrap(PseudoTerminal())
        let adapter = makeAdapter(on: pty)
        try await adapter.open(configuration: SerialConfiguration(path: pty.slavePath, baudRate: 115200))
        await adapter.close()
        do {
            try await adapter.write(Data([0x01]))
            XCTFail("close 后 write 应抛错")
        } catch let error as SerialError {
            XCTAssertEqual(error.category, .writeFailed)
        }
    }
}
