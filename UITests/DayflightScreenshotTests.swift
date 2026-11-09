import XCTest

/// Drives the main flows on a simulator and attaches a screenshot of every screen.
/// CI exports the attachments (see .github/workflows/ci.yml) so the UI can be reviewed.
final class DayflightScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ scenario: String, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "-UITestsScenario", scenario]
        if dark { app.launchArguments += ["-UITestsDark"] }
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNowRunningPauseAndComplete() {
        let app = launch("running")
        XCTAssertTrue(app.staticTexts["Deep work: launch brief"].waitForExistence(timeout: 10))
        snap(app, "01-now-running")

        let pause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        XCTAssertTrue(app.buttons["Resume"].firstMatch.waitForExistence(timeout: 5))
        snap(app, "02-now-paused")
        app.buttons["Resume"].firstMatch.tap()

        app.buttons["Complete"].firstMatch.tap()
        // The conveyor promotes the next block into the lens; an Undo toast appears.
        XCTAssertTrue(app.buttons["Undo"].firstMatch.waitForExistence(timeout: 5))
        snap(app, "03-now-after-complete")
    }

    func testOverrunState() {
        let app = launch("overrun")
        XCTAssertTrue(app.staticTexts["Deep work: launch brief"].waitForExistence(timeout: 10))
        snap(app, "04-now-overrun")
        XCTAssertTrue(app.buttons["Add 5 minutes"].firstMatch.exists)
    }

    func testGapAndEmptyStates() {
        let gap = launch("gap")
        XCTAssertTrue(gap.staticTexts["Until Design review"].waitForExistence(timeout: 10))
        snap(gap, "05-now-gap")
        gap.terminate()

        let empty = launch("empty")
        XCTAssertTrue(empty.staticTexts["Plan a block and the timer starts when you do."].waitForExistence(timeout: 10))
        snap(empty, "06-now-empty")
    }

    func testQuickCapture() {
        let app = launch("running")
        app.buttons["Add a block"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("gym 6:30pm 45m #health")
        snap(app, "07-quick-capture")
        field.typeText("\n")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Gym'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testPlanAssistantAndSettingsTabs() {
        let app = launch("running")
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        snap(app, "08-plan-day")

        app.tabBars.buttons["Assistant"].tap()
        XCTAssertTrue(app.staticTexts["Plan out loud."].waitForExistence(timeout: 5))
        snap(app, "09-assistant-empty")
        app.buttons["Plan my day"].firstMatch.tap()
        snap(app, "10-assistant-template")
        app.buttons["Cancel"].firstMatch.tap()

        app.tabBars.buttons["Now"].tap()
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        snap(app, "11-settings")
    }

    func testDarkMode() {
        let app = launch("running", dark: true)
        XCTAssertTrue(app.staticTexts["Deep work: launch brief"].waitForExistence(timeout: 10))
        snap(app, "12-now-running-dark")
        app.tabBars.buttons["Plan"].tap()
        snap(app, "13-plan-dark")
    }
}
