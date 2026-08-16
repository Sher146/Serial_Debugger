import Foundation
import XCTest
@testable import SerialCore

final class SerialConfigurationTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = SerialConfiguration(
            path: "/dev/cu.usbserial-TEST",
            baudRate: 9600,
            dataBits: .seven,
            parity: .even,
            stopBits: .two,
            flowControl: .rtsCts
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SerialConfiguration.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDefaultValues() {
        let config = SerialConfiguration(path: "/dev/cu.test")
        XCTAssertEqual(config.baudRate, 115200)
        XCTAssertEqual(config.dataBits, .eight)
        XCTAssertEqual(config.parity, .none)
        XCTAssertEqual(config.stopBits, .one)
        XCTAssertEqual(config.flowControl, .none)
    }

    func testCaseIterableCounts() {
        XCTAssertEqual(SerialConfiguration.DataBits.allCases.count, 4)
        XCTAssertEqual(SerialConfiguration.DataBits.allCases.map(\.rawValue), [5, 6, 7, 8])
        XCTAssertEqual(SerialConfiguration.Parity.allCases.count, 3)
        XCTAssertEqual(SerialConfiguration.Parity.allCases.map(\.rawValue), ["none", "even", "odd"])
        XCTAssertEqual(SerialConfiguration.StopBits.allCases.count, 2)
        XCTAssertEqual(SerialConfiguration.StopBits.allCases.map(\.rawValue), ["one", "two"])
        XCTAssertEqual(SerialConfiguration.FlowControl.allCases.count, 3)
        XCTAssertEqual(SerialConfiguration.FlowControl.allCases.map(\.rawValue), ["none", "rtsCts", "xonXoff"])
    }

    func testCommonBaudRatesContains9600And115200() {
        XCTAssertTrue(SerialConfiguration.commonBaudRates.contains(9600))
        XCTAssertTrue(SerialConfiguration.commonBaudRates.contains(115200))
    }
}
