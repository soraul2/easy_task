import UIKit
import XCTest

final class PlanBaseLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryTabNavigation() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-archive-mode", "activity"
        ]
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
        XCTAssertTrue(
            app.descendants(matching: .any)["activity-overview"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "최근 1년 최고")
            ).firstMatch.waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["최근 16주"].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "iPhone-Activity-16-Weeks")

        let statisticsSegment = app.segmentedControls.firstMatch.buttons["통계"]
        XCTAssertTrue(statisticsSegment.waitForExistence(timeout: 5))
        statisticsSegment.tap()
        XCTAssertTrue(
            app.staticTexts["선택 기간 작업 요약"].waitForExistence(timeout: 10)
        )

        boardTab.tap()
        XCTAssertTrue(
            app.textFields["해당 날짜에 할 일 입력"]
                .waitForExistence(timeout: 10)
        )
    }

    @MainActor
    func testIPadUsesNativeWindowInPortraitAndLandscape() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad 전용 전체 화면 회귀 테스트")
        }

        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-archive-mode", "activity"
        ]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        XCTAssertGreaterThan(window.frame.width, 700)
        XCTAssertGreaterThan(window.frame.height, 1_000)

        for title in ["칸반", "캘린더", "기록", "메모"] {
            XCTAssertTrue(
                app.buttons[title].firstMatch.waitForExistence(timeout: 5)
            )
        }
        addReferenceScreenshot(named: "iPad-Board-Portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscapeExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return element.frame.width > element.frame.height
            },
            object: window
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [landscapeExpectation], timeout: 10),
            .completed
        )
        XCTAssertGreaterThan(window.frame.width, 1_000)
        XCTAssertGreaterThan(window.frame.height, 700)

        app.buttons["캘린더"].firstMatch.tap()
        let addEventButton = app.buttons["이벤트 추가"]
        XCTAssertTrue(addEventButton.waitForExistence(timeout: 10))
        addEventButton.tap()
        let addEventNavigationBar = app.navigationBars["이벤트 추가"]
        XCTAssertTrue(addEventNavigationBar.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.textFields["event-title-field"].waitForExistence(timeout: 5)
        )
        addEventNavigationBar.buttons["취소"].tap()

        app.buttons["기록"].firstMatch.tap()
        XCTAssertTrue(app.buttons["기록 필터"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["activity-overview"]
                .waitForExistence(timeout: 10)
        )
        addReferenceScreenshot(named: "iPad-Activity-Landscape")

        app.buttons["메모"].firstMatch.tap()
        XCTAssertTrue(app.buttons["새 메모"].waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "iPad-Memo-Landscape")
    }

    @MainActor
    func testAccessibilityTextSizeKeepsBoardActionsReachable() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("iPhone 접근성 글자 크기 회귀 테스트")
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-accessibility-text-size",
            "--ui-testing-archive-mode", "activity"
        ]
        app.launch()

        XCTAssertTrue(
            app.scrollViews["board-accessibility-scroll"]
                .waitForExistence(timeout: 15)
        )
        XCTAssertTrue(
            app.staticTexts["board-date-title"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.buttons["board-status-filter-menu"].waitForExistence(timeout: 5)
        )

        let taskTitle = "오늘 처리할 작업 빠르게 추가해보기"
        let editButton = app.buttons["\(taskTitle) 작업 편집"]
        XCTAssertTrue(scrollToHittable(editButton, in: app))

        let statusMenu = app.buttons["\(taskTitle)-status-menu"]
        XCTAssertTrue(scrollToHittable(statusMenu, in: app))
        XCTAssertTrue(statusMenu.isHittable)
        addReferenceScreenshot(named: "iPhone-Board-Accessibility-Text")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        tabBar.buttons["캘린더"].tap()
        XCTAssertTrue(app.buttons["이벤트 추가"].waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "iPhone-Calendar-Accessibility-Text")

        tabBar.buttons["기록"].tap()
        XCTAssertTrue(app.buttons["기록 필터"].waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "iPhone-Archive-Accessibility-Text")

        tabBar.buttons["메모"].tap()
        XCTAssertTrue(app.buttons["새 메모"].waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "iPhone-Memo-Accessibility-Text")
    }

    @MainActor
    func testVerticalScrollStartingOnTaskStatusDoesNotChangeStatus() {
        let app = launchReminderFixtureApp()
        let taskTitle = "알림 완료 테스트: 알림 없음"
        let doingButton = app.buttons["\(taskTitle) 진행 중 상태"]

        XCTAssertTrue(scrollToHittable(doingButton, in: app))

        let start = doingButton.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        start.press(
            forDuration: 0.05,
            thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220))
        )

        let doingFilter = app.buttons["board-status-filter-doing"]
        XCTAssertTrue(doingFilter.waitForExistence(timeout: 5))
        doingFilter.tap()
        XCTAssertTrue(waitForSelected(doingFilter))
        XCTAssertFalse(app.staticTexts[taskTitle].waitForExistence(timeout: 1))

        let todoFilter = app.buttons["board-status-filter-todo"]
        todoFilter.tap()
        XCTAssertTrue(waitForSelected(todoFilter))

        let currentTodoButton = app.buttons["\(taskTitle) 할 일 상태"]
        XCTAssertTrue(scrollToHittable(currentTodoButton, in: app))
        XCTAssertTrue(waitForSelected(currentTodoButton))
    }

    @MainActor
    func testArchiveTasksStayCollapsedAndBoardNavigationWorks() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-archive-mode", "activity"
        ]
        app.launch()

        let archiveTab = app.tabBars.firstMatch.buttons["기록"]
        XCTAssertTrue(archiveTab.waitForExistence(timeout: 15))
        archiveTab.tap()

        let disclosure = app.buttons["그날 완료한 일 펼치기"].firstMatch
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

        let carryoverButton = app.buttons["carryover-button"]
        XCTAssertTrue(carryoverButton.waitForExistence(timeout: 15))
        XCTAssertTrue(carryoverButton.isHittable)

        let templateButton = app.buttons["template-library-button"]
        XCTAssertTrue(templateButton.waitForExistence(timeout: 5))
        XCTAssertTrue(templateButton.isHittable)

        XCTAssertFalse(app.buttons["테마 선택"].exists)

        let reviewButton = app.buttons["review-compose-button"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
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
        let carryoverButton = app.buttons["carryover-button"]
        XCTAssertTrue(carryoverButton.waitForExistence(timeout: 15))
        carryoverButton.tap()

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
    func testPastDoingTaskAppearsOnlyInCarryover() {
        let app = launchReminderFixtureApp()
        let taskTitle = "알림 완료 테스트: 이월 미래 알림"

        let doingFilter = app.buttons["board-status-filter-doing"]
        XCTAssertTrue(doingFilter.waitForExistence(timeout: 5))
        doingFilter.tap()
        XCTAssertTrue(waitForSelected(doingFilter))
        XCTAssertFalse(app.staticTexts[taskTitle].waitForExistence(timeout: 1))

        let carryoverButton = app.buttons["carryover-button"]
        XCTAssertTrue(carryoverButton.waitForExistence(timeout: 5))
        carryoverButton.tap()

        XCTAssertTrue(app.navigationBars["이월함"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[taskTitle].waitForExistence(timeout: 5))
    }

    @MainActor
    func testThemePickerExposesCurrentAppearanceAndEveryPreset() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let memoTab = app.buttons["메모"].firstMatch
        XCTAssertTrue(memoTab.waitForExistence(timeout: 15))
        memoTab.tap()

        let themeButton = app.buttons["테마 선택"].firstMatch
        XCTAssertTrue(themeButton.waitForExistence(timeout: 5))
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
    func testThemePickerCustomizesAndPersistsActivityEmoji() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let memoTab = app.buttons["메모"].firstMatch
        XCTAssertTrue(memoTab.waitForExistence(timeout: 15))
        memoTab.tap()
        app.buttons["테마 선택"].firstMatch.tap()

        let activitySection = app.buttons["활동 그래프"].firstMatch
        XCTAssertTrue(activitySection.waitForExistence(timeout: 5))
        activitySection.tap()

        let emojiStyle = app.buttons["이모지"].firstMatch
        XCTAssertTrue(emojiStyle.waitForExistence(timeout: 5))
        emojiStyle.tap()

        let emojiField = app.textFields["activity-heatmap-emoji-field"]
        XCTAssertTrue(emojiField.waitForExistence(timeout: 5))
        emojiField.tap()
        emojiField.typeText("🎯")
        XCTAssertEqual(emojiField.value as? String, "🎯")
        addReferenceScreenshot(named: "Theme activity emoji editor")

        app.navigationBars["테마"].buttons["완료"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["메모"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["메모"].firstMatch.tap()
        app.buttons["테마 선택"].firstMatch.tap()
        app.buttons["활동 그래프"].firstMatch.tap()
        app.buttons["이모지"].firstMatch.tap()

        let restoredEmojiField = app.textFields["activity-heatmap-emoji-field"]
        XCTAssertTrue(restoredEmojiField.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredEmojiField.value as? String, "🎯")

        app.buttons["기본값"].tap()
        app.buttons["테마 색상"].firstMatch.tap()
    }

    @MainActor
    func testCloudSyncStatusButtonAppearsOnlyInMemoToolbar() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["cloud-sync-status-button"].exists)

        let memoTab = tabBar.buttons["메모"]
        XCTAssertTrue(memoTab.waitForExistence(timeout: 5))
        memoTab.tap()

        let syncButton = app.buttons["cloud-sync-status-button"]
        XCTAssertTrue(syncButton.waitForExistence(timeout: 5))
        XCTAssertTrue(syncButton.isHittable)
    }

    @MainActor
    func testEventHistoryVisualReferenceScreens() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-event-history-fixtures",
            "--ui-testing-archive-mode", "statistics"
        ]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))

        let archiveTab = tabBar.buttons["기록"]
        archiveTab.tap()
        XCTAssertTrue(app.buttons["기록 필터"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["archive-overview"]
                .waitForExistence(timeout: 10)
        )
        addReferenceScreenshot(named: "event-history-archive")

        let boardTab = tabBar.buttons["칸반"]
        boardTab.tap()
        let reviewButton = app.buttons["review-compose-button"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 10))
        reviewButton.tap()
        XCTAssertTrue(app.navigationBars["회고 작성"].waitForExistence(timeout: 10))
        app.buttons["작업 요약"].tap()
        XCTAssertTrue(app.staticTexts["그날 실제 완료한 일"].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "event-history-review")
        app.buttons["취소"].tap()

        let calendarTab = tabBar.buttons["캘린더"]
        calendarTab.tap()
        let addEventButton = app.buttons["이벤트 추가"]
        XCTAssertTrue(addEventButton.waitForExistence(timeout: 10))
        addEventButton.tap()
        XCTAssertTrue(app.navigationBars["이벤트 추가"].waitForExistence(timeout: 10))
        let eventTitleField = app.textFields["event-title-field"]
        eventTitleField.tap()
        eventTitleField.typeText("공")
        XCTAssertTrue(
            recommendationButtons(in: app).firstMatch
                .waitForExistence(timeout: 5)
        )
        addReferenceScreenshot(named: "event-history-event-editor")
    }

    @MainActor
    func testEventHistoryDateBasisAndReviewAxes() {
        let app = launchEventHistoryFixtureApp(archiveMode: "statistics")
        let tabBar = app.tabBars.firstMatch

        tabBar.buttons["기록"].tap()
        let overview = app.descendants(matching: .any)["archive-overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        XCTAssertTrue(overview.label.contains("계획 작업"))
        XCTAssertTrue(overview.label.contains("완료 작업"))
        XCTAssertTrue(overview.label.contains("완료일 기준"))

        let disclosure = app.buttons["그날 완료한 일 펼치기"].firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10))
        disclosure.tap()
        XCTAssertTrue(app.staticTexts["UI 검증: 지연 완료"].waitForExistence(timeout: 5))
        let dateMeaning = app.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "계획일",
                "완료일"
            )
        ).firstMatch
        XCTAssertTrue(dateMeaning.waitForExistence(timeout: 5))

        app.buttons["기록 필터"].tap()
        XCTAssertTrue(app.navigationBars["검색 필터"].waitForExistence(timeout: 5))
        let dateBasisPicker = app.descendants(matching: .any)[
            "archive-date-basis-picker"
        ]
        XCTAssertTrue(dateBasisPicker.waitForExistence(timeout: 5))
        let plannedBasis = app.buttons["계획일 기준"].firstMatch
        XCTAssertTrue(plannedBasis.waitForExistence(timeout: 5))
        plannedBasis.tap()
        app.navigationBars["검색 필터"].buttons["완료"].tap()
        XCTAssertTrue(
            app.buttons["그날 계획한 일 펼치기"].firstMatch
                .waitForExistence(timeout: 10)
        )

        tabBar.buttons["칸반"].tap()
        let reviewButton = app.buttons["review-compose-button"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 10))
        reviewButton.tap()
        XCTAssertTrue(app.navigationBars["회고 작성"].waitForExistence(timeout: 10))
        app.buttons["작업 요약"].tap()
        XCTAssertTrue(app.staticTexts["그날 계획한 일"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["그날 실제 완료한 일"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UI 검증: 지연 완료"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCalendarRecommendationAndIndependentDuplicateFlow() {
        let app = launchEventHistoryFixtureApp()
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons["캘린더"].tap()

        let addEventButton = app.buttons["이벤트 추가"]
        XCTAssertTrue(addEventButton.waitForExistence(timeout: 10))
        addEventButton.tap()
        XCTAssertTrue(app.navigationBars["이벤트 추가"].waitForExistence(timeout: 5))

        let titleField = app.textFields["event-title-field"]
        titleField.tap()
        titleField.typeText("공")
        let recommendations = recommendationButtons(in: app)
        XCTAssertTrue(recommendations.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(recommendations.count, 5)
        recommendations.firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["이전 일정의 기간·색상·메모를 적용했어요"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(titleField.value as? String, "공")
        app.navigationBars["이벤트 추가"].buttons["취소"].tap()

        let todayCell = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                koreanDayDisplay(Date())
            )
        ).firstMatch
        XCTAssertTrue(todayCell.waitForExistence(timeout: 10))
        todayCell.tap()

        let eventMenu = app.buttons["공장 출하 일정 메뉴"].firstMatch
        XCTAssertTrue(eventMenu.waitForExistence(timeout: 10))
        eventMenu.tap()
        let duplicateAction = app.buttons["일정 복제"]
        XCTAssertTrue(duplicateAction.waitForExistence(timeout: 5))
        duplicateAction.tap()

        let duplicateNavigation = app.navigationBars["이벤트 복제"]
        XCTAssertTrue(duplicateNavigation.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["복제한 일정"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.textFields["event-title-field"].value as? String,
            "공장 출하"
        )
        duplicateNavigation.buttons["추가"].tap()
        let confirmation = app.alerts["이벤트를 추가할까요?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["추가"].tap()
        XCTAssertTrue(
            app.staticTexts["독립된 복제 일정을 추가했어요"]
                .waitForExistence(timeout: 8)
        )
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
    private func launchEventHistoryFixtureApp(
        archiveMode: String = "activity"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-event-history-fixtures",
            "--ui-testing-archive-mode", archiveMode
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func recommendationButtons(
        in app: XCUIApplication
    ) -> XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "최근 일정 적용."
            )
        )
    }

    private func koreanDayDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy.MM.dd E"
        return formatter.string(from: date)
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

    @MainActor
    private func addReferenceScreenshot(named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
