# UI 测试与界面检查清单

> 更新日期：2026-10-17。运行入口：`zsh Scripts/run-automated-tests.zsh`（含 UI）或
> `xcodebuild ... -only-testing:SerialMonitorUITests`。UI 场景由 `SessionScenarioClient`
> 提供，替换真实串口，不访问硬件。

## 自动化覆盖（`SerialMonitor/Tests/UITests/SerialMonitorUITests.swift`）

| 能力 | 测试 | 结果 |
|---|---|---|
| 启动、端口选择器、连接/取消/断开 | `testLaunchShowsWorkspaceAndConnectsWithScenarioPort`、`testOpeningCanBeCancelled` | 覆盖 |
| 设备移除错误可恢复 | `testDeviceRemovalShowsRecoverableError` | 覆盖 |
| 最小窗口尺寸（1120×680） | `testMainWindowRespectsMinimumSize` | 覆盖 |
| 工具栏端口宽度与 32pt 图标命中区 | `testToolbarProvidesWidePortPickerAndLargeIconTargets` | 覆盖 |
| 高速波特率选择（921,600） | `testToolbarSelectsHighSpeedBaudRate` | 覆盖 |
| HEX 非法输入拦截与校验提示 | `testHexInputIsRejectedWithValidationError` | 覆盖 |
| 暂停横幅显隐 | `testPauseShowsBannerAndResumeHidesIt` | 覆盖 |
| ASCII/HEX 接收投影切换 | `testReceiveFormatSwitchReprojectsRecordsAsHex` | 覆盖 |
| 预设新建、单次发送、删除 | `testPresetCanBeCreatedSentAndDeleted` | 覆盖 |
| 日志开始/停止状态 | `testLoggingToggleReflectsRecordingState` | 覆盖 |
| 自动发送循环启停 | `testAutoSendLoopCanStartAndStop` | 覆盖 |
| 菜单/快捷键（⌘K 连接、⇧⌘P 暂停） | `testMenuShortcutsConnectAndTogglePause` | 覆盖 |
| 核心控件可访问标签与取值 | `testCoreControlsExposeAccessibleLabelsAndValues` | 覆盖 |
| 深色/浅色外观可用 | `testAppearanceModesKeepWorkspaceUsable` | 覆盖 |
| 四连接状态截图证据 | `testCaptureConnectionStateScreenshots` | 覆盖（截图为 xcresult 附件） |

截图证据：`testCaptureConnectionStateScreenshots` 以 `XCTAttachment(lifetime: .keepAlways)`
归档 `state-disconnected/opening/connected/error`，可从 `.xcresult` 导出。

## 本次界面检查发现与修复

| 问题 | 位置 | 处理 |
|---|---|---|
| 控制台/预设工具条被窗口工具条遮挡（内容使用全尺寸 content view） | `WindowConfigurationBridge` | 移除 `.fullSizeContentView`，恢复内容位于工具条之下 |
| 容器 `accessibilityIdentifier` 覆盖子控件标识 | `SessionView`/`SettingsView` | 容器加 `.accessibilityElement(children: .contain)` |
| 记录行可访问性标签触发无限递归崩溃 | `ConsoleRecordRow` | 改为 `.accessibilityElement(children: .ignore)` 单一元素 |
| 暂停横幅 `Label` + `.combine` 触发递归崩溃 | 暂停横幅 | 改用 `Image` + `Text` + `.contain` |
| 视图中同步 `@Published` 写入（“Publishing changes from within view updates”） | `SendEditor.onChange` | 延迟到 `Task { @MainActor in … }` |
| 控制台接收格式分段控件暴露为单一 CheckBox | `ConsoleToolbar` | 移出 `ControlGroup`，暴露为 RadioGroup |

## 仅人工验证（本轮未自动化）

| 项目 | 说明 | 状态 |
|---|---|---|
| macOS 26 原生 Liquid Glass 视觉走查 | 工具栏、状态栏、检查器、Popover 系统 Glass 层级一致性 | 待人工 |
| VoiceOver 实际朗读路径 | 自动化仅断言 label/value，未做真实朗读 | 待人工 |
| 对比度与 Reduce Motion | Reduce Motion 已在代码中处理，未做视觉对比度测量 | 待人工 |
| macOS 14–25 Material 降级 | 当前仅 macOS 26 环境；无法运行 14–25 | 阻塞 |
| 真实窗口拖拽/缩放交互 | 仅验证最小尺寸约束 | 部分覆盖 |

## 已知偏差

- 设置窗口仍暴露“隐藏边栏”工具条按钮（macOS 26 上 `.toolbar(removing: .sidebarToggle)`
  未生效）；原“无边栏开关”要求未达成，登记为界面偏差。
- 暂停横幅由 `Label` 改为 `Image` + `Text`，视觉一致，仅为规避系统可访问性递归缺陷。
