# P0 POC 报告：SerialGate 串口库技术验证

> 依据：`开发计划/01-P0-串口技术验证POC与SerialCore抽象.md` 步骤 8（固定七段结构 + 附录）
> 验证环境：macOS 26 arm64，Swift 6.3.3（仅 Command Line Tools，无完整 Xcode）
> 被测库：SerialGate 4.1.0，锁 commit `845805702b9da4c5612fc13f17589588eaa83801`（MIT）
> 报告日期：2026-08-16

## ① 结论

**条件通过 / 待定：暂采用 SerialGate 4.1.0（锁 commit），条件为"实机矩阵补齐后复核本报告"。**

- 可本机完成的判定项全部通过：SerialCore 契约与测试、PTY 集成测试（含热拔出事件顺序 20/20 无 flaky）、占用/权限错误分类、ad-hoc 签名 + App Sandbox 下的发现/打开/读写、许可证与依赖登记。
- 判定标准 1（四类芯片实机全项）与标准 2/4 的实机部分**无法在本机完成**（开发机无任何 USB-UART 设备，`/dev/cu.*` 仅 Bluetooth 与 debug-console），标注"待硬件验证"。硬件到位后按 `POC/SerialGatePOC/README.md` 的 runbook 逐格补齐矩阵并复核结论；若出现无法绕行的 ❌，按 01 文档回退触发条件改判。
- 已知限制（见 §④、§⑦）均有可行绕行，不足以在本阶段直接触发回退。

## ② 判定标准逐项对照

| # | 判定标准（01 文档 §8） | 结果 | 证据 |
|---|---|---|---|
| 1 | 四类芯片发现/打开/9600+115200 配置/回环读写/热拔出全 ✅ | **待硬件验证** | 开发机无 USB-UART 设备；PTY 等价项全过（打开/参数/读写/拔出，见附录 A） |
| 2 | 热拔出"先事件、后流终止、无崩溃、可重新 open" | PTY **通过**；实机**待硬件验证** | 拔出用例单次 + 20 连跑全过（顺序断言：先 `.deviceRemoved` 事件、后 `incomingBytes` 以 `SerialError(.deviceRemoved)` 终止） |
| 3 | 占用→`.portBusy`；权限缺失→`.permissionDenied` | **通过** | portBusy：PTY 双开测试通过；permissionDenied：沙盒对照包实测 open 返回 EPERM 并映射为 `category=permissionDenied`（§②-4 同次运行）；ENOENT 实测映射 `portNotFound` |
| 4 | 沙盒 + 签名构建下功能正常（D6） | **通过（本机范围）**；实机芯片**待硬件验证** | ad-hoc 签名 + `app-sandbox` + `device.serial`：list 枚举成功、open 成功、tcgetattr 核对 ispeed=115200、stress 读路径正常；对照包（无 serial entitlement）open 失败且为 `permissionDenied`（`SandboxHarness/run_sandbox_check.sh` 输出 PASS） |
| 5 | 许可证兼容、依赖登记完整 | **通过** | MIT；`POC/依赖登记表.md` 含版本/commit/哈希/许可证/升级策略；`Package.resolved` revision 与登记一致 |

### 附录 A：XCTest 限制与等价 runner（务必阅读）

- **限制**：本机仅安装 Command Line Tools，无完整 Xcode，**XCTest 模块不存在**，`swift test` 报 `no such module 'XCTest'` 无法运行（已亲自复现）。`xcodebuild` 亦不可用。
- **等价 runner 覆盖范围**：临时 SPM 可执行包（`/tmp/P0EquivRunner`，不进仓库），逐条复刻以下测试文件的全部断言，与被测代码锁同一 SerialGate revision；适配器/错误映射/PseudoTerminal 源码以副本编入 runner 模块（等价 `@testable import`），SerialGate 以 `-Xswiftc -enable-testing` 编译以获得 internal `SGPort.init`：
  - `SerialConfigurationTests`（Codable 往返、默认值、CaseIterable、commonBaudRates）
  - `SerialErrorTests`（六类 errno 分类与 isRetryable、occurredAt 注入、Equatable）
  - `ErrorMapperTests`（SGError→Category、EIO→deviceRemoved、未知错误兜底）
  - `SerialGateAdapterPTYTests`（8 用例：发现/波特率配置/写达主端/收流/拔出顺序/占用/close 幂等/close 后写）
- **结果**：93 断言全过、0 失败；拔出用例 20 连跑 20/20 无 flaky；1 项按文档豁免跳过（SerialGate 不枚举 PTY `/dev/ttys` 节点，IOKit 仅列 `cu.*`，与预期一致）。
- **最终确认义务**：XCTest 测试文件本身是交付物，未删除、未改动语义；**安装完整 Xcode 后须在 `Packages/SerialCore` 与 `POC/SerialGatePOC` 分别以 `swift test` 复跑全部测试作为最终确认**（命令见 POC 包 README）。

## ③ 实机验证矩阵

开发机无任何 USB-UART 硬件（`/dev/cu.*` 仅有 `cu.Bluetooth-Incoming-Port` 与
`cu.debug-console`），全部实机格子标注未测，**不留空**：

| 芯片 \ 项目 | 发现 | 打开 | 参数配置（9600/115200） | 写→回环收 | 读（1KB） | 热拔出 | 占用冲突 | 沙盒签名构建下前三项 |
|---|---|---|---|---|---|---|---|---|
| CH340 | 未测（开发机无 USB-UART 设备） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） |
| CP210x | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） |
| FTDI | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） |
| CDC-ACM | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） | 未测（同上） |

各芯片实测最高波特率、不支持的 parity/flowControl 组合：**待硬件验证**。

**本机补充验证记录（非矩阵替代，仅证明工具链可用）**——对象为本机真实 `cu.*`
节点 `/dev/cu.Bluetooth-Incoming-Port`（非 USB-UART 芯片）与 PTY：

| 项 | 结果 | 证据 |
|---|---|---|
| `poc-cli list` | ✅ 枚举 2 个 `cu.*` 节点 | 输出含 `cu.Bluetooth-Incoming-Port`、`cu.debug-console` |
| open + termios 9600 / 115200 | ✅ | `ispeed=9600/115200` 与配置一致（独立 fd `tcgetattr` 核对） |
| open 不存在路径 | ✅ | `category=portNotFound code=2`，exit 1（AC-01"不存在路径不崩溃"） |
| open PTY 从端（CLI 路径） | ⚠️ 预期内失败 | `portNotFound`：SerialGate `SGPort` init 为 internal，生产路径只能打开 IOKit 枚举节点（见 §④-1）；PTY 打开/读写经测试注入路径已验证 |
| stress 3s 持续读 | ✅ 无崩溃，统计正确 | `received=0B chunks=0`（无对端发送，符合预期） |
| echo（CLI 级回环） | 未测 | 无回环设备；写阻塞发现见 §④-5；echo 底层 write/read 已由 PTY 集成测试覆盖，CLI 级回环列入硬件 runbook 第 3 步 |

## ④ SerialGate API 实测与文档差异

以 checkout 源码（commit `8458057`）与实测为准：

1. **`SGPort` 的 `init(_:)` 是 internal**（`SGPort.swift:57`）：实例只能经
   `SGPortManager.shared.availablePortsStream` 枚举获得，无法按路径构造。
   影响：生产路径只能打开 IOKit 枚举出的 `cu.*` 节点；PTY/`tty.*` 节点无法打开
   （适配器 `findPort` 落空映射为 `portNotFound`）。对目标场景（USB-UART 均为
   IOKit 枚举的 `cu.*`）无影响；PTY 测试经 `@testable import` 注入。README 未提及此限制。
2. **`SGError` 不携带底层 errno**（各 case 仅携带端口名）：notFound/busy/
   permissionDenied 无法从 SGError 分类。绕行：适配器在 open 前以 `Darwin.open`
   预检拿 errno，经契约 `SerialError.mapErrno` 分类（本报告 §⑤）。
3. **`SGPort.read` 静默吞掉 `read(2)` 的 0/-1**：读路径不产生错误信号；PTY 无
   IOKit 节点，`portStateStream` 不会对 PTY 报 `.removed`。绕行：适配器自持 fd
   `poll(2)`（POLLHUP/POLLERR/POLLNVAL）做拔出兜底，`portStateStream` 作旁路；
   实测 macOS 26 上 `poll` 的 events 必须非 0 才会报告 POLLHUP。
4. **固定 CS8、无流控 API**（`SGPort.open` 内 `options.c_cflag |= CS8`，无
   dataBits/flowControl setter）：适配器对非 8 数据位、非 none 流控直接抛
   `configurationUnsupported`，不调用 SGPort。parity（N/E/O）与 stopBits（1/2）
   有公开 setter，正常。
5. **写是阻塞 `write(2)`、无超时**：实测对无对端的 `cu.Bluetooth-Incoming-Port`
   执行 echo，`send(data:)` 挂起超过 3 分钟无返回。影响评估：对正常设备+回环
   场景无影响；对"设备侧流控拉死/线缆异常"场景，写可能长时间阻塞。缓解：03
   文档 SessionCoordinator 设计 TX 超时/取消策略（已登记 R7）。
6. **`SGPortManager` 依赖 AppKit**（NSWorkspace 睡眠/唤醒、NSApplication 终止
   通知）：在 CLI 与沙盒 CLI 中实测可用；纯无 AppKit 环境不适用（本项目是
   SwiftUI App，无影响）。
7. **枚举不保证含全部 serial 节点**：`kIOSerialBSDServiceValue` 匹配仅返回 IOKit
   注册的节点；PTY（`/dev/ttysNNN`）不在其中（与 01 文档步骤 5 的预期一致，
   发现用例按文档豁免跳过并在此记录）。

## ⑤ 错误映射覆盖度

契约 `SerialError.Category` 共 9 类，适配器覆盖情况：

| Category | 触发路径 | 覆盖证据 |
|---|---|---|
| portNotFound | open 预检 ENOENT（路径不存在 / 未被枚举） | runner 断言 + CLI 实测（`/dev/cu.notexist`、PTY 路径） |
| portBusy | open 预检 EBUSY / 进程内占用登记 | runner PTY 双开用例（含 isRetryable=true） |
| permissionDenied | open 预检 EPERM/EACCES | **沙盒对照包实测**：缺 serial entitlement 时 open 返回 EPERM → `category=permissionDenied`（D6 同次验证） |
| configurationUnsupported | 非 8 数据位/非 none 流控前置校验；SGError.failedToSetOptions | runner ErrorMapper 断言 |
| openFailed | SGError.failedToOpenPort/portIsNotOpen；mapErrno 默认分支 | runner 断言 |
| readFailed | SGError.failedToEncodeText；mapReadError 兜底 | runner 断言（SGPort.read 实际不产出错误，见 §④-3） |
| writeFailed | SGError.failedToWriteData/portIsNotOpen/failedToEncodeData；close 后写 | runner 断言 + PTY close 后写用例 |
| deviceRemoved | 拔出（poll 兜底 / portStateStream 旁路 / write EIO） | runner 拔出用例（先事件后流终止，20/20）+ write EIO 断言 |
| timeout | mapErrno ETIMEDOUT/EAGAIN | runner 断言（当前适配器无超时触发路径，保留供上层/自研适配器） |

`SerialError.mapErrno` 六类 errno（ENOENT/EBUSY/EPERM+EACCES/EINVAL+ENOTSUP/
EIO/ETIMEDOUT+EAGAIN）的分类与 isRetryable 全部有断言。未知错误兜底按操作
分别落到 openFailed/readFailed/writeFailed，均有断言。

## ⑥ 回退方案论证与工作量估算

**论证（"自研适配器能做到同一接口"成立）**：

- 契约隔离已生效：上层只依赖 `SerialPorting` + 值类型；SerialGate 类型仅出现在
  `SerialGateAdapter`/`SerialGateErrorMapper` 两个文件内（约 500 行），替换不波及
  SerialCore 与上层。
- 自研适配器所需的全部能力在本 POC 中已被实际验证可落地：termios 打开/配置
  （`cfsetspeed`/`tcsetattr`，适配器预检与 CLI 核对已用）、IOKit 发现 + USB 信息
  回溯（`SerialGateAdapter.usbInfoByCalloutPath` 即自研代码，可直接迁移）、拔出
  检测（自持 fd `poll(2)` 兜底方案为自研，已验证 20/20 无 flaky；IOKit 通知为
  成熟路径）、错误分类（契约 `mapErrno` 与底层无关）。
- 测试资产全部可复用：PseudoTerminal、8 个 PTY 集成用例、ErrorMapperTests 只需
  把构造点从 `SGPort` 注入改为新适配器构造。

**工作量估算**（按 01 文档 §8 口径复核，结论一致）：termios 打开/配置/读写
2–3 天；IOKit 发现 + 拔出通知 1–2 天；测试迁移与矩阵重跑 0.5–1 天。
**合计约 4–6 个工作日**（含实机矩阵重跑）；若仅替换实现、矩阵沿用 P0 结果则
3.5–5 天。

## ⑦ 遗留风险

1. **硬件验证缺口（最高优先级）**：四类芯片矩阵全格未测；判定标准 1 及标准 2/4
   的实机部分"待硬件验证"。硬件到位后按 POC 包 README runbook 补齐并复核本结论。
2. **开发环境缺口**：本机仅 CLT，无 XCTest/xcodebuild——**开发 SwiftUI 应用与运行
   XCTest 均需安装完整 Xcode**；Xcode 就位后须 `swift test` 复跑两包全部测试作为
   最终确认（等价 runner 结果不能替代）。
3. **写阻塞无超时**（§④-5）：SerialGate `send(data:)` 为阻塞 write(2)；03 文档
   SessionCoordinator 需设计 TX 超时与取消策略，避免设备异常时 TX 管线挂死。
4. **参数支持面**：SerialGate 固定 8 数据位、无流控 API；需求默认值 8/N/1 无流控
   不受影响，但若未来需要 7E1 或 RTS/CTS，SerialGate 无法满足（只能走回退方案）。
5. **维护活跃度**：SerialGate 最近 push 为 2025-01-12，仓库未归档但活跃度低；
   锁 commit 已规避意外变更，升级需重跑全矩阵（登记在案）。
6. **沙盒验证范围**：D6 以 ad-hoc 签名 + CLI 形态在本机真实 `cu.*` 节点通过；
   PTY 的沙盒打开受 §④-1 限制无法经 CLI 验证（预期 portNotFound）；实机芯片的
   沙盒项待硬件；Developer ID + notarization 属 P3（08 文档）。
7. **`SGPortManager` AppKit 依赖**（§④-6）：本项目为 SwiftUI App 无影响；若未来
   拆出纯 CLI 工具且无 AppKit 环境，需要重新评估。
