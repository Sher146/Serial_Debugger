import Foundation
import SerialCore
import SerialGate

/// SerialGate 错误 → `SerialError` 分类映射。
///
/// 实测事实（SerialGate 4.1.0，`8458057`）：`SGError` 各 case 只携带端口名，
/// 不保留底层 errno。因此 notFound/busy/permissionDenied 的分类由适配器在
/// open 预检（`Darwin.open` 探测 + 进程内占用登记）阶段经 `SerialError.mapErrno`
/// 完成；落到这里的一律是 SGPort 自身抛出的语义错误。
public enum SerialGateErrorMapper {
    /// open 路径错误映射。
    public static func mapOpenError(_ error: Error, path: String) -> SerialError {
        guard let sgError = error as? SGError else {
            return fallback(.openFailed, error: error, operation: "open", path: path)
        }
        switch sgError {
        case let .failedToSetOptions(port):
            // cfsetspeed/tcsetattr 失败：参数组合不被支持（如非标准波特率）。
            return SerialError(category: .configurationUnsupported,
                               userMessage: "open failed: unsupported configuration for \(port)",
                               isRetryable: false)
        case let .failedToOpenPort(port):
            return SerialError(category: .openFailed,
                               userMessage: "open failed on \(port)",
                               isRetryable: true)
        case let .portIsNotOpen(port):
            // SGPort 状态非 .closed 时的重复 open。
            return SerialError(category: .openFailed,
                               userMessage: "open failed: port \(port) is already open",
                               isRetryable: false)
        default:
            return fallback(.openFailed, error: error, operation: "open", path: path)
        }
    }

    /// write 路径错误映射。`fallbackErrno` 为适配器在 catch 后立刻捕获的 errno
    /// （SGPort 不保留 errno，尽力而为）；EIO 判定为设备拔出。
    public static func mapWriteError(_ error: Error, path: String, fallbackErrno: Int32? = nil) -> SerialError {
        if let code = fallbackErrno, code == EIO {
            return SerialError(category: .deviceRemoved, systemCode: Int(code),
                               systemDomain: "NSPOSIXErrorDomain",
                               userMessage: "write failed: device at \(path) went away",
                               isRetryable: true)
        }
        guard let sgError = error as? SGError else {
            return fallback(.writeFailed, error: error, operation: "write", path: path)
        }
        switch sgError {
        case let .failedToWriteData(port):
            return SerialError(category: .writeFailed,
                               systemCode: fallbackErrno.map(Int.init),
                               systemDomain: fallbackErrno == nil ? nil : "NSPOSIXErrorDomain",
                               userMessage: "write failed on \(port)",
                               isRetryable: true)
        case let .portIsNotOpen(port):
            return SerialError(category: .writeFailed,
                               userMessage: "write failed: port \(port) is not open",
                               isRetryable: false)
        case let .failedToEncodeData(port):
            return SerialError(category: .writeFailed,
                               userMessage: "write failed: cannot encode data for \(port)",
                               isRetryable: false)
        default:
            return fallback(.writeFailed, error: error, operation: "write", path: path)
        }
    }

    /// dataStream `.failure` 元素 → 读路径错误。SGPort 的读失败元素均为可忽略的
    /// 瞬时语义（定时器在状态迁移窗口内空转），仅 portIsNotOpen 之外的情况才上报。
    public static func mapReadError(_ error: Error, path: String) -> SerialError {
        guard let sgError = error as? SGError else {
            return fallback(.readFailed, error: error, operation: "read", path: path)
        }
        switch sgError {
        case let .failedToEncodeText(port):
            return SerialError(category: .readFailed,
                               userMessage: "read failed: cannot encode received data on \(port)",
                               isRetryable: true)
        default:
            return fallback(.readFailed, error: error, operation: "read", path: path)
        }
    }

    /// 未知错误兜底：保持调用方给定的分类。
    public static func fallback(
        _ category: SerialError.Category,
        error: Error,
        operation: String,
        path: String
    ) -> SerialError {
        SerialError(category: category,
                    userMessage: "\(operation) failed on \(path): \(error.localizedDescription)",
                    isRetryable: true)
    }
}
