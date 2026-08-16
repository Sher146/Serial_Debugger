import Darwin
import XCTest
@testable import SerialCore

final class SerialErrorTests: XCTestCase {
    func testErrnoClassification() {
        XCTAssertEqual(SerialError.fromErrno(ENOENT, operation: "open").category, .portNotFound)
        XCTAssertEqual(SerialError.fromErrno(EBUSY, operation: "open").category, .portBusy)
        XCTAssertEqual(SerialError.fromErrno(EACCES, operation: "open").category, .permissionDenied)
        XCTAssertEqual(SerialError.fromErrno(EIO, operation: "read").category, .deviceRemoved)
        XCTAssertEqual(SerialError.fromErrno(ETIMEDOUT, operation: "write").category, .timeout)
    }
}
