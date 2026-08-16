import XCTest

final class SerialMonitorUITests: XCTestCase {
    func testLaunchShowsP0Placeholder() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Serial Monitor"].waitForExistence(timeout: 5))
    }
}
