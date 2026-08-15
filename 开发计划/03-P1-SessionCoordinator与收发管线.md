# 03 · P1 SessionCoordinator 与收发管线

> 版本：V1.0 ｜ 阶段：P1 核心会话 ｜ 状态：开发基线
> 上游权威：《设计与需求文档.html》§5.1、§9、§11、§12、§13、§15、§16；《00-开发计划总览.md》

---

## 1. 文档信息

| 项 | 内容 |
|---|---|
| 对应阶段 | P1 核心会话（需求文档 §17：完成连接、RX/TX、编码、状态机、内存记录） |
| 前置文档 | 01（SerialCore 抽象与 `SerialPorting` 契约）、02（Domain 模型、编码校验、状态机） |
| 后续文档 | 04（主工作区 UI，消费本文档的事件流与状态投影）、05（自动发送与预设，接入本文档的调度任务槽位与 TX 队列）、06（日志系统，实现本文档的 `LogServicing`） |
| 覆盖验收项 | AC-02（连接与状态机）、AC-03（接收，管线部分）、AC-04（发送，管线部分） |

**本文档写作前提**：01、02 文档按契约交付。本文档在 §4 列出所依赖契约的**假定签名**；实现时若与 01/02 实际定义不一致，以 01/02 为准调整本文档代码的调用点，签名级冲突按 §10 流程记录到 00 文档第 9 节并停止，不得静默改契约。

---

## 2. 目标与完成定义

### 2.1 目标

交付 Application 层的核心 actor `SessionCoordinator`：作为**唯一**拥有活跃串口、TX 串行化队列、RX fan-out、日志生命周期钩子与调度任务取消权的对象，把 02 定义的 `SessionState` 状态机落地为可运行的连接/收发/错误/退出流程，并向 ViewModel（04 实现）提供单一的 `AsyncStream<SessionEvent>` 事件源。

### 2.2 Definition of Done（逐条勾选）

- [ ] `SessionCoordinator` 编译通过（Swift 6 严格并发，零警告），公开 API 与 §6.4 完全一致。
- [ ] 连接流程覆盖 §11.2 状态转换表全部 7 行，每行的附加动作（锁定参数、启动 RX Stream、取消旧任务、保存错误上下文、flush 日志等）逐行落实（§7 步骤 3）。
- [ ] 打开失败 / 设备拔出 / 配置不支持 / 读写失败均产生结构化 `SessionError` 并进入 `error` 状态；只有显式 `connect` / `disconnect` 可离开 `error`。
- [ ] RX 管线：`incomingBytes()` 每个数据块生成一条 RX `CommunicationRecord` → `RecordStore` → 事件发布；提供 16–50ms 批处理投影接口。
- [ ] TX 管线：manual / autoSend / preset 三来源共用同一 FIFO 队列；排入队列即创建 TX 记录（`sendResult = .pending`）；写失败标记 `.failed`；不可恢复错误转 `error` 并停止一切发送；同一时刻至多一个 `port.write` 在途。
- [ ] `LogServicing` 协议与 `NullLogService` 就位；连接成功按需自动 start，closing/error/退出时 flush + stop；日志失败只停日志、不停会话。
- [ ] 退出流程 `prepareForTermination()` 按 §7 步骤 7 的确定顺序执行完毕。
- [ ] `MockSerialPorting` 可脚本化打开失败/延时/写失败/拔出事件，满足 §9.1 全部能力。
- [ ] §9 列出的全部测试用例通过：`swift test` 全绿。
- [ ] 未创建 §5 文件清单之外的任何文件；未引入新第三方依赖。

---

## 3. 范围

### 3.1 In scope

- `actor SessionCoordinator` 完整实现（连接、断开、发送、事件流、内部任务管理、退出）。
- TX FIFO 队列与串行写泵（pump）实现。
- RX 消费任务与 RX 记录生成、RecordStore 写入、事件发布。
- `LogServicing` 协议占位 + `NullLogService`。
- 错误分类到用户反馈的结构化映射（数据层面；弹窗与文案渲染在 04）。
- 调度任务的**所有权与取消机制**（任务槽位、启动前取消并 await 旧任务）；自动发送/预设循环的**具体任务体不在本文档**（05 实现，通过 `registerScheduledTask` 挂入）。
- `MockSerialPorting`、虚拟时钟、伪终端集成测试。

### 3.2 Out of scope

- 自动发送 / 预设循环的任务体与 UI（05）。
- JSONL 日志的真实落盘、轮转、文件名清洗（06；本阶段用 `NullLogService` 验证挂接点）。
- 任何 SwiftUI / AppKit 代码、错误弹窗、状态栏渲染（04）。
- RecordStore 的截断策略实现（02 Domain 已含；本文档只调用 `append` / `updateSendResult`）。
- 串口真实硬件适配器（01 已交付）。

### 3.3 明确禁止事项

- 禁止在 `SessionCoordinator` 之外任何对象持有 `SerialPorting` 实例或直接调用 `open/close/write`。
- 禁止三来源（manual/autoSend/preset）绕过 TX 队列直接写串口。
- 禁止在 MainActor 上执行 `port.write`、RX 循环或日志 I/O。
- 禁止引入 Combine、DispatchQueue、NSLock 等替代并发原语（本项目统一 Swift Concurrency）。
- 禁止新增第三方依赖。

---

## 4. 依赖与前置条件

### 4.1 文档依赖

| 文档 | 需已完成的内容 |
|---|---|
| 01 | `SerialPorting` 协议、真实适配器、`SerialPortDescriptor`、伪终端可打开 `/dev/cu.*`（或 `tty` 端）的验证结论 |
| 02 | `SerialConfiguration`、`CommunicationRecord`、`SessionState` + `SessionStateMachine`、`SendSource`、`SendResult`、`ValidationError`、`SessionError`（Domain 错误模型）、`RecordStore` actor |

### 4.2 引用自 01 的契约（假定签名，不重定义）

```swift
// 01 · Infrastructure/SerialCore/SerialPorting.swift（引用，勿复制到本阶段文件）
public protocol SerialPorting: Sendable {
    func availablePorts() async -> [SerialPortDescriptor]
    func open(configuration: SerialConfiguration) async throws
    func close() async
    func write(_ data: Data) async throws
    func incomingBytes() -> AsyncThrowingStream<Data, any Error>
    func connectionEvents() -> AsyncStream<SerialConnectionEvent>
}

public enum SerialConnectionEvent: Sendable {
    case deviceRemoved          // 设备拔出
    case driverError(String)    // 驱动层不可恢复错误（附带系统描述）
}
```

### 4.3 引用自 02 的契约（假定签名，不重定义）

```swift
// 02 · Domain（引用，勿复制到本阶段文件）
public struct SerialConfiguration: Codable, Equatable, Sendable { /* path/baudRate/dataBits/parity/stopBits/flowControl */ }

public enum SessionState: Sendable, Equatable {
    case disconnected
    case opening(configuration: SerialConfiguration)      // 参数已锁定
    case connected(session: ConnectedSession)
    case closing(previous: SerialConfiguration)
    case error(context: SessionErrorContext)              // 保留失败时的配置，用于重试
}

public struct ConnectedSession: Sendable, Equatable {
    public let configuration: SerialConfiguration
    public let connectedAt: Date
}

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
    public let systemCode: Int?         // errno / IOKit code，可空
    public let systemDescription: String
    public let occurredAt: Date
    public let isRetryable: Bool
}

public struct SessionErrorContext: Sendable, Equatable {
    public let error: SessionError
    public let failedConfiguration: SerialConfiguration?  // 打开失败时为当时锁定的配置
}

public struct CommunicationRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let direction: Direction            // .rx / .tx
    public let rawBytes: Data
    public let displayFormat: DisplayFormat    // .ascii / .hex
    public let source: SendSource              // .serial(RX) / .manual / .autoSend / .preset
    public var sendResult: SendResult          // .pending / .success / .failed(reason)（RX 恒 .success）
    public let presetSnapshot: PresetSnapshot? // id + name 快照
}

public enum SessionStateMachine {
    /// 纯函数：非法转换返回 nil。事件枚举与转换表见 02 §状态机。
    public static func transition(from state: SessionState, event: SessionStateEvent) -> SessionState?
}

public actor RecordStore {
    public func append(_ record: CommunicationRecord)
    public func updateSendResult(_ id: UUID, _ result: SendResult)
    public func record(_ id: UUID) -> CommunicationRecord?
    public var counters: (rxBytes: Int, txBytes: Int) { get }
}
```

### 4.4 环境前置条件

- Xcode / Swift 6 工具链；工程已启用严格并发检查（02 阶段已配置）。
- `swift test` 可运行；伪终端测试在 macOS 本机可 `openpty`（01 POC 已验证）。
- 系统 `date` 与 `ContinuousClock` 单调时钟可用。

---

## 5. 涉及文件清单

| 相对路径 | 新建/修改 | 一句话职责 |
|---|---|---|
| `SerialMonitor/Application/SessionCoordinator.swift` | 新建 | 唯一会话协调 actor：连接状态机驱动、RX/TX 管线、日志钩子、任务取消、退出 |
| `SerialMonitor/Application/SessionEvent.swift` | 新建 | 对 UI 发布的事件枚举与事件流工厂 |
| `SerialMonitor/Application/SendRequest.swift` | 新建 | 统一发送请求模型（三来源同一入口） |
| `SerialMonitor/Application/TXSendQueue.swift` | 新建 | FIFO 发送队列与串行写泵（仅被 SessionCoordinator 持有） |
| `SerialMonitor/Application/LogServicing.swift` | 新建 | 日志协议占位 + `NullLogService`（P2 由 06 替换为 JSONL 实现） |
| `SerialMonitor/Application/SessionClock.swift` | 新建 | 时钟抽象（系统时钟 / 测试虚拟时钟），供调度与批处理使用 |
| `SerialMonitor/Application/ErrorUserFeedback.swift` | 新建 | `SessionError.Category` → 结构化用户反馈（发生了什么/影响/怎么办）映射 |
| `SerialMonitor/Tests/Support/MockSerialPorting.swift` | 新建 | 可脚本化打开失败/延时/写失败/拔出的 Mock |
| `SerialMonitor/Tests/Support/ManualSessionClock.swift` | 新建 | 虚拟时钟（手动推进），供状态机序列测试 |
| `SerialMonitor/Tests/Unit/SessionCoordinatorConnectTests.swift` | 新建 | 连接流程与状态机事件序列测试（§9.2） |
| `SerialMonitor/Tests/Unit/SessionCoordinatorTXTests.swift` | 新建 | TX 队列串行化/失败/防重入测试（§9.3） |
| `SerialMonitor/Tests/Unit/SessionCoordinatorRXTests.swift` | 新建 | RX 管线与批处理投影测试（§9.4） |
| `SerialMonitor/Tests/Unit/SessionCoordinatorLifecycleTests.swift` | 新建 | 错误恢复与退出流程测试（§9.5） |
| `SerialMonitor/Tests/Integration/PseudoTerminalSessionTests.swift` | 新建 | 伪终端端到端收发/拔出测试（§9.6） |

> 不修改 01、02 已交付的任何文件。若 `SessionError` / `SessionState` 假定签名与 02 实际不符，改动仅限本清单内文件的调用点。

---

## 6. 接口与数据模型（可直接照抄）

### 6.1 `SessionEvent` —— 对 UI 的唯一事件源

```swift
// SerialMonitor/Application/SessionEvent.swift
import Foundation

/// ViewModel 消费的唯一事件流。所有事件已由 SessionCoordinator 按发生顺序串行发出；
/// UI 可观察状态的 MainActor 跳转由 04 的 SessionViewModel 负责，本层不依赖 SwiftUI。
public enum SessionEvent: Sendable {
    /// 状态机迁移完成（新状态）。ViewModel 据此切换工具栏/按钮可用性。
    case stateChanged(SessionState)
    /// 新记录已入 RecordStore（RX 到达或 TX 排队）。
    case recordAppended(CommunicationRecord.ID)
    /// 已存在记录被更新（TX 写完成/失败回填 sendResult）。
    case recordUpdated(CommunicationRecord.ID)
    /// 收发字节计数变化（状态栏用）。
    case countersChanged(rxBytes: Int, txBytes: Int)
    /// 日志运行状态变化（开始/停止/失败）。
    case logStatusChanged(LogStatus)
}

public enum LogStatus: Sendable, Equatable {
    case idle
    case recording(fileName: String)
    case failed(reason: String)   // 日志失败：停日志，不停会话（§13）
}

public extension AsyncStream where Element == SessionEvent {
    /// 高流量投影策略（需求 §12.1）：把 recordAppended 合并为 16–50ms 窗口的批量事件，
    /// 其余事件（状态/计数/日志）不延迟、直通。UI 在 115200bps 下按批次刷新而非逐条刷新。
    /// - Parameter window: 批窗口，默认 33ms；合法范围 clamp 到 16...50ms。
    func batchingRecordEvents(window: Duration = .milliseconds(33),
                              clock: any SessionClock = SystemSessionClock()) -> AsyncStream<SessionEventBatch> {
        let clamped = max(.milliseconds(16), min(.milliseconds(50), window))
        let upstream = self
        return AsyncStream { continuation in
            let task = Task {
                var pending: [CommunicationRecord.ID] = []
                var lastFlush = clock.now()
                var iterator = upstream.makeAsyncIterator()
                while let event = await iterator.next() {
                    if Task.isCancelled { break }
                    switch event {
                    case .recordAppended(let id):
                        pending.append(id)
                        if clock.now() - lastFlush >= clamped {
                            continuation.yield(.records(pending))
                            pending.removeAll(keepingCapacity: true)
                            lastFlush = clock.now()
                        }
                    case .stateChanged(let s):
                        if !pending.isEmpty { continuation.yield(.records(pending)); pending.removeAll(keepingCapacity: true); lastFlush = clock.now() }
                        continuation.yield(.stateChanged(s))
                    case .recordUpdated(let id):
                        continuation.yield(.recordUpdated(id))
                    case .countersChanged(let rx, let tx):
                        continuation.yield(.countersChanged(rxBytes: rx, txBytes: tx))
                    case .logStatusChanged(let s):
                        continuation.yield(.logStatusChanged(s))
                    }
                }
                if !pending.isEmpty { continuation.yield(.records(pending)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public enum SessionEventBatch: Sendable {
    case records([CommunicationRecord.ID])
    case stateChanged(SessionState)
    case recordUpdated(CommunicationRecord.ID)
    case countersChanged(rxBytes: Int, txBytes: Int)
    case logStatusChanged(LogStatus)
}
```

> 说明：批处理是**拉取侧节流**——上游事件一个不少，下游渲染按窗口合并。`RecordStore` 写入与日志 append 不经过批处理，保证数据完整性（§12.1「切换 ASCII/HEX 只重建展示投影」同理）。

### 6.2 `SendRequest` —— 三来源统一入口

```swift
// SerialMonitor/Application/SendRequest.swift
import Foundation

/// manual / autoSend / preset 统一构造 SendRequest 后进入同一 FIFO 队列。
/// 编码与合法性校验（HEX 偶数字符、非空、间隔合法）在进入本对象之前由
/// ViewModel/Domain 完成（02）；非法请求根本不会到达 SessionCoordinator。
public struct SendRequest: Sendable, Equatable {
    public let bytes: Data                     // 已编码、已追加行结束符的最终字节
    public let displayFormat: DisplayFormat    // 记录与日志的 format 字段
    public let source: SendSource              // .manual / .autoSend / .preset
    public let presetSnapshot: PresetSnapshot? // source == .preset 时必有

    public init(bytes: Data, displayFormat: DisplayFormat,
                source: SendSource, presetSnapshot: PresetSnapshot? = nil) {
        precondition(!bytes.isEmpty, "emptyPayload 应在 Domain 校验阶段拦截")
        self.bytes = bytes
        self.displayFormat = displayFormat
        self.source = source
        self.presetSnapshot = presetSnapshot
    }
}
```

### 6.3 `SessionClock` —— 时钟抽象

```swift
// SerialMonitor/Application/SessionClock.swift
import Foundation

/// 单调时钟抽象：调度间隔计算与批处理窗口必须使用单调时钟（需求 §12.2「按单调时钟重新计算」）。
public protocol SessionClock: Sendable {
    func now() -> ContinuousClock.Instant
    func sleep(for duration: Duration) async throws
}

public struct SystemSessionClock: SessionClock {
    public init() {}
    public func now() -> ContinuousClock.Instant { ContinuousClock.now }
    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
```

### 6.4 `SessionCoordinator` —— 完整公开 API 与内部骨架

```swift
// SerialMonitor/Application/SessionCoordinator.swift
import Foundation

/// 应用层唯一会话协调者（需求 §9、§11.2、§12.1）。
/// 所有权铁律：
///  - 唯一持有 SerialPorting 实例；连接生命周期、RX 任务、连接事件任务在此出生、在此死亡。
///  - 唯一持有调度任务槽位（自动发送/预设循环，任务体由 05 注册）；启动新任务前取消并 await 旧任务。
///  - TX 唯一入口为 send(_:)，经内部 FIFO 队列串行写串口。
/// 线程模型：actor 隔离保证全部内部状态串行访问；port I/O 发生在 actor 内的 Task，
/// 不在 MainActor；事件经 AsyncStream 单向发布。
public actor SessionCoordinator {

    // MARK: 依赖（构造注入，测试可替换）
    private let port: any SerialPorting
    private let recordStore: RecordStore
    private var logService: any LogServicing
    private let clock: any SessionClock
    private let autoStartLogOnConnect: Bool   // 来自设置「连接成功自动记录」（06 接线，本期由构造参数传入）

    // MARK: 可观察状态（actor 隔离；UI 经 events() 订阅变化）
    public private(set) var state: SessionState = .disconnected

    // MARK: 内部任务与队列
    private var rxTask: Task<Void, Never>?
    private var connectionEventTask: Task<Void, Never>?
    private var scheduledTasks: [ScheduledTaskKind: Task<Void, Never>] = [:]
    private let txQueue = TXSendQueue()

    // MARK: 事件发布
    private var eventContinuation: AsyncStream<SessionEvent>.Continuation?
    private lazy var eventStream: AsyncStream<SessionEvent> = AsyncStream { [weak self] continuation in
        Task { await self?.setEventContinuation(continuation) }
    }

    public init(port: any SerialPorting,
                recordStore: RecordStore,
                logService: any LogServicing = NullLogService(),
                clock: any SessionClock = SystemSessionClock(),
                autoStartLogOnConnect: Bool = false) {
        self.port = port
        self.recordStore = recordStore
        self.logService = logService
        self.clock = clock
        self.autoStartLogOnConnect = autoStartLogOnConnect
    }

    // MARK: - 公开 API

    /// 对 UI 的事件流。多次调用返回同一流的迭代视图（fan-out 由 ViewModel 单订阅承担，见 04）。
    public nonisolated func events() -> AsyncStream<SessionEvent> { eventStream }

    /// 用户打开（或从 error 重试）。仅 disconnected / error 可进入；
    /// 其余状态调用抛 ValidationError.invalidSetting 并被忽略（防御性，UI 层已禁用按钮）。
    public func connect(configuration: SerialConfiguration) async throws {
        switch state {
        case .disconnected, .error: break
        case .opening, .connected, .closing:
            throw ValidationError.invalidSetting("当前状态不允许发起连接")
        }
        await cancelAllScheduledTasks(reason: .reconnect)          // §11.2 行1附加动作：取消旧任务
        transition(to: .opening(configuration: configuration))     // 参数锁定体现在状态关联值
        do {
            try await port.open(configuration: configuration)
        } catch {
            let sessionError = mapOpenError(error)                 // 结构化错误（§6.5）
            transition(to: .error(SessionErrorContext(error: sessionError,
                                                      failedConfiguration: configuration)))
            throw sessionError                                     // 恢复可编辑配置由 UI 按 error 上下文处理
        }
        startRXStream()                                            // §11.2 行2附加动作
        startConnectionEventMonitor()
        transition(to: .connected(session: ConnectedSession(configuration: configuration,
                                                            connectedAt: Date())))
        if autoStartLogOnConnect { await startLogIfPossible() }    // §11.2 行2附加动作：按需启动日志
    }

    /// 用户关闭。connected / error 可调用；error 下调用视为「关闭并清理」，落到 disconnected。
    public func disconnect() async {
        switch state {
        case .disconnected, .closing: return                       // 幂等：重复点击不产生副作用
        case .opening:
            // opening 期间取消：尽力关闭底层资源后回 disconnected
            transition(to: .closing(previous: currentConfiguration))
            await teardownPort()
            transition(to: .disconnected)
        case .connected(let session):
            transition(to: .closing(previous: session.configuration))
            await cancelAllScheduledTasks(reason: .userStop)       // §11.2 行4：停止发送调度
            await flushAndStopLog()                                // §11.2 行4：flush 日志
            await teardownPort()
            transition(to: .disconnected)                          // §11.2 行6：允许新连接
        case .error(let context):
            transition(to: .closing(previous: context.failedConfiguration ?? currentConfiguration))
            await cancelAllScheduledTasks(reason: .userStop)
            await flushAndStopLog()
            await teardownPort()
            transition(to: .disconnected)
        }
    }

    /// 唯一发送入口。成功返回 TX 记录 id（sendResult 已回填 success）；
    /// 写失败抛 SessionError 且记录已回填 failed。
    @discardableResult
    public func send(_ request: SendRequest) async throws -> CommunicationRecord.ID {
        guard case .connected = state else { throw ValidationError.notConnected }   // §5.3 前置条件
        let record = CommunicationRecord(
            id: UUID(), timestamp: Date(),
            direction: .tx, rawBytes: request.bytes,
            displayFormat: request.displayFormat, source: request.source,
            sendResult: .pending,                       // §5.3：排入队列即创建记录
            presetSnapshot: request.presetSnapshot)
        await recordStore.append(record)
        emit(.recordAppended(record.id))
        do {
            try await txQueue.enqueue(bytes: request.bytes, recordID: record.id, using: port)
        } catch let error as SessionError {
            await recordStore.updateSendResult(record.id, .failed(error.systemDescription))
            emit(.recordUpdated(record.id))
            if error.category == .deviceDisconnected || error.category == .writeFailed {
                await enterError(error)                 // 不可恢复：转 error 并停止一切发送
            }
            throw error
        }
        await recordStore.updateSendResult(record.id, .success)
        emit(.recordUpdated(record.id))
        let c = await recordStore.counters
        emit(.countersChanged(rxBytes: c.rxBytes, txBytes: c.txBytes))
        return record.id
    }

    /// 05 的挂接点：注册/替换调度任务。启动新任务前取消并 await 旧任务（需求 §12.1）。
    /// V1.0 互斥规则：.autoSend 与 .presetLoop 不得同时存在（05 在注册前调用对侧取消）。
    public func registerScheduledTask(_ kind: ScheduledTaskKind, task: Task<Void, Never>) async {
        if let old = scheduledTasks[kind] { old.cancel(); _ = await old.value }
        scheduledTasks[kind] = task
    }

    /// 停止指定调度任务（05 / 状态栏停止按钮）。
    public func cancelScheduledTask(_ kind: ScheduledTaskKind) async {
        guard let task = scheduledTasks.removeValue(forKey: kind) else { return }
        task.cancel()
        _ = await task.value
    }

    /// 应用退出（需求 §13「应用退出」）：确定性顺序——停调度 → 停队列 → flush 日志 → 关端口。
    /// 由 AppDelegate applicationShouldTerminate 链路调用（04/08 接线），结束后进程方可退出。
    public func prepareForTermination() async {
        await cancelAllScheduledTasks(reason: .appTermination)
        await txQueue.cancelAndDrain()                  // 丢弃待发送项，等待在途写结束
        rxTask?.cancel(); _ = await rxTask?.value; rxTask = nil
        connectionEventTask?.cancel(); _ = await connectionEventTask?.value; connectionEventTask = nil
        await flushAndStopLog()
        await teardownPort()
        transition(to: .disconnected)
    }

    // MARK: - RX 管线（§12.1：Device → Adapter → 本 actor → RecordStore → 投影/日志）

    private func startRXStream() {
        rxTask?.cancel()
        rxTask = Task { [port, recordStore, weak self] in
            do {
                for try await chunk in port.incomingBytes() {     // 每个数据块 = 一条 RX 记录（§5.2）
                    if Task.isCancelled { break }
                    let record = CommunicationRecord(
                        id: UUID(), timestamp: Date(),
                        direction: .rx, rawBytes: chunk,
                        displayFormat: .ascii,                    // 展示格式只是投影偏好，原始字节为准
                        source: .serial, sendResult: .success, presetSnapshot: nil)
                    await recordStore.append(record)
                    await self?.handleRXAppended(record.id, bytes: chunk)
                }
            } catch {
                if !Task.isCancelled {
                    await self?.handleRXFailure(error)            // 读失败 → error（§11.2 行5）
                }
            }
        }
    }

    private func handleRXAppended(_ id: CommunicationRecord.ID, bytes: Data) {
        emit(.recordAppended(id))
        Task { [logService] in try? await logService.append(record: recordPlaceholder(id)) }
        // 注：日志 append 失败通过 LogServicing 内部状态上报（见 §6.5 LogServicing.onFailure），
        // 按 §13 只停日志不停会话。
    }

    private func handleRXFailure(_ error: any Error) {
        let sessionError = SessionError(category: .readFailed,
                                        systemCode: (error as NSError).code == 0 ? nil : (error as NSError).code,
                                        systemDescription: error.localizedDescription,
                                        occurredAt: Date(), isRetryable: false)
        Task { await enterError(sessionError) }
    }

    // MARK: - 连接事件（拔出 / 驱动错误）

    private func startConnectionEventMonitor() {
        connectionEventTask?.cancel()
        connectionEventTask = Task { [port, weak self] in
            for await event in port.connectionEvents() {
                if Task.isCancelled { break }
                switch event {
                case .deviceRemoved:
                    await self?.handleDeviceRemoved()
                case .driverError(let description):
                    await self?.enterError(SessionError(category: .deviceDisconnected,
                                                        systemCode: nil,
                                                        systemDescription: description,
                                                        occurredAt: Date(), isRetryable: false))
                }
            }
        }
    }

    private func handleDeviceRemoved() {
        // §11.2 行5：立刻取消发送、保留错误上下文、结束日志、进入 error
        enterError(SessionError(category: .deviceDisconnected, systemCode: nil,
                                systemDescription: "Device removed", occurredAt: Date(),
                                isRetryable: true))               // 重插后可重试
    }

    // MARK: - 状态机对接（转换合法性由 02 SessionStateMachine 裁决）

    private func transition(to newState: SessionState) {
        // 02 的纯函数状态机做合法性校验；非法转换是程序错误，直接断言（测试期暴露）。
        let event = SessionStateEvent.from(target: newState)      // 02 提供的目标态→事件映射辅助
        if let validated = SessionStateMachine.transition(from: state, event: event) {
            state = validated
        } else {
            assertionFailure("非法状态转换: \(state) -> \(newState)")
            state = newState                                      // Release 下容错前进，不崩溃
        }
        emit(.stateChanged(state))
    }

    private func enterError(_ error: SessionError) {
        guard case .connected = state, !state.isError else { return }
        transition(to: .error(SessionErrorContext(error: error,
                                                  failedConfiguration: currentConfiguration)))
        Task {
            await cancelAllScheduledTasks(reason: .error)         // §5.4：停止所有自动发送
            await txQueue.cancelAndDrain()
            await flushAndStopLog()                               // §13 拔出：结束日志
            await teardownPort()                                  // 尽力释放 fd；失败不影响 error 落定
        }
    }

    // MARK: - 资源与日志生命周期

    private func teardownPort() async {
        rxTask?.cancel(); _ = await rxTask?.value; rxTask = nil
        connectionEventTask?.cancel(); _ = await connectionEventTask?.value; connectionEventTask = nil
        await port.close()                                        // close 必须幂等（01 契约）
    }

    private func startLogIfPossible() async {
        do {
            try await logService.start()
            emit(.logStatusChanged(.recording(fileName: logService.currentFileName ?? "")))
        } catch {
            // §13：日志失败 → 显示路径与错误、停止日志、不影响会话
            emit(.logStatusChanged(.failed(reason: error.localizedDescription)))
        }
    }

    private func flushAndStopLog() async {
        try? await logService.flush()
        await logService.stop()
        emit(.logStatusChanged(.idle))
    }

    // MARK: - 工具

    private var currentConfiguration: SerialConfiguration {
        switch state {
        case .opening(let c), .closing(let c): return c
        case .connected(let s): return s.configuration
        case .error(let ctx): return ctx.failedConfiguration ?? placeholderConfiguration
        case .disconnected: return placeholderConfiguration
        }
    }

    private func cancelAllScheduledTasks(reason: StopReason) async {
        for (_, task) in scheduledTasks { task.cancel() }
        for (_, task) in scheduledTasks { _ = await task.value }
        scheduledTasks.removeAll()
    }

    private func emit(_ event: SessionEvent) { eventContinuation?.yield(event) }
    private func setEventContinuation(_ c: AsyncStream<SessionEvent>.Continuation) { eventContinuation = c }
}

public enum ScheduledTaskKind: String, Sendable { case autoSend, presetLoop }
public enum StopReason: String, Sendable { case userStop, reconnect, error, appTermination }
```

> 实现说明（骨架中的占位须在编码时补全，均为机械工作）：
> - `recordPlaceholder(_:)`：从 `recordStore.record(id)` 取回记录传给日志；骨架压缩为一行。
> - `placeholderConfiguration`：仅在无历史配置的边角路径使用，取 02 的 `SerialConfiguration.default`。
> - `SessionStateEvent.from(target:)`：02 提供的辅助；若 02 未提供，则在本文档实现为一个 `private` 映射函数并**回写 02 文档缺口**到 00 文档第 9 节。

### 6.5 `TXSendQueue` —— FIFO 串行写泵

```swift
// SerialMonitor/Application/TXSendQueue.swift
import Foundation

/// 仅由 SessionCoordinator 持有的 actor：保证同一时刻至多一个 port.write 在途（防重入）。
/// 下一次发送必须等上一次完成或明确失败后才发起（需求 §5.4、§12.2）。
actor TXSendQueue {
    private struct Item {
        let bytes: Data
        let recordID: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var pending: [Item] = []
    private var isPumping = false
    private var isCancelled = false

    /// 入队并等待本次写完成（或失败）。调用方（SessionCoordinator.send）因此天然串行。
    func enqueue(bytes: Data, recordID: UUID, using port: any SerialPorting) async throws {
        if isCancelled { throw CancellationError() }
        try await withCheckedThrowingContinuation { continuation in
            pending.append(Item(bytes: bytes, recordID: recordID, continuation: continuation))
            if !isPumping { isPumping = true; Task { await pump(port: port) } }
        }
    }

    /// 丢弃全部待发送项（恢复 CancellationError），等待在途写结束。断开/错误/退出时调用。
    func cancelAndDrain() async {
        isCancelled = true
        let dropped = pending
        pending.removeAll()
        for item in dropped { item.continuation.resume(throwing: CancellationError()) }
        while isPumping { try? await Task.sleep(for: .milliseconds(1)) }  // 等在途 write 落定
        isCancelled = false                                                // 允许后续会话复用
    }

    private func pump(port: any SerialPorting) async {
        defer { isPumping = false }
        while !pending.isEmpty {
            let item = pending.removeFirst()
            do {
                try await port.write(item.bytes)         // 串行点：await 期间不会有第二个 write
                item.continuation.resume()
            } catch {
                let mapped = (error as? SessionError) ?? SessionError(
                    category: .writeFailed, systemCode: (error as NSError).code,
                    systemDescription: error.localizedDescription,
                    occurredAt: Date(), isRetryable: false)
                item.continuation.resume(throwing: mapped)
                // 写失败后仍继续服务后续排队项；是否进入 error 由 SessionCoordinator 按分类裁决。
            }
        }
    }
}
```

### 6.6 `LogServicing` 与 `NullLogService`

```swift
// SerialMonitor/Application/LogServicing.swift
import Foundation

/// 日志生命周期挂接点（需求 §6.1）。P2 由 06 文档交付 JSONL 落盘实现；
/// 本阶段仅定义协议并提供空实现，验证挂接时机正确。
/// 约束：所有方法不得阻塞调用方超过常数时间；真实实现的磁盘 I/O 在内部 actor 串行执行。
public protocol LogServicing: Sendable {
    /// 开始记录：创建文件（真实实现按命名规则 SerialMonitor_yyyyMMdd_HHmmss_<port>.log）。
    func start() async throws
    /// 追加一条记录（串行异步；UI 不等待磁盘 I/O）。
    func append(record: CommunicationRecord) async throws
    /// 落盘冲刷：停止记录 / 关闭会话 / 退出前必须调用（§6.1 结束行为）。
    func flush() async throws
    /// 停止并关闭。幂等。
    func stop() async
    /// 当前文件名（状态栏/日志面板展示用）。
    var currentFileName: String? { get }
}

/// 本阶段默认实现：全部 no-op，仅记录状态以便测试断言挂接顺序。
public actor NullLogService: LogServicing {
    public private(set) var currentFileName: String? = nil
    public private(set) var callOrder: [String] = []   // 测试断言用：["start","append",...,"flush","stop"]
    public init() {}
    public func start() async throws { callOrder.append("start"); currentFileName = "null.log" }
    public func append(record: CommunicationRecord) async throws { callOrder.append("append") }
    public func flush() async throws { callOrder.append("flush") }
    public func stop() async { callOrder.append("stop"); currentFileName = nil }
}
```

### 6.7 错误分类与用户反馈映射（需求 §13 表落地）

```swift
// SerialMonitor/Application/ErrorUserFeedback.swift
import Foundation

/// §13「错误信息不得只显示底层系统码」：每条反馈含 发生了什么 / 影响 / 可以怎么做。
/// 字符串为 String Catalog key（04 负责解析与渲染；详细错误放可复制展开区域）。
public struct ErrorUserFeedback: Sendable, Equatable {
    public let summaryKey: String      // 发生了什么
    public let impactKey: String       // 影响是什么
    public let recoveryKey: String     // 可以怎么做
    public let offersRetry: Bool
    public let offersRefresh: Bool     // 端口占用/不存在时提供「刷新」
}

public enum ErrorUserFeedbackMapper {
    public static func feedback(for error: SessionError) -> ErrorUserFeedback {
        switch error.category {
        case .portUnavailable:
            return .init(summaryKey: "error.portUnavailable.summary",      // 「端口 xxx 不存在或已被占用」
                         impactKey: "error.portUnavailable.impact",        // 「未建立连接」
                         recoveryKey: "error.portUnavailable.recovery",    // 「刷新端口列表或关闭占用程序后重试」
                         offersRetry: true, offersRefresh: true)
        case .openFailed, .unsupportedConfiguration:
            return .init(summaryKey: "error.openFailed.summary",
                         impactKey: "error.openFailed.impact",
                         recoveryKey: "error.openFailed.recovery",         // 「检查参数后重试」
                         offersRetry: true, offersRefresh: false)
        case .deviceDisconnected:
            return .init(summaryKey: "error.deviceRemoved.summary",        // 「设备已断开」
                         impactKey: "error.deviceRemoved.impact",          // 「已停止所有发送并结束日志」
                         recoveryKey: "error.deviceRemoved.recovery",      // 「重新连接设备后重试」
                         offersRetry: true, offersRefresh: true)
        case .readFailed, .writeFailed:
            return .init(summaryKey: "error.ioFailed.summary",
                         impactKey: "error.ioFailed.impact",               // 「会话已停止，自动发送已取消」
                         recoveryKey: "error.ioFailed.recovery",
                         offersRetry: true, offersRefresh: false)
        }
    }
}
```

**离开 error 状态的纪律（§11.2 行7）**：`SessionCoordinator` 中只有两条路径离开 `.error`——显式 `connect(configuration:)`（重试）与显式 `disconnect()`（关闭清理）。`enterError` 外的任何内部任务结束、流终止、计数变化都不得触碰状态机。该纪律由 §9.5 测试固化。

---

## 7. 实现步骤（按依赖排序）

### 步骤 1：时钟与发送请求模型

- **做什么**：创建 `SessionClock.swift`、`SendRequest.swift`（照抄 §6.3、§6.2）。
- **产出**：两个文件编译通过。
- **自验证**：`swift build` 通过；`SystemSessionClock().now()` 单调性单测（连续两次调用后值不减）。

### 步骤 2：TX 队列

- **做什么**：创建 `TXSendQueue.swift`（照抄 §6.5）。
- **产出**：actor 化 FIFO 队列。
- **自验证**：`swift test --filter TXSendQueueTests`——并发 50 个 enqueue，用 Mock 记录 write 调用序列，断言严格 FIFO 且任意时刻在途 write ≤ 1。

### 步骤 3：SessionCoordinator 主体

- **做什么**：创建 `SessionCoordinator.swift`、`SessionEvent.swift`（照抄 §6.4、§6.1 并补全骨架占位），对照需求 §11.2 表逐行核对附加动作：

| §11.2 行 | 转换 | 附加动作落实位置 |
|---|---|---|
| 1 | disconnected→opening | `connect`：`cancelAllScheduledTasks` + 参数锁定于 `.opening(configuration:)` |
| 2 | opening→connected | `startRXStream()` + `startConnectionEventMonitor()` + `startLogIfPossible()` |
| 3 | opening→error | `mapOpenError` 结构化错误 + `failedConfiguration` 存入上下文 |
| 4 | connected→closing | `disconnect`：`cancelAllScheduledTasks(.userStop)` + `flushAndStopLog()` |
| 5 | connected→error | `enterError`：立即 `txQueue.cancelAndDrain` + 保留上下文 + 结束日志 |
| 6 | closing→disconnected | `teardownPort()` 完成后转换，emit 状态 |
| 7 | error→closing/opening | 仅 `connect` / `disconnect` 显式入口，无其他路径 |

- **产出**：核心 actor。
- **自验证**：`swift build` 零警告；`swift test --filter SessionCoordinatorConnectTests` 全绿（§9.2 用例 1–8）。

### 步骤 4：RX 管线与批处理投影

- **做什么**：落实 `startRXStream` / `handleRXAppended` 与 `batchingRecordEvents`。
- **自验证**：`swift test --filter SessionCoordinatorRXTests`（§9.4）；其中高流量用例：Mock 注入 5,000 块 × 2ms，断言 RecordStore 收到 5,000 条且批事件次数显著小于 5,000（≥ 10× 合并）。

### 步骤 5：日志挂接点

- **做什么**：创建 `LogServicing.swift`（协议 + `NullLogService`），接通 `startLogIfPossible` / `flushAndStopLog`。
- **自验证**：`swift test --filter SessionCoordinatorLifecycleTests` 中用 `NullLogService.callOrder` 断言：connect（autoStartLog=true）→ `["start", ...]`；disconnect → 尾部为 `["flush", "stop"]`；error 路径同样以 `flush, stop` 收尾。

### 步骤 6：错误映射

- **做什么**：创建 `ErrorUserFeedback.swift`；实现 `mapOpenError`（把 01 的底层错误按 errno/库错误类型映射为 `SessionError.Category`：占用/不存在 → `.portUnavailable`，参数拒绝 → `.unsupportedConfiguration`，其余 → `.openFailed`）。
- **自验证**：`swift test --filter ErrorMappingTests`——每个 Category 至少一例底层错误输入，断言分类与 `isRetryable` 正确。

### 步骤 7：退出流程

- **做什么**：落实 `prepareForTermination()`，顺序固定为：取消调度 → `txQueue.cancelAndDrain` → 取消 RX/事件任务 → `flushAndStopLog` → `teardownPort` → 转 disconnected。
- **自验证**：§9.5 退出用例——用 Mock 记录调用顺序，断言严格按上述序列且全程无崩溃、无任务泄漏（退出后 `ScheduledTaskKind` 全部为空）。

### 步骤 8：集成测试

- **做什么**：`PseudoTerminalSessionTests.swift`——`openpty` 建伪终端对，01 的真实适配器接 slave 端路径，协调器 connect → master 端写入 → 断言 RX 记录字节一致；协调器 send → master 端读回断言一致；关闭 master → 断言状态进入 error（deviceDisconnected）。
- **自验证**：`swift test --filter PseudoTerminalSessionTests` 全绿。

---

## 8. 验收标准（映射需求文档 §16）

| AC 编号 | §16 通过条件 | 本文档验证方式 |
|---|---|---|
| AC-02 | 正确参数可连接；被占用或不存在端口有清晰错误；状态机无非法跳转 | §9.2 用例 1–8：全转换表覆盖 + 非法转换断言；Mock 脚本化 EBUSY/ENOENT → `.portUnavailable` 结构化错误（§13 映射含重试/刷新） |
| AC-03 | 连续 RX 可在 ASCII/HEX 下显示；暂停时仍记录并可恢复展示 | 本文档负责「连续 RX 逐块入 RecordStore 且不丢」（§9.4）；ASCII/HEX 显示与暂停投影属 04，依赖本文档事件流完整性验证 |
| AC-04 | ASCII、HEX、CRLF 可正确发送；非法 HEX 与未连接状态均被阻止 | §9.3：编码后字节经 TX 队列正确写出（伪终端读回比对）；未连接 `send` 抛 `ValidationError.notConnected`；非法 HEX 由 02 校验拦截（本文档 `SendRequest` precondition 兜底断言） |

---

## 9. 测试要求

### 9.1 `MockSerialPorting` 能力要求（`Tests/Support/MockSerialPorting.swift`）

必须支持脚本化：

```swift
final class MockSerialPorting: SerialPorting, @unchecked Sendable {
    enum OpenBehavior { case success, failure(SessionError), delayedSuccess(Duration) }
    var openBehavior: OpenBehavior = .success
    var writeBehavior: (Data) -> Result<Void, Error> = { _ in .success(()) }
    var writeDelay: Duration = .zero                       // 模拟慢写，验证防重入
    // RX：由测试向 rxContinuation yield Data 或 finish(throwing:)
    // 拔出：调用 simulateDeviceRemoval() 向 connectionEvents 发 .deviceRemoved
    // 观测：recordedWrites: [Data]、openCallCount、closeCallCount（断言生命周期配对）
}
```

- `open` 按 `openBehavior` 成功/失败/延时成功；失败抛注入的 `SessionError`。
- `write` 记录每次写入字节到 `recordedWrites`，可按脚本失败第 N 次。
- `incomingBytes()` 返回测试可控 stream（`yield` / `finish(throwing:)`）。
- `connectionEvents()` 返回测试可控 stream；`simulateDeviceRemoval()` 触发拔出。
- `close()` 幂等并计数（断言 connect/disconnect/退出路径 close 恰好一次）。

### 9.2 连接与状态机事件序列（`SessionCoordinatorConnectTests.swift`，用 ManualSessionClock）

1. `disconnected → connect(有效) → opening → connected`，事件流顺序为 `.stateChanged(.opening)` → `.stateChanged(.connected)`。
2. opening 期间 `port.open` 挂起时调用 `disconnect()` → 落到 `disconnected`，close 被调用。
3. open 抛 EBUSY 映射错误 → `.error`，`failedConfiguration` 保留；再次 `connect` 可重试（→ opening）。
4. open 失败后再 `send` → 抛 `notConnected`；状态保持 error。
5. connected → `disconnect()` → closing → disconnected；事件序列完整；log `callOrder` 尾部 flush→stop。
6. connected 时 `simulateDeviceRemoval()` → error(deviceDisconnected)；TX 队列被清空；log flush→stop。
7. error 状态下除 `connect`/`disconnect` 外无任何路径改变状态（RX 流结束、计数事件均不改变）。
8. 全表非法转换断言：对 02 状态机穷举 5×N 状态×事件，非法组合返回 nil（与 02 的测试互补，此处验证协调器不触发非法转换）。

### 9.3 TX 管线（`SessionCoordinatorTXTests.swift`）

1. 三个来源（manual/autoSend/preset 构造的 `SendRequest`）交错 send 50 次，`recordedWrites` 严格等于入队顺序。
2. `writeDelay = 5ms` 下并发 send：任意时刻在途 write ≤ 1（Mock 内计数器断言）——防重入。
3. 排队即建记录：send 返回前 RecordStore 已存在 `sendResult == .pending` 的 TX 记录；写完成后回填 `.success`。
4. 第 3 次写失败 → 该记录 `.failed(reason)`，send 抛 `SessionError.writeFailed`，协调器进入 error，后续排队项收到 `CancellationError`。
5. `presetSnapshot` 原样落入记录（source == .preset）。
6. error 后 `connect` 重试成功，TX 队列可再次服务（`isCancelled` 复位验证）。

### 9.4 RX 管线（`SessionCoordinatorRXTests.swift`）

1. Mock yield 3 个 Data 块 → RecordStore 恰有 3 条 RX 记录，字节、时间戳单调递增。
2. 高流量：5,000 块 × 2ms 注入 → 记录全量入库；`batchingRecordEvents(window: 33ms)` 输出批次数 < 500；批次内 ID 顺序与到达顺序一致。
3. RX 流 `finish(throwing:)` → 状态转 error(readFailed)。
4. 状态/日志事件不被批窗口延迟（批投影直通验证）。

### 9.5 生命周期与退出（`SessionCoordinatorLifecycleTests.swift`）

1. `prepareForTermination` 在 connected 状态调用：Mock 观测顺序 = 取消调度 → drain → close；log `callOrder` 尾部 flush→stop；终态 disconnected。
2. 在 error 状态调用 `prepareForTermination`：不崩溃，close 幂等（closeCallCount 不重复增长）。
3. `registerScheduledTask` 同 kind 重复注册：旧任务被 cancel 且 await 完成（任务内 flag 断言）。
4. 日志 start 失败（自定义 LogServicing 抛错）：会话仍 connected，事件含 `.logStatusChanged(.failed)`。

### 9.6 伪终端集成（`PseudoTerminalSessionTests.swift`）

1. openpty 对 + 真实适配器 connect → master 写入 `0x55 0xAA` → RecordStore RX 记录字节一致。
2. send ASCII 编码字节 → master 读回一致；CRLF 追加由 02 编码器产出，此处端到端验证。
3. 关闭 master fd → 协调器进入 error(deviceDisconnected)。

---

## 10. 防漫游约束（重申，逐条有效）

1. **只做 §5 文件清单内的 14 个文件**；发现必须改动清单外文件（含 01/02 已交付文件）时，停止该分支工作并记录，不得自行扩大范围。
2. **不引入未列依赖**：本文档零第三方依赖；Foundation 以外 import 出现即为越界。
3. 接口契约以 §6 的 Swift 定义为准；与 01/02 实际签名冲突时，以 01/02 为准改调用点，并在 00 文档第 9 节追加风险记录（R6 起），**不静默改 01/02 签名**。
4. 不实现 Out of scope 内容：不写自动发送/预设循环任务体（05）、不写 JSONL 落盘（06）、不碰 SwiftUI/AppKit（04）。
5. 不做顺手重构、格式化、重命名无关代码；02 的 Domain 类型即使命名不合手也不得改。
6. 每个实现步骤完成后必须运行其自验证命令，红了先修，不跳步。
7. 需求矛盾或信息缺失（例如 02 未提供 `SessionStateEvent.from(target:)`）时，记录到 00 文档第 9 节「风险与决策点」并停止该分支，不自行发明需求。
