# 发布检查清单

> 状态：脚本就绪，执行受限。签名/公证凭据与真实设备缺失，相关内容标注为阻塞，不得记为通过。

## AC 证据映射（AC-01 … AC-10）

| 编号 | 验收 | 自动化/证据 | 状态 |
|---|---|---|---|
| AC-01 | 端口发现 | `testEventProjection...`、UI 启动/刷新 | 通过（mock/PTY） |
| AC-02 | 连接/关闭/异常/非法状态转移 | `SessionCoordinatorTests`、`testOpeningCanBeCancelled`、`testDeviceRemoval...` | 通过 |
| AC-03 | 原始字节接收与 ASCII/HEX | `testIncomingBytes...`、`testHexDisplayUsesRawUTF8Bytes`、`testReceiveFormatSwitch...` | 通过 |
| AC-04 | 暂停显示、FIFO 发送、输入校验 | `testPausedDisplay...`、`testFiftyInterleavedSends...`、`testHexInputIsRejected...` | 通过 |
| AC-05 | 自动发送互斥 | `testStartingPresetLoopReplacesEditorLoop`、`testDisconnectStopsAutoSendLoop` | 通过 |
| AC-06 | 预设 CRUD/排序/循环与恢复 | 预设相关 ViewModel/UI 测试、`testPresetAndPreferencesStoresRoundTripLocally` | 通过 |
| AC-07 | JSONL、轮转、失败隔离 | `testFileLogServiceWrites...`、`testFileLogServiceRotates...`、`testLoggingFailureIsIsolatedFromSession` | 通过 |
| AC-08 | 设置持久化与即时生效、损坏回退 | `testSettingsDraft...`、`testCorruptPreferences...`、`testCorruptPresets...` | 通过 |
| AC-09 | 菜单/快捷键、深浅色、VoiceOver | `testMenuShortcuts...`、`testAppearanceModes...`；VoiceOver 实读待人工 | 部分通过 |
| AC-10 | 115200 bps 30 分钟 | `--stress`（Py + XCTest）；Instruments 待人工 | 待执行 |

## 可访问性

| 项 | 证据 | 状态 |
|---|---|---|
| 控件标签/取值 | `testCoreControlsExposeAccessibleLabelsAndValues` | 通过 |
| Reduce Motion | `ReceiveConsole` 依据 `accessibilityReduceMotion` 关闭跟随动画 | 代码就绪，待人工走查 |
| 深浅色 | `testAppearanceModesKeepWorkspaceUsable` | 通过 |
| VoiceOver 实读、对比度、键盘全路径 | 无自动化 | 待人工 |

## 发布流程

1. `zsh Scripts/run-automated-tests.zsh --all`（必要时 `--stress`）全绿。
2. `bash Scripts/build_release.sh` 归档并导出（需 Developer ID，未配置则阻塞）。
3. `bash Scripts/notarize.sh <archive>` 提交/等待/staple（需钥匙串 profile，未配置则阻塞）。
4. `bash Scripts/verify_release.sh <app>` 验证签名、entitlement、Gatekeeper、公证与包内无用户数据。
5. 在 macOS 26 与 macOS 14–25 归档同场景截图；完成 `Docs/RealDeviceTestMatrix.md`。
6. 全部勾选后生成 RC。

## 跨版本与硬件证据

| 项 | 入口 | 状态 |
|---|---|---|
| macOS 26/27 本机 | `zsh Scripts/run-automated-tests.zsh --all`（本机） | 通过 |
| macOS 15 跨版本 | `.github/workflows/regression.yml` 的 `app` job（macos-15 + Xcode 26） | CI 运行 |
| macOS 14 核心 | `serialcore` job（macos-14，`swift test`） | CI 运行 |
| macOS 14 App 运行时 | 需 14 主机/VM | 阻塞（未覆盖） |
| 真实设备矩阵 | `bash Scripts/hardware-smoke.sh --port /dev/cu.<device>` + `Docs/RealDeviceTestMatrix.md` | 待硬件执行 |

## 阻塞项

- 无 Developer ID / 公证凭据：步骤 2–4 无法真实执行，仅在本地做无签名 Release 构建冒烟。
- 无 CH340/CP210x/FTDI/CDC-ACM 实机：矩阵保持“未验证”。
- macOS 14 App 运行时、14–25 上 Liquid Glass 人工走查：受旧系统主机限制。
