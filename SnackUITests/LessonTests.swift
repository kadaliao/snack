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
        app.launchArguments = [
            "-SnackInMemory", "YES", "-SnackGames", "match,listen,cloze,build,type,flip,fix,choose",
            "-sounds", "NO", "-speakAnswers", "NO", "-AppleLanguages", "(zh-Hans)",
        ]
        app.launch()

        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '开始一节'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20), "no lesson to start")
        shoot(app, "today")
        start.tap()

        var seen = Set<String>()
        for _ in 0..<40 {
            if app.buttons["完成"].waitForExistence(timeout: 1) { break }
            if app.staticTexts["配一配"].exists {
                once(&seen, "match", app)
                pairUp(app)
                once(&seen, "match-done", app)
            } else if app.staticTexts["听一听"].exists {
                once(&seen, "listen", app)
                answerWithTilesOrOptions(app)
            } else if app.staticTexts["拼一拼"].exists {
                once(&seen, "build", app)
                answerWithTilesOrOptions(app)
                once(&seen, "build-checked", app)
            } else if let game = ["默一默", "填一填", "改一改"].first(where: { app.staticTexts[$0].exists }) {
                let field = app.textFields.firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 3))
                field.typeText(" not it")
                once(&seen, ["默一默": "type", "填一填": "cloze", "改一改": "fix"][game]!, app)
                app.buttons["检查"].tap()
            } else if app.staticTexts["翻一翻"].exists {
                once(&seen, "flip", app)
                app.buttons["翻过来"].tap()
                XCTAssertTrue(app.buttons["记得"].waitForExistence(timeout: 3))
                app.buttons["记得"].tap()
                continue
            } else if app.staticTexts["选一选"].exists {
                once(&seen, "choose", app)
                app.buttons.matching(identifier: "option").element(boundBy: 0).tap()
            } else {
                XCTFail("neither a question nor the last page")
            }
            let next = app.buttons["继续"].exists ? app.buttons["继续"] : app.buttons["知道了"]
            XCTAssertTrue(next.waitForExistence(timeout: 3), "no feedback after an answer")
            once(&seen, "feedback-\(app.buttons["继续"].exists ? "right" : "wrong")", app)
            next.tap()
        }
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5), "the lesson did not end")
        XCTAssertTrue(seen.isSuperset(of: ["match", "listen", "build", "flip"]), "games seen: \(seen)")
        sleep(1)
        shoot(app, "end")
        app.buttons["完成"].tap()

        // The lesson counts for today.
        XCTAssertTrue(app.staticTexts["今天刷了 1 节"].waitForExistence(timeout: 5))
        shoot(app, "today-after")
    }

    /// Tries each front with each back until it pairs.
    @MainActor private func pairUp(_ app: XCUIApplication) {
        let fronts = app.buttons.matching(identifier: "front")
        let backs = app.buttons.matching(identifier: "back")
        for i in 0..<fronts.count {
            for j in 0..<backs.count where fronts.element(boundBy: i).isEnabled {
                guard backs.element(boundBy: j).isEnabled else { continue }
                fronts.element(boundBy: i).tap()
                backs.element(boundBy: j).tap()
                usleep(500_000)
            }
        }
    }

    @MainActor private func answerWithTilesOrOptions(_ app: XCUIApplication) {
        let tiles = app.buttons.matching(identifier: "tile")
        if tiles.count >= 2 {
            tiles.element(boundBy: 0).tap()
            tiles.element(boundBy: 1).tap()
            app.buttons["检查"].tap()
        } else {
            app.buttons.matching(identifier: "option").element(boundBy: 0).tap()
        }
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

/// The widget: its link starts a lesson, and its faces as the gallery draws them.
final class WidgetTests: XCTestCase {
    @MainActor func testTheWidgetLinkStartsALesson() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SnackInMemory", "YES", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '开始一节'")).firstMatch.waitForExistence(timeout: 20))
        app.open(URL(string: "snack://lesson")!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["打开"].waitForExistence(timeout: 3) { springboard.buttons["打开"].tap() }
        XCTAssertTrue(app.buttons["退出"].waitForExistence(timeout: 10), "no lesson started")
    }

    @MainActor func testTheWidgetFaces() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SnackWidgetGallery", "YES", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        sleep(2)
        let shot = app.screenshot()
        if let folder = ProcessInfo.processInfo.environment["SNACK_SHOTS"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("widgets.png"))
        }
    }
}

/// A deck that comes with the app is added with a tap.
final class StarterTests: XCTestCase {
    @MainActor func testAStarterDeckIsAddedWithATap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SnackInMemory", "YES", "-addedStarters", "()", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        app.tabBars.buttons["牌组"].tap()
        let add = app.buttons["添加日语 · 旅行入门"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "no starter deck to add")
        add.tap()
        XCTAssertTrue(app.staticTexts["日语 · 旅行入门"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["添加日语 · 旅行入门"].waitForExistence(timeout: 2))
        let shot = app.screenshot()
        if let folder = ProcessInfo.processInfo.environment["SNACK_SHOTS"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("starters.png"))
        }
    }
}
