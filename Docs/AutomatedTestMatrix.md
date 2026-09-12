# 自动化测试矩阵

`zsh Scripts/run-automated-tests.zsh` 是本项目的日常本地回归入口。它只使用 Mock、PTY 与 UI 场景替身，不访问 USB-UART、Bluetooth 或 debug-console。

| 阶段 | 验收能力 | 自动化层级 | 状态 |
|---|---|---|---|
| P0 | SerialCore 配置与 errno 映射 | Swift Package Unit | 已覆盖 |
| P0 | POSIX 打开、双向收发、关闭 | PTY Integration | 已覆盖 |
| P0 | USB-UART、Sandbox、物理拔出 | 不适用（无实机） | 未验证 |
| P1 | 编码、状态机、FIFO、取消、错误恢复、统计 | Unit / Mock Integration | 已覆盖 |
| P1 | 115200-bps 长时收包与缓存截断 | PTY Stress（`--stress`） | 已覆盖 |
| P2 | 工作区、端口、连接/取消、参数锁定、批量收包、设备移除、预设面板、最小窗口 | XCUITest 场景替身 | 已覆盖 |
| P2 | ASCII/HEX、行结束符、暂停/恢复、清空、发送失败、统计与重连 | ViewModel / Mock Integration | 已覆盖 |
| P2 | 原生 Glass 的人工视觉走查 | 手工 | 未自动化 |
| P3 | 自动发送、预设 CRUD/循环、NDJSON 日志、设置、菜单与快捷键 | Unit / Mock Integration / UI | 已实现；整体压测待试用后决定 |
| P4 | 签名、公证、兼容性矩阵与发布验证 | 发布流程 | 待实现、未执行 |

默认模式运行 Package、App Unit/PTy 与 UI 回归；`--quick` 跳过 UI，`--stress` 在默认回归后追加 30 分钟 PTY 压测。每次运行在 `TestArtifacts/` 保存 `.xcresult`、日志、测试汇总和覆盖率报告；覆盖率当前仅记录，不设百分比门禁。

PTY 不能证明 USB-UART 驱动、App Sandbox 串口权限或物理热拔出行为。上述项目保持“未验证”，不得因自动化套件通过而标记为兼容。
