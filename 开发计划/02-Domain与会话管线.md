# P1 · Domain 与会话管线

## 目标、前置与文件所有权

交付可连接、收发、记录和恢复错误的开发版，并一次性冻结 Presentation 使用的 Application 边界。前置条件是 P0 的 SerialCore 契约与 PTY 测试；真实设备门禁尚未完成时仅可使用 P0 的 mock/PTY 适配器。

本阶段创建 `SerialMonitor/Domain/**`、`SerialMonitor/Application/{SessionCoordinator,SessionClient,SessionEvent,TXSendQueue,LogServicing}.swift` 及对应 Unit/Integration tests。仅允许 P0 的适配器按已冻结 `SerialPorting` 被注入，不改其签名。

## 冻结模型与接口

- Domain 只定义一次：`CommunicationRecord`、`RecordDirection`、`DisplayFormat`、`SendSource`、`SendResult`、`PresetSnapshot`、`LineEnding`、`SessionState`、`SessionError`、`ValidationError`、`RecordStore`、`HexCodec`、`TextPayloadCodec`、`SendPayloadEncoder`。
- `RecordStore` 是 actor，保存原始 `Data`，默认上限 50,000 条或 16 MiB；淘汰最旧项并累积截断次数/时间。清空记录不清字节计数。
- `SessionClient` 是 UI 的唯一入口：`subscribe()`、`refreshPorts()`、`connect(configuration:)`、`disconnect()`、`send(_: SendRequest)`、`clearRecords()`。`SessionCoordinator` 是唯一实现者。
- 每个 `subscribe()` 返回独立 stream。`SessionEvent` 固定为 `portsChanged`、`stateChanged`、`recordsAppended([CommunicationRecord])`、`statisticsChanged`、`logStatusChanged`、`latestErrorChanged`。
- `SessionCoordinator` 用连接尝试 ID 防止已取消的 `open` 恢复后重新连接；所有手动/自动/预设发送最终进入一个 FIFO `TXSendQueue`。

## 实现顺序

1. 先完成纯 Domain 模型、状态机、编码器、格式化器和 RecordStore；HEX 支持空白与设置的额外分隔符，ASCII 无法解码时保留可识别替换字符。
2. 实现纯状态机：`disconnected → opening → connected → closing → disconnected`，打开/读写/拔出错误进入 `error`；仅显式重连或断开可离开 error。
3. 实现多订阅事件 hub 和 `SessionClient`；所有 UI 记录事件按 16–50 ms 批量发布，状态和错误事件直通。
4. 实现协调器与 FIFO 写泵：排队即建立 pending TX 记录，成功/失败回填；写超时、取消、拔出或不可恢复错误取消队列、结束日志并进入 error。
5. 实现确定性退出：停止调度槽位、取消/有界等待 TX、停止 RX/事件、flush 日志、关闭端口、发布 disconnected。此阶段使用 `NullLogService`，但其接口不再变更。

## 验证与完成条件

- Domain 单测覆盖编码、行结束符、状态机非法迁移、缓存截断、原始字节不变和安全文件名清洗。
- 协调器测试覆盖 50 个交错发送的 FIFO 顺序、连接中取消、写超时、拔出、错误重连、多订阅事件与退出顺序。
- PTY 集成测试覆盖 RX/TX、断开和错误映射；`xcodebuild test -scheme SerialMonitor` 全绿。
- P1 结束时，03/04 只允许消费本文件的已实现 `SessionClient`、`SessionEvent` 与 Domain 名称。
