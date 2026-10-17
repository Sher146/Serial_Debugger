# 依赖与许可证

| 名称 | 版本 | 许可证 | 用途 | 状态 |
|---|---|---|---|---|
| Foundation / SwiftUI / AppKit | macOS SDK | Apple 系统组件 | UI、并发、文件 | 随系统 |
| Darwin / POSIX termios / IOKit | macOS SDK | Apple 系统组件 | P0 串口实现与发现 | 当前基线 |
| Swift Package `SerialCore` | 仓库内 | 本项目 | 串口值类型与协议 | 本地依赖 |

本项目不引入任何第三方串口库，`Packages/SerialCore` 仅依赖 Foundation/Darwin。

## 升级策略

若未来引入候选库，必须先在本表登记：名称、精确版本/revision、许可证文本链接、哈希，
并在引入后重跑 `Scripts/run-automated-tests.zsh --all`、PTY 压测与实机矩阵。

## 发布前动作

- 归档应用包使用 `otool -L` 检查是否链接了非系统 dylib。
- 若链接第三方代码，补充其许可证副本到应用包 `Contents/Resources/Licenses`。
