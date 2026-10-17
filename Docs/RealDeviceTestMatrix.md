# 真实设备测试矩阵

> 状态：阻塞。当前开发环境无 USB-UART 硬件，且仅 macOS 26；下列各项均未验证，不得以“自动化通过”替代。

必测门禁设备：CH340、CP210x；兼容性补充：FTDI、CDC-ACM。

| 设备 | 发现 | 9600 打开/回环 | 115200 打开/回环 | 热拔出 | 占用错误 | Sandbox | 结果 | 备注 |
|---|---|---|---|---|---|---|---|---|
| CH340 | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 | 未验证（阻塞） | 需设备与回环线 |
| CP210x | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 | 未验证（阻塞） | 需设备与回环线 |
| FTDI | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 | 未验证（阻塞） | 兼容性补充 |
| CDC-ACM | 未测 | 未测 | 未测 | 未测 | 未测 | 未测 | 未验证（阻塞） | 兼容性补充 |

## 前置条件

- 具备 Developer ID 签名与 App Sandbox（`com.apple.security.device.serial`）的 Release App。
- 每种设备的回环夹具、可执行物理拔出的走线。
- 记录 macOS 版本、适配器 revision 与测试日期。

## 运行硬件冒烟

接好设备与 TX-RX 跳线后（此步骤不进入 CI）：

```zsh
bash Scripts/hardware-smoke.sh                       # 列出可用 /dev/cu.*
bash Scripts/hardware-smoke.sh --port /dev/cu.usbserial-XXXX
bash Scripts/hardware-smoke.sh --port /dev/cu.usbserial-XXXX --wait-unplug 20 \
  --output TestArtifacts/hardware-<chip>.json
```

脚本自动验证：9600/115200 打开与配置、跳线回环收发、二次打开占用。热拔出需
`--wait-unplug` 并在提示时物理拔出。沙盒权限需在签名 App 中人工确认。

## 结果回填模板

把每次运行的 chip、日期、macOS 版本、适配器 revision 与
`hardware-<chip>.json` 的通过项填入上表；“未测”改为“通过/失败”并附证据路径。
缺少硬件时保持“未验证（阻塞）”，不得以 PTY 或自动化结果替代。

PTY 与 `Scripts/pty_stress.py` 只是自动化替身，不替代上表实机结果。
