# SandboxHarness —— D6 沙盒 + 签名构建验证材料

对应 01 文档步骤 7（验收 D6）：验证 App Sandbox 下串口访问行为，
以及缺少 `com.apple.security.device.serial` entitlement 时错误正确映射为
`SerialError(.permissionDenied)`。

## 材料

| 文件 | 作用 |
|---|---|
| `entitlements-serial.plist` | `com.apple.security.app-sandbox=YES` + `com.apple.security.device.serial=YES`（被测组） |
| `entitlements-noserial.plist` | 仅 `com.apple.security.app-sandbox=YES`（对照组） |
| `run_sandbox_check.sh` | 一键脚本：release 构建 → ad-hoc 签名两份 → 运行 list/open → 自动判定 |

## 为什么用 poc-cli 而不是 App 壳工程

01 文档允许"poc-cli 的 sandbox 打包脚本"作为 SandboxHarness 形态。
entitlement 是否生效由代码签名决定、与 target 形态无关；CLI 直接可观察
stdout 的结构化错误分类，比 App 壳更易判定。本机无完整 Xcode，也无法生成
App 壳工程；脚本只依赖 CLT 自带的 `swift build` 与 `codesign`。

## 执行

```bash
cd POC/SerialGatePOC
SandboxHarness/run_sandbox_check.sh /dev/cu.usbserial-XXXX 115200
```

判定标准（脚本自动检查）：

1. 带 serial entitlement 的 ad-hoc 签名构建：`list` 与 `open` 成功；
2. 对照构建（仅 app-sandbox）：`open` 失败，输出含 `category=permissionDenied`。

PTY 变体：将路径换成 PTY 从端（如 `python3 pty_peer.py echo` 打印的
`/dev/ttysNNN`）即可做无硬件版本验证；注意生产路径的适配器只能打开
SGPortManager 枚举出的 `cu.*` 节点（详见 POC 报告 §④），因此 PTY 变体
预期在 `findPort` 处报 portNotFound，不能用于"打开成功"判定——PTY 的沙盒
打开验证需以注入方式另行构造，本次未做，记录在 POC 报告遗留风险中。

## 本机执行结果

见 `POC/POC报告.md` §② 判定标准 4 与 §⑦ 遗留风险：命令、输出与结论均如实记录。
