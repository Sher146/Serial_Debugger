import Foundation
import XCTest

final class SerialMonitorUITests: XCTestCase {
    @MainActor
    func testSettingsUsesConfirmationActionsWithoutSidebarToggle() {
        let app = launch(scenario: "echo")
        app.typeKey(",", modifierFlags: .command)

        let cancel = button(app, "settings.cancel")
        let save = button(app, "settings.save")
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        XCTAssertTrue(save.exists)
        XCTAssertFalse(button(app, "隐藏边栏").exists)

        // "Restore defaults" must ask for confirmation before mutating the draft.
        button(app, "settings.reset").click()
        let confirm = app.sheets.buttons["恢复默认"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        app.sheets.buttons["取消"].firstMatch.click()
    }

    func testLaunchShowsWorkspaceAndConnectsWithScenarioPort() {
        let app = launch(scenario: "echo")
        XCTAssertTrue(element(app, "session.workspace").waitForExistence(timeout: 5))
        XCTAssertTrue(button(app, "session.connect-button").exists)
        XCTAssertTrue(element(app, "console.records").exists)
        XCTAssertTrue(element(app, "session.port-picker").exists)

        button(app, "session.connect-button").click()
        XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "connected"))
    }

    func testBurstScenarioDisplaysIncomingRecordAndClearRemainsAvailable() {
        let app = launch(scenario: "burst")
        connect(app)
        XCTAssertTrue(waitForConsole(app, containing: "FIRST"))
        XCTAssertTrue(button(app, "console.clear").isEnabled)
    }

    func testOpeningCanBeCancelled() {
        let app = launch(scenario: "opening")
        button(app, "session.connect-button").click()
        XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "opening"))
        XCTAssertFalse(button(app, "session.parameters").isEnabled)
        button(app, "session.connect-button").click()
        XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "disconnected"))
    }

    func testDeviceRemovalShowsRecoverableError() {
        let app = launch(scenario: "device-removal")
        connect(app)
        XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "error", timeout: 6))
    }

    func testMainWindowRespectsMinimumSize() {
        let app = launch(scenario: "echo")
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.width, 980)
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.height, 680)
    }

    func testToolbarProvidesWidePortPickerAndLargeIconTargets() {
        let app = launch(scenario: "echo")
        let portPicker = element(app, "session.port-picker")
        XCTAssertTrue(portPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(portPicker.value as? String, "cu.Bluetooth-Incoming-Port")

        for identifier in ["session.refresh", "session.parameters", "session.presets-toggle", "log.toggle"] {
            let control = button(app, identifier)
            XCTAssertTrue(control.exists, "Missing toolbar button \(identifier)")
            XCTAssertGreaterThanOrEqual(control.frame.width, 32, "Toolbar button \(identifier) is too narrow")
            XCTAssertGreaterThanOrEqual(control.frame.height, 32, "Toolbar button \(identifier) is too short")
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

    func testHexInputIsRejectedWithValidationError() {
        let app = launch(scenario: "echo")
        connect(app)
        selectSegment(app, container: "send.format", title: "HEX")

        let editor = app.textViews["send.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click()
        editor.typeText("0")

        XCTAssertTrue(element(app, "send.validation-error").waitForExistence(timeout: 2))
        XCTAssertFalse(button(app, "send.button").isEnabled)
    }

    func testPauseShowsBannerAndResumeHidesIt() {
        let app = launch(scenario: "burst")
        connect(app)
        button(app, "console.pause").click()
        let banner = element(app, "console.paused-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 2))

        button(app, "console.pause").click()
        XCTAssertFalse(element(app, "console.paused-banner").waitForExistence(timeout: 1))
    }

    func testReceiveFormatSwitchReprojectsRecordsAsHex() {
        let app = launch(scenario: "burst")
        connect(app)
        XCTAssertTrue(waitForConsole(app, containing: "FIRST"))

        selectSegment(app, container: "console.display-format", title: "HEX")

        XCTAssertTrue(waitForConsole(app, containing: "46 49"))
    }

    func testPresetCanBeCreatedSentAndDeleted() {
        let app = launch(scenario: "echo")
        connect(app)
        ensurePresetInspector(app)

        button(app, "presets.add").click()
        let name = app.textFields["presets.editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.click()
        name.typeText("复位")
        let content = app.textViews["presets.editor.content"]
        content.click()
        content.typeText("AT")
        button(app, "presets.editor.save").click()

        let preset = app.staticTexts["复位"]
        XCTAssertTrue(preset.waitForExistence(timeout: 3))

        let inspector = element(app, "presets.inspector")
        inspector.buttons["发送"].firstMatch.click()
        XCTAssertTrue(waitForConsole(app, containing: "AT"))

        let delete = inspector.descendants(matching: .button)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "presets.delete."))
            .firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.click()
        XCTAssertFalse(app.staticTexts["复位"].waitForExistence(timeout: 2))
    }

    func testLoggingToggleReflectsRecordingState() {
        let app = launch(scenario: "echo")
        connect(app)
        XCTAssertTrue(waitForValue(element(app, "status.log"), "inactive"))

        button(app, "log.toggle").click()
        XCTAssertTrue(waitForValue(element(app, "status.log"), "recording", timeout: 3))

        button(app, "log.toggle").click()
        XCTAssertTrue(waitForValue(element(app, "status.log"), "inactive", timeout: 3))
    }

    func testAutoSendLoopCanStartAndStop() {
        let app = launch(scenario: "auto-send")
        connect(app)
        selectSegment(app, container: "send.format", title: "HEX")
        let editor = app.textViews["send.editor"]
        editor.click()
        editor.typeText("41")

        button(app, "auto-send.toggle").click()
        XCTAssertTrue(element(app, "auto-send.status").waitForExistence(timeout: 3))
        XCTAssertEqual(button(app, "auto-send.toggle").label, "停止循环")

        button(app, "auto-send.toggle").click()
        XCTAssertFalse(element(app, "auto-send.status").waitForExistence(timeout: 2))
    }

    func testMenuShortcutsConnectAndTogglePause() {
        let app = launch(scenario: "echo")
        XCTAssertTrue(element(app, "session.workspace").waitForExistence(timeout: 5))

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "connected", timeout: 3))

        app.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertTrue(element(app, "console.paused-banner").waitForExistence(timeout: 2))

        app.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertFalse(element(app, "console.paused-banner").waitForExistence(timeout: 1))
    }

    func testCoreControlsExposeAccessibleLabelsAndValues() {
        let app = launch(scenario: "echo")
        XCTAssertTrue(element(app, "session.workspace").waitForExistence(timeout: 5))

        XCTAssertEqual(element(app, "session.connection-status").value as? String, "disconnected")
        XCTAssertEqual(button(app, "session.connect-button").label, "连接")
        XCTAssertTrue(button(app, "send.button").label.contains("发送"))
        for identifier in ["status.rx", "status.tx", "status.records", "status.log"] {
            XCTAssertTrue(element(app, identifier).exists, "Missing status element \(identifier)")
        }
        XCTAssertEqual(element(app, "status.log").value as? String, "inactive")
    }

    func testAppearanceModesKeepWorkspaceUsable() {
        for mode in ["Dark", "Light"] {
            let app = launch(scenario: "echo", extraArguments: ["-AppleInterfaceStyle", mode])
            XCTAssertTrue(element(app, "session.workspace").waitForExistence(timeout: 5), "\(mode) workspace missing")
            button(app, "session.connect-button").click()
            XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "connected"), "\(mode) failed to connect")
            app.terminate()
        }
    }

    func testGlobalFontScaleChangesTextSize() {
        let standard = launch(scenario: "echo")
        let standardPlaceholder = element(standard, "presets.placeholder")
        XCTAssertTrue(standardPlaceholder.waitForExistence(timeout: 5))
        let baseHeight = standardPlaceholder.frame.height
        XCTAssertGreaterThan(baseHeight, 0)
        standard.terminate()

        let enlarged = launch(scenario: "echo", extraArguments: ["-ui-testing-font-scale", "xlarge"])
        let enlargedPlaceholder = element(enlarged, "presets.placeholder")
        XCTAssertTrue(enlargedPlaceholder.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(enlargedPlaceholder.frame.height, baseHeight, "全局字体“特大”应放大文本")
    }

    func testCaptureConnectionStateScreenshots() {
        let disconnected = launch(scenario: "echo")
        XCTAssertTrue(element(disconnected, "session.workspace").waitForExistence(timeout: 5))
        attachScreenshot(disconnected, named: "state-disconnected")

        let opening = launch(scenario: "opening")
        button(opening, "session.connect-button").click()
        XCTAssertTrue(waitForValue(element(opening, "session.connection-status"), "opening"))
        attachScreenshot(opening, named: "state-opening")

        let connected = launch(scenario: "echo")
        connect(connected)
        attachScreenshot(connected, named: "state-connected")

        let error = launch(scenario: "device-removal")
        connect(error)
        XCTAssertTrue(waitForValue(element(error, "session.connection-status"), "error", timeout: 6))
        attachScreenshot(error, named: "state-error")
    }

    private func launch(scenario: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-scenario", scenario] + extraArguments
        app.launch()
        return app
    }

    private func connect(_ app: XCUIApplication) {
        XCTAssertTrue(element(app, "session.workspace").waitForExistence(timeout: 5))
        button(app, "session.connect-button").click()
        XCTAssertTrue(waitForValue(element(app, "session.connection-status"), "connected"))
    }

    private func ensurePresetInspector(_ app: XCUIApplication) {
        if !element(app, "presets.inspector").waitForExistence(timeout: 2) {
            button(app, "session.presets-toggle").click()
            XCTAssertTrue(element(app, "presets.inspector").waitForExistence(timeout: 2))
        }
    }

    private func selectSegment(_ app: XCUIApplication, container identifier: String, title: String) {
        let control = element(app, identifier)
        XCTAssertTrue(control.waitForExistence(timeout: 3), "Missing segmented control \(identifier)")
        if control.buttons[title].exists {
            control.buttons[title].click()
            return
        }
        if control.radioButtons[title].exists {
            control.radioButtons[title].click()
            return
        }
        // Some segmented pickers surface as a single toggle whose click advances
        // to the requested segment (e.g. the console ASCII/HEX control).
        if control.elementType == .checkBox {
            control.click()
            return
        }
        control.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch.click()
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func button(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.buttons.matching(identifier: identifier).firstMatch
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 2) -> Bool {
        NSPredicate(format: "value == %@", value).evaluate(with: element) ||
            XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)], timeout: timeout) == .completed
    }

    private func waitForConsole(_ app: XCUIApplication, containing value: String, timeout: TimeInterval = 3) -> Bool {
        let textView = app.textViews["console.records"]
        guard textView.waitForExistence(timeout: timeout) else { return false }
        let predicate = NSPredicate(format: "value CONTAINS %@", value)
        return XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: textView)], timeout: timeout) == .completed
    }
}
