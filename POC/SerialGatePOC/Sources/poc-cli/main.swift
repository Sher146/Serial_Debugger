import Foundation
import SerialCore
import SerialGateAdapter

// poc-cli —— P0 实机/PTY 验证工具。
//
// 用法：
//   poc-cli list
//   poc-cli open   <path> <baud> [seconds]   打开并核对 termios，保持 seconds 秒后关闭
//   poc-cli echo   <path> <baud> <seconds>   自环收发统计（实机需 TX/RX 跳线短接；
//                                            PTY 需对端回显，见 README 自测脚本）
//   poc-cli stress <path> <baud> <seconds>   持续读统计字节数与耗时
//
// 说明：文档 §5 清单中的 close 子命令与进程生命周期绑定（串口 fd 随进程退出释放，
// 无法跨进程"关闭"），其语义已并入 open 的打开-保持-关闭流程，详见 POC 报告。

func usage() -> Never {
    print("""
    usage:
      poc-cli list
      poc-cli open   <path> <baud> [seconds]
      poc-cli echo   <path> <baud> <seconds>
      poc-cli stress <path> <baud> <seconds>
    """)
    exit(2)
}

/// 独立 fd 上 tcgetattr 核对（不依赖适配器内部状态）。
func dumpTermios(path: String) -> String {
    let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
    guard fd >= 0 else { return "tcgetattr: open failed errno=\(errno)" }
    defer { Darwin.close(fd) }
    var options = termios()
    guard tcgetattr(fd, &options) == 0 else { return "tcgetattr failed errno=\(errno)" }
    return "ispeed=\(cfgetispeed(&options)) ospeed=\(cfgetospeed(&options)) cflag=0x\(String(options.c_cflag, radix: 16))"
}

func runList() async {
    let adapter = SerialGateAdapter()
    let ports = await adapter.availablePorts()
    if ports.isEmpty {
        print("（未发现串口）")
        return
    }
    for port in ports {
        let vid = port.usbVendorID.map { String(format: "0x%04X", $0) } ?? "-"
        let pid = port.usbProductID.map { String(format: "0x%04X", $0) } ?? "-"
        let vendor = port.usbVendorName ?? "-"
        let product = port.usbProductName ?? "-"
        print("\(port.path)\n    name=\(port.displayName) vid=\(vid) pid=\(pid) vendor=\(vendor) product=\(product)")
    }
}

func makeConfiguration(path: String, baud: Int) -> SerialConfiguration {
    SerialConfiguration(path: path, baudRate: baud)
}

/// 打开失败时打印结构化错误并退出（open/echo/stress 共用）。
func openOrReport(_ adapter: SerialGateAdapter, configuration: SerialConfiguration) async {
    do {
        try await adapter.open(configuration: configuration)
    } catch let error as SerialError {
        print("open 失败: category=\(error.category.rawValue) code=\(error.systemCode.map(String.init) ?? "-") domain=\(error.systemDomain ?? "-") retryable=\(error.isRetryable)\n  \(error.userMessage)")
        exit(1)
    } catch {
        print("open 失败: \(error)")
        exit(1)
    }
}

func runOpen(path: String, baud: Int, seconds: UInt64) async throws {
    let adapter = SerialGateAdapter()
    await openOrReport(adapter, configuration: makeConfiguration(path: path, baud: baud))
    print("open 成功: \(path) baud=\(baud)")
    print("termios 核对: \(dumpTermios(path: path))")
    if seconds > 0 {
        print("保持 \(seconds)s ...")
        try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
    }
    await adapter.close()
    print("close 完成")
}

func runEcho(path: String, baud: Int, seconds: UInt64) async throws {
    let adapter = SerialGateAdapter()
    await openOrReport(adapter, configuration: makeConfiguration(path: path, baud: baud))
    print("echo 开始: \(path) baud=\(baud) \(seconds)s（需 TX/RX 短接或对端回显）")
    let inbox = ByteInbox()
    let receiveTask = Task {
        do {
            for try await chunk in adapter.incomingBytes() { await inbox.append(chunk) }
        } catch let error as SerialError {
            print("读流终止: category=\(error.category.rawValue) \(error.userMessage)")
        }
    }
    var sentBytes = 0
    var receivedBytes = 0
    var rounds = 0
    var mismatches = 0
    let deadline = Date().addingTimeInterval(TimeInterval(seconds))
    while Date() < deadline {
        rounds += 1
        var pattern = Data()
        for i in 0..<64 { pattern.append(UInt8(truncatingIfNeeded: rounds &+ i)) }
        do {
            try await adapter.write(pattern)
        } catch let error as SerialError {
            print("write 失败: category=\(error.category.rawValue) \(error.userMessage)")
            break
        }
        sentBytes += pattern.count
        if let echoed = await inbox.take(count: pattern.count, timeoutMs: 1000) {
            receivedBytes += echoed.count
            if echoed != pattern { mismatches += 1 }
        } else {
            mismatches += 1
        }
    }
    receiveTask.cancel()
    print("echo 结果: sent=\(sentBytes)B received=\(receivedBytes)B rounds=\(rounds) mismatches=\(mismatches)")
    await adapter.close()
}

func runStress(path: String, baud: Int, seconds: UInt64) async throws {
    let adapter = SerialGateAdapter()
    await openOrReport(adapter, configuration: makeConfiguration(path: path, baud: baud))
    print("stress 开始: \(path) baud=\(baud) \(seconds)s 持续读")
    let inbox = ByteInbox()
    let start = Date()
    let receiveTask = Task {
        do {
            for try await chunk in adapter.incomingBytes() { await inbox.append(chunk) }
        } catch let error as SerialError {
            print("读流终止: category=\(error.category.rawValue) \(error.userMessage)")
        }
    }
    try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
    receiveTask.cancel()
    let elapsed = Date().timeIntervalSince(start)
    let totalBytes = await inbox.totalBytes
    let chunkCount = await inbox.chunkCount
    let rate = elapsed > 0 ? Double(totalBytes) / elapsed : 0
    print(String(format: "stress 结果: received=%dB chunks=%d elapsed=%.2fs rate=%.0fB/s", totalBytes, chunkCount, elapsed, rate))
    await adapter.close()
}

/// 跨任务汇聚收到字节的收件箱（echo 等长取数 / stress 计数共用）。
actor ByteInbox {
    private var buffer = Data()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var totalBytes = 0
    private(set) var chunkCount = 0

    func append(_ chunk: Data) {
        buffer.append(chunk)
        totalBytes += chunk.count
        chunkCount += 1
        while !waiters.isEmpty { waiters.removeFirst().resume() }
    }

    /// 等到恰好 count 字节可取（超时返回 nil）；多余字节留在缓冲供下一次取。
    func take(count: Int, timeoutMs: UInt64) async -> Data? {
        let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
        while buffer.count < count {
            if ContinuousClock.now >= deadline { return nil }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters.append(continuation)
            }
        }
        let taken = buffer.prefix(count)
        buffer.removeFirst(taken.count)
        return Data(taken)
    }
}

// MARK: - main

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { usage() }
let command = arguments[1]

switch command {
case "list":
    await runList()
case "open":
    guard arguments.count >= 4, let baud = Int(arguments[3]) else { usage() }
    let seconds = arguments.count >= 5 ? UInt64(arguments[4]) ?? 2 : 2
    try await runOpen(path: arguments[2], baud: baud, seconds: seconds)
case "echo":
    guard arguments.count >= 5, let baud = Int(arguments[3]), let seconds = UInt64(arguments[4]) else { usage() }
    try await runEcho(path: arguments[2], baud: baud, seconds: seconds)
case "stress":
    guard arguments.count >= 5, let baud = Int(arguments[3]), let seconds = UInt64(arguments[4]) else { usage() }
    try await runStress(path: arguments[2], baud: baud, seconds: seconds)
default:
    usage()
}
