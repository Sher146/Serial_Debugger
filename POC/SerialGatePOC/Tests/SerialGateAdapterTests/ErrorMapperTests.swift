import Foundation
import SerialCore
import SerialGate
import XCTest
@testable import SerialGateAdapter

final class ErrorMapperTests: XCTestCase {
    private let path = "/dev/cu.test"

    func testOpenErrorMapping() {
        XCTAssertEqual(
            SerialGateErrorMapper.mapOpenError(SGError.failedToSetOptions(path), path: path).category,
            .configurationUnsupported
        )
        XCTAssertEqual(
            SerialGateErrorMapper.mapOpenError(SGError.failedToOpenPort(path), path: path).category,
            .openFailed
        )
        XCTAssertEqual(
            SerialGateErrorMapper.mapOpenError(SGError.portIsNotOpen(path), path: path).category,
            .openFailed
        )
    }

    func testWriteErrorMapping() {
        XCTAssertEqual(
            SerialGateErrorMapper.mapWriteError(SGError.failedToWriteData(path), path: path).category,
            .writeFailed
        )
        XCTAssertEqual(
            SerialGateErrorMapper.mapWriteError(SGError.portIsNotOpen(path), path: path).category,
            .writeFailed
        )
        XCTAssertEqual(
            SerialGateErrorMapper.mapWriteError(SGError.failedToEncodeData(path), path: path).category,
            .writeFailed
        )
    }

    func testWriteErrorEIOMapsToDeviceRemoved() {
        let error = SerialGateErrorMapper.mapWriteError(
            SGError.failedToWriteData(path), path: path, fallbackErrno: EIO
        )
        XCTAssertEqual(error.category, .deviceRemoved)
        XCTAssertEqual(error.systemCode, Int(EIO))
        XCTAssertEqual(error.systemDomain, "NSPOSIXErrorDomain")
        XCTAssertTrue(error.isRetryable)
    }

    func testReadErrorMapping() {
        XCTAssertEqual(
            SerialGateErrorMapper.mapReadError(SGError.failedToEncodeText(path), path: path).category,
            .readFailed
        )
    }

    func testUnknownErrorFallbacks() {
        let unknown = CocoaError(.fileReadUnknown)
        XCTAssertEqual(
            SerialGateErrorMapper.mapOpenError(unknown, path: path).category,
            .openFailed
        )
        XCTAssertEqual(
            SerialGateErrorMapper.mapWriteError(unknown, path: path).category,
            .writeFailed
        )
        XCTAssertEqual(
            SerialGateErrorMapper.mapReadError(unknown, path: path).category,
            .readFailed
        )
    }
}
