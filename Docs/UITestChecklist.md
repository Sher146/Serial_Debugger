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

## 2026-10-17 问题清单修复

| 问题 | 根因 | 处理 |
|---|---|---|
| 新接设备不自动识别，必须手动刷新 | 仅在启动/手动刷新时枚举端口，无热插拔感知 | `SessionCoordinator` 增加轮询（默认 1.2s，变化才发布 `.portsChanged`）+ 窗口激活时刷新；`testPortMonitorPublishesWhenPortsChange` |
| 顶部端口/波特率“当前值”空白，下拉才显示 | 工具栏 `Picker` 在 macOS 26/27 不绘制选中值 | 端口/波特率/行结束符改为 `Menu` + 显式值标签 |
| 行结束符 CRLF 显示不全（“C…”) | `.frame(width: 120)` 容纳标签+值被截断 | 改为 `Menu` 自绘值（“行结束符 CRLF”），宽度自适应 |
| 控制台 ASCII/HEX 控件点击跳动、与“时间戳”重叠 | 分段 `Picker` 固有宽度随选择变化而溢出 | 新增固定尺寸 `FormatSegmentedControl`，控制台/发送区统一替换 |
| 日志换行怪异、UTF-8 被切断、无法跨行复制 | 每个接收分片渲染成独立 `Text` 行 | 新增 `ConsoleTextView`（NSTextView）+ `ConsoleLineAssembler`：按 `\n` 行缓冲、原生换行、跨行选择/复制、增量追加 |
| 预设不显示原始指令 | 预设行只显示名称与格式 | 预设行增加等宽内容回显（HEX 原样、超长截断 + `.help`） |
| HEX 输入不自动两两分组 | 输入无格式化 | 新增 `HexInputFormatter`，发送区与预设编辑器 HEX 模式下自动分组；`testHexInputFormatterGroupsPairsAndFiltersNoise` |

对应 UI 断言更新：控制台内容改通过 `app.textViews["console.records"].value` 校验（`FIRST`、`46 49`、`AT`）。

## 2026-10-17 字号/圆角/标题图标

| 问题 | 根因 | 处理 |
|---|---|---|
| 全局字体大中小无反应 | 仅用 `.dynamicTypeSize`，而 UI 全是固定点值/语义字号 | 新增 `\.appFontScale` Environment + `.appFont(role)`：字号 = 基值 × multiplier，替换全部 `.font` |
| 同行字号不一致 | 固定点值、语义字号、控制台独立字号混用 | 统一到角色 token；移除独立的“控制台字号”，控制台/编辑器用 `.appFont(.mono)`（随全局缩放） |
| 字号档位太少 | 仅 3 档 | `AppFontScale` 扩为 5 档：特小/小/标准/大/特大（0.85/0.925/1.0/1.1/1.2） |
| 组件/文本框圆角不统一 | 各写各的 5/7/直角 | 统一 `controlCornerRadius=6`、`containerCornerRadius=10`；新增 `containerSurface()` 应用于控制台面板、文本框、预设卡片、Popover |
| 标题旁可点胶囊图标 | `ToolbarItem(placement:.navigation)` 被渲染成玻璃胶囊 | 删除工具栏项，改为控制台工具条行首的纯装饰图标（`.allowsHitTesting(false)`） |

新增测试：`testGlobalFontScaleChangesTextSize`（通过启动参数切换字号并比较文本高度）、`testFontScaleMultipliersIncreaseAndScaleMonoSize`。

## 2026-10-17 布局对齐与标题图标

| 问题 | 根因 | 处理 |
|---|---|---|
| 预设卡片只有半宽、不左右对齐 | 行 `VStack` 未撑满，`listRowInsets` 与标题内边距不一致 | 行加 `.frame(maxWidth: .infinity, alignment: .leading)`，卡片内边距与行内边距统一为 `contentInset(12)` |
| 发送框光标与占位词对不齐 | `TextEditor` 内边距与占位词内边距不同，且内部还有行内边距 | 发送框/预设框改用自绘 `PlainTextEditor`（`textContainerInset=8`、`lineFragmentPadding=0`），占位词用同样 8pt 内边距 |
| 标题图标被移位 | 上一轮擅自把 `ToolbarItem` 换成内容区图标 | 删除内容区图标；用 `NSTitlebarAccessoryViewController(.leading)` 在标题栏左侧放纯 `NSImageView`（非交互、无玻璃胶囊） |
| 到处对不齐、间距不统一 | 水平内边距混用 8/12 | 新增 `DesignTokens.contentInset = 12`，统一控制台工具条/卡片、发送区、预设标题与行的水平内边距 |
| 顶部选项框圆角与系统弹出菜单不一致 | 端口/波特率/行结束符用了 `.menuStyle(.borderlessButton)`；ASCII/HEX 为自绘 | 菜单改回系统默认样式；ASCII/HEX 改回系统 `Picker(.segmented)`（固定宽度 120） |

自动化测试运行改为**在副屏显示**（`UITestWindowPlacementBridge`，仅当存在第二块屏幕且带 `-ui-testing-scenario` 时生效），避免占用主屏。

## 2026-10-18 设计规范对齐（Apple HIG）

设计基线改为 Apple 官方 Human Interface Guidelines，并更新 `Serial_Monitor_UI设计规范_V1.0.html`。落地令牌：

- **间距**：8pt 栅格；`compactSpacing 8` / `standardSpacing 16` / `sectionSpacing 20` / `contentInset 20`（顶部各栏、行、状态栏水平留白）。
- **圆角**：`controlCornerRadius 6` / `containerCornerRadius 10`（仅两级）。
- **字号**：`AppFontRole` 取 HIG macOS text styles —— title 17 / title3 15 / headline 13(半粗) / body 13 / callout 12 / subheadline 11 / caption 10 / mono 12 / control 13；仍随“全局字号”整体缩放。


## 仅人工验证（本轮未自动化）

| 项目 | 说明 | 状态 |
|---|---|---|
| macOS 26 原生 Liquid Glass 视觉走查 | 工具栏、状态栏、检查器、Popover 系统 Glass 层级一致性 | 待人工 |
| VoiceOver 实际朗读路径 | 自动化仅断言 label/value，未做真实朗读 | 待人工 |
| 对比度与 Reduce Motion | Reduce Motion 已在代码中处理，未做视觉对比度测量 | 待人工 |
| macOS 14–25 Material 降级 | 当前仅 macOS 26 环境；无法运行 14–25 | 阻塞 |
| 真实窗口拖拽/缩放交互 | 仅验证最小尺寸约束 | 部分覆盖 |

## 已知偏差

- 暂停横幅由 `Label` 改为 `Image` + `Text`，视觉一致，仅为规避系统可访问性递归缺陷。
- 控制台在 ASCII/GB18030 模式按 `\n` 行缓冲：设备未以换行结尾的裸流会显示为一行（符合“流式终端”语义），不再按接收分片断行。
