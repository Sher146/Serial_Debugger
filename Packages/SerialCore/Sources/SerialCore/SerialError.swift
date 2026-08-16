import Darwin
import Foundation

public struct SerialError: Error, Sendable, Equatable, LocalizedError {
    public enum Category: String, Sendable, Codable, CaseIterable {
        case portNotFound
        case portBusy
        case permissionDenied
        case configurationUnsupported
        case openFailed
        case readFailed
        case writeFailed
        case deviceRemoved
        case timeout
    }

    public let category: Category
    public let systemCode: Int?
    public let operation: String
    public let path: String?
    public let message: String

    public init(
        category: Category,
        systemCode: Int? = nil,
        operation: String,
        path: String? = nil,
        message: String
    ) {
        self.category = category
        self.systemCode = systemCode
        self.operation = operation
        self.path = path
        self.message = message
    }

    public var errorDescription: String? { message }

    public static func fromErrno(
        _ code: Int32,
        operation: String,
        path: String? = nil
    ) -> SerialError {
        let category: Category
        switch code {
        case ENOENT, ENXIO:
            category = .portNotFound
        case EBUSY:
            category = .portBusy
        case EPERM, EACCES:
            category = .permissionDenied
        case EINVAL, ENOTSUP:
            category = .configurationUnsupported
        case EIO:
            category = .deviceRemoved
        case ETIMEDOUT, EAGAIN:
            category = .timeout
        default:
            switch operation {
            case "read": category = .readFailed
            case "write": category = .writeFailed
            default: category = .openFailed
            }
        }

        let systemMessage = String(cString: strerror(code))
        let location = path.map { " (\($0))" } ?? ""
        return SerialError(
            category: category,
            systemCode: Int(code),
            operation: operation,
            path: path,
            message: "\(operation) failed\(location): \(systemMessage)"
        )
    }
}
