# 自动化测试矩阵

`zsh Scripts/run-automated-tests.zsh` 是本项目的日常本地回归入口。它只使用 mock、PTY 与 UI 场景替身，不访问 USB-UART、Bluetooth 或 debug-console。

## 运行模式

| 命令 | 阶段 |
|---|---|
| `run-automated-tests.zsh` / `--all` / `--ci` | SerialCore → App 单元/PTY → UI |
| `--quick` | SerialCore → App 单元/PTY（跳过 UI） |
| `--ui-only` | 仅 XCUITest |
| `--stress` | 默认套件 + `Scripts/pty_stress.py`（默认 30 分钟） |
| `--stress-minutes N` | 调整 Py PTY 压测时长 |
| `--xctest-stress` | 追加 `PTYStressTests`（30 分钟） |
| `--release` | App 单元/UI 使用 Release 配置 |

每次运行把 `.xcresult`、逐阶段日志、覆盖率报告与 `summary.json` / `summary.md`
写入 gitignore 的 `TestArtifacts/<时间戳>/`。任一阶段失败时退出码非零并列出失败阶段。

## 覆盖矩阵

| 阶段 | 验收能力 | 自动化层级 | 状态 |
|---|---|---|---|
| P0 | SerialCore 配置与 errno 映射 | Swift Package Unit | 已覆盖 |
| P0 | POSIX 打开、双向收发、关闭、自定义波特率 | PTY Integration | 已覆盖 |
| P0 | USB-UART、Sandbox、物理拔出 | 不适用（无实机） | 未验证（阻塞） |
| P1 | 编码、状态机、FIFO、取消、错误恢复、统计 | Unit / Mock Integration | 已覆盖 |
| P1 | 115200-bps 长时收包与缓存截断 | PTY Stress（`--stress` / `--xctest-stress`） | 已覆盖 |
| P2 | 工作区、端口、连接/取消、参数锁定、批量收包、设备移除、预设面板、最小窗口、多窗口独立会话 | XCUITest 场景替身 | 已覆盖 |
| P2 | ASCII/HEX 投影切换、暂停/恢复、清空、发送失败、统计与重连 | ViewModel / UI | 已覆盖 |
| P2 | 原生 Glass 与 Material 的人工视觉走查 | 手工 | 未自动化（见 UITestChecklist） |
| P3 | 自动发送、预设 CRUD/循环、NDJSON 日志、设置、菜单与快捷键 | Unit / Mock / UI | 已覆盖 |
| P3 | 损坏 preferences/preset 回退与备份 | Domain Unit | 已覆盖 |
| P4 | Py PTY 吞吐/内存/停顿指标 | `Scripts/pty_stress.py` | 已覆盖 |
| P4 | 签名、公证、兼容性矩阵与发布验证 | 发布流程 | 待执行（凭据/硬件阻塞） |

## 覆盖率

`app-unit`、`app-ui`、`pty-stress` 阶段分别产出 `*-coverage.txt`。当前只记录，不设百分比门禁。

PTY 不能证明 USB-UART 驱动、App Sandbox 串口权限或物理热拔出行为。上述项目保持“未验证”，不得因自动化套件通过而标记为兼容。
