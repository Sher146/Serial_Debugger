# Serial Monitor

面向 macOS 的单窗口串口监视与调试工具。当前开发版本支持发现串口、配置通信参数、连接/断开、接收原始字节、以 ASCII 或 HEX 查看记录，以及手动发送数据。

> 当前工程的实际最低运行版本为 **macOS 26.0**。产品开发计划中的 macOS 14+ 兼容目标尚未重新验证，不能视为当前运行承诺。

## 当前状态

已完成的开发能力：

- 串口端口发现与完整通信参数配置（波特率、数据位、校验、停止位、流控制）
- 单一活跃会话的连接、取消连接、断开、接收与 FIFO 手动发送
- ASCII / HEX 记录显示、时间戳、自动跟随、暂停显示和清空记录
- 中文 SwiftUI 主工作区，以及 macOS 原生工具栏和检查器布局

尚未完成：自动发送、预设编辑与循环、真实日志、设置窗口、菜单命令及发布流程。

## 环境要求

- macOS 26.0 或更高版本
- 完整版 Xcode 26.6（仅安装 Command Line Tools 不足以运行和测试此 App）
- 已选择完整 Xcode 工具链，例如：`xcode-select -p` 应指向 `/Applications/Xcode.app/Contents/Developer`
- 当前已在 Apple Silicon 开发机上验证

项目使用仓库内的本地 Swift Package `Packages/SerialCore`；打开工程或执行构建时，Xcode 会自动解析它，不需要安装 Homebrew 或第三方串口库。

## 用 Xcode 运行

1. 在 Finder 中打开 `SerialMonitor.xcodeproj`。
2. 在 Xcode 顶部选择 `SerialMonitor` scheme 和 **My Mac** 运行目标。
3. 点击运行按钮（或按 `⌘R`）。如需验证沙盒下的实际串口访问，请在 **Signing & Capabilities** 配置可用的开发签名身份。
4. 启动后点击“刷新”，选择目标串口和波特率；如有需要，通过“参数”设置数据位、校验、停止位和流控制。
5. 点击“连接”。连接成功后，在下方发送区选择 ASCII 或 HEX、行结束符并输入数据，再点击“发送”（或按 `⌘↩`）。

未连接时，发送按钮会保持禁用。HEX 模式只接受合法的十六进制字节；校验错误会显示在输入框下方且不会清除已输入内容。

## 命令行构建与测试

先运行开发环境检查：

```zsh
zsh Scripts/verify-development-environment.sh
```

以下命令可进行无签名 Debug 构建，适用于本地工程、Swift 6 并发和依赖解析检查：

```zsh
xcodebuild \
  -project SerialMonitor.xcodeproj \
  -scheme SerialMonitor \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build
```

`CODE_SIGNING_ALLOWED=NO` 不能验证 App Sandbox、串口设备权限或已签名 App 的行为。需要完整测试时，请配置开发签名后运行：

```zsh
xcodebuild \
  -project SerialMonitor.xcodeproj \
  -scheme SerialMonitor \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  test
```

该 scheme 同时包含 Unit Tests 和 UI Tests。UI 测试需要能启动测试 Runner 的有效开发签名；当前没有可用签名身份时，相关失败应按环境限制处理，而不是误判为串口或界面逻辑失败。

## 常见问题

### 刷新后没有可选串口

确认 USB 转串口设备已连接、驱动已被 macOS 识别，并再次点击“刷新”。开发机内置的 Bluetooth/debug-console 端口不等同于已验证的 USB-UART 设备。

### 连接或访问串口失败

确认端口未被其他程序占用，通信参数与设备端一致。若在签名 App 中测试，请确认 App Sandbox 的串口设备权限已启用；项目 entitlement 已声明 `com.apple.security.device.serial`。

### UI 测试 Runner 无法打开或提示已损坏

通常是缺少或不匹配的开发签名。请在 Xcode 的 **Settings → Accounts** 登录开发账号，并为 App 和测试 target 选择同一有效 Team，然后重新构建测试。

## 硬件验证边界

当前串口实现以系统 POSIX/termios 和 IOKit 为基线，但尚未完成 CH340、CP210x、FTDI、CDC-ACM 的实机回环、热拔出、占用和沙盒测试。因此项目尚不宣称支持或认证任何特定 USB-UART 芯片。

详细的环境配置、验证命令与限制见 [开发环境说明](Docs/DevelopmentEnvironment.md)，设备验证进度见 [串口兼容性矩阵](Docs/SerialCompatibilityMatrix.md)，依赖决策见 [依赖登记](Docs/Dependencies.md)。
