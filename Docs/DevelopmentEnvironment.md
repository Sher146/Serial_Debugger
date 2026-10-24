# 开发环境

本项目以 macOS 14+ 为最低运行版本，并以 macOS 26 的 Liquid Glass 视觉为优先验收目标。开发机必须使用包含 macOS 26 SDK 的完整 Xcode；Command Line Tools 不能构建、运行或测试该 App。

## 当前状态（2026-10-17）

当前开发机为 Apple Silicon、macOS 27.0.1，完整 Xcode 27.1（27A9275）已安装并由 `xcode-select` 选中，`xcodebuild`、XCTest、`simctl` 和本地 Swift Package 解析均可用。工程部署目标已由 26.0 降为 14.0（`SerialCore` 亦为 14），本机 `run-automated-tests.zsh --all`（SerialCore + 单元/PTY + 18 项 UI）全绿。仍没有可用代码签名身份，且不执行真实串口硬件测试；CI（`macos-15` + Xcode 26）负责跨版本运行时验证，macOS 14 的 App 运行时尚未覆盖。因此 P0 的串口实机结论仍为“未决”。

## 一次性安装

1. 从 App Store 或 Apple Developer 下载并安装与 macOS 26 SDK 匹配的完整 Xcode，建议保留在 `/Applications/Xcode.app`。
2. 首次启动 Xcode，登录 Apple ID 并接受许可；随后在终端执行：

   ```zsh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   sudo xcodebuild -license accept
   ```

3. 在 Xcode 的 **Settings → Accounts** 登录用于开发的 Apple ID。仅在执行 P0 的沙盒签名验证时，启用 Xcode managed signing；不要把 Team ID 或证书写入仓库。
4. 运行仓库检查：

   ```zsh
   zsh Scripts/verify-development-environment.sh
   ```

该脚本会解析本地 `SerialCore` 包，并执行无签名 Debug 构建。无签名构建只用于工程和并发检查，不可代替沙盒、串口权限、签名或公证验证。

## 环境边界

- 不安装第三方串口库；P0 当前基线为系统 POSIX/termios，实现选择仍待 PTY 与实机证据决定。
- macOS App 不需要 iOS 模拟器；`simctl` 仅作为完整 Xcode 安装完整性的检查项。
- CH340、CP210x、回环线及实机拔出测试暂不执行。设备到位后按 [SerialCompatibilityMatrix.md](SerialCompatibilityMatrix.md) 填写矩阵。
- Developer ID、App Store Connect 凭据和公证凭据仅在 P4 配置；不得保存在仓库、脚本或 CI 日志。
- 2026-10-24 本机（macOS 27 + Xcode 27）：`zsh Scripts/run-automated-tests.zsh --ui-only` 的 ad-hoc 签名构建
  启动后没有窗口，22 个 UI 用例全部报 “workspace missing”；同一份代码（含改动前的 `db452fa`）在
  `CODE_SIGNING_ALLOWED=NO` 下全部通过。签名/沙箱的 UI 启动问题尚未定位，UI 用例暂以无签名构建验证；
  跑 UI 前还需确认没有同 bundle id 的旧实例在运行，否则同样会拿不到窗口。

## 日常命令

```zsh
zsh Scripts/verify-development-environment.sh
xcodebuild -project SerialMonitor.xcodeproj -scheme SerialMonitor -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES test
zsh Scripts/run-automated-tests.zsh
```

第二条命令必须在完整 Xcode、开发签名配置妥当后运行。`ONLY_ACTIVE_ARCH=YES` 仅用于开发机的 Debug 测试，避免本机双架构并行构建与本地 Swift Package 的模块产物发生竞态；Release 仍应在 P4 分别验证 arm64 与 x86_64。它会覆盖 Unit 与 UI target；硬件矩阵仍需单独执行。

`run-automated-tests.zsh` 使用隔离的 DerivedData、PTY 和内置 UI 场景替身，可在无真实串口、无签名身份的开发机运行。使用 `--quick` 跳过 UI；使用 `--stress` 追加 30 分钟 PTY 压测。报告保存在 gitignore 的 `TestArtifacts/`。
