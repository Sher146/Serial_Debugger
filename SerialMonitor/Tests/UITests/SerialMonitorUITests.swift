import Foundation
import XCTest

final class SerialMonitorUITests: XCTestCase {
    func testLaunchShowsWorkspaceAndConnectsWithScenarioPort() {
        let app = launch(scenario: "echo")
        XCTAssertTrue(element(app, "session.workspace").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["session.connect-button"].exists)
        XCTAssertTrue(element(app, "console.records").exists)
        XCTAssertTrue(element(app, "session.port-picker").exists)

        app.buttons["session.connect-button"].click()
        XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "connected"))
    }

    func testBurstScenarioDisplaysIncomingRecordAndClearRemainsAvailable() {
        let app = launch(scenario: "burst")
        connect(app)
        XCTAssertTrue(element(app, "console.record.RX.4649525354").waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["console.clear"].isEnabled)
    }

    func testOpeningCanBeCancelled() {
        let app = launch(scenario: "opening")
        app.buttons["session.connect-button"].click()
        XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "opening"))
        XCTAssertFalse(app.buttons["session.parameters"].isEnabled)
        app.buttons["session.connect-button"].click()
        XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "disconnected"))
    }

    func testDeviceRemovalShowsRecoverableError() {
        let app = launch(scenario: "device-removal")
        connect(app)
        XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "error", timeout: 3))
    }

    func testMainWindowRespectsMinimumSize() {
        let app = launch(scenario: "echo")
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.width, 1_120)
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.height, 680)
    }

    func testToolbarProvidesWidePortPickerAndLargeIconTargets() {
        let app = launch(scenario: "echo")
        let portPicker = element(app, "session.port-picker")
        XCTAssertTrue(portPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(portPicker.value as? String, "cu.Bluetooth-Incoming-Port")

        for identifier in ["session.refresh", "session.parameters", "session.presets-toggle", "log.toggle"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, "Missing toolbar button \(identifier)")
            XCTAssertGreaterThanOrEqual(button.frame.width, 32, "Toolbar button \(identifier) is too narrow")
            XCTAssertGreaterThanOrEqual(button.frame.height, 32, "Toolbar button \(identifier) is too short")
        }
    }

    func testToolbarSelectsHighSpeedBaudRate() {
        let app = launch(scenario: "echo")
        let baudRate = element(app, "session.baud-rate")
        XCTAssertTrue(baudRate.waitForExistence(timeout: 5))
        baudRate.click()
        let highSpeedRate = app.menuItems["921,600"]
        XCTAssertTrue(highSpeedRate.waitForExistence(timeout: 2))
        highSpeedRate.click()
        XCTAssertTrue(waitForValue(baudRate, "921,600"))
    }

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-scenario", scenario]
        app.launch()
        return app
    }

    private func connect(_ app: XCUIApplication) {
        XCTAssertTrue(element(app, "session.workspace").waitForExistence(timeout: 5))
        app.buttons["session.connect-button"].click()
        XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "connected"))
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 2) -> Bool {
        NSPredicate(format: "value == %@", value).evaluate(with: element) ||
            XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)], timeout: timeout) == .completed
    }
}
