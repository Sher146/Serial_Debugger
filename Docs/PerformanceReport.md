# 性能报告

> 状态：进行中。自动化指标已纳入流水线；Instruments 采样与真实设备吞吐为本机/硬件受限项，标注为待补。

## 方法与工具

- 控制台投影热点：`SerialMonitorTests/SessionDomainTests.testConsoleProjectionPerformance`
  使用 `measure` 记录 64 KiB 记录在 HEX 编码/解码与 ASCII 投影下的耗时（仅记录，不设基线门禁）。
- PTY 吞吐/内存/停顿：`python3 Scripts/pty_stress.py --baud 115200 --duration-min 30`，
  输出 `sent_bytes`、`received_bytes`、`throughput_bytes_per_second`、`max_gap_seconds`、
  `stalls`、`peak_rss_bytes`、`cpu_seconds`。
- 结果落在 `TestArtifacts/<时间戳>/pty-stress-report.json` 与 `*-coverage.txt`。

## 设计约束（来自开发总览）

- 控制台记录事件按 16–50 ms 批量发布（当前实现为 25 ms）；
- `RecordStore` 默认上限 50,000 条或 16 MiB，淘汰最旧项并累计截断；
- 只有 SwiftUI 渲染无法达标时，才引入受测的 `NSTextView` bridge（R3）。

## 待补证据

| 项目 | 状态 |
|---|---|
| 115200 bps 连续 30 分钟 Py 压测指标 | 需运行 `--stress` 产出 |
| Instruments Time Profiler / Allocations 采样 | 待人工 |
| 真实设备吞吐与内存平台 | 阻塞（无实机） |
| xccov 覆盖率快照 | 每次流水线自动产出 |

## 判读规则

- 30 分钟压测要求：无崩溃、无队列失控、`received_bytes` 与 `sent_bytes` 一致（≥99%）、`stalls == 0`。
- 覆盖率仅记录，不设百分比门禁。
