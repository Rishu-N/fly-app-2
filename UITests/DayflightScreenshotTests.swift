import XCTest

/// Drives the main flows on a simulator and attaches a screenshot of every screen.
/// CI exports the attachments (see .github/workflows/ci.yml) so the UI can be reviewed, and
/// `LayoutAudit` prints a compact text dump of each screen (frames, clipping, overlaps) into the
/// test log for reviewers who can't open the screenshot artifact.
final class DayflightScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    private func launch(_ scenario: String, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "-UITestsScenario", scenario]
        if dark { app.launchArguments += ["-UITestsDark"] }
        app.launch()
        return app
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        LayoutAudit.report(app, name)
    }

    /// Any element whose label contains `text` (toasts and cards merge their children into one
    /// accessibility element, so exact button labels aren't reliable there).
    @MainActor
    private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
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
        XCTAssertTrue(element(containing: "Undo", in: app).waitForExistence(timeout: 5))
        snap(app, "03-now-after-complete")
    }

    @MainActor
    func testOverrunState() {
        let app = launch("overrun")
        XCTAssertTrue(app.staticTexts["Deep work: launch brief"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add 5 minutes"].firstMatch.waitForExistence(timeout: 5))
        snap(app, "04-now-overrun")
    }

    @MainActor
    func testGapAndEmptyStates() {
        let gap = launch("gap")
        XCTAssertTrue(gap.staticTexts["Until Design review"].waitForExistence(timeout: 10))
        snap(gap, "05-now-gap")
        gap.terminate()

        let empty = launch("empty")
        XCTAssertTrue(empty.staticTexts["Plan a block and the timer starts when you do."].waitForExistence(timeout: 10))
        snap(empty, "06-now-empty")
    }

    @MainActor
    func testQuickCapture() {
        let app = launch("running")
        let add = app.buttons["Add a block"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let field = app.textFields.firstMatch
        guard field.waitForExistence(timeout: 5) else {
            snap(app, "07x-after-add-tap") // layout dump of whatever is on screen instead
            XCTFail("Quick capture sheet did not open")
            return
        }
        field.tap()
        field.typeText("gym 6:30pm 45m #health")
        snap(app, "07-quick-capture")
        field.typeText("\n")
        XCTAssertTrue(element(containing: "Gym", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testPlanAssistantAndSettingsTabs() {
        let app = launch("running")
        XCTAssertTrue(app.staticTexts["Deep work: launch brief"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        snap(app, "08-plan-day")

        let week = app.buttons["Week"].firstMatch
        if week.waitForExistence(timeout: 3) {
            week.tap()
            snap(app, "08b-plan-week")
            app.buttons["Day"].firstMatch.tap()
        }

        app.tabBars.buttons["Assistant"].tap()
        XCTAssertTrue(app.staticTexts["Plan out loud."].waitForExistence(timeout: 5))
        snap(app, "09-assistant-empty")
        // Template tiles merge title + subtitle into one button label.
        let template = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Plan my day")).firstMatch
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.tap()
        XCTAssertTrue(app.navigationBars["Plan my day"].waitForExistence(timeout: 5))
        snap(app, "10-assistant-template")
        app.buttons["Cancel"].firstMatch.tap()

        app.tabBars.buttons["Now"].tap()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        snap(app, "11-settings")
    }

    @MainActor
    func testInsights() {
        let app = launch("running")
        let insights = app.buttons["Insights"].firstMatch
        XCTAssertTrue(insights.waitForExistence(timeout: 10))
        insights.tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
        snap(app, "14-insights")
    }

    @MainActor
    func testDarkMode() {
        let app = launch("running", dark: true)
        XCTAssertTrue(app.staticTexts["Deep work: launch brief"].waitForExistence(timeout: 10))
        snap(app, "12-now-running-dark")
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        snap(app, "13-plan-dark")
        app.tabBars.buttons["Assistant"].tap()
        XCTAssertTrue(app.staticTexts["Plan out loud."].waitForExistence(timeout: 5))
        snap(app, "15-assistant-dark")
    }
}

/// Prints one line per visible element (`UITREE|screen|type|label|x,y,w,h`) plus findings:
/// `CLIP` (cut off at the screen's left/right edge), `OVERLAP` (two pieces of content drawn over
/// each other) and `SMALL` (tap target under 32 pt).
@MainActor
enum LayoutAudit {
    private struct Item {
        let type: XCUIElement.ElementType
        let label: String
        let frame: CGRect
    }

    static func report(_ app: XCUIApplication, _ name: String) {
        guard let root = try? app.snapshot() else {
            print("UITREE|\(name)|snapshot failed")
            return
        }
        let screen = root.frame
        var items: [Item] = []
        collect(root, into: &items)
        let visible = items.filter { item in
            item.frame.width > 0 && item.frame.height > 0
                && item.frame.maxY > screen.minY && item.frame.minY < screen.maxY
        }
        print("UITREE|\(name)|screen|\(Int(screen.width))x\(Int(screen.height))|\(visible.count) elements")
        for item in visible {
            print("UITREE|\(name)|\(abbreviation(item.type))|\(item.label.prefix(60))|\(rect(item.frame))")
        }
        for item in visible where item.frame.minX < screen.minX - 1 || item.frame.maxX > screen.maxX + 1 {
            print("UITREE|\(name)|CLIP|\(abbreviation(item.type)) \(item.label.prefix(40))|\(rect(item.frame))")
        }
        for item in visible where item.type == .button && (item.frame.width < 32 || item.frame.height < 32) {
            print("UITREE|\(name)|SMALL|\(item.label.prefix(40))|\(rect(item.frame))")
        }
        let content = visible.filter { [.staticText, .button, .textField, .image, .switch].contains($0.type) }
        for i in content.indices {
            for j in content.indices where j > i {
                let a = content[i].frame, b = content[j].frame
                let overlap = a.intersection(b)
                guard !overlap.isNull, overlap.width > 2, overlap.height > 2 else { continue }
                let smaller = min(a.width * a.height, b.width * b.height)
                let contained = a.insetBy(dx: -1, dy: -1).contains(b) || b.insetBy(dx: -1, dy: -1).contains(a)
                if !contained, overlap.width * overlap.height > smaller * 0.2 {
                    print("UITREE|\(name)|OVERLAP|\(content[i].label.prefix(30)) <> \(content[j].label.prefix(30))|\(rect(a)) <> \(rect(b))")
                }
            }
        }
    }

    private static func collect(_ node: XCUIElementSnapshot, into items: inout [Item]) {
        let label = node.label.isEmpty ? (node.value as? String ?? "") : node.label
        let interesting: Set<XCUIElement.ElementType> = [
            .staticText, .button, .textField, .secureTextField, .image, .switch, .segmentedControl,
            .navigationBar, .tabBar, .slider, .stepper, .datePicker, .picker, .link, .menuButton,
        ]
        if interesting.contains(node.elementType), !label.isEmpty || node.elementType == .tabBar || node.elementType == .navigationBar {
            items.append(Item(type: node.elementType, label: label.replacingOccurrences(of: "\n", with: " "), frame: node.frame))
        }
        for child in node.children { collect(child, into: &items) }
    }

    private static func rect(_ r: CGRect) -> String {
        "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"
    }

    private static func abbreviation(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .staticText: "text"
        case .button: "btn"
        case .textField, .secureTextField: "field"
        case .image: "img"
        case .switch: "switch"
        case .segmentedControl: "seg"
        case .navigationBar: "navbar"
        case .tabBar: "tabbar"
        case .slider: "slider"
        case .stepper: "stepper"
        case .datePicker: "date"
        case .picker: "picker"
        case .link: "link"
        case .menuButton: "menu"
        default: "el\(type.rawValue)"
        }
    }
}
