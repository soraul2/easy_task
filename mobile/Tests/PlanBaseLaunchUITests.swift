import XCTest

final class PlanBaseLaunchUITests: XCTestCase {
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
        for identifier in [
            "board-status-filter-todo",
            "board-status-filter-doing",
            "board-status-filter-done"
        ] {
            let statusFilter = app.buttons[identifier]
            XCTAssertTrue(statusFilter.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(statusFilter.frame.height, 44)
        }
        for identifier in [
            "board-status-filter-doing",
            "board-status-filter-done",
            "board-status-filter-todo"
        ] {
            let statusFilter = app.buttons[identifier]
            statusFilter.tap()
            XCTAssertTrue(waitForSelected(statusFilter))
        }

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
    func testArchiveTasksStayCollapsedAndBoardNavigationWorks() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let archiveTab = app.tabBars.firstMatch.buttons["기록"]
        XCTAssertTrue(archiveTab.waitForExistence(timeout: 15))
        archiveTab.tap()

        let disclosure = app.buttons["그날 한 일 펼치기"].firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10))
        let completedTaskTitle = app.staticTexts["완료 영역 접힘 확인"]
        XCTAssertFalse(completedTaskTitle.exists)

        disclosure.tap()
        XCTAssertTrue(completedTaskTitle.waitForExistence(timeout: 5))

        let boardButton = app.buttons.matching(
            NSPredicate(format: "label ENDSWITH %@", "칸반보드 열기")
        ).firstMatch
        XCTAssertTrue(boardButton.waitForExistence(timeout: 5))
        boardButton.tap()
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
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board"]
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

        let editButton = app.descendants(matching: .any)["\(taskTitle) 작업 편집"]
        XCTAssertTrue(scrollToHittable(editButton, in: app))
        editButton.tap()

        let newChecklistField = app.textFields["새 체크리스트 항목"]
        XCTAssertTrue(scrollToHittable(newChecklistField, in: app))
        newChecklistField.tap()
        newChecklistField.typeText("\(firstItemTitle)\n")

        XCTAssertTrue(app.buttons["\(firstItemTitle) 완료 상태"].waitForExistence(timeout: 5))
        newChecklistField.tap()
        newChecklistField.typeText(secondItemTitle)
        let addChecklistButton = app.buttons["체크리스트 항목 추가"]
        addChecklistButton.tap()
        let secondItemButton = app.buttons["\(secondItemTitle) 완료 상태"]
        if !secondItemButton.waitForExistence(timeout: 2) {
            addChecklistButton.tap()
        }
        XCTAssertTrue(secondItemButton.waitForExistence(timeout: 5))
        app.swipeDown()

        let reorderButton = app.buttons["체크리스트 순서 편집"]
        XCTAssertTrue(scrollToHittable(reorderButton, in: app))
        reorderButton.tap()
        let finishReorderButton = app.buttons["체크리스트 순서 편집 완료"]
        XCTAssertTrue(scrollToHittable(finishReorderButton, in: app))
        finishReorderButton.tap()

        app.buttons["\(firstItemTitle) 완료 상태"].tap()
        app.buttons["저장"].tap()

        let progressChip = app.descendants(matching: .any)
            .matching(identifier: "\(taskTitle)-checklist-progress")
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

        let doingFilter = app.buttons["board-status-filter-doing"]
        XCTAssertTrue(doingFilter.waitForExistence(timeout: 5))
        doingFilter.tap()
        XCTAssertTrue(waitForSelected(doingFilter))

        let checklistDisclosure = app.buttons["\(taskTitle)-checklist-progress"]
        let boardTaskList = app.descendants(matching: .any)["board-task-list"]
        XCTAssertTrue(boardTaskList.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(
            checklistDisclosure,
            in: boardTaskList,
            attempts: 20,
            velocity: .fast
        ))
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
        XCTAssertTrue(waitForSelected(currentDoingStatusButton))

        checklistDisclosure.tap()
        XCTAssertFalse(secondItemToggle.waitForExistence(timeout: 1))
    }

    @MainActor
    func testReminderCompletionSkipsAlertForNoneAndPast() {
        let app = launchReminderFixtureApp()
        let noReminderTitle = "알림 완료 테스트: 알림 없음"
        let pastReminderTitle = "알림 완료 테스트: 지난 알림"

        let noReminderDone = app.buttons["\(noReminderTitle) 완료 상태"]
        XCTAssertTrue(scrollToHittable(noReminderDone, in: app))
        noReminderDone.tap()
        XCTAssertFalse(app.alerts["예정된 알림이 있습니다"].waitForExistence(timeout: 1))

        let pastReminderDone = app.buttons["\(pastReminderTitle) 완료 상태"]
        XCTAssertTrue(scrollToHittable(pastReminderDone, in: app))
        pastReminderDone.tap()
        XCTAssertFalse(app.alerts["예정된 알림이 있습니다"].waitForExistence(timeout: 1))

        let doneFilter = app.buttons["board-status-filter-done"]
        XCTAssertTrue(doneFilter.waitForExistence(timeout: 5))
        doneFilter.tap()
        XCTAssertTrue(waitForSelected(doneFilter))
        let record = app.descendants(matching: .any)["\(pastReminderTitle) 알림 기록"]
        XCTAssertTrue(scrollToHittable(record, in: app))
        XCTAssertTrue(record.label.contains("설정했던 알림"))
    }

    @MainActor
    func testFutureReminderCompletionCanCancelAndThenPreservesRecord() {
        let app = launchReminderFixtureApp()
        let taskTitle = "알림 완료 테스트: 미래 알림"
        let doneButton = app.buttons["\(taskTitle) 완료 상태"]
        XCTAssertTrue(scrollToHittable(doneButton, in: app))
        doneButton.tap()

        let alert = app.alerts["예정된 알림이 있습니다"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["완료하기"].exists)
        XCTAssertTrue(alert.buttons["취소"].exists)
        alert.buttons["취소"].tap()
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))

        doneButton.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["완료하기"].tap()

        let doneFilter = app.buttons["board-status-filter-done"]
        XCTAssertTrue(doneFilter.waitForExistence(timeout: 5))
        doneFilter.tap()
        XCTAssertTrue(waitForSelected(doneFilter))
        let record = app.descendants(matching: .any)["\(taskTitle) 알림 기록"]
        XCTAssertTrue(scrollToHittable(record, in: app))
        XCTAssertTrue(record.label.contains("설정했던 알림"))
    }

    @MainActor
    func testCarryoverCompletionReportsFutureReminderCount() {
        let app = launchReminderFixtureApp()
        let boardMenu = app.buttons["보드 작업"]
        XCTAssertTrue(boardMenu.waitForExistence(timeout: 15))
        boardMenu.tap()
        app.buttons["이월함"].tap()

        let completeAll = app.buttons["원래 날짜에 모두 완료"]
        XCTAssertTrue(completeAll.waitForExistence(timeout: 5))
        completeAll.tap()

        let alert = app.alerts["예정된 알림이 있습니다"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "1개의 작업")
        ).firstMatch.exists)
        alert.buttons["취소"].tap()
    }

    @MainActor
    func testThemePickerExposesCurrentAppearanceAndEveryPreset() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let themeButton = app.buttons["테마 선택"].firstMatch
        XCTAssertTrue(themeButton.waitForExistence(timeout: 15))
        themeButton.tap()

        XCTAssertTrue(app.navigationBars["테마"].waitForExistence(timeout: 5))
        let appearanceDescription = app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@", "모드 미리보기")
        ).firstMatch
        XCTAssertTrue(appearanceDescription.exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Theme picker current appearance"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let themeScrollView = app.scrollViews.firstMatch
        XCTAssertTrue(themeScrollView.exists)
        let presetNames = [
            "Apple System",
            "Maroon Ember",
            "Navy Blush",
            "Plum Night",
            "Rose Lilac",
            "Forest Cream",
            "Teal Paper",
            "Solar Berry"
        ]
        for presetName in presetNames {
            XCTAssertTrue(
                scrollToHittable(
                    app.buttons["\(presetName) 테마"],
                    in: themeScrollView,
                    attempts: 10
                )
            )
        }
    }

    @MainActor
    private func launchReminderFixtureApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reminder-fixtures"]
        app.launch()
        XCTAssertTrue(
            app.textFields["해당 날짜에 할 일 입력"]
                .waitForExistence(timeout: 15)
        )
        return app
    }

    @MainActor
    private func scrollToHittable(
        _ element: XCUIElement,
        in scrollable: XCUIElement,
        attempts: Int = 14,
        velocity: XCUIGestureVelocity = .slow
    ) -> Bool {
        for _ in 0..<attempts {
            if element.waitForExistence(timeout: 0.5), element.isHittable {
                return true
            }
            scrollable.swipeUp(velocity: velocity)
        }
        for _ in 0..<(attempts * 2) {
            if element.waitForExistence(timeout: 0.5), element.isHittable {
                return true
            }
            scrollable.swipeDown(velocity: velocity)
        }
        return element.exists && element.isHittable
    }

    @MainActor
    private func waitForSelected(
        _ element: XCUIElement,
        timeout: TimeInterval = 2
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            let value = element.value as? String
            return value == "선택됨" || value == "현재 상태"
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
