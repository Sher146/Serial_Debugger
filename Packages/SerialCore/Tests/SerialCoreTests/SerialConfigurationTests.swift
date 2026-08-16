import XCTest
@testable import SerialCore

final class SerialConfigurationTests: XCTestCase {
    func testDefaultConfigurationUsesSerialMonitorDefaults() throws {
        let configuration = SerialConfiguration(path: "/dev/cu.test")
        XCTAssertEqual(configuration.baudRate, 115_200)
        XCTAssertEqual(configuration.dataBits, .eight)
        XCTAssertEqual(configuration.parity, .none)
        XCTAssertEqual(configuration.stopBits, .one)
        XCTAssertEqual(configuration.flowControl, .none)
    }

    func testConfigurationRoundTripsThroughCodable() throws {
        let original = SerialConfiguration(path: "/dev/cu.usbserial", baudRate: 9_600, dataBits: .seven, parity: .even, stopBits: .two, flowControl: .hardware)
        let decoded = try JSONDecoder().decode(SerialConfiguration.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
