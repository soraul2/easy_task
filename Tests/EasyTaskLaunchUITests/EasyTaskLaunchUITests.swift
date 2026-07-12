import XCTest

final class EasyTaskLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryTabNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))

        let boardTab = tabBar.buttons["칸반"]
        let calendarTab = tabBar.buttons["캘린더"]
        let archiveTab = tabBar.buttons["기록"]

        XCTAssertTrue(boardTab.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.textFields["해당 날짜에 할 일 입력"]
                .waitForExistence(timeout: 10)
        )

        calendarTab.tap()
        XCTAssertTrue(app.buttons["이벤트 추가"].waitForExistence(timeout: 10))

        archiveTab.tap()
        XCTAssertTrue(app.buttons["기록 필터"].waitForExistence(timeout: 10))

        boardTab.tap()
        XCTAssertTrue(
            app.textFields["해당 날짜에 할 일 입력"]
                .waitForExistence(timeout: 10)
        )
    }
}
