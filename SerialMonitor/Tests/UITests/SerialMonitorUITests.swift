import XCTest

final class SerialMonitorUITests: XCTestCase {
    func testLaunchShowsMainWorkspaceAndAccessibilityLabels() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["session.workspace"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["session.connect-button"].exists)
        XCTAssertTrue(app.otherElements["console.records"].exists)
        XCTAssertTrue(app.otherElements["send.editor-container"].exists)
    }

    func testConnectedMockValidatesHexAndTogglesConsole() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-connected"]
        app.launch()

        app.segmentedControls["send.format"].buttons["HEX"].click()
        let editor = app.textViews["send.editor"]
        editor.click()
        editor.typeText("A")
        XCTAssertTrue(app.otherElements["send.validation-error"].waitForExistence(timeout: 2))

        app.buttons["console.pause"].click()
        XCTAssertTrue(app.otherElements["console.paused-banner"].waitForExistence(timeout: 2))
        app.segmentedControls["console.display-format"].buttons["HEX"].click()
    }

    func testMainWindowRespectsMinimumSize() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.width, 980)
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.height, 680)
    }
}
