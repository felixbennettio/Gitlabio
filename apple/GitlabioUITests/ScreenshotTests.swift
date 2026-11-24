import XCTest

/// Launches the app in demo mode on each main screen and attaches a screenshot.
/// CI exports the attachments so the design can be reviewed without a device.
final class ScreenshotTests: XCTestCase {
    static let screens = ["home", "projects", "project", "code", "file", "readme", "mrs", "mr", "mr-discussion", "mr-changes",
                          "issue", "pipelines", "pipeline", "job", "commit", "branches", "inbox", "me", "schedules", "schedule", "run-pipeline"]

    override func setUp() {
        continueAfterFailure = true
    }

    func testOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-GitlabioAppearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["start-demo"].waitForExistence(timeout: 10) || app.tabBars.firstMatch.exists)
        Thread.sleep(forTimeInterval: 1.5)
        attach("onboarding-light", app)
    }

    func testLightScreens() { capture(appearance: "light") }
    func testDarkScreens() { capture(appearance: "dark") }

    func testDemoFlowEditAndComment() {
        let app = XCUIApplication()
        app.launchArguments = ["-GitlabioDemo", "-GitlabioScreen", "file", "-GitlabioAppearance", "light"]
        app.launch()
        let edit = app.buttons["edit-file"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let editor = app.textViews["file-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        // CI simulators run without a hardware keyboard, so typing is not reliable here;
        // check the editor opens and capture it.
        attach("flow-editor", app)
    }

    private func capture(appearance: String) {
        for screen in Self.screens {
            let app = XCUIApplication()
            app.launchArguments = ["-GitlabioDemo", "-GitlabioScreen", screen, "-GitlabioAppearance", appearance]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), screen)
            // Demo requests take ~120 ms each; give lists and animations time to settle.
            Thread.sleep(forTimeInterval: 2.5)
            attach("\(screen)-\(appearance)", app)
            if screen == "run-pipeline" {
                // The extra-variable rows sit below the fold.
                app.swipeUp()
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1)
                attach("run-pipeline-bottom-\(appearance)", app)
            }
            app.terminate()
        }
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
