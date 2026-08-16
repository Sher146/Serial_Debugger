# SerialGatePOC —— P0 串口技术验证包

对应 `开发计划/01-P0-串口技术验证POC与SerialCore抽象.md`。本包验证 SerialGate
（4.1.0，锁 commit `8458057`）能否作为项目串口库，并提供 `SerialPorting` 契约的
候选适配器实现。

## 包结构

```
Sources/SerialGateAdapter/   SerialGate → SerialPorting 适配器 + 错误映射
Sources/poc-cli/             CLI 验证工具（list/open/echo/stress）
Tests/SerialGateAdapterTests/  PTY 集成测试（8 用例）+ 错误映射单测 + PseudoTerminal
SandboxHarness/              D6 沙盒 + ad-hoc 签名验证材料（见其中 README）
```

## 构建

```bash
cd POC/SerialGatePOC
swift build                 # debug，零警告
swift build -c release      # release
```

## 测试（重要：需要完整 Xcode）

本开发机只有 Command Line Tools，**CLT 环境没有 XCTest 模块，`swift test` 报
"no such module 'XCTest'" 无法运行**。P0 期间的测试结论由临时等价 runner
（逐条复刻 XCTest 断言、不含 XCTest 依赖）得出：93 断言全过、拔出用例
20/20 无 flaky；等价 runner 的构造方式与结果详见 `POC/POC报告.md` §② 附录。

**安装完整 Xcode 后，必须以 `swift test` 复跑全部测试作为最终确认：**

```bash
cd Packages/SerialCore && swift test        # SerialCore 契约单测
cd POC/SerialGatePOC && swift test          # 适配器 PTY 集成测试 + 错误映射单测
# 拔出用例 flaky 检查：
for i in {1..20}; do swift test --filter testMasterCloseTerminatesStream || break; done
```

## poc-cli 用法

```bash
CLI=.build/debug/poc-cli
$CLI list                              # 枚举串口（cu.* 优先，含 USB VID/PID/名称）
$CLI open <path> <baud> [seconds]      # 打开 + tcgetattr 核对，保持后关闭
$CLI echo <path> <baud> <seconds>      # 自环收发统计（需回环，见下）
$CLI stress <path> <baud> <seconds>    # 持续读统计字节数/速率
```

open 失败会打印结构化错误分类（`category=portNotFound/portBusy/permissionDenied/
configurationUnsupported/openFailed`）并以 exit 1 退出。

## 无硬件自测（PTY 对端回显脚本）

poc-cli 只能打开 SGPortManager 枚举出的 `cu.*` 节点（SerialGate 的 `SGPort` init
为 internal，无法按路径构造，详见 POC 报告 §④），因此 PTY 不能作为 CLI 的
echo 目标；PTY 的打开/读写/拔出验证由 `Tests/` 集成测试经 `@testable` 注入完成。
无硬件时可对系统已有的 `cu.*` 节点（如 `/dev/cu.Bluetooth-Incoming-Port`）验证
list/open/stress：

```bash
$CLI open /dev/cu.Bluetooth-Incoming-Port 115200 1   # termios 核对 ispeed=115200
$CLI stress /dev/cu.Bluetooth-Incoming-Port 115200 3 # 读路径（无对端则 received=0B）
```

注意：不要对该蓝牙端口跑 `echo`——SerialGate 的写是阻塞 write(2)、无超时，
无对端时 write 会挂起（实测，已记入 POC 报告 §④）。

## 实机手动测试 runbook（用户插入硬件后执行）

前置：CH340 需先装官方驱动并确认识别（系统兼容性提示范畴）；准备 TX/RX 短接跳线。
每类芯片（CH340 / CP210x / FTDI / CDC-ACM）逐项执行并把结果填入
`POC/POC报告.md` §③ 矩阵（✅/❌/未测+原因）：

1. **发现**：插入设备，`$CLI list`，核对 VID/PID 与厂商/产品名
   （CH340=0x1A86/0x7523，CP210x=0x10C4，FTDI=0x0403，CDC-ACM 按设备）。
2. **打开 + 参数配置**：
   `$CLI open <path> 9600 2` 与 `$CLI open <path> 115200 2`，
   核对输出 `ispeed` 与配置一致。
3. **写→回环收**：跳线短接 TX/RX，`$CLI echo <path> 115200 10`，
   期望 `mismatches=0` 且 `sent == received`。
4. **读（设备侧发 1KB）**：设备固件或另一终端向本机连续发送 1KB，
   `$CLI stress <path> 115200 10`，核对 `received` 字节数。
5. **热拔出**：`$CLI open <path> 115200 60` 保持期间拔出设备，
   期望进程不崩溃；拔出事件顺序（先 `.deviceRemoved` 事件、后流终止）
   已由 PTY 集成测试覆盖，实机以"无崩溃、可重新 open"为准，重插后重跑步骤 2。
6. **占用冲突**：`screen <path> 115200` 占用后另开终端
   `$CLI open <path> 115200 1`，期望 `category=portBusy`（`screen` 用 `C-a \` 退出）。
7. **沙盒签名构建**：`SandboxHarness/run_sandbox_check.sh <path> 115200`，
   期望输出 `PASS`（带 entitlement 打开成功，对照组 `permissionDenied`）。

附加记录（填入报告 §③ 附注）：各芯片实测最高可用波特率、不支持的
parity/flowControl 组合。注意 SerialGate 固定 8 数据位且无流控 API，适配器对
非 8/N/1 之外的组合直接报 `configurationUnsupported`（不经硬件）。

## 沙盒验证

见 `SandboxHarness/README.md`；一键脚本：

```bash
SandboxHarness/run_sandbox_check.sh <path> 115200
```
