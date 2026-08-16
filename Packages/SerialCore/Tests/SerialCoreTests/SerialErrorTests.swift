import Foundation
import XCTest
@testable import SerialCore

final class SerialErrorTests: XCTestCase {
    private let path = "/dev/cu.test"
    private let op = "open"

    func testMapErrnoCategoryMapping() {
        XCTAssertEqual(SerialError.mapErrno(ENOENT, operation: op, path: path).category, .portNotFound)
        XCTAssertEqual(SerialError.mapErrno(EBUSY, operation: op, path: path).category, .portBusy)
        XCTAssertEqual(SerialError.mapErrno(EPERM, operation: op, path: path).category, .permissionDenied)
        XCTAssertEqual(SerialError.mapErrno(EACCES, operation: op, path: path).category, .permissionDenied)
        XCTAssertEqual(SerialError.mapErrno(EINVAL, operation: op, path: path).category, .configurationUnsupported)
        XCTAssertEqual(SerialError.mapErrno(EIO, operation: op, path: path).category, .deviceRemoved)
        XCTAssertEqual(SerialError.mapErrno(ETIMEDOUT, operation: op, path: path).category, .timeout)
    }

    func testMapErrnoIsRetryable() {
        XCTAssertFalse(SerialError.mapErrno(ENOENT, operation: op, path: path).isRetryable)
        XCTAssertTrue(SerialError.mapErrno(EBUSY, operation: op, path: path).isRetryable)
        XCTAssertFalse(SerialError.mapErrno(EPERM, operation: op, path: path).isRetryable)
        XCTAssertFalse(SerialError.mapErrno(EINVAL, operation: op, path: path).isRetryable)
        XCTAssertTrue(SerialError.mapErrno(EIO, operation: op, path: path).isRetryable)
        XCTAssertTrue(SerialError.mapErrno(ETIMEDOUT, operation: op, path: path).isRetryable)
    }

    func testOccurredAtInjectionAndFields() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let error = SerialError.mapErrno(ENOENT, operation: op, path: path, occurredAt: date)
        XCTAssertEqual(error.occurredAt, date)
        XCTAssertEqual(error.systemCode, Int(ENOENT))
        XCTAssertEqual(error.systemDomain, "NSPOSIXErrorDomain")
        XCTAssertFalse(error.userMessage.isEmpty)
    }

    func testEquatable() {
        let date = Date(timeIntervalSince1970: 42)
        let a = SerialError(category: .portBusy, systemCode: 16, systemDomain: "NSPOSIXErrorDomain",
                            userMessage: "busy", occurredAt: date, isRetryable: true)
        let b = SerialError(category: .portBusy, systemCode: 16, systemDomain: "NSPOSIXErrorDomain",
                            userMessage: "busy", occurredAt: date, isRetryable: true)
        let c = SerialError(category: .portBusy, systemCode: 16, systemDomain: "NSPOSIXErrorDomain",
                            userMessage: "busy", occurredAt: date, isRetryable: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
