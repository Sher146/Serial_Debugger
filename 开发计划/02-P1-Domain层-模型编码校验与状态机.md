# 02 · P1 Domain 层：模型、编码校验与状态机

> 版本：V1.0 ｜ 状态：开发基线 ｜ 上游权威：《设计与需求文档.html》§5.2、§5.3、§9、§11、§12.1、§14、§15、§16；《00-开发计划总览.md》；01 文档（SerialCore 契约）；03 文档（本文档契约的第一消费方）

---

## 1. 文档信息

| 项 | 内容 |
|---|---|
| 对应阶段 | P1 核心会话（需求文档 §17）之 Domain 层部分：模型、编码/校验、状态机、内存记录仓库、安全清洗 |
| 前置文档 | 00（全局约定，必读全文）、01（SerialCore 抽象：`SerialConfiguration`/`SerialError` 等，本文档直接引用、不重复定义） |
| 后续文档 | 03（SessionCoordinator 直接消费本文档全部契约，其 §4.3 假定签名以本文档 §6 为准）、05（预设快照/间隔校验）、06（日志文件名生成） |
| 需求文档依据 | §5.2（接收记录）、§5.3（发送与校验）、§9（分层约束：Domain 不得依赖第三方串口库/SwiftUI/AppKit）、§11（核心协议与状态机）、§12.1（数据管线与缓存）、§14（安全清洗）、§15（可测试性）、§16（AC-03/AC-04 部分） |
| 覆盖验收项 | AC-02 部分（状态机合法性）、AC-03 部分（原始字节保存与展示投影）、AC-04 部分（HEX/ASCII 校验与编码） |

**分层纪律（需求 §9）**：本文档全部代码只允许 `import Foundation` 与 `import SerialCore`（01 交付的第一方抽象包，零三方依赖）。出现 `import SwiftUI` / `import AppKit` / 任何第三方库即为越界。

---

## 2. 目标与完成定义（Definition of Done）

逐项勾选，全部完成本阶段才算结束：

- [ ] D1 第 5 节文件清单全部创建，Swift 定义与本文档 §6 逐字一致，`swift build`（或 Xcode 构建）通过，Swift 6 严格并发检查零警告。
- [ ] D2 `CommunicationRecord` / `Direction` / `DisplayFormat` / `SendSource` / `SendResult` / `PresetSnapshot` / `LineEnding` 模型就位，与 03 文档 §4.3 假定签名完全一致。
- [ ] D3 `SessionState` + `SessionStateEvent` + `SessionStateMachine` 实现 §6.4 转换表全部 8 行合法转换；非法组合一律返回 `nil`；`SessionStateEvent.from(target:)` 辅助就位（03 §6.4 `transition(to:)` 依赖它）。
- [ ] D4 HEX 编解码器：允许 Unicode 空白与配置分隔符；非法字符（带原始输入定位）、奇数长度报 `.invalidHex`；空数据报 `.emptyPayload`；ASCII 编解码含 U+FFFD 占位策略；行结束符追加逻辑就位。
- [ ] D5 `ValidationError` 五个 case（invalidHex/emptyPayload/invalidInterval/notConnected/invalidSetting）均携带用户可读说明（英文兜底 + String Catalog key）。
- [ ] D6 `RecordStore` actor 就位：双阈值（50,000 条 / 16 MiB，可配置）淘汰最早项；暴露累计截断统计与最后截断时间；惰性展示投影接口就位；下调配置立即裁剪。
- [ ] D7 展示格式化器：HEX 显示（分隔符/大小写/每行字节数）、ASCII 显示（占位）、时间戳 `HH:MM:SS.mmm` 全部纯函数且有测试。
- [ ] D8 `PathSanitizer` 与 `LogFileNameGenerator` 就位，注入攻击用例全绿；文件名格式严格为 `SerialMonitor_yyyyMMdd_HHmmss_<port>.log`。
- [ ] D9 第 9 节全部单元测试通过；测试不依赖硬件、不依赖 UI。
- [ ] D10 未创建清单外文件、未引入任何第三方依赖；如发现与 01/03 的签名级冲突，已按第 10 节记录到 00 文档第 9 节。

---

## 3. 范围

### In scope

- Domain 全部值类型与错误模型：记录模型、枚举、配置别名、`ValidationError`、`SessionError`/`SessionErrorContext`。
- 连接状态机 `SessionStateMachine`（纯函数，可用事件序列单测驱动）。
- 编码与校验：HEX 解码（校验一体）、HEX 紧凑编码、文本（ASCII/UTF-8 等）编解码与占位策略、行结束符追加、发送载荷组装（校验 + 编码 + 行结束符）、自动发送间隔校验常量。
- `RecordStore` actor：容量策略、截断统计、惰性展示投影。
- 展示格式化纯函数：HEX 显示、ASCII 显示、时间戳 `HH:MM:SS.mmm`。
- 安全清洗与日志文件名生成纯函数。
- 上述全部内容的纯 Swift 单元测试。

### Out of scope（本阶段明确不做）

- 不实现 `SessionCoordinator`、TX 队列、RX 管线、事件流（03）。
- 不实现任何 UI、ViewModel、String Catalog 文案（04 起）；本文档只提供 catalog key 与英文兜底说明。
- 不实现 JSONL 落盘、日志轮转、崩溃恢复标记（06）；只提供文件名生成纯函数。
- 不实现预设持久化模型（05）；只提供 `PresetSnapshot` 值类型与间隔校验。
- 不实现自动发送/预设循环任务体（05）；只提供 `SendIntervalLimits` 校验。
- 不修改 01 已交付的 SerialCore 包内任何文件（允许在 Domain 中以 `extension` 做纯增量补充，见 §6.2）。

### 明确禁止事项

- 禁止 `import SwiftUI` / `import AppKit` / 任何第三方库（需求 §9 Domain 层约束）。
- 禁止在 Domain 引入 actor 以外的共享可变状态；纯函数不得读写全局可变变量。
- 禁止照抄 Figma 原型的已知瑕疵：原型 HEX 显示按 `charCode` 逐字符转字节（`设计图/src/types.ts` 及组件内 `isValidHex` 仅做正则校验，显示路径把 JS 字符串按 UTF-16 code unit 处理），**SwiftUI 版必须一律按 UTF-8 字节转换**；原型 `isValidHex` 不识别配置分隔符，本实现必须支持。
- 禁止把底层系统错误串直接作为用户文案（需求 §13）；`userMessage` 仅作开发期英文兜底。

---

## 4. 依赖与前置条件

| 依赖 | 要求 |
|---|---|
| 01 文档 | 已完成 D1–D2：`Packages/SerialCore` 包存在，`SerialConfiguration`（含嵌套 `DataBits`/`Parity`/`StopBits`/`FlowControl`）与 `SerialError` 可 import。本文档 §6.2 直接引用，**不得重复定义**。 |
| 工具链 | Xcode 16+ / Swift 6 工具链；严格并发检查开启（`SWIFT_STRICT_CONCURRENCY = complete` 或 SPM `swift-tools-version: 6.0`）。 |
| 工程壳 | 主 App 工程 `SerialMonitor`（含 Unit Test target，macOS 14+，Swift 6）。**若执行时尚不存在**（01 只创建了 Packages），按 §7 步骤 0 创建最小工程壳：空 App 入口 + Unit Test target，并把 `Packages/SerialCore` 作为本地包依赖挂入；此属清单内允许项，完成后在 00 文档第 9 节追加一条记录说明。 |
| 03 文档 | 仅作契约消费方参考（§4.3 假定签名），本阶段不读其实现章节亦可执行。 |

**已核对的跨文档事实（执行时不必再查）：**

- 03 §4.3 假定：`SessionState` 五态携带 `configuration`/`session`/`previous`/`context` 关联值；`SessionError.Category` 六分类；`RecordStore` 为 actor 且暴露 `append/updateSendResult/record/counters`；`ValidationError.invalidSetting(String)` 与 `.notConnected`。本文档 §6 与之逐字对齐。
- 03 §6.4 骨架引用 `SessionStateEvent.from(target:)` 与 `SerialConfiguration.default`：两者均由本文档提供（§6.4、§6.2），补齐了 03 标注的潜在缺口。
- 需求 §6.1 日志样例中 RX 记录 `"source":"serial"`，故 `SendSource` 必须含 `.serial` 案（RX 记录恒用 `.serial`；§11.1 表格只列 manual/autoSend/preset 是指 TX 来源）。此点已在 00 文档规则下按"需求文档内部样例优先"解决，不构成矛盾。

---

## 5. 涉及文件清单

所有路径相对项目根 `/Users/lucas_wang/Work/Serial_Debugger/`。**只允许新建/修改下表文件。**

| 相对路径 | 新建/修改 | 一句话职责 |
|---|---|---|
| `SerialMonitor.xcodeproj`（或等价 SPM 工程壳） | 新建（仅当不存在） | 最小 App 工程壳：空 App 入口 + Unit Test target + 本地包 SerialCore 依赖 |
| `SerialMonitor/Domain/Models/CommunicationRecord.swift` | 新建 | 记录模型 + `Direction`/`DisplayFormat`/`SendSource`/`SendResult`/`PresetSnapshot` |
| `SerialMonitor/Domain/Models/LineEnding.swift` | 新建 | 行结束符枚举与字节追加逻辑 |
| `SerialMonitor/Domain/Models/SerialParameterAliases.swift` | 新建 | 01 嵌套枚举的顶层别名 + `SerialConfiguration.default` 增量扩展 |
| `SerialMonitor/Domain/Errors/ValidationError.swift` | 新建 | `ValidationError` + `HexInputError` + `SendIntervalLimits` |
| `SerialMonitor/Domain/Errors/SessionError.swift` | 新建 | `SessionError` + `SessionErrorContext`（Domain 结构化错误） |
| `SerialMonitor/Domain/StateMachine/SessionState.swift` | 新建 | `SessionState` 五态 + `ConnectedSession` + 状态便利属性 |
| `SerialMonitor/Domain/StateMachine/SessionStateMachine.swift` | 新建 | `SessionStateEvent` + 纯函数转换表 + `from(target:)` 辅助 |
| `SerialMonitor/Domain/Encoding/HexCodec.swift` | 新建 | HEX 解码（校验一体，带定位）与紧凑编码 |
| `SerialMonitor/Domain/Encoding/TextPayloadCodec.swift` | 新建 | 文本编码发送 / 接收字节按编码解码（U+FFFD 占位策略） |
| `SerialMonitor/Domain/Encoding/SendPayloadEncoder.swift` | 新建 | 发送载荷组装：校验 + 编码 + 行结束符 |
| `SerialMonitor/Domain/Records/RecordStore.swift` | 新建 | 内存记录仓库 actor：容量淘汰、截断统计、惰性投影 |
| `SerialMonitor/Domain/Formatting/DisplayFormatter.swift` | 新建 | HEX/ASCII 显示格式化与时间戳 `HH:MM:SS.mmm` 纯函数 |
| `SerialMonitor/Domain/Security/PathSanitizer.swift` | 新建 | 文件名/端口名/预设名路径安全清洗 |
| `SerialMonitor/Domain/Security/LogFileNameGenerator.swift` | 新建 | 日志文件名生成纯函数 |
| `SerialMonitor/Tests/Unit/HexCodecTests.swift` | 新建 | HEX 编解码全部边界用例 |
| `SerialMonitor/Tests/Unit/TextPayloadCodecTests.swift` | 新建 | 文本编解码与占位策略用例 |
| `SerialMonitor/Tests/Unit/SendPayloadEncoderTests.swift` | 新建 | 行结束符与载荷组装用例 |
| `SerialMonitor/Tests/Unit/SessionStateMachineTests.swift` | 新建 | 转换表全覆盖 + 非法矩阵 + 事件序列用例 |
| `SerialMonitor/Tests/Unit/RecordStoreTests.swift` | 新建 | 条数/字节双阈值截断、统计、投影用例 |
| `SerialMonitor/Tests/Unit/DisplayFormatterTests.swift` | 新建 | HEX/ASCII 显示与时间戳格式用例 |
| `SerialMonitor/Tests/Unit/PathSanitizerTests.swift` | 新建 | 清洗注入攻击与文件名生成用例 |
| `开发计划/00-开发计划总览.md` | 修改（仅必要时） | 仅当发现矛盾/缺口或创建了工程壳时，追加第 9 节风险条目，其他内容不动 |

> 不修改 01 的 `Packages/SerialCore/**` 任何文件；Domain 对 01 类型只做顶层 `typealias` 与纯增量 `extension`。

---

## 6. 接口与数据模型（可直接照抄）

以下为契约，实现时逐字照抄；签名变更必须回写本文档（00 文档规则 4）。除标注 `import SerialCore` 的文件外，文件头统一 `import Foundation`。

### 6.1 记录模型与枚举（`CommunicationRecord.swift`）

```swift
import Foundation

/// 收发方向。
public enum Direction: String, Sendable, Codable, Equatable, CaseIterable {
    case rx
    case tx
}

/// 展示/输入编码格式。注意：这只是原始字节的投影方式，
/// 切换格式不得改写任何已存储的 rawBytes（需求 §12.1）。
public enum DisplayFormat: String, Sendable, Codable, Equatable, CaseIterable {
    case ascii
    case hex
}

/// 记录来源。RX 记录恒为 `.serial`（对端设备，对应需求 §6.1 日志样例 "source":"serial"）；
/// TX 记录为 manual / autoSend / preset 之一（需求 §11.1）。
public enum SendSource: String, Sendable, Codable, Equatable, CaseIterable {
    case serial
    case manual
    case autoSend
    case preset
}

/// 发送结果。RX 记录恒为 `.success`（到达即成功）；TX 记录排入队列时为 `.pending`，
/// 写完成回填 `.success`，写失败回填 `.failed(reason)`（需求 §5.3）。
public enum SendResult: Sendable, Equatable {
    case pending
    case success
    case failed(reason: String)
}

/// 预设快照（需求 §5.4：每次实际发送均生成带 presetID 与 presetName 快照的 TX 记录）。
/// 快照在发送瞬间取值，之后预设改名/删除不影响历史记录。
/// - 约定：05 文档的预设模型必须以 UUID 作为主键 id（Figma 原型的字符串 id 仅作参考）。
public struct PresetSnapshot: Sendable, Equatable {
    public let presetID: UUID
    public let presetName: String

    public init(presetID: UUID, presetName: String) {
        self.presetID = presetID
        self.presetName = presetName
    }
}

/// 一条 RX/TX 通信记录（需求 §11.1）。原始字节为唯一事实来源；
/// displayFormat 仅记录"产生时的偏好"，展示字符串一律由 DisplayFormatter 惰性投影。
public struct CommunicationRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// 产生时间（RX=数据块到达时间，TX=排入队列时间）。
    public let timestamp: Date
    public let direction: Direction
    /// 原始字节。任何展示/编码切换都不得修改本字段。
    public let rawBytes: Data
    public let displayFormat: DisplayFormat
    public let source: SendSource
    public var sendResult: SendResult
    /// source == .preset 时必有值；其余来源为 nil。
    public let presetSnapshot: PresetSnapshot?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        direction: Direction,
        rawBytes: Data,
        displayFormat: DisplayFormat,
        source: SendSource,
        sendResult: SendResult,
        presetSnapshot: PresetSnapshot? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.rawBytes = rawBytes
        self.displayFormat = displayFormat
        self.source = source
        self.sendResult = sendResult
        self.presetSnapshot = presetSnapshot
    }

    /// 原始字节数（RecordStore 字节统计用）。
    public var byteCount: Int { rawBytes.count }
}
```

### 6.2 串口参数：引用 01，不重复定义（`SerialParameterAliases.swift`）

`SerialConfiguration` 及其嵌套枚举 `DataBits` / `Parity` / `StopBits` / `FlowControl` 的**唯一定义在 01 文档**（`Packages/SerialCore/Sources/SerialCore/SerialConfiguration.swift`）。本文件只做两件事：顶层别名（Domain 内部书写便利）、纯增量扩展（03 骨架需要的 `.default` 占位）。

```swift
import Foundation
import SerialCore

// MARK: - 顶层别名（定义见 01 文档 §6.3，此处不重复定义）

public typealias DataBits = SerialConfiguration.DataBits
public typealias Parity = SerialConfiguration.Parity
public typealias StopBits = SerialConfiguration.StopBits
public typealias FlowControl = SerialConfiguration.FlowControl

// MARK: - 纯增量扩展（不修改 SerialCore 包内文件）

extension SerialConfiguration {
    /// 占位默认配置（空端口路径）。仅用于"无历史配置"的边角路径
    /// （如 error 上下文 failedConfiguration 为 nil 时的 closing 关联值）。
    public static let `default` = SerialConfiguration(path: "")
}
```

### 6.3 行结束符（`LineEnding.swift`）

```swift
import Foundation

/// 发送行结束符（需求 §5.3 ASCII 模式行）。
public enum LineEnding: String, Sendable, Codable, Equatable, CaseIterable {
    case none
    case cr
    case lf
    case crlf

    /// 追加到载荷尾部的字节序列；none 为空。
    public var bytes: [UInt8] {
        switch self {
        case .none: return []
        case .cr:   return [0x0D]
        case .lf:   return [0x0A]
        case .crlf: return [0x0D, 0x0A]
        }
    }

    /// 返回追加行结束符后的新 Data（不修改入参）。
    public func appending(to data: Data) -> Data {
        var result = data
        result.append(contentsOf: bytes)
        return result
    }
}
```

### 6.4 连接状态机（`SessionState.swift` + `SessionStateMachine.swift`）

`SessionState` 与 03 §4.3 假定签名逐字一致：

```swift
import Foundation
import SerialCore

/// 一次已建立连接的上下文。
public struct ConnectedSession: Sendable, Equatable {
    public let configuration: SerialConfiguration
    public let connectedAt: Date

    public init(configuration: SerialConfiguration, connectedAt: Date) {
        self.configuration = configuration
        self.connectedAt = connectedAt
    }
}

/// 连接状态机（需求 §5.1、§11.1）。任何时刻只能处于一个状态；
/// opening/closing 携带被锁定的配置（连接过程中参数不可编辑，需求 §5.1）。
public enum SessionState: Sendable, Equatable {
    case disconnected
    case opening(configuration: SerialConfiguration)
    case connected(session: ConnectedSession)
    case closing(previous: SerialConfiguration)
    case error(context: SessionErrorContext)
}

public extension SessionState {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    /// 当前状态下被锁定/保留的配置（disconnected 为 nil）。
    var lockedConfiguration: SerialConfiguration? {
        switch self {
        case .disconnected: return nil
        case .opening(let c): return c
        case .connected(let s): return s.configuration
        case .closing(let c): return c
        case .error(let ctx): return ctx.failedConfiguration
        }
    }
}
```

**转换表**（实现即下表的逐行代码化；第 1–7 行照需求 §11.2，第 8 行为支撑 03 `disconnect()` 在 opening 期间取消的扩展行，附加动作由 03 的 SessionCoordinator 落实，本表只裁决合法性）：

| # | 当前状态 | 事件（`SessionStateEvent`） | 下一状态 | 附加动作（03 落实） |
|---|---|---|---|---|
| 1 | disconnected | `.openRequested(c)`（用户打开且参数有效） | opening(c) | 锁定连接参数；取消旧任务 |
| 2 | opening | `.openSucceeded(at:)`（底层打开成功） | connected(session) | 启动 RX Stream；按需启动日志 |
| 3 | opening | `.failureOccurred(e)`（打开失败） | error(context，保留 c) | 保存错误；恢复可编辑配置 |
| 4 | connected | `.closeRequested`（用户关闭） | closing(previous) | 停止发送调度；flush 日志 |
| 5 | connected | `.failureOccurred(e)`（设备移除/不可恢复 I/O） | error(context，保留配置) | 立刻取消发送；保留错误上下文 |
| 6 | closing | `.closeCompleted`（资源关闭完成） | disconnected | 更新 UI，允许新连接 |
| 7 | error | `.openRequested(c)`（重试）/ `.closeRequested`（用户关闭） | opening(c) / closing | **仅显式操作可离开 error** |
| 8 | opening | `.closeRequested`（打开过程中取消） | closing(previous: c) | 尽力关闭底层资源（03 disconnect 的 .opening 分支） |

> 设计说明：需求 §11.2 第 3 行"打开失败"与第 5 行"设备移除/不可恢复 I/O"在状态机层合并为单一事件 `.failureOccurred(SessionError)`——两者目标态相同、合法性规则相同（仅来源态不同），附加动作差异由 03 的 SessionCoordinator 按来源态区分。这样 `from(target:)` 才能从目标态唯一反推事件（03 §6.4 `transition(to:)` 依赖该辅助）。

```swift
import Foundation
import SerialCore

/// 状态机事件。事件语义见上方转换表。
public enum SessionStateEvent: Sendable, Equatable {
    /// 用户显式发起打开（含 error 态重试）。配置已校验有效。
    case openRequested(configuration: SerialConfiguration)
    /// 底层打开成功（at 为连接建立时间，由调用方注入以保证纯函数可测）。
    case openSucceeded(at: Date)
    /// 打开失败（来自 opening）或连接丢失：设备拔出/不可恢复读写错误（来自 connected）。
    case failureOccurred(SessionError)
    /// 用户显式关闭（connected/error），或打开过程中取消（opening）。
    case closeRequested
    /// 底层资源关闭完成（来自 closing）。
    case closeCompleted
}

public extension SessionStateEvent {
    /// 目标态 → 事件的规范映射，供 03 `SessionCoordinator.transition(to:)` 做合法性校验。
    /// 注意这是"意图声明"而非通用反推：仅适用于协调器按转换表发起的合法迁移。
    static func from(target: SessionState) -> SessionStateEvent {
        switch target {
        case .disconnected:
            return .closeCompleted
        case .opening(let configuration):
            return .openRequested(configuration: configuration)
        case .connected(let session):
            return .openSucceeded(at: session.connectedAt)
        case .closing:
            return .closeRequested
        case .error(let context):
            return .failureOccurred(context.error)
        }
    }
}

/// 连接状态机（纯函数裁决器）。非法转换返回 nil；不持有任何状态，可事件序列单测驱动。
public enum SessionStateMachine {
    public static func transition(from state: SessionState, event: SessionStateEvent) -> SessionState? {
        switch (state, event) {
        // 行 1 / 行 7（重试）：disconnected 或 error 显式打开
        case (.disconnected, .openRequested(let configuration)),
             (.error, .openRequested(let configuration)):
            return .opening(configuration: configuration)

        // 行 2：打开成功
        case (.opening(let configuration), .openSucceeded(let at)):
            return .connected(session: ConnectedSession(configuration: configuration, connectedAt: at))

        // 行 3：打开失败，保留当时锁定的配置
        case (.opening(let configuration), .failureOccurred(let error)):
            return .error(context: SessionErrorContext(error: error,
                                                       failedConfiguration: configuration))

        // 行 5：连接丢失，保留会话配置
        case (.connected(let session), .failureOccurred(let error)):
            return .error(context: SessionErrorContext(error: error,
                                                       failedConfiguration: session.configuration))

        // 行 4：用户关闭
        case (.connected(let session), .closeRequested):
            return .closing(previous: session.configuration)

        // 行 7（用户关闭清理）：error → closing；无历史配置时用占位默认配置
        case (.error(let context), .closeRequested):
            return .closing(previous: context.failedConfiguration ?? .default)

        // 行 8：打开过程中取消
        case (.opening(let configuration), .closeRequested):
            return .closing(previous: configuration)

        // 行 6：资源关闭完成
        case (.closing, .closeCompleted):
            return .disconnected

        default:
            return nil
        }
    }
}
```

### 6.5 Domain 错误模型（`SessionError.swift` + `ValidationError.swift`）

`SessionError` 是 Domain/Application 层的结构化错误（需求 §5.1）；01 的 `SerialError` 属 SerialCore 层，由 03 的 `mapOpenError` 映射为本类型。与 03 §4.3 假定签名逐字一致：

```swift
import Foundation
import SerialCore

/// 会话层结构化错误（需求 §5.1：分类、系统错误码、用户可读说明、发生时间、是否可重试）。
public struct SessionError: Error, Sendable, Equatable {
    public enum Category: String, Sendable, Codable {
        case portUnavailable            // 端口不存在 / 被占用
        case openFailed                 // 其他打开失败
        case unsupportedConfiguration   // 配置不支持（如波特率/位组合）
        case deviceDisconnected         // 设备拔出
        case readFailed                 // 读失败
        case writeFailed                // 写失败
    }

    public let category: Category
    /// errno / IOKit code，可空。
    public let systemCode: Int?
    /// 系统描述（开发期英文兜底；UI 按 category 走 String Catalog，需求 §13）。
    public let systemDescription: String
    public let occurredAt: Date
    public let isRetryable: Bool

    public init(
        category: Category,
        systemCode: Int? = nil,
        systemDescription: String,
        occurredAt: Date = Date(),
        isRetryable: Bool
    ) {
        self.category = category
        self.systemCode = systemCode
        self.systemDescription = systemDescription
        self.occurredAt = occurredAt
        self.isRetryable = isRetryable
    }
}

/// error 状态的上下文：保留失败时的配置用于重试（需求 §11.2 行 3/5）。
public struct SessionErrorContext: Sendable, Equatable {
    public let error: SessionError
    /// 打开失败时为当时锁定的配置；防御性可空。
    public let failedConfiguration: SerialConfiguration?

    public init(error: SessionError, failedConfiguration: SerialConfiguration?) {
        self.error = error
        self.failedConfiguration = failedConfiguration
    }
}
```

```swift
import Foundation

/// HEX 输入错误的定位信息（需求 §13：HEX 格式错误须"标记输入位置或错误类型"）。
public struct HexInputError: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// 含非十六进制字符。
        case illegalCharacter
        /// 去除空白与分隔符后字符数为奇数。
        case oddLength
    }

    public let kind: Kind
    /// illegalCharacter 时为该字符；oddLength 为 nil。
    public let character: Character?
    /// illegalCharacter 时为原始输入字符串中的 Character 偏移（0 起），供 UI 高亮定位；
    /// oddLength 为 nil（整体性问题，无单点位置）。
    public let position: Int?

    public init(kind: Kind, character: Character?, position: Int?) {
        self.kind = kind
        self.character = character
        self.position = position
    }
}

/// 发送/设置校验错误（需求 §11.1）。每个 case 经 `userMessage` 携带用户可读说明
/// （开发期英文兜底），`catalogKey` 供 04 起经 String Catalog 映射 zh-CN 文案。
public enum ValidationError: Error, Sendable, Equatable {
    /// HEX 非法字符或奇数长度，携带定位信息。
    case invalidHex(HexInputError)
    /// 空数据（HEX 去空白后无字符 / ASCII 空字符串）。
    case emptyPayload
    /// 自动发送间隔越界（合法区间见 SendIntervalLimits）。
    case invalidInterval(actual: Int, allowed: ClosedRange<Int>)
    /// 未连接状态下尝试发送（需求 §5.3 前置条件）。
    case notConnected
    /// 其他非法设置/状态调用，携带说明或 catalog key。
    case invalidSetting(String)
}

public extension ValidationError {
    /// String Catalog key（04 负责解析渲染；本层不产出 zh-CN 文案）。
    var catalogKey: String {
        switch self {
        case .invalidHex(let detail):
            switch detail.kind {
            case .illegalCharacter: return "validation.hex.illegalCharacter"
            case .oddLength:        return "validation.hex.oddLength"
            }
        case .emptyPayload:    return "validation.emptyPayload"
        case .invalidInterval: return "validation.invalidInterval"
        case .notConnected:    return "validation.notConnected"
        case .invalidSetting:  return "validation.invalidSetting"
        }
    }

    /// 开发期英文兜底说明；正式 UI 不得直接展示（需求 §13，按 catalogKey 映射）。
    var userMessage: String {
        switch self {
        case .invalidHex(let detail):
            switch detail.kind {
            case .illegalCharacter:
                let char = detail.character.map { String($0) } ?? "?"
                let pos = detail.position.map { " at position \($0)" } ?? ""
                return "Invalid HEX character '\(char)'\(pos); only 0-9 A-F allowed"
            case .oddLength:
                return "HEX input must contain an even number of hexadecimal digits"
            }
        case .emptyPayload:
            return "Payload is empty"
        case .invalidInterval(let actual, let allowed):
            return "Interval \(actual) ms is out of range \(allowed.lowerBound)-\(allowed.upperBound) ms"
        case .notConnected:
            return "Port is not connected"
        case .invalidSetting(let message):
            return message
        }
    }
}

/// 自动发送间隔约束（需求 §5.4、§12.2：最小 10ms，默认 1000ms，上限 3,600,000ms）。
public enum SendIntervalLimits {
    public static let minMilliseconds = 10
    public static let maxMilliseconds = 3_600_000
    public static let defaultMilliseconds = 1_000
    public static let allowed: ClosedRange<Int> = minMilliseconds...maxMilliseconds

    /// 校验间隔；越界抛 `.invalidInterval`。
    public static func validate(_ milliseconds: Int) throws {
        guard allowed.contains(milliseconds) else {
            throw ValidationError.invalidInterval(actual: milliseconds, allowed: allowed)
        }
    }
}
```

### 6.6 HEX 编解码（`HexCodec.swift`）

规则（需求 §5.3 HEX 行）：允许空白、换行和配置的分隔符；去除空白（与配置分隔符）后必须为偶数个十六进制字符；非法字符、奇数字符数或空数据均不得发送。错误优先级：扫描中先遇到的非法字符立即报（带定位）→ 无有效字符报空 → 奇数长度。

```swift
import Foundation

/// HEX 输入解码（校验一体）与紧凑编码。展示用格式化（分隔/大小写/换行）见 DisplayFormatter。
public enum HexCodec {
    /// 解码选项。
    public struct Options: Sendable, Equatable {
        /// 除 Unicode 空白（空格/制表符/换行等）外额外允许的分隔符，
        /// 来自设置"HEX 分隔"（如 "-"、","、":"）。
        public var extraSeparators: Set<Character>

        public init(extraSeparators: Set<Character> = []) {
            self.extraSeparators = extraSeparators
        }
    }

    /// 将用户输入的 HEX 文本解码为字节序列。
    /// - Throws: `ValidationError.invalidHex`（非法字符，携带原始输入定位；或奇数长度）、
    ///   `.emptyPayload`（去除空白与分隔符后无任何字符）。
    public static func decode(_ text: String, options: Options = .init()) throws -> Data {
        var digits: [Character] = []
        digits.reserveCapacity(text.count)
        for (offset, character) in text.enumerated() {
            if character.isWhitespace || options.extraSeparators.contains(character) { continue }
            guard character.isASCII, character.isHexDigit else {
                throw ValidationError.invalidHex(
                    HexInputError(kind: .illegalCharacter, character: character, position: offset))
            }
            digits.append(character)
        }
        guard !digits.isEmpty else { throw ValidationError.emptyPayload }
        guard digits.count % 2 == 0 else {
            throw ValidationError.invalidHex(
                HexInputError(kind: .oddLength, character: nil, position: nil))
        }
        var bytes = Data()
        bytes.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            bytes.append(nibble(digits[index]) << 4 | nibble(digits[index + 1]))
            index += 2
        }
        return bytes
    }

    /// 紧凑编码：字节 → 连续大写 HEX（无分隔，如 "55AA01"）。显示用分隔格式见 DisplayFormatter。
    public static func encode(_ data: Data) -> String {
        var result = String()
        result.reserveCapacity(data.count * 2)
        for byte in data {
            result.append(Self.hexDigits[Int(byte >> 4)])
            result.append(Self.hexDigits[Int(byte & 0x0F)])
        }
        return result
    }

    private static let hexDigits: [Character] = Array("0123456789ABCDEF")

    private static func nibble(_ character: Character) -> UInt8 {
        // 调用点已保证 isASCII && isHexDigit
        let value = character.asciiValue!
        switch value {
        case 48...57:  return value - 48        // '0'...'9'
        case 65...70:  return value - 65 + 10   // 'A'...'F'
        default:       return value - 97 + 10   // 'a'...'f'
        }
    }
}
```

> 原型瑕疵修正（00 文档规则 6）：Figma 原型 `isValidHex` 只去 `\s` 且不识别配置分隔符；HEX 显示路径按 JS 字符串 `charCodeAt`（UTF-16 code unit）转字节。**本实现一律按 UTF-8 字节处理**（见 TextPayloadCodec），分隔符集合由设置注入。

### 6.7 文本（ASCII）编解码（`TextPayloadCodec.swift`）

```swift
import Foundation

/// 文本载荷编解码（需求 §5.2、§5.3 ASCII 行）。所有转换一律按字节（Data）进行。
public enum TextPayloadCodec {
    /// 编码发送文本为字节。
    /// - Throws: `.emptyPayload`（空字符串）；
    ///   `.invalidSetting("error.encoding.unrepresentable")`（当前编码无法表示输入，
    ///   如中文送入 US-ASCII；catalog key 供 UI 映射）。
    public static func encode(_ text: String, encoding: String.Encoding = .utf8) throws -> Data {
        guard !text.isEmpty else { throw ValidationError.emptyPayload }
        guard let data = text.data(using: encoding) else {
            throw ValidationError.invalidSetting("error.encoding.unrepresentable")
        }
        return data
    }

    /// 解码接收字节为显示文本。无法解码的字节必须以 U+FFFD（�）占位显示，
    /// 不得静默丢弃（需求 §5.2）。
    /// 策略：可整体解码则直接返回；UTF-8 走标准库容错替换；
    /// 其余编码退化为"最长可解码前缀 + 单字节占位"循环。
    public static func decode(_ data: Data, encoding: String.Encoding = .utf8) -> String {
        if data.isEmpty { return "" }
        if let exact = String(data: data, encoding: encoding) { return exact }
        if encoding == .utf8 {
            // 标准库按 Unicode 规范以 U+FFFD 替换非法序列
            return String(decoding: data, as: UTF8.self)
        }
        var result = String()
        var remaining = data[...]
        while !remaining.isEmpty {
            // 找最长可解码前缀（长度从 count-1 递减；整体已失败，故从 count-1 起）
            var length = remaining.count - 1
            var prefix: String?
            while length > 0 {
                if let decoded = String(data: Data(remaining.prefix(length)), encoding: encoding) {
                    prefix = decoded
                    break
                }
                length -= 1
            }
            if let prefix { result += prefix }
            result.append("\u{FFFD}")               // 单个无法解码字节的占位
            remaining = remaining.dropFirst(length + 1)
        }
        return result
    }
}
```

> 说明：非 UTF-8 编码的逐字节兜底是"可识别、不丢失"的保守策略——多字节编码的截断序列可能产生多于实际坏字节数的占位符，属可接受的展示近似；原始字节不受影响（RecordStore 只存 Data）。

### 6.8 发送载荷组装（`SendPayloadEncoder.swift`）

```swift
import Foundation

/// 发送载荷组装：校验 + 编码 + 行结束符，产出可直接写入串口的最终字节。
/// 调用时机：ViewModel 校验通过后与 03 的 SendRequest 构造之前；非法输入在此被拦截，
/// 根本不会到达 SessionCoordinator（03 §6.2 约定）。
public enum SendPayloadEncoder {
    /// - ASCII 模式：按 textEncoding 编码后追加 lineEnding（none 不追加）。
    /// - HEX 模式：HexCodec 解码；**不追加行结束符**——需求 §5.3 表将行结束符列于
    ///   ASCII 模式行，HEX 行未提及（决策记录：若后续需求澄清 HEX 也需追加，
    ///   改此一处并回写本文档）。
    /// - Throws: `ValidationError`（emptyPayload / invalidHex / invalidSetting）。
    public static func makePayload(
        text: String,
        format: DisplayFormat,
        lineEnding: LineEnding,
        textEncoding: String.Encoding = .utf8,
        hexOptions: HexCodec.Options = .init()
    ) throws -> Data {
        switch format {
        case .ascii:
            let data = try TextPayloadCodec.encode(text, encoding: textEncoding)
            return lineEnding.appending(to: data)
        case .hex:
            return try HexCodec.decode(text, options: hexOptions)
        }
    }
}
```

### 6.9 内存记录仓库（`RecordStore.swift`）

容量策略（需求 §5.2、§12.1）：默认最多 50,000 条记录或 16 MiB 原始字节，任一条件先达到则从最早记录开始淘汰；阈值可配置；下调阈值即时生效（§7.1）。截断统计（累计截断次数与最后一次截断时间）供状态栏展示。

```swift
import Foundation

/// RecordStore 容量配置（默认值见需求 §12.1；可在设置中调整）。
public struct RecordStoreConfiguration: Sendable, Equatable {
    /// 最大记录条数（>= 1）。
    public var maxRecords: Int
    /// 最大原始字节数（>= 1）。
    public var maxBytes: Int

    public init(maxRecords: Int = 50_000, maxBytes: Int = 16 * 1024 * 1024) {
        precondition(maxRecords >= 1 && maxBytes >= 1, "RecordStore 容量下限为 1")
        self.maxRecords = maxRecords
        self.maxBytes = maxBytes
    }

    public static let `default` = RecordStoreConfiguration()
}

/// 截断统计（需求 §5.2：界面显示累计截断次数与最后一次截断时间）。
public struct TruncationStats: Sendable, Equatable {
    /// 发生截断的次数（一次 append/降阈值可能淘汰多条，记 1 次事件）。
    public private(set) var truncationEventCount: Int = 0
    /// 被淘汰的记录总条数。
    public private(set) var totalTruncatedRecords: Int = 0
    /// 最后一次截断发生时间；从未截断为 nil。
    public private(set) var lastTruncationAt: Date?
}

/// 内存记录仓库（需求 §12.1：保存原始 Data；展示字符串按当前偏好惰性生成，
/// 切换 ASCII/HEX 只重建展示投影）。actor 隔离保证与 RX/TX 管线并发安全。
///
/// 实现要点（数组 + head 偏移的逻辑队列）：
/// - 淘汰只推进 head，O(1)；head 积累到一定规模后一次性压实（compact），避免频繁 removeFirst 的 O(n)。
/// - id → 物理下标字典支撑 updateSendResult / record 的 O(1) 查找。
public actor RecordStore {
    public private(set) var configuration: RecordStoreConfiguration

    private var storage: [CommunicationRecord] = []
    private var head: Int = 0
    private var indexByID: [CommunicationRecord.ID: Int] = [:]

    /// 当前在册原始字节总量（随淘汰减少）。
    public private(set) var totalBytes: Int = 0
    /// 累计收发字节计数（状态栏用；只增不减，不受淘汰/清空影响）。
    public private(set) var counters: (rxBytes: Int, txBytes: Int) = (0, 0)
    public private(set) var truncation = TruncationStats()

    public init(configuration: RecordStoreConfiguration = .default) {
        self.configuration = configuration
    }

    /// 当前在册记录条数。
    public var count: Int { storage.count - head }

    /// 追加一条记录并触发容量淘汰。RX/TX 计数按原始字节累计。
    public func append(_ record: CommunicationRecord) {
        indexByID[record.id] = storage.count
        storage.append(record)
        totalBytes += record.byteCount
        switch record.direction {
        case .rx: counters.rxBytes += record.byteCount
        case .tx: counters.txBytes += record.byteCount
        }
        evictIfNeeded()
    }

    /// 回填发送结果（03：写完成/失败后调用）。记录已被淘汰时为 no-op。
    public func updateSendResult(_ id: CommunicationRecord.ID, _ result: SendResult) {
        guard let index = indexByID[id], index >= head else { return }
        storage[index].sendResult = result
    }

    /// 按 id 取记录；已被淘汰返回 nil。
    public func record(_ id: CommunicationRecord.ID) -> CommunicationRecord? {
        guard let index = indexByID[id], index >= head else { return nil }
        return storage[index]
    }

    /// 全部在册记录（时间升序）。供 03 日志补写、04 控制台初始装载。
    public func allRecords() -> [CommunicationRecord] {
        Array(storage[head...])
    }

    /// 清空内存显示记录（需求 §5.2：不影响正在写入的日志文件——日志由 06 自持）。
    /// 保留累计 counters 与截断统计。
    public func clear() {
        storage.removeAll(keepingCapacity: true)
        indexByID.removeAll(keepingCapacity: true)
        head = 0
        totalBytes = 0
    }

    /// 调整容量配置；下调阈值立即按最早优先裁剪（需求 §7.1 即时生效）。
    public func updateConfiguration(_ newConfiguration: RecordStoreConfiguration) {
        configuration = newConfiguration
        evictIfNeeded()
    }

    /// 惰性展示投影：按调用时传入的显示偏好现场格式化，不写回存储。
    /// 切换 ASCII/HEX 只影响后续投影调用，原始数据不变（需求 §12.1）。
    public func displayString(
        for id: CommunicationRecord.ID,
        format: DisplayFormat,
        hexStyle: HexDisplayStyle = .init(),
        textEncoding: String.Encoding = .utf8
    ) -> String? {
        guard let record = record(id) else { return nil }
        return DisplayFormatter.string(for: record, format: format,
                                       hexStyle: hexStyle, textEncoding: textEncoding)
    }

    // MARK: - 内部

    private func evictIfNeeded() {
        var evicted = 0
        // count > 0 守卫：单条超大记录超过 maxBytes 时淘汰自身后退出，不死循环
        while count > 0, count > configuration.maxRecords || totalBytes > configuration.maxBytes {
            let victim = storage[head]
            head += 1
            indexByID.removeValue(forKey: victim.id)
            totalBytes -= victim.byteCount
            evicted += 1
        }
        if evicted > 0 {
            truncation.truncationEventCount += 1
            truncation.totalTruncatedRecords += evicted
            truncation.lastTruncationAt = Date()
            compactIfNeeded()
        }
    }

    private func compactIfNeeded() {
        guard head >= 1_024, head * 2 >= storage.count else { return }
        storage.removeFirst(head)
        head = 0
        indexByID.removeAll(keepingCapacity: true)
        for (index, record) in storage.enumerated() {
            indexByID[record.id] = index
        }
    }
}
```

### 6.10 展示格式化器（`DisplayFormatter.swift`）

```swift
import Foundation

/// HEX 显示样式（需求 §5.2：分隔符、大小写和换行规则由设置指定）。
public struct HexDisplayStyle: Sendable, Equatable {
    /// 字节间分隔符，默认单个空格（"55 AA 01"）。
    public var separator: String
    /// 是否大写，默认 true（"AA" 而非 "aa"）。
    public var uppercase: Bool
    /// 每行字节数；nil 或 <= 0 表示不换行（单行）。
    public var bytesPerRow: Int?

    public init(separator: String = " ", uppercase: Bool = true, bytesPerRow: Int? = nil) {
        self.separator = separator
        self.uppercase = uppercase
        self.bytesPerRow = bytesPerRow
    }
}

/// 展示格式化纯函数集合。全部无状态、线程安全，可在任意 actor 上下文调用。
public enum DisplayFormatter {
    /// HEX 显示（如 "55 AA 01"）。空数据返回空串。
    public static func hexString(for data: Data, style: HexDisplayStyle = .init()) -> String {
        let perRow = (style.bytesPerRow ?? 0) > 0 ? style.bytesPerRow! : Int.max
        var rows: [String] = []
        var tokens: [String] = []
        tokens.reserveCapacity(min(data.count, perRow == Int.max ? data.count : perRow))
        for (index, byte) in data.enumerated() {
            var token = String(byte, radix: 16)
            if token.count == 1 { token = "0" + token }
            if style.uppercase { token = token.uppercased() }
            tokens.append(token)
            if tokens.count == perRow, index < data.count - 1 {
                rows.append(tokens.joined(separator: style.separator))
                tokens.removeAll(keepingCapacity: true)
            }
        }
        if !tokens.isEmpty { rows.append(tokens.joined(separator: style.separator)) }
        return rows.joined(separator: "\n")
    }

    /// ASCII 显示：按编码解码，无法解码字节以 U+FFFD 占位（委托 TextPayloadCodec，需求 §5.2）。
    public static func asciiString(for data: Data, encoding: String.Encoding = .utf8) -> String {
        TextPayloadCodec.decode(data, encoding: encoding)
    }

    /// 控制台时间戳：HH:MM:SS.mmm（24 小时制 + 3 位毫秒，00 文档第 5 节）。
    /// 展示用本地时区；日志落盘的 ISO8601 格式属 06 文档，不在此。
    public static func timestampString(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let milliseconds = (components.nanosecond ?? 0) / 1_000_000
        return String(format: "%02d:%02d:%02d.%03d",
                      components.hour ?? 0, components.minute ?? 0,
                      components.second ?? 0, milliseconds)
    }

    /// 记录 → 展示字符串的统一入口（RX/TX 通用；只读 rawBytes，不改记录）。
    public static func string(
        for record: CommunicationRecord,
        format: DisplayFormat,
        hexStyle: HexDisplayStyle = .init(),
        textEncoding: String.Encoding = .utf8
    ) -> String {
        switch format {
        case .hex:   return hexString(for: record.rawBytes, style: hexStyle)
        case .ascii: return asciiString(for: record.rawBytes, encoding: textEncoding)
        }
    }
}
```

### 6.11 安全清洗与日志文件名（`PathSanitizer.swift` + `LogFileNameGenerator.swift`）

需求 §14：对文件名、端口名和预设名称做路径安全清洗；不得允许通过名称构造越界路径。日志文件名规则（§6.1）：`SerialMonitor_yyyyMMdd_HHmmss_<port>.log`，端口名需安全清洗（轮转追加 `_001` 等后缀属 06，不在此）。

```swift
import Foundation

/// 路径安全清洗（需求 §14）。清洗结果保证：
/// - 不含 "/" 与 "\"（替换为 "-"），不含 ":"（Mac 传统路径分隔符，替换为 "-"）；
/// - 不含控制字符（含 NUL、换行；直接剔除）；
/// - 不以 "." 开头（防隐藏文件与 "."/".." 越界名）；
/// - 首尾无空白与 "."；非空（空则回退 fallback）；长度不超过 maxLength 个 Character。
/// 中文等 Unicode 字母数字原样保留（需求 §14：名称必须支持中文）。
public enum PathSanitizer {
    public static func sanitized(
        _ name: String,
        fallback: String = "unnamed",
        maxLength: Int = 64
    ) -> String {
        var result = String()
        result.reserveCapacity(name.count)
        for scalar in name.unicodeScalars {
            switch scalar {
            case "/", "\\", ":":
                result.append("-")
            default:
                if CharacterSet.controlCharacters.contains(scalar) { continue }
                result.unicodeScalars.append(scalar)
            }
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix(".") { result.removeFirst() }
        result = String(result.prefix(maxLength))
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return result.isEmpty ? fallback : result
    }
}
```

```swift
import Foundation

/// 日志文件名生成（需求 §6.1）。纯函数：日期与端口路径注入，可确定性测试。
public enum LogFileNameGenerator {
    /// 生成 `SerialMonitor_yyyyMMdd_HHmmss_<port>.log`。
    /// - port 段取端口路径最后一段（如 /dev/cu.usbserial-1420 → cu.usbserial-1420），
    ///   再经 PathSanitizer 清洗；空/非法端口名回退 "unknown-port"。
    /// - 时间戳使用 calendar（默认本地时区）的挂钟时间。
    public static func makeLogFileName(
        portPath: String,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let lastComponent = (portPath as NSString).lastPathComponent
        let safePort = PathSanitizer.sanitized(lastComponent, fallback: "unknown-port")
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(format: "%04d%02d%02d_%02d%02d%02d",
                           c.year ?? 0, c.month ?? 0, c.day ?? 0,
                           c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return "SerialMonitor_\(stamp)_\(safePort).log"
    }
}
```

---

## 7. 实现步骤（按依赖排序）

每步完成立即执行自验证，红了先修再继续（00 文档规则 7）。

### 步骤 0：工程壳就位（仅当主工程不存在）

- **做什么**：检查项目根是否存在 `SerialMonitor.xcodeproj`（或等价 SPM 工程）。不存在则创建最小工程壳：macOS App target（空 `SerialMonitorApp` 入口，deployment target 14.0，Swift 6，严格并发 complete）+ Unit Test target，本地包依赖 `Packages/SerialCore`；在 00 文档第 9 节追加一条记录（R6 起）说明"工程壳由 02 阶段创建"。已存在则跳过本步。
- **产出**：可构建的空工程。
- **自验证**：构建通过；测试 target 可运行空测试。

### 步骤 1：模型与别名

- **做什么**：创建 `CommunicationRecord.swift`、`LineEnding.swift`、`SerialParameterAliases.swift`、`SessionError.swift`、`ValidationError.swift`（照抄 §6.1–§6.5）。
- **产出**：5 个文件。
- **自验证**：构建通过零警告；`SerialParameterAliases` 中 `DataBits.allCases.count == 4`、`Parity.allCases.count == 3` 编译期可用（在步骤 6 测试中断言）。

### 步骤 2：状态机

- **做什么**：创建 `SessionState.swift`、`SessionStateMachine.swift`（照抄 §6.4），逐行对照转换表 8 行。
- **产出**：2 个文件。
- **自验证**：`SessionStateMachineTests` 全绿（§9：8 行合法转换逐一断言 + 非法矩阵 5 状态 × 5 事件穷举返回 nil + 事件序列场景 + `from(target:)` 对各可达目标态round-trip）。

### 步骤 3：编码与校验

- **做什么**：创建 `HexCodec.swift`、`TextPayloadCodec.swift`、`SendPayloadEncoder.swift`（照抄 §6.6–§6.8）。
- **产出**：3 个文件。
- **自验证**：`HexCodecTests` / `TextPayloadCodecTests` / `SendPayloadEncoderTests` 全绿（§9 用例清单）。

### 步骤 4：展示格式化器

- **做什么**：创建 `DisplayFormatter.swift`（照抄 §6.10）。
- **产出**：1 个文件。
- **自验证**：`DisplayFormatterTests` 全绿：含 "55 AA 01" 基例、小写、无分隔、每行 16 字节换行、时间戳正则 `^\d{2}:\d{2}:\d{2}\.\d{3}$`。

### 步骤 5：RecordStore

- **做什么**：创建 `RecordStore.swift`（照抄 §6.9）。
- **产出**：1 个文件。
- **自验证**：`RecordStoreTests` 全绿（§9：条数阈值、字节阈值、统计字段、降阈值即裁剪、单条超限不死循环、淘汰后 updateSendResult no-op、counters 只增不减、投影不改原始数据）。

### 步骤 6：安全清洗与文件名

- **做什么**：创建 `PathSanitizer.swift`、`LogFileNameGenerator.swift`（照抄 §6.11）。
- **产出**：2 个文件。
- **自验证**：`PathSanitizerTests` 全绿（§9 注入用例表逐条断言；文件名注入固定 Date 断言精确字符串）。

### 步骤 7：契约一致性核对

- **做什么**：逐条对照 03 文档 §4.3 假定签名与本文档 §6 实际定义（`SessionState` 五态关联值名、`SessionError.Category` 六案、`RecordStore` 四个公开成员、`ValidationError.invalidSetting(String)`/`.notConnected`、`SessionStateEvent.from(target:)`、`SerialConfiguration.default`）。如有出入：以 01/02 为准，把差异追加记录到 00 文档第 9 节（供 03 执行时调整调用点）。
- **产出**：核对结论（无出入则在 03 无新增风险；有出入则 00 第 9 节新增条目）。
- **自验证**：03 §4.3 代码块中每个符号在本文档 §6 可找到逐字对应定义。

---

## 8. 验收标准（映射需求文档 §16）

| AC 编号 | §16 通过条件（相关部分） | 本文档验证方式 |
|---|---|---|
| AC-02（部分） | 状态机无非法跳转 | §9 `SessionStateMachineTests`：转换表 8 行全覆盖 + 非法组合穷举返回 nil；03 以事件序列测试复核协调器不触发非法转换 |
| AC-03（部分） | 连续 RX 可在 ASCII/HEX 下显示（数据层前提：原始字节保存、切换格式不改数据） | `RecordStoreTests`：`append` 后 `rawBytes` 逐字节相等；同一记录分别以 ascii/hex 投影结果不同而原始数据不变；`TextPayloadCodecTests` 占位策略不丢字节 |
| AC-04（部分） | ASCII、HEX、CRLF 可正确发送；非法 HEX 与未连接状态均被阻止 | `SendPayloadEncoderTests`：ASCII+CR/LF/CRLF 字节断言、HEX 解码字节断言；`HexCodecTests`：非法字符（含定位）/奇数/空三类拦截；`ValidationError.notConnected` 案存在且带说明（未连接拦截的执行在 03/04） |

---

## 9. 测试要求

测试统一放 `SerialMonitor/Tests/Unit/`，纯 Swift、不依赖硬件与 UI。执行：Xcode 测试 target 全绿（或等价 `swift test`）。

| 测试文件 | 用例清单 |
|---|---|
| `HexCodecTests.swift` | ①合法：`"55 AA 01 00"` → `[0x55,0xAA,0x01,0x00]`；②小写 `"55aa"` 等价；③无分隔 `"55AA01"`；④换行/制表符混合空白；⑤配置分隔符 `"55-AA-01"`（Options.extraSeparators=["-"]）通过、未配置时 `"-"` 报 illegalCharacter 且 position 指向第一个 `-`；⑥奇数 `"55A"` → `.invalidHex(oddLength)`；⑦非法字符 `"55 GG"` → `.invalidHex(illegalCharacter)`，character=='G'，position==3；⑧空串与纯空白串 → `.emptyPayload`；⑨非 ASCII 字符（如 `"５５"`全角、`"中"`）→ illegalCharacter；⑩`encode` 紧凑大写 `[0x55,0xAA]` → `"55AA"`；⑪单字节 `[0x05]` → `"05"` 前导零 |
| `TextPayloadCodecTests.swift` | ①UTF-8 round-trip（含中文 `"温度"`）；②`encode("")` → `.emptyPayload`；③中文送入 `.ascii` 编码 → `.invalidSetting`；④`decode` 合法 UTF-8；⑤UTF-8 非法字节 `[0x41,0xFF,0x42]` → 含 U+FFFD 且 'A'、'B' 保留，占位不丢字节；⑥截断的多字节序列（如 `"温".utf8` 去尾字节）→ 占位；⑦空 Data → 空串 |
| `SendPayloadEncoderTests.swift` | ①ASCII+none 原样；②+lf 尾 0x0A；③+cr 尾 0x0D；④+crlf 尾 0x0D 0x0A；⑤HEX 模式不追加行结束符（决策断言）；⑥HEX 非法输入抛错不产字节；⑦ASCII 空串 → `.emptyPayload`；⑧`SendIntervalLimits.validate(9)` 抛 `.invalidInterval`、`(10)` 与 `(3_600_000)` 通过 |
| `SessionStateMachineTests.swift` | ①转换表 8 行逐行断言（关联值一并断言，如行 3 的 failedConfiguration）；②非法矩阵：5 状态 × 5 事件共 25 组合中，除 8 组合法外全部返回 nil；③事件序列：`openRequested → failureOccurred → openRequested → openSucceeded → closeRequested → closeCompleted` 终态 disconnected；④序列：`openRequested → openSucceeded → failureOccurred` 终态 error 且保留配置；⑤error 态除 openRequested/closeRequested 外任意事件返回 nil；⑥`from(target:)` 对 opening/connected/closing/disconnected/error 各目标态生成的事件，从对应合法源态 transition 后等于目标态；⑦`SerialConfiguration.default` 路径为空 |
| `RecordStoreTests.swift` | ①append/record/updateSendResult 基本路径；②条数阈值：maxRecords=3 追加 5 条 → 剩后 3 条且最早两条被淘汰；③字节阈值：maxBytes=10、每条 4 字节追加 4 条 → totalBytes ≤ 10；④截断统计：eventCount、totalTruncatedRecords、lastTruncationAt 非 nil；⑤`updateConfiguration` 下调后立即裁剪；⑥单条 20 字节记录 + maxBytes=10 → 不死循环、最终被清空；⑦被淘汰 id 的 updateSendResult 为 no-op；⑧counters 累计且淘汰/clear 后不清零；⑨`clear()` 后 count/totalBytes 归零、统计保留；⑩`displayString` 以 ascii 与 hex 投影结果不同且 `record(id).rawBytes` 不变；⑪时间升序：allRecords 顺序与 append 一致 |
| `DisplayFormatterTests.swift` | ①`[0x55,0xAA,0x01]` → `"55 AA 01"`；②小写 → `"55 aa 01"`；③separator:"" → `"55AA01"`；④bytesPerRow=2 的 5 字节 → 两行 + 单行尾（`"55 AA\n01 02\n03"`）；⑤时间戳正则 `^\d{2}:\d{2}:\d{2}\.\d{3}$` 且注入固定 Date（已知时分秒毫秒）断言精确串；⑥ASCII 显示含 U+FFFD 占位 |
| `PathSanitizerTests.swift` | 注入用例逐条断言：①`"../../etc/passwd"` → 不含 `/`、不以 `.` 开头；②`".."` → fallback；③`"."` → fallback；④`"a/b\\c:d"` → `"a-b-c-d"`；⑤`"log\u{0}name"` → `"logname"`；⑥`"  padded  "` → `"padded"`；⑦中文 `"温度传感器"` 原样保留；⑧超长名截断到 maxLength 个 Character；⑨全非法字符 → fallback；⑩文件名生成：注入固定 Date + `"/dev/cu.usbserial-1420"` → 精确断言 `"SerialMonitor_yyyyMMdd_HHmmss_cu.usbserial-1420.log"`（按注入日期展开）；⑪端口名为 `"../.."` → 端口段回退/清洗后无越界风险；⑫中文端口显示名进入文件名 |

---

## 10. 防漫游约束（重申，逐条有效）

1. **只做第 5 节文件清单内的文件**；发现必须新增/修改清单外文件时，停止该分支工作，把情况追加记录到 00 文档第 9 节（R6 起），等待指示，不自行扩大范围。
2. **不引入未列依赖**：本文档零第三方依赖；允许 import 仅 `Foundation` 与 `SerialCore`；出现其他 import 即为越界。
3. 接口契约以 §6 的 Swift 定义为准，逐字照抄；确有实现障碍时先做最小可行调整并**回写本文档对应代码块**，不静默改签名。与 01/03 假定签名冲突时，以 01/02 为准并记录到 00 文档第 9 节。
4. 不实现 Out of scope 内容：不写 SessionCoordinator/TX 队列/RX 管线（03）、不写 UI 与 String Catalog 文案（04+）、不写预设持久化与循环任务体（05）、不写 JSONL 落盘与轮转（06）。
5. 不做顺手重构、重命名、格式化无关代码；不修改 `Packages/SerialCore/**`。
6. Figma 原型已知瑕疵不得照抄：HEX 显示必须按 UTF-8 字节转换（原型按 charCode）；HEX 校验必须支持配置分隔符（原型只认 `\s`）。
7. 每个实现步骤完成后必须运行其自验证，红了先修，不跳步。
8. 需求矛盾或信息缺失时（例如 §5.3 未明确 HEX 模式是否追加行结束符这类解释性分歧升级为需求级矛盾时），记录到 00 文档第 9 节"风险与决策点"并停止该分支工作，不自行发明需求。本文档已做的解释性决策（HEX 不追加行结束符、SendSource 含 .serial、失败事件合并为 failureOccurred、§11.2 外补充 opening→closing 行）均已在 §6 对应位置标注依据；执行者若发现这些决策与新证据冲突，同样按本条处理。
