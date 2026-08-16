import Foundation

/// 结构化串口错误（需求 §5.1：分类、系统错误码、用户可读说明、发生时间、是否可重试）。
///
/// - 用户可见文案规则：`userMessage` 存放**开发期英文兜底说明**；
///   正式 UI（04 文档起）必须按 `category` 经 String Catalog 映射 zh-CN 文案，
///   不得直接把底层系统错误串展示给用户（需求 §13）。
public struct SerialError: Error, Sendable, Equatable {
    /// 错误分类，决定 UI 提示策略与重试引导。
    public enum Category: String, Sendable, Codable, Equatable, CaseIterable {
        /// 路径不存在（设备未插入或节点已消失）。
        case portNotFound
        /// 端口被其他进程占用。
        case portBusy
        /// 权限不足（沙盒 entitlement 缺失或节点权限拒绝）。
        case permissionDenied
        /// 参数组合不被设备/驱动支持（如该芯片不支持的波特率）。
        case configurationUnsupported
        /// open 调用的其他失败。
        case openFailed
        /// 读失败（非拔出原因）。
        case readFailed
        /// 写失败（非拔出原因）。
        case writeFailed
        /// 设备拔出导致的终止。
        case deviceRemoved
        /// 操作超时。
        case timeout
    }

    public let category: Category
    /// 底层系统错误码（POSIX errno 或 IOKit 返回码）；无对应值为 nil。
    public let systemCode: Int?
    /// 错误域标识（如 "NSPOSIXErrorDomain"、"IOKit"）；无对应值为 nil。
    public let systemDomain: String?
    /// 开发期英文兜底说明；正式 UI 按 category 走 String Catalog，不直接展示本字段。
    public let userMessage: String
    /// 发生时间（UTC）。
    public let occurredAt: Date
    /// 是否值得重试（如 portBusy 提示用户释放后重试；deviceRemoved 引导重插）。
    public let isRetryable: Bool

    public init(
        category: Category,
        systemCode: Int? = nil,
        systemDomain: String? = nil,
        userMessage: String,
        occurredAt: Date = Date(),
        isRetryable: Bool
    ) {
        self.category = category
        self.systemCode = systemCode
        self.systemDomain = systemDomain
        self.userMessage = userMessage
        self.occurredAt = occurredAt
        self.isRetryable = isRetryable
    }
}

extension SerialError {
    /// errno → Category 的标准映射。各适配器（SerialGate / 自研）统一使用，
    /// 保证上层看到的分类与底层实现无关。
    public static func mapErrno(
        _ code: Int32,
        operation: String,
        path: String,
        occurredAt: Date = Date()
    ) -> SerialError {
        let domain = "NSPOSIXErrorDomain"
        let message = String(cString: strerror(code))
        switch code {
        case ENOENT:
            return SerialError(category: .portNotFound, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed: port \(path) does not exist (\(message))",
                               occurredAt: occurredAt, isRetryable: false)
        case EBUSY:
            return SerialError(category: .portBusy, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed: port \(path) is busy (\(message))",
                               occurredAt: occurredAt, isRetryable: true)
        case EPERM, EACCES:
            return SerialError(category: .permissionDenied, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed: permission denied for \(path) (\(message))",
                               occurredAt: occurredAt, isRetryable: false)
        case EINVAL, ENOTSUP:
            return SerialError(category: .configurationUnsupported, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed: unsupported configuration for \(path) (\(message))",
                               occurredAt: occurredAt, isRetryable: false)
        case EIO:
            // EIO 在读写路径上通常意味着设备消失；open 路径按 openFailed 处理由调用方决定，
            // 此处保守映射为 deviceRemoved 需调用方覆写时直接构造。
            return SerialError(category: .deviceRemoved, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed: device at \(path) went away (\(message))",
                               occurredAt: occurredAt, isRetryable: true)
        case ETIMEDOUT, EAGAIN:
            return SerialError(category: .timeout, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) timed out on \(path) (\(message))",
                               occurredAt: occurredAt, isRetryable: true)
        default:
            return SerialError(category: .openFailed, systemCode: Int(code),
                               systemDomain: domain,
                               userMessage: "\(operation) failed on \(path) (\(message))",
                               occurredAt: occurredAt, isRetryable: true)
        }
    }
}
