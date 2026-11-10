import XCTest

/// Plays a lesson through, each game in turn, on whatever cards the app has,
/// with progress kept in memory only. Set TEST_RUNNER_SNACK_SHOTS to a folder to
/// get a screenshot of each game and of the last page there.
final class LessonTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testALessonThroughEveryGame() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SnackInMemory", "YES", "-SnackGames", "build,type,flip,choose", "-AppleLanguages", "(zh-Hans)"]
        app.launch()

        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '开始一节'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20), "no lesson to start")
        shoot(app, "today")
        start.tap()

        var seen = Set<String>()
        for _ in 0..<40 {
            if app.buttons["完成"].waitForExistence(timeout: 1) { break }
            if app.staticTexts["拼一拼"].exists {
                once(&seen, "build", app)
                app.buttons.matching(identifier: "tile").element(boundBy: 0).tap()
                app.buttons.matching(identifier: "tile").element(boundBy: 1).tap()
                app.buttons["检查"].tap()
                once(&seen, "build-checked", app)
            } else if app.staticTexts["默一默"].exists {
                let field = app.textFields.firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 3))
                field.typeText("not it")
                once(&seen, "type", app)
                app.buttons["检查"].tap()
            } else if app.staticTexts["翻一翻"].exists {
                once(&seen, "flip", app)
                app.buttons["翻过来"].tap()
                XCTAssertTrue(app.buttons["记得"].waitForExistence(timeout: 3))
                once(&seen, "flip-turned", app)
                app.buttons["记得"].tap()
                continue
            } else if app.staticTexts["选一选"].exists {
                once(&seen, "choose", app)
                app.buttons.matching(identifier: "option").element(boundBy: 0).tap()
                once(&seen, "choose-answered", app)
            } else {
                XCTFail("neither a question nor the last page")
            }
            let next = app.buttons["继续"].exists ? app.buttons["继续"] : app.buttons["知道了"]
            XCTAssertTrue(next.waitForExistence(timeout: 3), "no feedback after an answer")
            once(&seen, "feedback-\(app.buttons["继续"].exists ? "right" : "wrong")", app)
            next.tap()
        }
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5), "the lesson did not end")
        XCTAssertTrue(seen.isSuperset(of: ["build", "type", "flip", "choose"]), "games seen: \(seen)")
        sleep(1)
        shoot(app, "end")
        app.buttons["完成"].tap()

        // The lesson counts for today.
        XCTAssertTrue(app.staticTexts["1/3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1"].exists)
        shoot(app, "today-after")
    }

    @MainActor private func once(_ seen: inout Set<String>, _ name: String, _ app: XCUIApplication) {
        guard seen.insert(name).inserted else { return }
        shoot(app, name)
    }

    @MainActor private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SNACK_SHOTS"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
        }
    }
}
