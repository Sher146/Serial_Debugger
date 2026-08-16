# 01 · P0 串口技术验证 POC 与 SerialCore 抽象

> 版本：V1.0 ｜ 状态：待执行 ｜ 里程碑交付：POC 报告 + 依赖锁定决定 + 风险清单（回写 00 文档第 9 节 R1）

## 1. 文档信息

| 项 | 内容 |
|---|---|
| 对应阶段 | P0：技术验证（需求文档 §17） |
| 前置文档 | 无（首份执行文档）；执行前必读 `00-开发计划总览.md` 全文 |
| 后续文档 | 02（Domain 层依赖本文档的 SerialCore 契约）、03（SessionCoordinator 依赖 `SerialPorting`） |
| 需求文档依据 | §10（框架与依赖、SerialGate POC 决策）、§10.1（代码签名与权限）、§11.1（核心协议）、§15（可测试性）、§16 AC-01、§18（串口库风险）、§2.3（平台策略） |
| 覆盖验收项 | AC-01 部分（端口发现；实机矩阵见本文档第 4、8 节） |

**本阶段回答的唯一问题：SerialGate 能否作为本项目的串口库？** 同时把上层将永久依赖的 `SerialPorting` 契约（SerialCore 抽象层）一次性定义冻结，保证"换实现不换接口"（需求 §10 依赖决策、§2.3 平台策略）。

## 2. 目标与完成定义（Definition of Done）

逐项勾选，全部完成 P0 才算结束：

- [ ] D1 `Packages/SerialCore` 本地 Swift 包创建完成，包含第 6 节全部 Swift 定义，签名与本文档逐字一致，`swift build` 通过（Swift 6 严格并发检查无警告）。
- [ ] D2 `SerialConfiguration` Codable 双向编解码、Equatable、`SerialError` 字段完整性的单元测试全部通过。
- [ ] D3 `POC/SerialGatePOC` 独立 Swift Package 创建完成，可执行目标能列出端口、打开、写、读、关闭。
- [ ] D4 伪终端（PTY）自动化测试基建可用：`SerialGateAdapter` 对 PTY 从端的发现/打开/参数配置/读写/关闭/从端消失，全部有自动化测试并通过。
- [ ] D5 实机验证矩阵（第 7 节步骤 6）执行完毕：CH340、CP210x、FTDI、CDC-ACM 四类芯片逐项记录结果；缺项标注"未测"并写明原因，不允许留空。
- [ ] D6 沙盒 + 签名构建（Developer ID 或本地开发签名 + App Sandbox entitlement）下，PTY 与至少一类实机芯片的发现/打开/读写通过。
- [ ] D7 依赖登记表 `POC/依赖登记表.md` 填写完成：SerialGate 版本、commit/哈希、许可证、用途、升级策略。
- [ ] D8 POC 报告 `POC/POC报告.md` 完成，含决策门结论（采用 SerialGate / 回退自研适配器）。
- [ ] D9 00 文档第 9 节 R1 行更新为最终决策结果与日期；如 POC 暴露新风险，追加 R6+ 条目。

## 3. 范围

### In scope

- SerialCore 抽象层（协议 + 数据模型 + 错误模型）的定义、包结构与单元测试。
- SerialGate 候选库的 POC：适配器（`SerialGateAdapter`）、CLI 验证工具、PTY 自动化测试、实机验证、沙盒签名验证。
- 回退方案的可行性评估（不自研实现，只验证"自研适配器能做到同一接口"的论证与工作量估算）。
- 依赖登记、POC 报告、决策门结论、风险回写。

### Out of scope（本阶段明确不做）

- 不实现任何 UI（无 SwiftUI/AppKit 代码；验证一律用 CLI 可执行目标与 XCTest）。
- 不实现 `SessionCoordinator`、RX/TX 管线、RecordStore（属于 03 文档）。
- 不接日志系统（JSONL、LogWriter，属于 06 文档）；POC 打印到 stdout 即可。
- 不实现 HEX/ASCII 编解码、校验、状态机（属于 02 文档）。
- 不实现自研 POSIX/termios + IOKit 适配器的完整代码；只有决策门判定回退时，才在 POC 报告批准后另立任务实施，且接口不变。
- 不处理 DTR/RTS 控制线、波特率自定义非标准值的兼容承诺（仅记录实测结果，写入 POC 报告）。

### 明确禁止事项

- 禁止改动 SerialCore 之外的上层目录结构（`App/`、`Features/`、`Domain/`、`Application/` 本阶段不创建）。
- 禁止在 SerialCore 包中 import SerialGate 或任何第三方库——SerialCore 只能依赖 Foundation/Darwin（需求 §10：第三方库仅允许 Infrastructure 引用；抽象层本身零三方依赖）。
- 禁止虚构 SerialGate 的 API 行为：凡适配器代码中调用 SerialGate 的位置，必须以其仓库实际发布版本的 API 为准；实测与文档不符时记录到 POC 报告，不得假设。

## 4. 依赖与前置条件

| 依赖 | 要求 |
|---|---|
| 开发环境 | Xcode 16+（Swift 6 工具链），macOS 14+ 开发机 |
| 候选库 | SerialGate（Swift 6、macOS 13+；以其仓库 README 与发布 tag 为准，SPM 引入，POC 期间锁 commit） |
| 硬件 | CH340、CP210x、FTDI、CDC-ACM 四类 USB-UART 设备各至少一块；CH340 需提前在开发机装好官方驱动并确认系统能识别（驱动问题属系统兼容性提示范畴，需求 §10.1） |
| 回环手段 | TX/RX 短接（跳线）或两块互连设备，用于实机读写自收自发 |
| 签名 | Apple Developer 账号（Developer ID 证书）或至少可生成带 App Sandbox entitlement 的本地签名构建 |
| 知识准备 | Darwin `openpty(3)`/`posix_openpt(3)`、termios、IOKit 串口匹配键（`kIOSerialBSDServiceValue`、`IOCalloutDevice`）概念；不要求自研实现 |

**已知事实（执行时不必再查，但须在 POC 报告中复核）：**
- macOS 串口调用端口为 `/dev/cu.*`，发现时优先展示 `cu.*`（需求 §5.1）。
- PTY 主从对由 `openpty` 创建，从端路径形如 `/dev/ttysNNN`；PTY 不出现 USB 厂商信息，适配器须容忍 `usbVendorID == nil`。
- 沙盒下访问 `/dev/cu.*` 需要 `com.apple.security.device.serial` entitlement（值 YES）。此条必须在 D6 中实测确认，不接受文档推测。

## 5. 涉及文件清单

所有路径相对项目根 `/Users/lucas_wang/Work/Serial_Debugger/`。**只允许新建/修改下表文件。**

| 相对路径 | 新建/修改 | 一句话职责 |
|---|---|---|
| `Packages/SerialCore/Package.swift` | 新建 | SerialCore 本地包定义（library，macOS 14+，Swift 6） |
| `Packages/SerialCore/Sources/SerialCore/SerialPorting.swift` | 新建 | `SerialPorting` 协议（照需求 §11.1 签名） |
| `Packages/SerialCore/Sources/SerialCore/SerialPortDescriptor.swift` | 新建 | 端口描述值类型（路径、可读名称、USB 厂商/产品信息） |
| `Packages/SerialCore/Sources/SerialCore/SerialConfiguration.swift` | 新建 | 串口参数模型（Codable/Equatable）及 DataBits/Parity/StopBits/FlowControl 枚举 |
| `Packages/SerialCore/Sources/SerialCore/SerialConnectionEvent.swift` | 新建 | 连接异步事件枚举 |
| `Packages/SerialCore/Sources/SerialCore/SerialError.swift` | 新建 | 结构化串口错误模型 |
| `Packages/SerialCore/Tests/SerialCoreTests/SerialConfigurationTests.swift` | 新建 | 配置模型 Codable/Equatable/默认值测试 |
| `Packages/SerialCore/Tests/SerialCoreTests/SerialErrorTests.swift` | 新建 | 错误模型字段完整性与可重试判定测试 |
| `POC/SerialGatePOC/Package.swift` | 新建 | POC 包定义：依赖本地 SerialCore + 锁定的 SerialGate |
| `POC/SerialGatePOC/Sources/SerialGateAdapter/SerialGateAdapter.swift` | 新建 | SerialGate → `SerialPorting` 适配器（候选实现） |
| `POC/SerialGatePOC/Sources/SerialGateAdapter/SerialGateErrorMapper.swift` | 新建 | SerialGate 错误 → `SerialError` 分类映射 |
| `POC/SerialGatePOC/Sources/poc-cli/main.swift` | 新建 | CLI 验证工具：list/open/echo/stress/close 子命令 |
| `POC/SerialGatePOC/Tests/SerialGateAdapterTests/Helpers/PseudoTerminal.swift` | 新建 | `openpty` 封装的 PTY 主从对测试工具 |
| `POC/SerialGatePOC/Tests/SerialGateAdapterTests/SerialGateAdapterPTYTests.swift` | 新建 | 适配器对 PTY 的集成测试（发现/打开/读写/拔出/占用） |
| `POC/SerialGatePOC/Tests/SerialGateAdapterTests/ErrorMapperTests.swift` | 新建 | 错误映射单元测试 |
| `POC/SerialGatePOC/SandboxHarness/`（entitlements + 说明脚本，若需 Xcode 工程壳则记录生成方式于 README） | 新建 | D6 沙盒签名验证用最小壳工程材料 |
| `POC/SerialGatePOC/README.md` | 新建 | 构建、运行、实机测试操作步骤（给后续执行者） |
| `POC/依赖登记表.md` | 新建 | 第三方依赖登记（版本/许可证/哈希/升级策略） |
| `POC/POC报告.md` | 新建 | POC 结果与决策门结论（模板见第 7 节步骤 8） |
| `开发计划/00-开发计划总览.md` | 修改 | 仅更新第 9 节 R1 状态及追加新风险条目，其他内容不动 |

> 注：`Package.resolved` 由 SPM 生成、纳入 git，不手工编辑，但哈希值须抄入依赖登记表。

## 6. 接口与数据模型

以下为契约，实现时逐字照抄；签名变更必须回写本文档（00 文档规则 4）。文件头统一加 `import Foundation`。

### 6.1 `SerialPorting`（`SerialPorting.swift`）

```swift
import Foundation

/// 串口访问抽象。上层（Application/Domain）只依赖本协议，
/// 具体实现（SerialGate 适配器或自研 POSIX/termios + IOKit 适配器）
/// 仅存在于 Infrastructure 层，可整体替换而不影响上层。
///
/// 线程模型约定（实现者必须遵守）：
/// - 协议本身要求 `Sendable`；实现通常是 actor 或内部串行队列封装。
/// - `incomingBytes()` 与 `connectionEvents()` 返回的流在未打开状态下应立即结束
///   （finish），不得挂起等待。
/// - `close()` 必须幂等：重复调用、未打开时调用均不抛错。
/// - 设备拔出时：实现必须先通过 `connectionEvents()` 发出 `.deviceRemoved`，
///   再使 `incomingBytes()` 以 `SerialError(category: .deviceRemoved, ...)` 终止。
public protocol SerialPorting: Sendable {
    /// 枚举当前可用串口。macOS 优先返回 /dev/cu.* 调用端口；
    /// 无 USB 信息的端口（如 PTY）USB 字段为 nil。失败时返回空数组，不抛错。
    func availablePorts() async -> [SerialPortDescriptor]

    /// 按给定配置打开并配置串口。
    /// 失败时抛出 `SerialError`（category 覆盖 notFound/busy/permissionDenied/
    /// configurationUnsupported/openFailed）。重复 open 未先 close 属调用方错误，
    /// 实现应抛 `.openFailed` 而非静默复用。
    func open(configuration: SerialConfiguration) async throws

    /// 关闭串口并释放资源，终止两个流。幂等。
    func close() async

    /// 写入原始字节。仅在已打开状态合法；失败抛 `SerialError(.writeFailed)`，
    /// 设备已拔出时抛 `SerialError(.deviceRemoved)`。
    func write(_ data: Data) async throws

    /// RX 字节流。每次读到的数据块作为一个元素产出（不做任何拆分/合并/转码）。
    /// 发生不可恢复错误时以对应 `SerialError` throw 终止。
    func incomingBytes() -> AsyncThrowingStream<Data, Error>

    /// 连接异步事件流（设备拔出等）。`close()` 后 finish。
    func connectionEvents() -> AsyncStream<SerialConnectionEvent>
}
```

### 6.2 `SerialPortDescriptor`（`SerialPortDescriptor.swift`）

```swift
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
```

### 6.3 `SerialConfiguration`（`SerialConfiguration.swift`）

```swift
import Foundation

/// 串口通信参数。Codable 用于设置持久化（需求 §7.1 串口默认值），
/// Equatable 用于"连接过程中锁定参数"的变更检测（需求 §5.1）。
public struct SerialConfiguration: Sendable, Codable, Equatable {
    /// 目标端口路径，对应 SerialPortDescriptor.path。
    public var path: String
    /// 波特率（bps）。常用值见 `CommonBaudRates`；自定义值是否生效取决于驱动，
    /// 本层不校验合法性，由 open 时底层判定并可能抛 configurationUnsupported。
    public var baudRate: Int
    public var dataBits: DataBits
    public var parity: Parity
    public var stopBits: StopBits
    public var flowControl: FlowControl

    public init(
        path: String,
        baudRate: Int = 115200,
        dataBits: DataBits = .eight,
        parity: Parity = .none,
        stopBits: StopBits = .one,
        flowControl: FlowControl = .none
    ) {
        self.path = path
        self.baudRate = baudRate
        self.dataBits = dataBits
        self.parity = parity
        self.stopBits = stopBits
        self.flowControl = flowControl
    }

    public enum DataBits: Int, Sendable, Codable, Equatable, CaseIterable {
        case five = 5, six = 6, seven = 7, eight = 8
    }

    public enum Parity: String, Sendable, Codable, Equatable, CaseIterable {
        case none, even, odd
    }

    public enum StopBits: String, Sendable, Codable, Equatable, CaseIterable {
        case one, two
    }

    public enum FlowControl: String, Sendable, Codable, Equatable, CaseIterable {
        /// 无流控（默认）。
        case none
        /// RTS/CTS 硬件流控。
        case rtsCts
        /// XON/XOFF 软件流控。
        case xonXoff
    }

    /// 常用波特率，供 UI 下拉与测试引用；不构成合法值白名单。
    public static let commonBaudRates: [Int] = [
        300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600,
    ]
}
```

### 6.4 `SerialConnectionEvent`（`SerialConnectionEvent.swift`）

```swift
import Foundation

/// 打开后由底层异步产生的连接事件。
/// 正常 open/close 由调用方发起、不在此流中回显；本流只承载"非调用方发起"的变化。
public enum SerialConnectionEvent: Sendable, Equatable {
    /// 设备被物理拔出或节点消失。发出后 incomingBytes 将以 deviceRemoved 错误终止。
    case deviceRemoved
    /// 底层链路级异常（如帧错误、缓冲溢出）。可恢复性由携带的 SerialError.isRetryable 表达。
    case linkError(SerialError)
}
```

### 6.5 `SerialError`（`SerialError.swift`）

```swift
import Foundation

/// 结构化串口错误（需求 §5.1：分类、系统错误码、用户可读说明、发生时间、是否可重试）。
///
/// - 用户可见文案规则：`userMessage` 存放**开发期英文兜底说明**；
///   正式 UI（04 文档起）必须按 `category` 经 String Catalog 映射 zh-CN 文案，
///   不得直接把底层系统错误串展示给用户（需求 §13）。
public struct SerialError: Error, Sendable, Equatable {
    /// 错误分类，决定 UI 提示策略与重试引导。
    public enum Category: String, Sendable, Codable, Equatable, CaseIterable {
        /// 路径不存在（设备未插入或节点已消失）。
        case portNotFound
        /// 端口被其他进程占用。
        case portBusy
        /// 权限不足（沙盒 entitlement 缺失或节点权限拒绝）。
        case permissionDenied
        /// 参数组合不被设备/驱动支持（如该芯片不支持的波特率）。
        case configurationUnsupported
        /// open 调用的其他失败。
        case openFailed
        /// 读失败（非拔出原因）。
        case readFailed
        /// 写失败（非拔出原因）。
        case writeFailed
        /// 设备拔出导致的终止。
        case deviceRemoved
        /// 操作超时。
        case timeout
    }

    public let category: Category
    /// 底层系统错误码（POSIX errno 或 IOKit 返回码）；无对应值为 nil。
    public let systemCode: Int?
    /// 错误域标识（如 "NSPOSIXErrorDomain"、"IOKit"）；无对应值为 nil。
    public let systemDomain: String?
    /// 开发期英文兜底说明；正式 UI 按 category 走 String Catalog，不直接展示本字段。
    public let userMessage: String
    /// 发生时间（UTC）。
    public let occurredAt: Date
    /// 是否值得重试（如 portBusy 提示用户释放后重试；deviceRemoved 引导重插）。
    public let isRetryable: Bool

    public init(
        category: Category,
        systemCode: Int? = nil,
        systemDomain: String? = nil,
        userMessage: String,
        occurredAt: Date = Date(),
        isRetryable: Bool
    ) {
        self.category = category
        self.systemCode = systemCode
        self.systemDomain = systemDomain
        self.userMessage = userMessage
        self.occurredAt = occurredAt
        self.isRetryable = isRetryable
    }
}

extension SerialError {
    /// errno → Category 的标准映射。各适配器（SerialGate / 自研）统一使用，
    /// 保证上层看到的分类与底层实现无关。
    public static func mapErrno(
        _ code: Int32,
        operation: String,
        path: String,
        occurredAt: Date = Date()
    ) -> SerialError {
        let domain = "NSPOSIXErrorDomain"
        let message = String(cString: strerror(code))
        switch code {
        case ENOENT:
            return SerialError(category: .portNotFound, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed: port \(path) does not exist (\(message))",
                               occurredAt: occurredAt, isRetryable: false)
        case EBUSY:
            return SerialError(category: .portBusy, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed: port \(path) is busy (\(message))",
                               occurredAt: occurredAt, isRetryable: true)
        case EPERM, EACCES:
            return SerialError(category: .permissionDenied, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed: permission denied for \(path) (\(message))",
                               occurredAt: occurredAt, isRetryable: false)
        case EINVAL, ENOTSUP:
            return SerialError(category: .configurationUnsupported, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed: unsupported configuration for \(path) (\(message))",
                               occurredAt: occurredAt, isRetryable: false)
        case EIO:
            // EIO 在读写路径上通常意味着设备消失；open 路径按 openFailed 处理由调用方决定，
            // 此处保守映射为 deviceRemoved 需调用方覆写时直接构造。
            return SerialError(category: .deviceRemoved, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed: device at \(path) went away (\(message))",
                               occurredAt: occurredAt, isRetryable: true)
        case ETIMEDOUT, EAGAIN:
            return SerialError(category: .timeout, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) timed out on \(path) (\(message))",
                               occurredAt: occurredAt, isRetryable: true)
        default:
            return SerialError(category: .openFailed, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed on \(path) (\(message))",
                               occurredAt: occurredAt, isRetryable: true)
        }
    }
}
```

> 说明：原文档写作 `case EBUSY, EACCES where code == EBUSY:`，Swift 6 编译器对其报 "'where' only applies to the second pattern match" 警告（非重复 case 错误）；按本节原定指示做最小调整，保留 `case EBUSY:` 单独分支，EACCES 仍由下方 `case EPERM, EACCES:` 映射为 permissionDenied。已于 P0 步骤 1 回写本代码块。

### 6.6 适配器实现要点（SerialGateAdapter，非契约，属 POC 工作产物）

- 用 `actor SerialGateAdapter: SerialPorting` 实现；内部持有 SerialGate 的端口对象。
- `availablePorts()`：调用 SerialGate 枚举，过滤/排序为 `cu.*` 优先；USB VID/PID 若 SerialGate 不暴露，用 IOKit（`IOServiceGetMatchingServices` + `kIOSerialBSDServiceValue`）补齐，此逻辑属适配器内部，不进 SerialCore。
- `incomingBytes()`：把 SerialGate 的数据回调/轮询桥接为 `AsyncThrowingStream`，用 continuation 缓冲；`close()` 与拔出时正确 finish/throw。
- 拔出检测：若 SerialGate 无事件回调，用 IOKit 通知（`IOServiceAddInterestNotification`）或读失败 EIO 兜底；无论哪条路径，最终都必须满足 6.1 协议注释中的"先事件、后流终止"顺序。
- 错误一律经 `SerialGateErrorMapper` 或 `SerialError.mapErrno` 转成 `SerialError` 再抛出，禁止把 SerialGate 自有错误类型泄漏给上层。

## 7. 实现步骤

按依赖顺序执行；每步完成立即执行自验证，红了先修再继续（00 文档规则 7）。

### 步骤 1：创建 SerialCore 本地包
- 做什么：创建 `Packages/SerialCore/Package.swift`（`// swift-tools-version: 6.0`，library target `SerialCore`，`platforms: [.macOS(.v14)]`，仅依赖 Foundation），以及 6.1–6.5 五个源文件。
- 产出：第 5 节文件清单第 1–6 行。
- 自验证：`cd Packages/SerialCore && swift build` 通过，零警告；`grep -rn "import SerialGate" Sources/` 无输出。

### 步骤 2：SerialCore 单元测试
- 做什么：写 `SerialConfigurationTests`（Codable 编码→解码往返相等；各枚举 CaseIterable 计数符合预期；默认值为 115200/8/N/1/无流控）与 `SerialErrorTests`（`mapErrno` 对 ENOENT/EBUSY/EPERM/EINVAL/EIO/ETIMEDOUT 的分类与 isRetryable 断言；`occurredAt` 注入相等；Equatable 可用）。
- 产出：第 5 节清单第 7–8 行。
- 自验证：`swift test` 全绿。

### 步骤 3：登记依赖并创建 POC 包
- 做什么：
  1. 先填 `POC/依赖登记表.md`（模板：名称｜仓库 URL｜引入版本/commit｜Package.resolved 哈希｜许可证类型与原文链接｜用途｜升级策略：V1.0 内锁 commit，仅安全修复允许升级，升级需重跑本文档全部验证矩阵｜登记日期）。**先登记后引入**（00 文档第 5 节）。
  2. 创建 `POC/SerialGatePOC/Package.swift`：targets = library `SerialGateAdapter`（依赖 `../Packages/SerialCore` 与 SerialGate）+ executable `poc-cli` + testTarget `SerialGateAdapterTests`。SerialGate 以 `.package(url:branch 或 revision:)` 锁 commit。
- 产出：依赖登记表初版 + POC 包骨架。
- 自验证：`cd POC/SerialGatePOC && swift build` 通过；`Package.resolved` 中 SerialGate 的 revision 与登记表一致。

### 步骤 4：实现 SerialGateAdapter + 错误映射
- 做什么：按 6.6 要点实现 `SerialGateAdapter` 与 `SerialGateErrorMapper`。凡 SerialGate API 语义不确定处，先写最小验证代码实测，再定实现；实测结论记入 POC 报告附录。
- 产出：清单第 10–11 行。
- 自验证：`swift build` 通过；`ErrorMapperTests`（对能构造的 SerialGate 错误/errno 断言映射结果）全绿。

### 步骤 5：PTY 自动化测试基建与集成测试
- 做什么：
  1. `PseudoTerminal.swift`：用 `openpty(_:_:_:_:_:)` 创建主从对，暴露 `masterFD: Int32`、`slavePath: String`；提供 `closeMaster()`（模拟拔出，从端读将得到 EIO）、`closeSlave()`；deinit 关闭句柄。
  2. `SerialGateAdapterPTYTests` 用例：
     - `testAvailablePortsContainsPTYSlave`（若 SerialGate 枚举不含 ttys 节点，则跳过发现用例并记录到 POC 报告——PTY 主要用于打开/读写验证）；
     - `testOpenConfiguresBaudRate`：打开后对从端 `tcgetattr` 断言 `cfgetispeed` 与配置一致；
     - `testWriteBytesArriveAtMaster`：write 后从 masterFD 读到相同字节；
     - `testIncomingBytesFromMaster`：向 masterFD 写入，断言 `incomingBytes()` 产出相同 Data；
     - `testMasterCloseTerminatesStreamWithDeviceRemoved`：closeMaster 后断言流以 `SerialError(.deviceRemoved)` 终止，且 `connectionEvents()` 先收到 `.deviceRemoved`（顺序断言：先收事件再收流终止）；
     - `testOpenBusyPortThrowsPortBusy`：同一 slavePath 用两个独立底层句柄打开，第二次应抛 `.portBusy`；
     - `testCloseIsIdempotent`、`testWriteAfterCloseThrows`。
- 产出：清单第 12–14 行。
- 自验证：`swift test` 全绿；单独跑拔出力用例 20 次无 flaky（`for i in {1..20}; do swift test --filter testMasterCloseTerminatesStream || break; done`）。

### 步骤 6：实机验证矩阵
- 做什么：实现 `poc-cli`（子命令：`list`、`open <path> <baud>`、`echo <path> <baud> <seconds>` 自环收发统计、`stress <path> 115200 60` 持续读统计字节数与耗时）后，按下表逐格执行并记录结果（✅/❌/未测+原因）。回环收发用跳线短接 TX/RX。
- 矩阵（每个 ❌ 必须在 POC 报告中给出 SerialGate 侧证据与影响评估）：

| 芯片 \ 项目 | 发现（VID/PID/名称正确） | 打开 | 参数配置（9600 与 115200 tcgetattr 核对） | 写→回环收 | 读（设备侧发 1KB） | 热拔出（事件顺序+无崩溃） | 占用冲突（screen 占用后打开→portBusy） | 沙盒签名构建下前三项 |
|---|---|---|---|---|---|---|---|---|
| CH340 | | | | | | | | |
| CP210x | | | | | | | | |
| FTDI | | | | | | | | |
| CDC-ACM | | | | | | | | |

- 附加记录：各芯片实测支持的最高波特率、不支持的 parity/flowControl 组合。
- 产出：填好的矩阵（进 POC 报告）、poc-cli。
- 自验证：矩阵无空格；每条 ❌ 有对应报告条目。

### 步骤 7：沙盒 + 签名构建验证（D6）
- 做什么：在 `SandboxHarness/` 准备最小 App 壳（或 `poc-cli` 的 sandbox 打包脚本）：`com.apple.security.app-sandbox = YES` + `com.apple.security.device.serial = YES`，本地开发签名；运行 list/open/echo。再单独构建一个**不带** serial entitlement 的对照包，确认打开失败且映射为 `.permissionDenied`（这同时验证了错误分类正确）。
- 产出：SandboxHarness 材料 + 报告中的验证记录。
- 自验证：带 entitlement 构建下至少一类实机 + PTY 通过；对照包抛 `.permissionDenied`。

### 步骤 8：决策门、报告与回写
- 做什么：
  1. 按第 8 节判定标准下结论。
  2. 完成 `POC/POC报告.md`，结构固定：①结论（采用/回退）②判定标准逐项对照表 ③实机矩阵 ④SerialGate API 实测与文档差异 ⑤错误映射覆盖度 ⑥回退方案论证与工作量估算 ⑦遗留风险。
  3. 更新依赖登记表为最终状态（采用→升级策略生效；回退→SerialGate 标记"未采用"并移除依赖）。
  4. 修改 `00-开发计划总览.md` 第 9 节：R1 状态改为"已决策（采用 SerialGate X.Y / 回退自研适配器）+ 日期"；新风险按 R6+ 追加。
- 产出：清单第 16–18 行 + 00 文档更新。
- 自验证：报告含结论且每个判定标准有对应行；00 文档 diff 只触及第 9 节。

## 8. 验收标准

映射需求文档 §16：

| 编号 | 描述 | 本阶段验收方式 |
|---|---|---|
| AC-01（部分） | 端口发现：插入/拔出常见 USB-UART 后刷新可正确更新列表；异常端口不导致崩溃 | 实机矩阵"发现"列全 ✅；PTY 发现用例通过或记录在案；对不存在路径 open 抛 `.portNotFound` 而非崩溃 |
| AC-02（前置铺垫） | 连接状态机 | 本阶段不实现状态机，只保证协议事件顺序契约（6.1 注释）在适配器中成立，供 03 文档消费 |

### 决策门判定标准（SerialGate 通过条件）

全部满足判"采用"：
1. 四类实机芯片的发现、打开、9600/115200 配置、回环读写、热拔出——全部 ✅（允许个别"参数配置"项 ❌ 且有文档化的绕行方案并登记风险）。
2. 热拔出在 PTY 与实机下均满足"先 `.deviceRemoved` 事件、后流终止、无崩溃、可重新 open"。
3. 占用冲突正确映射为 `.portBusy`，权限缺失映射为 `.permissionDenied`。
4. 沙盒 + 签名构建下功能正常（D6）。
5. 许可证与项目兼容，依赖登记完整。

### 回退触发自研适配器的条件

任一满足即判"回退"，回退后实施项目内 POSIX/termios + IOKit 适配器，**接口不变、上层不改**：
- 任一判定标准 1–4 不满足且 POC 中找不到可靠绕行；
- SerialGate 维护状态/许可证在登记环节发现不可接受（如许可证缺失、仓库归档）；
- 严格并发（Swift 6）下适配器无法消除 data race 警告或存在实测竞态崩溃。

回退时的工作量估算（供决策参考，非本阶段任务）：termios 打开/配置/读写约 2–3 天，IOKit 发现 + 拔出通知约 1–2 天，复用本阶段 PTY 测试基建与错误映射，全部 `SerialGateAdapterTests` 改为针对新适配器运行。

## 9. 测试要求

| 测试文件 | 用例清单 |
|---|---|
| `Packages/SerialCore/Tests/SerialCoreTests/SerialConfigurationTests.swift` | Codable 往返相等；默认配置值断言；DataBits/Parity/StopBits/FlowControl 的 CaseIterable 完整性；commonBaudRates 含 9600 与 115200 |
| `Packages/SerialCore/Tests/SerialCoreTests/SerialErrorTests.swift` | mapErrno 六类 errno 分类断言；isRetryable 取值断言；occurredAt 可注入；两个字段相同的 SerialError 相等 |
| `POC/SerialGatePOC/Tests/SerialGateAdapterTests/ErrorMapperTests.swift` | 可构造的 SerialGate 错误 → Category 映射断言；未知错误 → openFailed/readFailed/writeFailed 兜底断言 |
| `POC/SerialGatePOC/Tests/SerialGateAdapterTests/SerialGateAdapterPTYTests.swift` | 步骤 5 列出的 8 个用例；拔出力用例 20 连跑无 flaky |

要求：`swift test` 在 `Packages/SerialCore` 与 `POC/SerialGatePOC` 两个包内分别全绿；测试不依赖实机硬件（实机项只在 poc-cli 手动矩阵中执行）；PTY 测试须兼容 CI 无 TTY 环境（openpty 自身创建伪终端，不依赖宿主 tty）。

## 10. 防漫游约束

1. 只做第 5 节文件清单内的文件；发现需要新增/修改清单外文件时，停止该分支工作，把情况追加记录到 00 文档第 9 节（R6 起），等待指示，不自行扩大范围。
2. 不引入本文件未列出的第三方依赖；SerialGate 必须先登记（步骤 3）后引入；socat、pyserial 等外来工具仅可作手动对照手段，不得进包、进测试。
3. 不实现 Out of scope 列出的任何内容（UI、SessionCoordinator、日志、编码校验、状态机）。
4. 第 6 节 Swift 定义是契约，逐字照抄；确有实现障碍（如编译器对 mapErrno switch 的限制）时，先做最小可行调整并**回写本文档对应代码块**，不静默改签名。
5. 每个实现步骤完成后必须执行其自验证命令，红了先修，不跳过。
6. SerialGate 实际行为与其文档/本文件假设矛盾时，记录到 POC 报告附录；若矛盾影响判定标准，按回退触发条件处理，不自行发明补丁式需求。
7. 需求文档内部、或需求文档与本文件矛盾时，记录到 00 文档第 9 节并停止相关工作分支，不自行取舍。
