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

    @MainActor
    func testChecklistDraftSaveCancelAndProgressChip() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let taskTitle = "Checklist UI Test"
        let firstItemTitle = "Pack charger"
        let secondItemTitle = "Confirm ticket"
        let cancelledItemTitle = "Do not save"
        let quickAddField = app.textFields["해당 날짜에 할 일 입력"]

        XCTAssertTrue(quickAddField.waitForExistence(timeout: 15))
        quickAddField.tap()
        quickAddField.typeText(taskTitle)
        app.buttons["작업 추가"].tap()

        let editButton = app.buttons["\(taskTitle) 작업 편집"]
        XCTAssertTrue(scrollToHittable(editButton, in: app))
        editButton.tap()

        let newChecklistField = app.textFields["새 체크리스트 항목"]
        XCTAssertTrue(scrollToHittable(newChecklistField, in: app))
        newChecklistField.tap()
        newChecklistField.typeText("\(firstItemTitle)\n")

        XCTAssertTrue(app.buttons["\(firstItemTitle) 완료 상태"].waitForExistence(timeout: 5))
        newChecklistField.tap()
        newChecklistField.typeText(secondItemTitle)
        app.buttons["체크리스트 항목 추가"].tap()

        let reorderButton = app.buttons["체크리스트 순서 편집"]
        XCTAssertTrue(reorderButton.waitForExistence(timeout: 5))
        reorderButton.tap()
        let finishReorderButton = app.buttons["체크리스트 순서 편집 완료"]
        XCTAssertTrue(finishReorderButton.waitForExistence(timeout: 5))
        finishReorderButton.tap()

        app.buttons["\(firstItemTitle) 완료 상태"].tap()
        app.buttons["저장"].tap()

        let progressChip = app.descendants(matching: .any)
            .matching(identifier: "checklist-progress")
            .firstMatch
        XCTAssertTrue(scrollToHittable(progressChip, in: app))
        XCTAssertEqual(progressChip.value as? String, "1개 완료, 전체 2개")

        XCTAssertTrue(scrollToHittable(editButton, in: app))
        editButton.tap()
        XCTAssertTrue(scrollToHittable(newChecklistField, in: app))
        newChecklistField.tap()
        newChecklistField.typeText(cancelledItemTitle)
        app.buttons["체크리스트 항목 추가"].tap()
        app.buttons["취소"].tap()

        XCTAssertTrue(scrollToHittable(progressChip, in: app))
        XCTAssertEqual(progressChip.value as? String, "1개 완료, 전체 2개")
    }

    @MainActor
    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        attempts: Int = 8
    ) -> Bool {
        for _ in 0..<attempts {
            if element.waitForExistence(timeout: 1), element.isHittable {
                return true
            }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }
}
