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
    func testReviewComposerIsDirectlyAccessibleFromBoard() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let reviewButton = app.buttons["review-compose-button"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 15))
        XCTAssertTrue(reviewButton.isHittable)
        reviewButton.tap()

        XCTAssertTrue(app.navigationBars["회고 작성"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["하루 회고"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["review-task-summary"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["이미지 추가"].waitForExistence(timeout: 5))

        app.buttons["취소"].tap()
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testReviewComposerConfirmsDiscardAndReportsSave() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let reviewButton = app.buttons["review-compose-button"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 15))
        reviewButton.tap()

        let titleField = app.textFields["review-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText("UI 회고")

        app.buttons["취소"].tap()
        XCTAssertTrue(app.staticTexts["변경사항을 버릴까요?"].waitForExistence(timeout: 5))
        app.buttons["계속 작성"].tap()

        let saveButton = app.buttons["review-save-button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let savedNotice = app.descendants(matching: .any)["board-status-notice"]
        XCTAssertTrue(savedNotice.waitForExistence(timeout: 5))
        XCTAssertTrue(savedNotice.label.contains("회고가 저장됐어요"))
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
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
        XCTAssertTrue(scrollToHittable(reorderButton, in: app))
        reorderButton.tap()
        let finishReorderButton = app.buttons["체크리스트 순서 편집 완료"]
        XCTAssertTrue(scrollToHittable(finishReorderButton, in: app))
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

        let doingStatusButton = app.buttons["\(taskTitle) 진행 중 상태"]
        XCTAssertTrue(scrollToHittable(doingStatusButton, in: app))
        doingStatusButton.tap()

        let statusPicker = app.segmentedControls.firstMatch
        XCTAssertTrue(statusPicker.buttons["진행 중"].waitForExistence(timeout: 5))
        statusPicker.buttons["진행 중"].tap()

        let checklistDisclosure = app.descendants(matching: .any)
            .matching(identifier: "checklist-progress")
            .firstMatch
        XCTAssertTrue(scrollToHittable(checklistDisclosure, in: app))
        XCTAssertTrue((checklistDisclosure.value as? String)?.contains("접힘") == true)
        checklistDisclosure.tap()

        let secondItemToggle = app.buttons["\(secondItemTitle) 체크리스트 항목"]
        XCTAssertTrue(secondItemToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(secondItemToggle.value as? String, "미완료")
        secondItemToggle.tap()
        XCTAssertEqual(secondItemToggle.value as? String, "완료")
        XCTAssertTrue((checklistDisclosure.value as? String)?.contains("2개 완료") == true)

        let currentDoingStatusButton = app.buttons["\(taskTitle) 진행 중 상태"]
        XCTAssertTrue(currentDoingStatusButton.waitForExistence(timeout: 5))
        XCTAssertTrue(currentDoingStatusButton.isSelected)

        checklistDisclosure.tap()
        XCTAssertFalse(secondItemToggle.waitForExistence(timeout: 1))
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
