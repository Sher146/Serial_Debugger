# AGENTS.md

本文件为在本仓库工作的自动化代理提供约定与命令。产品与用法见 [README.md](README.md)。

## 项目概览

- 面向 macOS 的单窗口串口监视/调试工具，界面为简体中文（zh-CN）。
- Swift 6 严格并发（`SWIFT_STRICT_CONCURRENCY = complete`），SwiftUI + 少量 AppKit bridge。
- 部署目标 **macOS 14.0**；但**编译必须使用包含 macOS 26 SDK 的 Xcode 26+**，因为 Liquid Glass 的
  `.glassEffect()` 需在编译期存在（运行期由 `@available(macOS 26.0, *)` 弱链接，低版本回退 Material）。
- 无第三方依赖；仓库内本地 Swift Package `Packages/SerialCore` 只依赖 Foundation/Darwin。

## 架构与边界

```
SerialMonitor/
  App/            应用入口、Commands、UI 测试场景注入
  Features/       SwiftUI 视图与 @MainActor ViewModel（Session、Settings）
  Application/    SessionCoordinator、SessionClient/Event、TXSendQueue、LogServicing
  Domain/         模型、校验、状态机、编码器、RecordStore、Preferences/PresetStore
  Infrastructure/ POSIX/termios 串口适配器、文件日志
  Shared/         DesignTokens、Localization、VisualEffectsSupport、WindowConfigurationBridge
  Tests/          Unit / PTY / UI 测试
Packages/SerialCore/  SerialPorting 协议与值类型（唯一串口抽象）
```

规则：

- `SerialPorting` 是唯一串口抽象，实现只能位于 Infrastructure；不得改变 `SerialCore` 的公开签名。
- `SessionCoordinator` 是唯一持有串口、TX 队列、调度与日志的 actor，并实现 UI 用的 `SessionClient`。
- `SessionClient.subscribe()` 为每个订阅者返回独立 `AsyncStream<SessionEvent>`。
- `CommunicationRecord.rawBytes: Data` 是收发事实来源；ASCII/HEX/日志均为投影。
- Presentation 不做串口/文件 I/O；Application 不依赖 SwiftUI/AppKit；UI 状态只在 `@MainActor` 更新。
- 仅 `VisualEffectsSupport` 可使用 `@available(macOS 26, *)` 的系统 Glass API。

## 构建与运行

环境检查：

```zsh
zsh Scripts/verify-development-environment.sh
```

无签名 Debug 构建：

```zsh
xcodebuild -project SerialMonitor.xcodeproj -scheme SerialMonitor \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
```

## 测试（日常入口）

```zsh
zsh Scripts/run-automated-tests.zsh            # SerialCore + 单元/PTY + UI
zsh Scripts/run-automated-tests.zsh --quick    # 跳过 UI
zsh Scripts/run-automated-tests.zsh --ui-only  # 仅 UI
zsh Scripts/run-automated-tests.zsh --all      # 与默认相同，显式全量
zsh Scripts/run-automated-tests.zsh --stress   # 追加 Scripts/pty_stress.py（默认 30 分钟）
zsh Scripts/run-automated-tests.zsh --xctest-stress  # 追加进程内 PTYStressTests
zsh Scripts/run-automated-tests.zsh --release  # App 单元/UI 使用 Release 配置
```

- 该脚本是唯一的回归入口。仅使用 mock、PTY 与 `SessionScenarioClient`，**不访问真实串口**。
- 产物写入 gitignore 的 `TestArtifacts/<时间戳>/`：逐阶段日志、`.xcresult`、覆盖率与 `summary.md/json`。
- 覆盖率仅记录，不设百分比门禁。覆盖矩阵见 [Docs/AutomatedTestMatrix.md](Docs/AutomatedTestMatrix.md)。
- 新增 `SerialMonitor/Tests/**` 文件必须手动加入 `SerialMonitor.xcodeproj/project.pbxproj`（工程为显式文件引用，非目录引用）。

## 发布与硬件（受限，勿伪造结果）

```zsh
bash Scripts/build_release.sh --smoke                    # 无签名 Release 冒烟
DEVELOPMENT_TEAM=<team> bash Scripts/build_release.sh    # 归档并导出
NOTARY_PROFILE=<profile> bash Scripts/notarize.sh <app>  # 提交/等待/staple
bash Scripts/verify_release.sh <app>                     # 验签/entitlement/Gatekeeper/公证/无用户数据
bash Scripts/hardware-smoke.sh --port /dev/cu.<device>   # 实机打开/回环/占用/热拔出
DIST_OUTPUT=build/dist bash Scripts/build_distribution.sh  # 通用二进制 .zip/.dmg（默认 ad-hoc）
```

- GitHub Release：推送 `v*` 标签触发 `.github/workflows/release.yml`，调用 `build_distribution.sh` 上传 `.dmg`/`.zip`；无凭据时为 ad-hoc 且未公证，用户首次打开需放行 Gatekeeper。
- 凭据只经钥匙串/环境变量提供，**绝不写入仓库或日志**。
- 无 Developer ID / 公证凭据、无 USB-UART 设备、无旧系统主机时，相关项保持“阻塞/未验证”，不得勾选通过。

## 代码约定

- 遵循既有风格；仅在有解释价值时写注释，不写赘述性注释。
- 用户可见字符串走本地化（`Localizable.xcstrings` / `L10n`），保持 zh-CN。
- 不引入第三方依赖；如需引入，先更新 [Docs/Dependencies.md](Docs/Dependencies.md)。
- 严格并发下避免在视图更新周期内写 `@Published`；输入校验用 Combine 去抖，不用 `onChange` 直接发布。
- 容器视图加 `.accessibilityElement(children: .contain)`，否则其 `accessibilityIdentifier` 会覆盖子控件；
  记录行等叶子用 `children: .ignore`。注意 `Label` + `.combine` 在部分系统上会触发可访问性递归崩溃。
- UI 测试查询统一用 `firstMatch`（同一标识可能匹配多个元素）。

## 已知限制

- 编译需 macOS 26+ SDK；macOS 14 的 App 运行时未实测（CI 仅覆盖 SerialCore 于 macos-14）。
- 14–25 的 Liquid Glass/Material 人工走查、VoiceOver 实读、真实设备矩阵均未完成。
- 设置窗口为固定侧栏（不使用 `NavigationSplitView`，以避免系统边栏开关）。
- 主窗口最小尺寸 980×680 pt。

## Git 工作流

- 提交信息使用 `feat:` / `fix:` / `docs:` / `chore:` / `test:` / `refactor:` 前缀。
- **仅在用户明确要求时**才 commit / push / 开 PR。默认分支 `main`。
- PR 需通过 `.github/workflows/regression.yml`（SerialCore on macos-14/15 + App 全量回归 on macos-15）。

## 文档索引

- 环境与限制：[Docs/DevelopmentEnvironment.md](Docs/DevelopmentEnvironment.md)
- 测试矩阵：[Docs/AutomatedTestMatrix.md](Docs/AutomatedTestMatrix.md)、[Docs/UITestChecklist.md](Docs/UITestChecklist.md)
- 发布：[Docs/ReleaseChecklist.md](Docs/ReleaseChecklist.md)、[Docs/Licenses.md](Docs/Licenses.md)
- 设备：[Docs/SerialCompatibilityMatrix.md](Docs/SerialCompatibilityMatrix.md)、[Docs/RealDeviceTestMatrix.md](Docs/RealDeviceTestMatrix.md)
- 性能：[Docs/PerformanceReport.md](Docs/PerformanceReport.md)
- 阶段计划：`开发计划/*.md`
