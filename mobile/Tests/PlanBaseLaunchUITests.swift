import UIKit
import XCTest

final class PlanBaseLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchDiscoveryApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let theme = additionalArguments.contains { $0.hasPrefix("--ui-testing-theme=") }
            ? [] : ["--ui-testing-theme=appleSystem"]
        app.launchArguments = ["--ui-testing", "--ui-testing-discovery-fixtures",
                               "--ui-testing-archive-collapsed",
                               "--ui-testing-memo-store=\(UUID().uuidString)"] + theme + additionalArguments
        app.launch()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["carryover-button"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    func testDiscoveryCarryoverAcknowledgementPersistsWithoutClearingTotal() {
        let app = launchDiscoveryApp()
        let inbox = app.buttons["carryover-button"]
        XCTAssertEqual(inbox.label, "이월함, 전체 4개, 새 작업 2개")
        addReferenceScreenshot(named: "discovery-carryover-new-badge")
        inbox.tap()
        let summary = app.staticTexts["carryover-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "전체 4개 · 새 작업 2개")
        addReferenceScreenshot(named: "discovery-carryover-new-sections")
        app.navigationBars["이월함"].buttons["닫기"].tap()
        XCTAssertEqual(inbox.label, "이월함, 전체 4개, 새 작업 0개")
        inbox.tap()
        XCTAssertEqual(summary.label, "전체 4개 · 새 작업 0개")
        let move = app.buttons["읽던 책 이어 읽기, 오늘로 이월"]
        XCTAssertTrue(scrollToHittable(move, in: app))
        move.tap()
        XCTAssertEqual(summary.label, "전체 3개 · 새 작업 0개")
        app.navigationBars["이월함"].buttons["닫기"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(inbox.waitForExistence(timeout: 15))
        XCTAssertEqual(inbox.label, "이월함, 전체 3개, 새 작업 0개")
    }

    @MainActor
    func testDiscoveryReviewReadActivityAndIndependentSearch() {
        let app = launchDiscoveryApp()
        app.buttons["기록"].firstMatch.tap()
        let picker = app.segmentedControls["archive-pane-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.buttons["회고"].tap()
        let today = localDayKey(Date())
        let open = app.buttons["review-open-\(today)"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["archive-overview-disclosure"].exists)
        addReferenceScreenshot(named: "discovery-review-list")
        open.tap()
        let activities = app.buttons["review-open-activity"]
        XCTAssertTrue(activities.waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "discovery-review-reader")
        activities.tap()
        XCTAssertTrue(app.navigationBars["하루 기록"].waitForExistence(timeout: 10))
        app.navigationBars["하루 기록"].buttons["닫기"].tap()
        XCTAssertTrue(activities.waitForExistence(timeout: 5))
        // Compact navigation exposes a back button; on iPad the list stays alongside the reader.
        if !picker.isHittable {
            let back = app.navigationBars["회고"].buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
        }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("작은 진전")
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        picker.buttons["활동 기록"].tap()
        XCTAssertTrue(app.buttons["archive-overview-disclosure"].waitForExistence(timeout: 10))
        XCTAssertNotEqual(app.searchFields.firstMatch.value as? String, "작은 진전")
        picker.buttons["회고"].tap()
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "작은 진전")
    }

    @MainActor
    func testDiscoveryReviewPhotoOnly() {
        let app = launchDiscoveryApp()
        app.buttons["기록"].firstMatch.tap()
        let picker = app.segmentedControls["archive-pane-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.buttons["회고"].tap()
        let yesterday = localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let photoOnly = app.buttons["review-open-\(yesterday)"]
        XCTAssertTrue(scrollToHittable(photoOnly, in: app, attempts: 2))
        photoOnly.tap()
        XCTAssertTrue(app.staticTexts["사진 1장"].firstMatch.waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "discovery-photo-only-review")
    }

    @MainActor
    func testDiscoveryLargeTextCarryoverAndReviewControls() {
        let app = launchDiscoveryApp(additionalArguments: ["--ui-testing-accessibility-text-size"])
        app.buttons["carryover-button"].tap()
        XCTAssertTrue(app.staticTexts["carryover-summary"].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "discovery-carryover-largest-text")
        app.navigationBars["이월함"].buttons["닫기"].tap()
        app.buttons["기록"].firstMatch.tap()
        let picker = app.buttons["archive-pane-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        app.buttons.matching(identifier: "회고").firstMatch.tap()
        let open = app.buttons["review-open-\(localDayKey(Date()))"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "discovery-review-largest-text")
    }

    @MainActor
    func testDiscoveryLiveCardTodoBrowseStartCompleteAndEnd() throws {
        let app = launchDiscoveryApp(additionalArguments: ["--ui-testing-live-card-audit"])
        let audit = app.staticTexts["live-card-audit"]
        XCTAssertTrue(audit.waitForExistence(timeout: 10))
        let created = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "cards=1|"), object: audit)
        XCTAssertEqual(XCTWaiter.wait(for: [created], timeout: 10), .completed)
        let initialActivity = audit.label.components(separatedBy: "|")[1]
        XCTAssertTrue(audit.label.contains("status=todo"))
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
        let allow = home.buttons["허용"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        let start = home.buttons["이 작업 시작"]
        let complete = home.buttons["이 작업 완료"]
        let browse = home.buttons["표시할 작업 변경"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(complete.exists)
        XCTAssertTrue(home.staticTexts["할 일"].exists)
        addReferenceScreenshot(named: "discovery-live-todo-initial")
        browse.tap()
        XCTAssertTrue(home.staticTexts["오늘 산책하기"].waitForExistence(timeout: 5))
        XCTAssertTrue(start.exists)
        start.tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        XCTAssertFalse(start.exists)
        addReferenceScreenshot(named: "discovery-live-started")
        browse.tap()
        XCTAssertTrue(home.staticTexts["오늘 문서 초안 작성"].waitForExistence(timeout: 5))
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()
        XCTAssertTrue(home.staticTexts["오늘 산책하기"].waitForExistence(timeout: 5))
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertFalse(browse.exists)
        addReferenceScreenshot(named: "discovery-live-last-doing")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(audit.waitForExistence(timeout: 5))
        XCTAssertTrue(audit.label.contains(initialActivity), "상태 전환은 같은 Activity를 갱신해야 합니다")
        XCUIDevice.shared.press(.home)
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()
        XCTAssertTrue(complete.waitForNonExistence(timeout: 10))
        XCTAssertFalse(start.exists)
        addReferenceScreenshot(named: "discovery-live-all-finished")
        XCUIDevice.shared.press(.home)
        app.activate()
        let ended = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "cards=0|"), object: audit)
        XCTAssertEqual(XCTWaiter.wait(for: [ended], timeout: 10), .completed)
    }

    @MainActor
    func testDiscoveryReviewEditAndAdaptiveNavigation() throws {
        let app = launchDiscoveryApp(additionalArguments: ["--ui-testing-adaptive-layout", "--ui-testing-theme=charcoalRose"])
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["기록"].firstMatch.tap()
        let picker = app.segmentedControls["archive-pane-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.buttons["회고"].tap()
        let today = localDayKey(Date())
        let open = app.buttons["review-open-\(today)"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let edit = app.buttons["회고 수정"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "discovery-review-wide-dark")
        if UIDevice.current.userInterfaceIdiom == .pad {
            app.buttons["layout-test-compact"].tap()
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            XCTAssertTrue(edit.isHittable)
            addReferenceScreenshot(named: "discovery-review-narrow-dark")
        }
        edit.tap()
        let title = app.textFields["review-title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(" 수정 완료")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue((title.value as? String)?.contains("수정 완료") == true)
        app.buttons["review-save-button"].tap()
        XCTAssertTrue(app.staticTexts["작은 진전을 남긴 하루 수정 완료"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["맑음 · 차분함"].firstMatch.exists)
        addReferenceScreenshot(named: "discovery-review-edited-metadata-retained")
    }

    @MainActor
    func testDiscoveryReviewScrollSurvivesPaneSwitch() {
        let app = launchDiscoveryApp()
        app.buttons["기록"].firstMatch.tap()
        let picker = app.segmentedControls["archive-pane-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.buttons["회고"].tap()
        let day = localDayKey(Calendar.current.date(byAdding: .day, value: -25, to: Date())!)
        let target = app.buttons["review-open-\(day)"]
        XCTAssertTrue(scrollToHittable(target, in: app.scrollViews.firstMatch, velocity: .fast))
        let previousY = target.frame.midY
        addReferenceScreenshot(named: "discovery-review-scroll-before-switch")
        picker.buttons["활동 기록"].tap()
        XCTAssertTrue(app.buttons["archive-overview-disclosure"].waitForExistence(timeout: 10))
        picker.buttons["회고"].tap()
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        XCTAssertTrue(target.isHittable, "탭을 돌아와도 읽던 회고가 보여야 합니다")
        XCTAssertLessThan(abs(target.frame.midY - previousY), 250)
        addReferenceScreenshot(named: "discovery-review-scroll-restored")
    }

    @MainActor
    func testAdaptiveVoiceOverCanNavigateAndActivateMemo() throws {
        guard ProcessInfo.processInfo.environment["PLANBASE_VOICEOVER_UI_AUDIT"] == "1" else {
            throw XCTSkip("VoiceOver 검사는 지원 런타임에서 명시적으로 실행합니다")
        }
        #if compiler(>=6.4)
        guard #available(iOS 27, *) else {
            throw XCTSkip("VoiceOver 제어에는 iOS 27 XCTest 런타임이 필요합니다")
        }
        let voiceOver = XCUIDevice.shared.voiceOverService
        let wasEnabled = voiceOver.isEnabled
        addTeardownBlock {
            await MainActor.run {
                if !wasEnabled { try? XCUIDevice.shared.voiceOverService.disable() }
            }
        }
        // Start with a fresh automation connection before the app launches.
        // The beta runtime can report enabled while its previous connection
        // rejects commands in both the tested app and system Settings.
        if wasEnabled { try voiceOver.disable() }
        try voiceOver.enable()
        XCTAssertTrue(voiceOver.isEnabled)
        let app = launchKanbanFlowApp()
        var speech: [String] = []
        func attachSpeech() {
            let attachment = XCTAttachment(string: speech.joined(separator: "\n"))
            attachment.name = "adaptive-voiceover-navigation"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        func focus(_ label: String, role: String? = nil, backwards: Bool = false) throws {
            func matches(_ utterance: String) -> Bool {
                let roleMatches = role.map {
                    let pattern = "(?:^|\\s)" + NSRegularExpression.escapedPattern(for: $0) + "(?:\\s|$)"
                    return utterance.range(of: pattern, options: .regularExpression) != nil
                } ?? true
                return utterance.contains(label) && roleMatches
            }
            if let current = try? voiceOver.currentSpeech().utterance {
                speech.append(current)
                if matches(current) {
                    attachSpeech()
                    return
                }
            }
            var previousUtterance: String?
            var repeatedUtterances = 0
            var direction = backwards
            var hasReversed = false
            for _ in 0..<80 {
                let utterance: String
                do {
                    utterance = try (direction ? voiceOver.moveBackward() : voiceOver.moveForward()).utterance
                } catch {
                    // Compare with a system app before attributing an
                    // automation transport failure to PlanBase's labels.
                    var diagnostic = "PlanBase: \(error)\n\(voiceOver.debugDescription)"
                    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
                    settings.launch()
                    do {
                        diagnostic += "\nSettings: \(try voiceOver.moveForward().utterance)"
                    } catch {
                        diagnostic += "\nSettings: \(error)"
                    }
                    let attachment = XCTAttachment(string: diagnostic)
                    attachment.name = "voiceover-system-app-comparison"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    app.activate()
                    throw error
                }
                speech.append(utterance)
                if matches(utterance) {
                    attachSpeech()
                    return
                }
                repeatedUtterances = utterance == previousUtterance ? repeatedUtterances + 1 : 0
                previousUtterance = utterance
                // A navigation change may focus the first control rather than
                // retain the tab. Reverse once at the boundary; never spin there.
                if repeatedUtterances >= 2 {
                    guard !hasReversed else { break }
                    direction.toggle()
                    hasReversed = true
                    previousUtterance = nil
                    repeatedUtterances = 0
                }
            }
            attachSpeech()
            XCTFail("VoiceOver로 \(label)에 도달하지 못했습니다")
        }
        try focus("해당 날짜에 할 일 입력", role: "텍스트 필드")
        try focus("캘린더", role: "탭 총")
        // Touch the element VoiceOver just focused. An application-centred
        // gesture can move focus to unrelated content before activation.
        app.tabBars.buttons["캘린더"].doubleTap()
        XCTAssertTrue(app.buttons["일정 추가"].waitForExistence(timeout: 10))
        try focus("일정 추가", role: "버튼", backwards: true)
        try focus("기록", role: "탭 총")
        app.tabBars.buttons["기록"].doubleTap()
        XCTAssertTrue(app.buttons["날짜로 기록 찾기"].waitForExistence(timeout: 10))
        try focus("날짜로 기록 찾기", role: "버튼", backwards: true)
        try focus("메모", role: "탭 총")
        app.tabBars.buttons["메모"].doubleTap()
        XCTAssertTrue(app.buttons["새 메모"].waitForExistence(timeout: 10))
        try focus("새 메모", role: "버튼", backwards: true)
        app.buttons["새 메모"].doubleTap()
        try focus("글 메모", role: "버튼")
        app.buttons["memo-create-text"].doubleTap()
        XCTAssertTrue(app.textViews["메모 내용"].waitForExistence(timeout: 10))
        let keyboardIntroduction = app.buttons["Continue"]
        if keyboardIntroduction.waitForExistence(timeout: 2) {
            try focus("Continue", role: "버튼")
            keyboardIntroduction.doubleTap()
            XCTAssertTrue(keyboardIntroduction.waitForNonExistence(timeout: 5))
        }
        try focus("메모 내용", role: "텍스트 필드", backwards: true)
        addReferenceScreenshot(named: "adaptive-voiceover-memo")
        #else
        throw XCTSkip("VoiceOver 제어에는 Xcode 27의 XCTest API가 필요합니다")
        #endif
    }

    @MainActor
    func testAdaptiveBoardKeepsScrolledTaskAndOpenDetailDraft() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("목록 열 전환의 스크롤 위치는 iPad에서 확인합니다")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp(additionalArguments: ["--ui-testing-adaptive-layout"])
        let quickEntry = app.textFields["해당 날짜에 할 일 입력"]
        for index in 1...10 {
            quickEntry.tap()
            quickEntry.typeText("스크롤 작업 \(index)")
            app.buttons["작업 추가"].tap()
            // Later cards are outside the lazy list's visible region. Verify
            // the submitted input clears, then scroll to the target below.
            XCTAssertEqual(quickEntry.value as? String, "해당 날짜에 할 일 입력")
        }
        let scroll = app.scrollViews["board-accessibility-scroll"]
        let edit = app.buttons["스크롤 작업 8 작업 편집"]
        XCTAssertTrue(scrollToHittable(edit, in: scroll))
        let wideY = edit.frame.midY
        app.buttons["layout-test-compact"].tap()
        XCTAssertTrue(edit.isHittable, "열 전환 후 사용자가 보던 작업을 계속 보여줘야 합니다")
        XCTAssertLessThan(abs(edit.frame.midY - wideY), 200)
        app.buttons["layout-test-expanded"].tap()
        XCTAssertTrue(edit.isHittable)
        addReferenceScreenshot(named: "adaptive-board-restored-scroll")
        edit.tap()
        let title = app.textFields["task-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "스크롤 작업 8")
        let note = app.textFields["task-detail-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("회전하면서 작성한 상세 초안")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(title.value as? String, "스크롤 작업 8")
        XCTAssertEqual(note.value as? String, "회전하면서 작성한 상세 초안")
        XCTAssertEqual(title.label, "제목")
        XCTAssertEqual(note.label, "메모")
        note.typeText(" 이어쓰기")
        XCTAssertEqual(note.value as? String, "회전하면서 작성한 상세 초안 이어쓰기")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(note.value as? String, "회전하면서 작성한 상세 초안 이어쓰기")
        app.buttons["task-detail-keyboard-dismiss"].tap()
        app.navigationBars["작업 상세"].buttons["저장"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(edit.isHittable)
        XCTAssertEqual(app.buttons.matching(identifier: "스크롤 작업 8 작업 편집").count, 1)
        edit.tap()
        XCTAssertEqual(note.value as? String, "회전하면서 작성한 상세 초안 이어쓰기")
        XCTAssertEqual(note.label, "메모")
        addReferenceScreenshot(named: "adaptive-task-detail-restored-draft")
    }

    @MainActor
    func testAdaptiveLargestTextCalendarAndArchiveRemainUsable() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("가장 큰 글자의 좁은 화면 검사는 iPhone에서 확인합니다")
        }
        XCUIDevice.shared.orientation = .portrait
        for theme in ["appleSystem", "charcoalRose"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-testing", "--ui-testing-accessibility-text-size",
                "--ui-testing-archive-collapsed", "--ui-testing-theme=\(theme)",
            ]
            app.launch()
            app.terminate()
            app.launch()
            let dateTitle = app.descendants(matching: .any)["board-date-title"].firstMatch
            XCTAssertTrue(dateTitle.waitForExistence(timeout: 15))
            XCTAssertTrue(isHorizontallyContained(dateTitle, in: app.windows.firstMatch))
            XCTAssertTrue(app.buttons["board-status-filter-menu"].isHittable)
            addReferenceScreenshot(named: "adaptive-AX5-\(theme)-board")

            tapRootDestination("캘린더", in: app)
            let month = app.staticTexts["calendar-month-title"]
            XCTAssertTrue(month.waitForExistence(timeout: 5))
            XCTAssertTrue(isHorizontallyContained(month, in: app.windows.firstMatch))
            let originalMonth = month.label
            let next = app.buttons["다음 달"]
            let previous = app.buttons["이전 달"]
            XCTAssertTrue(next.isHittable && previous.isHittable)
            next.tap()
            XCTAssertNotEqual(month.label, originalMonth)
            previous.tap()
            XCTAssertEqual(month.label, originalMonth)
            addReferenceScreenshot(named: "adaptive-AX5-\(theme)-calendar-month")
            let today = app.buttons.matching(NSPredicate(
                format: "label BEGINSWITH %@", koreanDayDisplay(Date())
            )).firstMatch
            XCTAssertTrue(today.waitForExistence(timeout: 5))
            XCTAssertTrue(today.isHittable)
            today.tap()
            XCTAssertTrue(app.buttons["일정 추가"].firstMatch.waitForExistence(timeout: 5))
            addReferenceScreenshot(named: "adaptive-AX5-\(theme)-calendar-day")

            tapRootDestination("기록", in: app)
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            XCTAssertTrue(isHorizontallyContained(search, in: app.windows.firstMatch))
            addReferenceScreenshot(named: "adaptive-AX5-\(theme)-archive-browse")
            // Compact iPhone search temporarily replaces navigation actions
            // with its system close button. Set the filter before entering it.
            app.buttons["기록 필터"].tap()
            let mode = app.buttons["archive-content-mode-picker"]
            XCTAssertTrue(scrollToHittable(mode, in: app.collectionViews.firstMatch))
            mode.tap()
            app.buttons["완료 작업"].tap()
            app.navigationBars["검색 필터"].buttons["완료"].tap()
            XCTAssertTrue(app.buttons["적용된 기록 필터 변경"].isHittable)
            search.tap()
            search.typeText("영어\n")
            XCTAssertEqual(search.value as? String, "영어")
            addReferenceScreenshot(named: "adaptive-AX5-\(theme)-archive-search")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "adaptive-AX5-\(theme)-archive-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let filters = app.scrollViews["적용된 기록 필터"]
            filters.swipeLeft()
            let clearFilters = app.buttons["모두 지우기"]
            XCTAssertTrue(isHorizontallyContained(clearFilters, in: app.windows.firstMatch))
            XCTAssertTrue(clearFilters.isHittable)
            addReferenceScreenshot(named: "adaptive-AX5-\(theme)-archive-filter-actions")
            clearFilters.tap()
            XCTAssertEqual(search.value as? String, "영어")
            XCTAssertTrue(filters.waitForNonExistence(timeout: 5))
        }
    }

    @MainActor
    func testAdaptiveBoardRetainsQuickEntryAcrossRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp()
        let input = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("회전 중 작성한 작업")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(input.value as? String, "회전 중 작성한 작업")
        app.buttons["작업 추가"].tap()
        let edit = app.buttons["회전 중 작성한 작업 작업 편집"]
        XCTAssertTrue(scrollToHittable(edit, in: app.scrollViews["board-accessibility-scroll"]))
        if UIDevice.current.userInterfaceIdiom == .pad {
            for status in ["todo", "doing", "done"] {
                XCTAssertTrue(app.descendants(matching: .any)["board-column-\(status)"].firstMatch.exists)
            }
        }
        addReferenceScreenshot(named: "adaptive-board-wide")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(scrollToHittable(edit, in: app.scrollViews["board-accessibility-scroll"]))
        XCTAssertEqual(app.buttons.matching(identifier: "회전 중 작성한 작업 작업 편집").count, 1)
        addReferenceScreenshot(named: "adaptive-board-portrait")
    }

    @MainActor
    func testAdaptiveBoardPreservesStatusAcrossColumnChanges() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("세 열과 단일 열 전환은 넓은 시뮬레이터에서 확인")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp(additionalArguments: ["--ui-testing-adaptive-layout"])
        let title = "넓은 보드에서 시작한 작업"
        addKanbanFlowTask(title, in: app)
        app.buttons["\(title) 진행 중 상태"].tap()
        let destination = app.buttons["board-status-destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        app.buttons["layout-test-compact"].tap()
        XCTAssertTrue(waitForSelected(app.buttons["board-status-filter-doing"]))
        let edit = app.buttons["\(title) 작업 편집"]
        XCTAssertTrue(scrollToHittable(edit, in: app.scrollViews["board-accessibility-scroll"]))
        XCTAssertEqual(app.buttons.matching(identifier: "\(title) 작업 편집").count, 1)
        app.buttons["layout-test-expanded"].tap()
        for status in ["todo", "doing", "done"] {
            XCTAssertTrue(app.descendants(matching: .any)["board-column-\(status)"].firstMatch.exists)
        }
        let done = app.buttons["\(title) 완료 상태"]
        XCTAssertTrue(scrollToHittable(done, in: app.scrollViews["board-accessibility-scroll"]))
        done.tap()
        let undo = app.buttons["board-completion-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        app.buttons["layout-test-compact"].tap()
        undo.tap()
        XCTAssertTrue(waitForSelected(app.buttons["board-status-filter-doing"]))
        XCTAssertTrue(scrollToHittable(edit, in: app.scrollViews["board-accessibility-scroll"]))
        addReferenceScreenshot(named: "adaptive-board-restored-status")
    }

    @MainActor
    func testAdaptiveBoardUsesSingleColumnForAccessibilityText() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("넓은 화면의 큰 글자 배치는 iPad에서 확인")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp(additionalArguments: ["--ui-testing-accessibility-text-size"])
        let statusMenu = app.buttons["board-status-filter-menu"]
        XCTAssertTrue(statusMenu.waitForExistence(timeout: 10))
        XCTAssertTrue(isHorizontallyContained(statusMenu, in: app.windows.firstMatch))
        XCTAssertFalse(app.descendants(matching: .any)["board-column-todo"].firstMatch.exists)
        let title = "큰 글자에서도 읽을 수 있는 작업"
        addKanbanFlowTask(title, in: app)
        let edit = app.buttons["\(title) 작업 편집"]
        XCTAssertTrue(scrollToHittable(edit, in: app.scrollViews["board-accessibility-scroll"]))
        XCTAssertTrue(isHorizontallyContained(edit, in: app.windows.firstMatch))
        addReferenceScreenshot(named: "adaptive-board-wide-accessibility-text")
    }

    @MainActor
    func testAdaptiveQuickEntryKeepsInputAcrossColumnChanges() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("열 전환 중 입력은 넓은 시뮬레이터에서 확인")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp(additionalArguments: ["--ui-testing-adaptive-layout"])
        let input = app.textFields["해당 날짜에 할 일 입력"]
        input.tap()
        input.typeText("넓게 작성")
        app.buttons["layout-test-compact"].tap()
        input.typeText(" 좁게 이어쓰기")
        XCTAssertEqual(input.value as? String, "넓게 작성 좁게 이어쓰기")
        app.buttons["layout-test-expanded"].tap()
        input.typeText(" 완료")
        XCTAssertEqual(input.value as? String, "넓게 작성 좁게 이어쓰기 완료")
    }

    @MainActor
    func testAdaptiveChecklistKeepsInputAcrossColumnChanges() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("열 전환 중 입력은 넓은 시뮬레이터에서 확인")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp(additionalArguments: ["--ui-testing-adaptive-layout"])
        tapRootDestination("메모", in: app)
        createMemo(in: app, type: "checklist")
        app.buttons["항목 추가"].tap()
        app.typeText("작성 중인 항목")
        app.buttons["layout-test-compact"].tap()
        app.typeText(" 계속 작성")
        let field = app.descendants(matching: .any)["memo-checklist-title"].firstMatch
        XCTAssertEqual(field.value as? String, "작성 중인 항목 계속 작성")
        app.buttons["layout-test-expanded"].tap()
        app.typeText(" 완료")
        XCTAssertEqual(field.value as? String, "작성 중인 항목 계속 작성 완료")
        app.buttons["memo-checklist-keyboard-dismiss"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["layout-test-compact"].tap()
        app.buttons["layout-test-expanded"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertEqual(field.value as? String, "작성 중인 항목 계속 작성 완료")
    }

    @MainActor
    func testAdaptiveMemoDraftSurvivesWindowResizeAndTiling() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("실제 창 너비 변경은 iPad에서 확인")
        }
        guard #available(iOS 26, *) else {
            throw XCTSkip("이 창 조절 검사는 iPadOS 26의 윈도우 제어기를 사용합니다")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let app = launchKanbanFlowApp()
        let window = app.windows.firstMatch
        if window.frame.width < 800 {
            window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 42, dy: 54)).press(forDuration: 1)
            let fill = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["채우기"].firstMatch
            XCTAssertTrue(fill.waitForExistence(timeout: 5))
            fill.tap()
            let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                window.frame.width > 800
            }, object: window)
            XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        }
        let originalFrame = window.frame
        addTeardownBlock {
            await MainActor.run {
                app.activate()
                let hideKeyboard = app.keyboards.buttons["키보드 가리기"]
                if hideKeyboard.isHittable { hideKeyboard.tap() }
                settings.terminate()
                if window.frame.width < originalFrame.width - 100 {
                    window.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: 42, dy: 54)).press(forDuration: 1)
                    let fill = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["채우기"].firstMatch
                    if fill.waitForExistence(timeout: 3) { fill.tap() }
                }
                XCUIDevice.shared.orientation = .portrait
            }
        }
        XCTAssertGreaterThan(originalFrame.width, 800)
        tapRootDestination("메모", in: app)
        createMemo(in: app)
        let editor = app.textViews["메모 내용"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("실제 창에서도 이어지는 메모")
        // The software keyboard covers iPadOS's bottom-corner resize handle.
        // Dismiss it deliberately; the separate column-change tests keep the
        // keyboard open and verify uninterrupted typing without tapping again.
        app.keyboards.buttons["키보드 가리기"].tap()
        XCTAssertTrue(waitForKeyboardHidden(in: app))
        let editorWindow = app.windows.containing(.textView, identifier: "메모 내용").firstMatch
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "adaptive-real-window-before-resize"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "adaptive-memo-real-window-before-resize")
        editorWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
            .press(forDuration: 0.3, thenDragTo:
                editorWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.9)))
        let narrowed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.state == .runningForeground && editorWindow.frame.width <= 600 && editor.isHittable
        }, object: editorWindow)
        XCTAssertEqual(XCTWaiter.wait(for: [narrowed], timeout: 5), .completed)
        addReferenceScreenshot(named: "adaptive-memo-real-window-after-resize")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("\n창을 줄인 뒤 계속 작성")
        let content = "실제 창에서도 이어지는 메모\n창을 줄인 뒤 계속 작성"
        XCTAssertEqual(editor.value as? String, content)
        let frames = XCTAttachment(string: "변경 전: \(originalFrame)\n변경 후: \(window.frame)")
        frames.name = "adaptive-real-window-frames"
        frames.lifetime = .keepAlways
        add(frames)
        addReferenceScreenshot(named: "adaptive-memo-real-narrow-window")
        app.keyboards.buttons["키보드 가리기"].tap()
        XCTAssertTrue(waitForKeyboardHidden(in: app))
        editorWindow.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 42, dy: 54)).press(forDuration: 1)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let tile = system.buttons["좌우"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        // Tiling a lone foreground window leaves the other half empty. Bring
        // Settings into this workspace from the Dock, rather than assuming
        // a previously launched background app is already beside PlanBase.
        let screenOrigin = system.coordinate(withNormalizedOffset: .zero)
        screenOrigin.withOffset(CGVector(dx: originalFrame.midX, dy: originalFrame.maxY - 2))
            .press(forDuration: 0.1, thenDragTo: screenOrigin.withOffset(CGVector(
                dx: originalFrame.midX, dy: originalFrame.maxY - 100)))
        let settingsIcon = system.icons["설정"].firstMatch
        XCTAssertTrue(settingsIcon.waitForExistence(timeout: 5))
        settingsIcon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: screenOrigin.withOffset(CGVector(
            dx: originalFrame.width * 0.75, dy: originalFrame.midY)))
        addReferenceScreenshot(named: "adaptive-tiling-arrangement")
        let arrangement = XCTAttachment(string: "PlanBase: \(editorWindow.frame)\nSettings: \(settings.debugDescription)\nSystem: \(system.debugDescription)")
        arrangement.name = "adaptive-tiling-arrangement"
        arrangement.lifetime = .keepAlways
        add(arrangement)
        let sideBySide = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let memoFrame = editorWindow.frame
            let settingsFrame = settings.windows.firstMatch.frame
            return memoFrame.width >= 320 && settingsFrame.width >= 320
                && memoFrame.width <= 600 && settingsFrame.width <= 600
                && (memoFrame.maxX <= settingsFrame.minX + 1 || settingsFrame.maxX <= memoFrame.minX + 1)
                && editor.isHittable && settings.windows.firstMatch.isHittable
        }, object: editorWindow)
        XCTAssertEqual(XCTWaiter.wait(for: [sideBySide], timeout: 10), .completed)
        XCTAssertEqual(editor.value as? String, content)
        addReferenceScreenshot(named: "adaptive-memo-side-by-side")
        // Dock dragging activates Settings. Return to PlanBase before tapping
        // the editor to bring back the keyboard we deliberately dismissed.
        app.activate()
        // The element's default activation point can place the cursor at the
        // start. Tap below the two existing lines to explicitly append instead.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15)).tap()
        editor.typeText("\n다른 앱 옆에서 계속 작성")
        XCTAssertEqual(editor.value as? String, content + "\n다른 앱 옆에서 계속 작성")
        addReferenceScreenshot(named: "adaptive-memo-side-by-side-edited")
        app.buttons["memo-editor-back"].tap()
        let row = app.buttons["실제 창에서도 이어지는 메모"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "실제 창에서도 이어지는 메모").count, 1)
        row.tap()
        XCTAssertEqual(editor.value as? String, content + "\n다른 앱 옆에서 계속 작성")
    }

    @MainActor
    func testAdaptiveBoardAndFocusRetainStateBesideAnotherApp() throws {
        let (app, settings, fullFrame) = try prepareAdaptiveWindowingApp()
        createFocusTask(in: app, title: "두 창 사이에서도 집중", minutes: 30)
        let input = app.textFields["해당 날짜에 할 일 입력"]
        input.tap()
        input.typeText("분할하며 작성한 작업")
        tileAdaptiveApp(app, beside: settings, fullFrame: fullFrame)
        XCTAssertEqual(input.value as? String, "분할하며 작성한 작업")
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        input.typeText(" 이어쓰기")
        app.buttons["작업 추가"].tap()
        let title = "분할하며 작성한 작업 이어쓰기"
        let edit = app.buttons["\(title) 작업 편집"]
        XCTAssertTrue(scrollToHittable(edit, in: app.scrollViews["board-accessibility-scroll"]))
        XCTAssertEqual(app.buttons.matching(identifier: "\(title) 작업 편집").count, 1)
        app.buttons["\(title) 진행 중 상태"].tap()
        app.buttons["board-status-destination"].tap()
        XCTAssertTrue(waitForSelected(app.buttons["board-status-filter-doing"]))
        addReferenceScreenshot(named: "adaptive-board-side-by-side")
        fillAdaptiveWindow(in: app)
        XCTAssertTrue(scrollToHittable(edit, in: app.scrollViews["board-accessibility-scroll"]))
        XCTAssertEqual(app.buttons.matching(identifier: "\(title) 작업 편집").count, 1)

        let entry = app.buttons["두 창 사이에서도 집중 집중 시작"]
        XCTAssertTrue(scrollToHittable(entry, in: app.scrollViews["board-accessibility-scroll"]))
        entry.tap()
        let scroll = app.scrollViews["focus-content-scroll"]
        let start = app.buttons["focus-start"]
        XCTAssertTrue(scrollToHittable(start, in: scroll))
        start.tap()
        let timer = app.descendants(matching: .any)["focus-timer"].firstMatch
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        func seconds(_ value: String?) -> Int? {
            guard let clock = value?.split(separator: ",").first else { return nil }
            let parts = clock.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return parts[0] * 60 + parts[1]
        }
        let before = try XCTUnwrap(seconds(timer.value as? String))
        let changedAt = Date()
        tileAdaptiveApp(app, beside: settings, fullFrame: fullFrame)
        let after = try XCTUnwrap(seconds(timer.value as? String))
        XCTAssertTrue((timer.value as? String)?.contains("진행 중") == true)
        XCTAssertGreaterThanOrEqual(before - after, 0)
        XCTAssertLessThanOrEqual(before - after, Int(Date().timeIntervalSince(changedAt)) + 4)
        let pause = app.buttons["focus-pause-resume"]
        XCTAssertTrue(scrollToHittable(pause, in: scroll))
        pause.tap()
        XCTAssertTrue(app.staticTexts["멈춘 시간은 집중 기록에 포함되지 않아요."].waitForExistence(timeout: 5))
        let paused = timer.value as? String
        addReferenceScreenshot(named: "adaptive-focus-side-by-side")
        fillAdaptiveWindow(in: app)
        XCTAssertEqual(timer.value as? String, paused)
        app.buttons["focus-close"].tap()
        let reopen = app.buttons["focus-active-launcher"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 5))
        reopen.tap()
        XCTAssertEqual(timer.value as? String, paused)
    }

    @MainActor
    func testAdaptiveCalendarAndArchiveRetainStateBesideAnotherApp() throws {
        let (app, settings, fullFrame) = try prepareAdaptiveWindowingApp(
            additionalArguments: ["--ui-testing-daily-activity-fixtures"])
        tapRootDestination("캘린더", in: app)
        let today = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", koreanDayDisplay(Date())
        )).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        today.tap()
        app.buttons["일정 추가"].firstMatch.tap()
        let title = app.textFields["event-title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("다른 앱 옆에서 저장한 일정")
        app.buttons["event-editor-keyboard-dismiss"].tap()
        tileAdaptiveApp(app, beside: settings, fullFrame: fullFrame)
        XCTAssertEqual(title.value as? String, "다른 앱 옆에서 저장한 일정")
        app.navigationBars["일정 추가"].buttons["추가"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["일정 편집"].firstMatch.waitForExistence(timeout: 10))
        let savedEvent = app.buttons["다른 앱 옆에서 저장한 일정 일정 메뉴"]
        XCTAssertTrue(savedEvent.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "다른 앱 옆에서 저장한 일정 일정 메뉴").count, 1)
        addReferenceScreenshot(named: "adaptive-calendar-side-by-side")
        fillAdaptiveWindow(in: app)
        XCTAssertTrue(app.buttons["일정 편집"].firstMatch.isHittable)
        XCTAssertTrue(savedEvent.isHittable)

        tapRootDestination("기록", in: app)
        app.buttons["기록 필터"].tap()
        let mode = app.segmentedControls["archive-content-mode-picker"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.buttons["완료 작업"].tap()
        app.navigationBars["검색 필터"].buttons["완료"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("영어\n")
        app.buttons["날짜로 기록 찾기"].tap()
        let detail = app.descendants(matching: .any)["archive-day-detail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        app.buttons["이전 날짜"].tap()
        let previousDayTask = detail.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "집중해서 책 읽기"
        )).firstMatch
        XCTAssertTrue(previousDayTask.waitForExistence(timeout: 5))
        tileAdaptiveApp(app, beside: settings, fullFrame: fullFrame)
        XCTAssertTrue(previousDayTask.waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "adaptive-archive-side-by-side")
        fillAdaptiveWindow(in: app)
        XCTAssertTrue(previousDayTask.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "영어")
        app.buttons["적용된 기록 필터 변경"].tap()
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(mode.buttons["완료 작업"].isSelected)
        app.navigationBars["검색 필터"].buttons["완료"].tap()
    }

    @MainActor
    private func prepareAdaptiveWindowingApp(
        additionalArguments: [String] = []
    ) throws -> (XCUIApplication, XCUIApplication, CGRect) {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("실제 두 앱 창 배치는 iPad에서 확인합니다")
        }
        guard #available(iOS 26, *) else {
            throw XCTSkip("이 창 배치 검사는 iPadOS 26의 윈도우 제어기를 사용합니다")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let app = launchKanbanFlowApp(additionalArguments: additionalArguments)
        addTeardownBlock {
            await MainActor.run {
                app.activate()
                let hide = app.keyboards.buttons["키보드 가리기"]
                if hide.isHittable { hide.tap() }
                settings.terminate()
                let window = app.windows.firstMatch
                if window.frame.width < 800 {
                    window.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: 42, dy: 54)).press(forDuration: 1)
                    let fill = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["채우기"].firstMatch
                    if fill.waitForExistence(timeout: 3) { fill.tap() }
                }
                XCUIDevice.shared.orientation = .portrait
            }
        }
        fillAdaptiveWindow(in: app)
        return (app, settings, app.windows.firstMatch.frame)
    }

    @MainActor
    private func fillAdaptiveWindow(in app: XCUIApplication) {
        app.activate()
        let hide = app.keyboards.buttons["키보드 가리기"]
        if hide.isHittable { hide.tap() }
        let window = app.windows.firstMatch
        guard window.frame.width < 800 else { return }
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 42, dy: 54)).press(forDuration: 1)
        let fill = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["채우기"].firstMatch
        XCTAssertTrue(fill.waitForExistence(timeout: 5))
        fill.tap()
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.frame.width > 800
        }, object: window)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
    }

    @MainActor
    private func tileAdaptiveApp(_ app: XCUIApplication, beside settings: XCUIApplication, fullFrame: CGRect) {
        let hide = app.keyboards.buttons["키보드 가리기"]
        if hide.isHittable { hide.tap() }
        XCTAssertTrue(waitForKeyboardHidden(in: app))
        let window = app.windows.firstMatch
        // A full-screen iPad window hides the traffic-light controls. Expose
        // them through the actual resize handle before opening their menu.
        if window.frame.width > 800 {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
                .press(forDuration: 0.3, thenDragTo:
                    window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.9)))
            let narrowed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                window.frame.width <= 600 && app.state == .runningForeground
            }, object: window)
            XCTAssertEqual(XCTWaiter.wait(for: [narrowed], timeout: 5), .completed)
        }
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 42, dy: 54)).press(forDuration: 1)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let tile = system.buttons["좌우"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        let origin = system.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: fullFrame.midX, dy: fullFrame.maxY - 2))
            .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(
                dx: fullFrame.midX, dy: fullFrame.maxY - 100)))
        let settingsIcon = system.icons["설정"].firstMatch
        XCTAssertTrue(settingsIcon.waitForExistence(timeout: 5))
        settingsIcon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: origin.withOffset(CGVector(
                dx: fullFrame.width * 0.75, dy: fullFrame.midY)))
        let sideBySide = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let a = window.frame
            let b = settings.windows.firstMatch.frame
            return a.width >= 320 && b.width >= 320 && a.width <= 600 && b.width <= 600
                && (a.maxX <= b.minX + 1 || b.maxX <= a.minX + 1)
                && window.isHittable && settings.windows.firstMatch.isHittable
        }, object: window)
        XCTAssertEqual(XCTWaiter.wait(for: [sideBySide], timeout: 10), .completed)
        app.activate()
    }

    @MainActor
    private func waitForKeyboardHidden(in app: XCUIApplication) -> Bool {
        // iPadOS can retain a zero-height keyboard accessibility element after
        // dismissal. Its presence alone doesn't mean it covers the window.
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let keyboard = app.keyboards.firstMatch
            return !keyboard.exists || keyboard.frame.height < 1
                || !keyboard.frame.intersects(app.windows.firstMatch.frame)
        }, object: app)
        return XCTWaiter.wait(for: [hidden], timeout: 5) == .completed
    }

    @MainActor
    func testAdaptiveMemoDraftAndSelectionSurviveRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem",
                               "--ui-testing-memo-save-failure-twice"]
        app.launch()
        tapRootDestination("메모", in: app)
        createMemo(in: app)
        let editor = app.textViews["메모 내용"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("크기가 바뀌어도 남는 메모\n초안 보존 확인")
        XCTAssertTrue(app.buttons["memo-save-retry"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(editor.value as? String, "크기가 바뀌어도 남는 메모\n초안 보존 확인")
        addReferenceScreenshot(named: "adaptive-memo-wide-draft")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(editor.value as? String, "크기가 바뀌어도 남는 메모\n초안 보존 확인")
        // Consume remaining injected failures without replacing the editor/session.
        for _ in 0..<2 where app.buttons["memo-save-retry"].exists {
            app.buttons["memo-save-retry"].tap()
        }
        app.buttons["memo-editor-back"].tap()
        let row = app.buttons["크기가 바뀌어도 남는 메모"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "크기가 바뀌어도 남는 메모").count, 1)
        row.tap()
        XCTAssertEqual(editor.value as? String, "크기가 바뀌어도 남는 메모\n초안 보존 확인")
        addReferenceScreenshot(named: "adaptive-memo-restored")
    }

    @MainActor
    func testAdaptiveCalendarPreservesEventDraftAndDaySelection() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp()
        tapRootDestination("캘린더", in: app)
        let today = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", koreanDayDisplay(Date())
        )).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        today.tap()
        app.buttons["일정 추가"].firstMatch.tap()
        let field = app.textFields["event-title-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("펼쳐도 유지되는 일정")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(field.value as? String, "펼쳐도 유지되는 일정")
        addReferenceScreenshot(named: "adaptive-calendar-editor-wide")
        app.navigationBars["일정 추가"].buttons["추가"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["일정 편집"].firstMatch.waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "adaptive-calendar-day")
    }

    @MainActor
    func testAdaptiveMemoSurvivesColumnCollapseAndExpansion() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("두 열과 단일 열 전환은 넓은 시뮬레이터에서 확인")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp(additionalArguments: ["--ui-testing-adaptive-layout"])
        tapRootDestination("메모", in: app)
        createMemo(in: app)
        let editor = app.textViews["메모 내용"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("동일 편집 세션 유지\n넓은 화면에서 작성")
        app.buttons["layout-test-compact"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "동일 편집 세션 유지\n넓은 화면에서 작성")
        editor.typeText("\n좁은 화면에서 이어쓰기")
        let content = "동일 편집 세션 유지\n넓은 화면에서 작성\n좁은 화면에서 이어쓰기"
        XCTAssertEqual(editor.value as? String, content)
        addReferenceScreenshot(named: "adaptive-width-memo-compact")
        app.buttons["layout-test-expanded"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, content)
        XCTAssertTrue(app.buttons["새 메모"].isHittable)
        for _ in 0..<2 {
            app.buttons["layout-test-compact"].tap()
            XCTAssertEqual(editor.value as? String, content)
            app.buttons["layout-test-expanded"].tap()
            XCTAssertEqual(editor.value as? String, content)
        }
        addReferenceScreenshot(named: "adaptive-width-memo-expanded")
        app.buttons["memo-editor-back"].tap()
        let row = app.buttons["동일 편집 세션 유지"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "동일 편집 세션 유지").count, 1)
        row.tap()
        XCTAssertEqual(editor.value as? String, content)
    }

    @MainActor
    func testAdaptiveArchiveSelectionSurvivesColumnCollapse() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("두 열과 단일 열 전환은 넓은 시뮬레이터에서 확인")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-activity-fixtures",
                               "--ui-testing-archive-collapsed", "--ui-testing-adaptive-layout"]
        app.launch()
        tapRootDestination("기록", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("영어\n")
        app.buttons["날짜로 기록 찾기"].tap()
        let detail = app.descendants(matching: .any)["archive-day-detail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        app.buttons["이전 날짜"].tap()
        let previousDayTask = detail.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "집중해서 책 읽기"
        )).firstMatch
        XCTAssertTrue(previousDayTask.waitForExistence(timeout: 10))
        app.buttons["layout-test-compact"].tap()
        XCTAssertTrue(previousDayTask.waitForExistence(timeout: 5))
        app.buttons["layout-test-expanded"].tap()
        XCTAssertTrue(previousDayTask.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "영어")
        addReferenceScreenshot(named: "adaptive-archive-expanded")
    }

    @MainActor
    func testAdaptiveMemoPreservesChecklistAndDrawingAcrossColumnChanges() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("두 열과 단일 열 전환은 넓은 시뮬레이터에서 확인")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp(additionalArguments: ["--ui-testing-adaptive-layout", "--ui-testing-legacy-memo"])
        tapRootDestination("메모", in: app)
        app.buttons["기존 복합 메모"].tap()
        let text = app.textViews["메모 내용"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        text.tap()
        text.typeText(" 추가 기록")
        app.buttons["체크리스트"].tap()
        app.buttons["항목 추가"].tap()
        app.typeText("전환 후에도 유지할 항목")
        app.buttons["memo-checklist-keyboard-dismiss"].tap()
        app.buttons["전환 후에도 유지할 항목 완료"].tap()
        app.buttons["layout-test-compact"].tap()
        XCTAssertTrue(app.buttons["전환 후에도 유지할 항목 완료 해제"].waitForExistence(timeout: 5))
        app.buttons["layout-test-expanded"].tap()
        XCTAssertTrue(app.buttons["전환 후에도 유지할 항목 완료 해제"].waitForExistence(timeout: 5))
        app.buttons["필기"].tap()
        let canvas = app.descendants(matching: .any)["memo-drawing-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        let clear = app.buttons["memo-clear-drawing"]
        XCTAssertTrue(clear.isEnabled)
        app.buttons["layout-test-compact"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertTrue(clear.isEnabled)
        addReferenceScreenshot(named: "adaptive-memo-drawing-compact")
        app.buttons["layout-test-expanded"].tap()
        XCTAssertTrue(clear.isEnabled)
        addReferenceScreenshot(named: "adaptive-memo-drawing-expanded")
        app.buttons["memo-editor-back"].tap()
        app.buttons["기존 복합 메모 추가 기록"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertTrue(clear.isEnabled)
        app.buttons["체크리스트"].tap()
        XCTAssertTrue(app.buttons["전환 후에도 유지할 항목 완료 해제"].waitForExistence(timeout: 5))
        app.buttons["텍스트"].tap()
        XCTAssertEqual(text.value as? String, "기존 복합 메모 추가 기록")
    }

    @MainActor
    func testAdaptiveArchivePreservesReviewDraftAcrossRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp()
        tapRootDestination("기록", in: app)
        app.buttons["날짜로 기록 찾기"].tap()
        let compose = app.buttons["회고 남기기"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10))
        compose.tap()
        let title = app.textFields["review-title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText("회전 중 작성한 하루 회고")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(title.value as? String, "회전 중 작성한 하루 회고")
        XCTAssertTrue(app.buttons["review-save-button"].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "adaptive-archive-review-draft")
        app.buttons["review-save-button"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        let edit = app.buttons["회고 수정"].firstMatch
        XCTAssertTrue(scrollToHittable(edit, in: app))
        edit.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.value as? String, "회전 중 작성한 하루 회고")
    }

    @MainActor
    func testAdaptiveFocusRetainsPausedSessionAcrossRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp()
        createFocusTask(in: app, title: "화면 변화 중 집중", minutes: 30)
        let entry = app.buttons["화면 변화 중 집중 집중 시작"]
        XCTAssertTrue(scrollToHittable(entry, in: app.scrollViews["board-accessibility-scroll"]))
        entry.tap()
        let scroll = app.scrollViews["focus-content-scroll"]
        let start = app.buttons["focus-start"]
        XCTAssertTrue(scrollToHittable(start, in: scroll))
        start.tap()
        let timer = app.descendants(matching: .any)["focus-timer"].firstMatch
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        let pause = app.buttons["focus-pause-resume"]
        XCTAssertTrue(scrollToHittable(pause, in: scroll))
        pause.tap()
        XCTAssertTrue(app.staticTexts["멈춘 시간은 집중 기록에 포함되지 않아요."].waitForExistence(timeout: 5))
        let pausedValue = timer.value as? String
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(timer.value as? String, pausedValue)
        XCTAssertTrue(pause.isHittable)
        addReferenceScreenshot(named: "adaptive-focus-wide-paused")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(timer.value as? String, pausedValue)
        app.buttons["focus-close"].tap()
        let reopen = app.buttons["focus-active-launcher"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 10))
        reopen.tap()
        XCTAssertEqual(timer.value as? String, pausedValue)
        addReferenceScreenshot(named: "adaptive-focus-restored")
    }

    private func requireWidgetAudit() throws {
        guard ProcessInfo.processInfo.environment["PLANBASE_WIDGET_UI_AUDIT"] == "1" else {
            throw XCTSkip("위젯 감사는 준비된 시뮬레이터에서 명시적으로 실행합니다")
        }
    }

    private func requireNotificationDeliveryAudit() throws {
        guard ProcessInfo.processInfo.environment["PLANBASE_NOTIFICATION_DELIVERY_AUDIT"] == "1" else {
            throw XCTSkip("알림 전달 감사는 권한 상태가 깨끗한 전용 시뮬레이터에서 실행합니다")
        }
    }

    @MainActor
    func testTaskReminderRequestsPermissionAndDeliversNotification() throws {
        try requireNotificationDeliveryAudit()
#if !targetEnvironment(simulator)
        throw XCTSkip("알림 전달 감사는 격리된 시뮬레이터에서만 실행합니다")
#else
        let title = "실제로 울리는 작업 알림"
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-empty-board",
            "--ui-testing-theme=appleSystem",
            "--ui-testing-notification-delivery",
        ]
        app.launch()

        let quickAdd = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 15))
        quickAdd.tap()
        quickAdd.typeText(title)
        app.buttons["작업 추가"].tap()

        let edit = app.buttons["\(title) 작업 편집"]
        XCTAssertTrue(scrollToHittable(edit, in: app.scrollViews["board-accessibility-scroll"]))
        edit.tap()
        XCTAssertTrue(app.navigationBars["작업 상세"].waitForExistence(timeout: 5))

        let reminderToggle = app.switches["작업 알림"]
        let detailNavigation = app.navigationBars["작업 상세"]
        XCTAssertTrue(
            scrollToFullyVisible(
                reminderToggle,
                in: app,
                below: detailNavigation
            )
        )
        reminderToggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        let reminderEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "0"),
            object: reminderToggle
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [reminderEnabled], timeout: 3),
            .completed
        )
        let tenMinutes = app.buttons["10분 후"]
        XCTAssertTrue(
            scrollToFullyVisible(
                tenMinutes,
                in: app,
                below: detailNavigation
            )
        )
        tenMinutes.tap()
        let permissionExplanation = app.staticTexts[
            "저장 후 이 기기의 알림 권한을 요청합니다."
        ]
        XCTAssertTrue(
            scrollToFullyVisible(
                permissionExplanation,
                in: app,
                below: detailNavigation
            )
        )
        addReferenceScreenshot(named: "task-reminder-before-permission")

        app.navigationBars["작업 상세"].buttons["저장"].tap()
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = home.buttons["허용"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10), home.debugDescription)
        addReferenceScreenshot(named: "task-reminder-permission-request")
        allow.tap()
        XCTAssertTrue(app.navigationBars["작업 상세"].waitForNonExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        let delivered = home.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", title)
        ).firstMatch
        XCTAssertTrue(delivered.waitForExistence(timeout: 15), home.debugDescription)
        let hierarchy = XCTAttachment(string: home.debugDescription)
        hierarchy.name = "task-reminder-delivered-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "task-reminder-delivered")
#endif
    }

    @MainActor
    func testTaskReminderDeniedPermissionExplainsAndOpensSettings() throws {
        try requireNotificationDeliveryAudit()
#if !targetEnvironment(simulator)
        throw XCTSkip("알림 권한 거부 감사는 격리된 시뮬레이터에서만 실행합니다")
#else
        let title = "권한이 꺼진 작업 알림"
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-empty-board",
            "--ui-testing-theme=appleSystem",
            "--ui-testing-notification-delivery",
        ]
        app.launch()

        let quickAdd = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 15))
        quickAdd.tap()
        quickAdd.typeText(title)
        app.buttons["작업 추가"].tap()

        let edit = app.buttons["\(title) 작업 편집"]
        XCTAssertTrue(scrollToHittable(edit, in: app.scrollViews["board-accessibility-scroll"]))
        edit.tap()
        XCTAssertTrue(app.navigationBars["작업 상세"].waitForExistence(timeout: 5))

        let detailNavigation = app.navigationBars["작업 상세"]
        let reminderToggle = app.switches["작업 알림"]
        XCTAssertTrue(
            scrollToFullyVisible(
                reminderToggle,
                in: app,
                below: detailNavigation
            )
        )
        reminderToggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        let reminderEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "0"),
            object: reminderToggle
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [reminderEnabled], timeout: 3),
            .completed
        )
        app.navigationBars["작업 상세"].buttons["저장"].tap()

        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = home.buttons["허용 안 함"]
        if deny.waitForExistence(timeout: 3) {
            addReferenceScreenshot(named: "task-reminder-permission-deny")
            deny.tap()
        }
        XCTAssertTrue(app.navigationBars["작업 상세"].waitForNonExistence(timeout: 10))

        let savedTask = app.buttons["\(title) 작업 편집"]
        XCTAssertTrue(scrollToHittable(savedTask, in: app.scrollViews["board-accessibility-scroll"]))
        savedTask.tap()
        XCTAssertTrue(app.navigationBars["작업 상세"].waitForExistence(timeout: 5))

        let deniedExplanation = app.staticTexts[
            "알림 시각은 저장되지만 이 기기에서는 울리지 않습니다."
        ]
        for _ in 0..<10 where !deniedExplanation.waitForExistence(timeout: 0.5) {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(deniedExplanation.exists)
        XCTAssertTrue(
            scrollToFullyVisible(
                deniedExplanation,
                in: app,
                below: app.navigationBars["작업 상세"]
            )
        )
        let fallbackGuidance = app.staticTexts[
            "바로 열리지 않으면 설정 > 앱 > PlanBase > 알림에서 허용해 주세요."
        ]
        XCTAssertTrue(
            scrollToFullyVisible(
                fallbackGuidance,
                in: app,
                below: app.navigationBars["작업 상세"]
            )
        )
        let openSettings = app.buttons["알림 설정 열기"]
        XCTAssertTrue(
            scrollToFullyVisible(
                openSettings,
                in: app,
                below: app.navigationBars["작업 상세"]
            )
        )
        addReferenceScreenshot(named: "task-reminder-permission-denied-explanation")

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        openSettings.tap()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(
            settings.navigationBars["PlanBase"].waitForExistence(timeout: 5)
                || settings.staticTexts["PlanBase"].waitForExistence(timeout: 1)
                || settings.navigationBars["설정"].waitForExistence(timeout: 1),
            "설정 앱에서 이동 가능한 화면을 열지 못했습니다.\n\(settings.debugDescription)"
        )
        addReferenceScreenshot(named: "task-reminder-settings-destination")
#endif
    }

    @MainActor
    func testInspectPlannerWidgetGallery() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("감사용 시뮬레이터의 위젯 갤러리만 점검합니다")
        #else
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if let encoded = ProcessInfo.processInfo.environment["PLANBASE_WIDGET_GALLERY_STEPS"] {
            let steps = try JSONDecoder().decode([[String: String]].self, from: Data(encoded.utf8))
            for step in steps {
                let kind = try XCTUnwrap(step["kind"])
                if kind == "prepareHome" {
                    _ = try preparePlannerWidgetHome(home)
                } else if kind == "openPlannerGallery" {
                    try openPlannerWidgetGallery(home)
                } else if kind == "home" {
                    XCUIDevice.shared.press(.home)
                } else if kind == "swipeLeft" {
                    home.swipeLeft()
                } else if kind == "swipeRight" {
                    home.swipeRight()
                } else if kind == "pressPlannerWidget" {
                    XCTAssertTrue(
                        home.buttons["플래너를 이번 달로 이동"].firstMatch
                            .waitForExistence(timeout: 10),
                        home.debugDescription
                    )
                    let widget = try XCTUnwrap(
                        home.icons.matching(identifier: "PlanBase")
                            .allElementsBoundByIndex.first {
                                $0.isHittable
                                    && ($0.value as? String) == "위젯"
                                    && $0.buttons["플래너를 이번 달로 이동"].exists
                            }, home.debugDescription)
                    widget.press(forDuration: 1.2)
                } else if kind == "tapCoordinate" {
                    let x = try XCTUnwrap(Double(try XCTUnwrap(step["x"])))
                    let y = try XCTUnwrap(Double(try XCTUnwrap(step["y"])))
                    home.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
                } else {
                    let label = try XCTUnwrap(step["label"])
                    let target: XCUIElement
                    switch step["element"] {
                    case "search": target = home.searchFields[label].firstMatch
                    case "cell": target = home.cells[label].firstMatch
                    case "text": target = home.staticTexts[label].firstMatch
                    case "icon": target = home.icons[label].firstMatch
                    default: target = home.buttons[label].firstMatch
                    }
                    XCTAssertTrue(target.waitForExistence(timeout: 10), home.debugDescription)
                    if kind == "type" {
                        target.tap()
                        target.typeText(try XCTUnwrap(step["value"]))
                    } else if kind == "press" {
                        target.press(forDuration: 1.2)
                    } else {
                        XCTAssertEqual(kind, "tap")
                        target.tap()
                    }
                }
            }
        } else {
            let widget = try preparePlannerWidgetHome(home)
            widget.press(forDuration: 1.2)
            XCTAssertTrue(home.buttons["홈 화면 편집"].waitForExistence(timeout: 5))
            home.buttons["홈 화면 편집"].tap()
        }
        let hierarchy = XCTAttachment(string: home.debugDescription)
        hierarchy.name = "planner-widget-gallery-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "planner-widget-gallery")
        #endif
    }

    @MainActor
    private func preparePlannerWidgetHome(_ home: XCUIApplication) throws -> XCUIElement {
        XCUIDevice.shared.press(.home)
        if home.buttons["편집"].exists && home.buttons["완료"].exists {
            home.buttons["완료"].tap()
        }
        func visibleWidgets() -> [XCUIElement] {
            home.icons.matching(identifier: "PlanBase").allElementsBoundByIndex
                .filter { $0.isHittable && ($0.value as? String) == "위젯" }
        }
        var widgets = visibleWidgets()
        if widgets.isEmpty {
            home.swipeLeft()
            widgets = visibleWidgets()
        }
        return try XCTUnwrap(widgets.first, home.debugDescription)
    }

    @MainActor
    private func openPlannerWidgetGallery(_ home: XCUIApplication) throws {
        let widget = try preparePlannerWidgetHome(home)
        widget.press(forDuration: 1.2)

        let editHomeScreen = home.buttons["홈 화면 편집"]
        XCTAssertTrue(editHomeScreen.waitForExistence(timeout: 5), home.debugDescription)
        editHomeScreen.tap()

        let edit = home.buttons["편집"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), home.debugDescription)
        edit.tap()

        let addWidget = home.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "위젯 추가"))
            .firstMatch
        XCTAssertTrue(addWidget.waitForExistence(timeout: 5), home.debugDescription)
        addWidget.tap()

        let search = home.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), home.debugDescription)
        search.tap()
        search.typeText("PlanBase")

        let result = home.cells["PlanBase"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), home.debugDescription)
        result.tap()
    }

    @MainActor
    func testInspectWidgetGalleryEntryPoints() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("격리된 시뮬레이터에서만 홈 화면을 점검합니다")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["칸반"].firstMatch.waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icons = home.icons.matching(identifier: "PlanBase")
        XCTAssertTrue(icons.firstMatch.waitForExistence(timeout: 10))
        let icon = try XCTUnwrap(
            icons.allElementsBoundByIndex
                .filter { $0.isHittable && $0.frame.minY > 0 }
                .min { $0.frame.minY < $1.frame.minY })
        let before = XCTAttachment(string: home.debugDescription)
        before.name = "widget-home-hierarchy"
        before.lifetime = .keepAlways
        add(before)
        addReferenceScreenshot(named: "widget-home-before-menu")
        icon.press(forDuration: 1.2)
        let menu = XCTAttachment(string: home.debugDescription)
        menu.name = "widget-home-icon-menu"
        menu.lifetime = .keepAlways
        add(menu)
        addReferenceScreenshot(named: "widget-home-icon-menu")
        let medium = home.buttons["중간 크기 위젯"]
        XCTAssertTrue(medium.waitForExistence(timeout: 5))
        medium.tap()
        let widget = home.buttons["이번 달로 이동"]
        XCTAssertTrue(widget.waitForExistence(timeout: 20))
        let placed = XCTAttachment(string: home.debugDescription)
        placed.name = "widget-home-medium-calendar"
        placed.lifetime = .keepAlways
        add(placed)
        addReferenceScreenshot(named: "widget-home-medium-calendar")
        #endif
    }

    @MainActor
    func testPlannerLargeStateFeedbackAndRoute() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("감사용 시뮬레이터의 준비된 플래너 상태만 점검합니다")
        #else
        let state = ProcessInfo.processInfo.environment["PLANBASE_WIDGET_EXPECTED_MARKER"] ?? "empty"
        XCTAssertTrue(["empty", "completed", "unavailable"].contains(state))
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        _ = try preparePlannerWidgetHome(home)
        let month = home.buttons["플래너를 이번 달로 이동"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 15), home.debugDescription)
        month.tap()
        let marker =
            state == "unavailable"
            ? "PlanBase를 열면 작업을 갱신해요"
            : "남은 0 · 완료 \(state == "completed" ? 3 : 0)"
        XCTAssertTrue(home.staticTexts[marker].firstMatch.waitForExistence(timeout: 20))
        let planner = try XCTUnwrap(
            home.icons.matching(identifier: "PlanBase")
                .allElementsBoundByIndex.first {
                    $0.isHittable && $0.buttons["플래너를 이번 달로 이동"].exists
                })
        let hierarchy = XCTAttachment(string: planner.debugDescription)
        hierarchy.name = "planner-large-\(state)-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "planner-large-\(state)")
        XCTAssertGreaterThan(planner.frame.height, 250)
        if state != "unavailable" {
            for label in ["플래너 이전 달", "플래너 다음 달"] {
                XCTAssertGreaterThanOrEqual(planner.buttons[label].frame.width, 44)
                XCTAssertGreaterThanOrEqual(planner.buttons[label].frame.height, 44)
            }
        }

        if state == "unavailable" {
            let footer = planner.staticTexts["PlanBase를 열면 일정을 갱신해요"].firstMatch
            XCTAssertTrue(footer.exists)
            let dates = planner.buttons.matching(
                NSPredicate(
                    format: "label MATCHES %@", "[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}.*"
                )
            ).allElementsBoundByIndex
            XCTAssertGreaterThanOrEqual(dates.count, 28)
            for date in dates {
                XCTAssertLessThanOrEqual(date.frame.maxY, footer.frame.minY, date.label)
            }
            XCTAssertFalse(planner.buttons["플래너 이전 달"].exists)
            XCTAssertFalse(planner.buttons["플래너 다음 달"].exists)
        } else if state == "completed" {
            XCTAssertTrue(planner.staticTexts["오늘 작업을 모두 마쳤어요"].exists)
            XCTAssertFalse(planner.staticTexts["오늘 할 일이 없어요"].exists)
            let originalMonth = try XCTUnwrap(month.value as? String)
            planner.buttons["플래너 이전 달"].tap()
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value != %@", originalMonth), object: month)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 20), .completed)
            addReferenceScreenshot(named: "planner-large-previous-month")
            month.tap()
            let restored = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", originalMonth), object: month)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 20), .completed)
        } else {
            XCTAssertTrue(planner.staticTexts["오늘 할 일이 없어요"].exists)
            XCTAssertFalse(planner.staticTexts["오늘 작업을 모두 마쳤어요"].exists)
        }
        let board = planner.buttons.matching(NSPredicate(format: "label CONTAINS %@", "오늘 보드 열기")).firstMatch
        XCTAssertTrue(board.exists)
        if state == "completed" { XCTAssertTrue(board.label.contains("완료 3개")) }
        board.tap()
        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["칸반"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["해당 날짜에 할 일 입력"].exists)
        addReferenceScreenshot(named: "planner-\(state)-today-board-route")
        #endif
    }

    @MainActor
    func testPlannerExtraLargePopulatedLayoutAndRoute() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("감사용 iPad 시뮬레이터에 배치한 초대형 플래너만 점검합니다")
        #else
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        _ = try preparePlannerWidgetHome(home)

        let month = home.buttons["플래너를 이번 달로 이동"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 15), home.debugDescription)
        month.tap()
        XCTAssertTrue(home.staticTexts["남은 9 · 완료 2"].firstMatch.waitForExistence(timeout: 20))

        let planner = try XCTUnwrap(
            home.icons.matching(identifier: "PlanBase")
                .allElementsBoundByIndex.first {
                    $0.isHittable
                        && $0.frame.width > 600
                        && $0.buttons["플래너를 이번 달로 이동"].exists
                }, home.debugDescription)
        XCTAssertGreaterThan(planner.frame.height, 300)

        for label in ["플래너 이전 달", "플래너 다음 달"] {
            let control = home.buttons[label].firstMatch
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }

        let board = planner.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@", "오늘 남은 작업 9개, 완료 2개"
            )
        ).firstMatch
        XCTAssertTrue(board.exists)
        XCTAssertTrue(board.label.contains("외 3개"), board.label)
        XCTAssertTrue(planner.staticTexts["+3개 더 있어요"].exists)

        let longTitle = planner.staticTexts[
            "위젯 검증 · 아주 긴 작업 제목이 패널 너비를 넘어가도 말줄임으로 안정적으로 표시되는지 확인"
        ]
        XCTAssertTrue(longTitle.exists)
        XCTAssertLessThanOrEqual(longTitle.frame.maxX, board.frame.maxX)

        let dates = planner.buttons.matching(
            NSPredicate(
                format: "label MATCHES %@", "[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}.*"
            )
        ).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(dates.count, 35)
        for date in dates {
            XCTAssertLessThanOrEqual(date.frame.maxX, board.frame.minX, date.label)
        }
        let today = planner.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@", "2026.09.05"
            )
        ).firstMatch
        XCTAssertTrue(today.label.contains("일정 5개"), today.label)

        let hierarchy = XCTAttachment(string: planner.debugDescription)
        hierarchy.name = "planner-extra-large-populated-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "planner-extra-large-populated")

        board.tap()
        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["칸반"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["해당 날짜에 할 일 입력"].exists)
        addReferenceScreenshot(named: "planner-extra-large-today-board-route")
        #endif
    }

    @MainActor
    func testPlannerExtraLargeThemeAndMonth() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("감사용 iPad 시뮬레이터의 초대형 플래너 테마만 점검합니다")
        #else
        let expectedMarker = try XCTUnwrap(
            ProcessInfo.processInfo.environment["PLANBASE_WIDGET_EXPECTED_MARKER"]
        )
        let themeID = try XCTUnwrap(
            ProcessInfo.processInfo.environment["PLANBASE_WIDGET_THEME_ID"]
        )
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // 홈 화면 편집이나 App Library에 남아 있어도 첫 페이지에서 같은 조건으로 시작합니다.
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)
        home.swipeLeft()

        let month = home.buttons["플래너를 이번 달로 이동"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 15), home.debugDescription)
        month.tap()
        XCTAssertTrue(home.staticTexts[expectedMarker].firstMatch.waitForExistence(timeout: 20))

        let planner = try XCTUnwrap(
            home.icons.matching(identifier: "PlanBase")
                .allElementsBoundByIndex.first {
                    $0.isHittable
                        && $0.frame.width > 600
                        && $0.buttons["플래너를 이번 달로 이동"].exists
                }, home.debugDescription)
        XCTAssertGreaterThan(planner.frame.height, 300)

        for label in ["플래너 이전 달", "플래너 다음 달"] {
            let control = home.buttons[label].firstMatch
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }

        XCTAssertTrue(planner.staticTexts["남은 9 · 완료 2"].exists)
        XCTAssertTrue(planner.staticTexts[expectedMarker].exists)
        XCTAssertTrue(planner.staticTexts["+3개 더 있어요"].exists)

        let board = planner.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@", "오늘 남은 작업 9개, 완료 2개"
            )
        ).firstMatch
        XCTAssertTrue(board.exists)
        XCTAssertTrue(board.label.contains("외 3개"), board.label)

        let fiveWeekDates = planner.buttons.matching(
            NSPredicate(
                format: "label MATCHES %@", "[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}.*"
            )
        ).allElementsBoundByIndex
        XCTAssertEqual(fiveWeekDates.count, 35)
        for date in fiveWeekDates {
            XCTAssertLessThanOrEqual(date.frame.maxX, board.frame.minX, date.label)
            XCTAssertLessThanOrEqual(date.frame.maxY, planner.frame.maxY, date.label)
        }

        let hierarchy = XCTAttachment(string: planner.debugDescription)
        hierarchy.name = "planner-extra-large-\(themeID)-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "planner-extra-large-\(themeID)-five-week")

        let originalMonth = try XCTUnwrap(month.value as? String)
        home.buttons["플래너 이전 달"].firstMatch.tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", originalMonth), object: month
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 20), .completed)

        let sixWeekDates = planner.buttons.matching(
            NSPredicate(
                format: "label MATCHES %@", "[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}.*"
            )
        ).allElementsBoundByIndex
        XCTAssertEqual(sixWeekDates.count, 42)
        for date in sixWeekDates {
            XCTAssertLessThanOrEqual(date.frame.maxX, board.frame.minX, date.label)
            XCTAssertLessThanOrEqual(date.frame.maxY, planner.frame.maxY, date.label)
        }
        XCTAssertTrue(planner.staticTexts[expectedMarker].exists)
        addReferenceScreenshot(named: "planner-extra-large-\(themeID)-six-week")

        month.tap()
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", originalMonth), object: month
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 20), .completed)
        #endif
    }

    @MainActor
    func testCalendarExtraLargePopulatedLayoutAndRoute() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("감사용 iPad 시뮬레이터에 배치한 초대형 캘린더만 점검합니다")
        #else
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        _ = try preparePlannerWidgetHome(home)

        let calendar = try XCTUnwrap(
            home.icons.matching(identifier: "PlanBase")
                .allElementsBoundByIndex.first {
                    $0.isHittable
                        && $0.frame.width > 600
                        && $0.buttons["이번 달로 이동"].exists
                }, home.debugDescription)
        XCTAssertGreaterThan(calendar.frame.height, 300)

        let month = calendar.buttons["이번 달로 이동"]
        month.tap()
        let today = calendar.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@", "2026.09.05"
            )
        ).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 20))
        XCTAssertTrue(today.label.contains("일정 5개"), today.label)
        XCTAssertTrue(today.label.contains("외 2개"), today.label)

        for label in ["이전 달", "다음 달"] {
            XCTAssertGreaterThanOrEqual(calendar.buttons[label].frame.width, 44)
            XCTAssertGreaterThanOrEqual(calendar.buttons[label].frame.height, 44)
        }
        let fiveWeekDates = calendar.buttons.matching(
            NSPredicate(
                format: "label MATCHES %@", "[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}.*"
            )
        ).allElementsBoundByIndex
        XCTAssertEqual(fiveWeekDates.count, 35)
        for date in fiveWeekDates {
            XCTAssertLessThanOrEqual(date.frame.maxX, calendar.frame.maxX)
            XCTAssertLessThanOrEqual(date.frame.maxY, calendar.frame.maxY)
        }

        let hierarchy = XCTAttachment(string: calendar.debugDescription)
        hierarchy.name = "calendar-extra-large-populated-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "calendar-extra-large-populated")

        let originalMonth = try XCTUnwrap(month.value as? String)
        calendar.buttons["이전 달"].tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", originalMonth), object: month
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 20), .completed)
        let sixWeekDates = calendar.buttons.matching(
            NSPredicate(
                format: "label MATCHES %@", "[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}.*"
            )
        ).allElementsBoundByIndex
        XCTAssertEqual(sixWeekDates.count, 42)
        for date in sixWeekDates {
            XCTAssertLessThanOrEqual(date.frame.maxY, calendar.frame.maxY)
        }
        addReferenceScreenshot(named: "calendar-extra-large-six-week")

        month.tap()
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", originalMonth), object: month
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 20), .completed)
        today.tap()
        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.staticTexts["2026.09.05 토"].firstMatch.waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "calendar-extra-large-date-route")
        #endif
    }

    @MainActor
    func testPlannerMediumCompletedStateAndRoute() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("감사용 시뮬레이터에 배치한 중간 플래너만 점검합니다")
        #else
        // The widget snapshot is prepared separately; UI testing suppresses shared publication.
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem"]
        app.launch()
        let input = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        for index in 1...3 {
            let title = "플래너 완료 확인 \(index)"
            input.tap()
            input.typeText(title + "\n")
            let done = app.buttons["\(title) 완료 상태"]
            XCTAssertTrue(scrollToHittable(done, in: app))
            done.tap()
        }
        addReferenceScreenshot(named: "planner-completed-source-board")
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        _ = try preparePlannerWidgetHome(home)
        let label = "오늘 작업을 모두 마쳤어요. 완료 3개. 오늘 보드 열기"
        let board = home.buttons[label].firstMatch
        for _ in 0..<3 {
            if board.exists && board.isHittable { break }
            home.swipeLeft()
        }
        XCTAssertTrue(board.waitForExistence(timeout: 20))
        let medium = try XCTUnwrap(
            home.icons.matching(identifier: "PlanBase")
                .allElementsBoundByIndex.first {
                    $0.isHittable && $0.buttons[label].exists
                })
        XCTAssertLessThan(medium.frame.height, 250)
        XCTAssertTrue(medium.staticTexts["오늘 작업을 모두 마쳤어요"].exists)
        XCTAssertFalse(medium.staticTexts["오늘 할 일이 없어요"].exists)
        let hierarchy = XCTAttachment(string: medium.debugDescription)
        hierarchy.name = "planner-medium-completed-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "planner-medium-completed")
        board.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.textFields["해당 날짜에 할 일 입력"].waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "planner-medium-completed-board-route")
        #endif
    }

    @MainActor
    func testPlannerMediumDateAccessibilityAndRoute() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("격리된 시뮬레이터에 배치한 플래너만 점검합니다")
        #else
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        func mediumWidgets() -> [XCUIElement] {
            home.icons.matching(identifier: "PlanBase").allElementsBoundByIndex.filter {
                $0.isHittable && ($0.value as? String) == "위젯" && $0.frame.height < 250
            }
        }
        var candidates = mediumWidgets()
        if candidates.isEmpty {
            home.swipeLeft()
            candidates = mediumWidgets()
        }
        let planner = try XCTUnwrap(candidates.first)
        let dates = planner.buttons.matching(
            NSPredicate(
                format: "label MATCHES %@", "[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}.*"
            )
        ).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(dates.count, 28)
        let hierarchy = XCTAttachment(string: home.debugDescription)
        hierarchy.name = "planner-medium-date-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "planner-medium-date-accessibility")
        for date in dates {
            XCTAssertGreaterThanOrEqual(date.frame.width, 20, date.label)
            XCTAssertGreaterThanOrEqual(date.frame.height, 20, date.label)
        }

        let eventDate = try XCTUnwrap(dates.first { $0.label.contains("일정 1개") })
        let selectedDate = String(eventDate.label.prefix(12))
        eventDate.tap()
        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["일정 추가"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars[selectedDate].exists, app.debugDescription)
        addReferenceScreenshot(named: "planner-selected-date-route")
        #endif
    }

    @MainActor
    func testCalendarUnavailableMonthControlsAndDateRoute() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("감사용 시뮬레이터의 오래된 캘린더 자료만 점검합니다")
        #else
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let month = home.buttons["이번 달로 이동"].firstMatch
        for _ in 0..<3 {
            if month.exists && month.isHittable { break }
            home.swipeLeft()
        }
        XCTAssertTrue(month.waitForExistence(timeout: 15))
        month.tap()
        let message = "PlanBase를 열면 일정을 갱신해요"
        XCTAssertTrue(home.staticTexts[message].firstMatch.waitForExistence(timeout: 20))
        let widget = try XCTUnwrap(
            home.icons.matching(identifier: "PlanBase")
                .allElementsBoundByIndex.first {
                    $0.isHittable && $0.buttons["이번 달로 이동"].exists
                })
        let hierarchy = XCTAttachment(string: widget.debugDescription)
        hierarchy.name = "calendar-unavailable-navigation-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "calendar-unavailable-navigation")
        XCTAssertFalse(widget.buttons["이전 달"].exists)
        XCTAssertFalse(widget.buttons["다음 달"].exists)
        let footer = widget.staticTexts[message].firstMatch
        let dates = widget.buttons.matching(
            NSPredicate(
                format: "label MATCHES %@", "[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}.*"
            )
        ).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(dates.count, 28)
        for date in dates {
            XCTAssertLessThanOrEqual(date.frame.maxY, footer.frame.minY, date.label)
        }
        let selected = try XCTUnwrap(dates.first)
        let selectedDate = String(selected.label.prefix(12))
        selected.tap()
        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["일정 추가"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars[selectedDate].exists, app.debugDescription)
        addReferenceScreenshot(named: "calendar-unavailable-selected-date-route")
        #endif
    }

    @MainActor
    func testCalendarWidgetHomeScreenLayoutAndDateRoute() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("격리된 시뮬레이터에 배치한 위젯만 점검합니다")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["칸반"].firstMatch.waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let month = home.buttons["이번 달로 이동"]
        XCTAssertTrue(month.waitForExistence(timeout: 15))
        let hierarchy = XCTAttachment(string: home.debugDescription)
        hierarchy.name = "widget-medium-layout-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "widget-medium-layout")
        XCTAssertGreaterThanOrEqual(month.frame.height, 44)
        XCTAssertFalse((month.value as? String ?? "").isEmpty)
        for title in ["이전 달", "다음 달"] {
            XCTAssertGreaterThanOrEqual(home.buttons[title].frame.height, 44)
            XCTAssertGreaterThanOrEqual(home.buttons[title].frame.width, 44)
        }
        let dates = home.buttons.matching(NSPredicate(format: "label MATCHES %@", "[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}.*"))
            .allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(dates.count, 28)
        let notice = home.staticTexts["PlanBase를 열면 일정을 갱신해요"].firstMatch
        if notice.exists {
            XCTAssertGreaterThanOrEqual(notice.frame.minY + 1, dates.map { $0.frame.maxY }.max() ?? 0)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        let today = home.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", formatter.string(from: Date()))).firstMatch
        XCTAssertTrue(today.exists)
        today.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["일정 추가"].firstMatch.waitForExistence(timeout: 10))
        let opened = XCTAttachment(string: app.debugDescription)
        opened.name = "widget-calendar-date-route"
        opened.lifetime = .keepAlways
        add(opened)
        addReferenceScreenshot(named: "widget-calendar-date-route")
        #endif
    }

    @MainActor
    func testCalendarWidgetMonthNavigation() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("격리된 시뮬레이터에 배치한 위젯만 점검합니다")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["칸반"].firstMatch.waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let month = home.buttons["이번 달로 이동"]
        XCTAssertTrue(month.waitForExistence(timeout: 15))
        let originalMonth = try XCTUnwrap(month.value as? String)
        home.buttons["이전 달"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", originalMonth), object: month)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 20), .completed)
        addReferenceScreenshot(named: "widget-previous-month")
        let changedHierarchy = XCTAttachment(string: home.debugDescription)
        changedHierarchy.name = "widget-previous-month-hierarchy"
        changedHierarchy.lifetime = .keepAlways
        add(changedHierarchy)
        XCTAssertNotEqual(app.state, .runningForeground)
        month.tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", originalMonth), object: month)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 20), .completed)
        addReferenceScreenshot(named: "widget-current-month-restored")
        XCTAssertNotEqual(app.state, .runningForeground)
        #endif
    }

    @MainActor
    func testCalendarWidgetSyntheticSnapshotLayout() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("감사용 시뮬레이터의 합성 위젯 자료만 점검합니다")
        #else
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let month = home.buttons["이번 달로 이동"]
        for _ in 0..<3 {
            if month.exists && month.isHittable { break }
            home.swipeLeft()
        }
        XCTAssertTrue(month.waitForExistence(timeout: 15))
        month.tap()
        let marker =
            ProcessInfo.processInfo.environment["PLANBASE_WIDGET_EXPECTED_MARKER"]
            ?? "위젯 검증 · 아주 긴 일정 제목"
        let fixtureDate = home.buttons.matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(fixtureDate.waitForExistence(timeout: 20))
        XCTAssertFalse(home.staticTexts["PlanBase를 열면 일정을 갱신해요"].firstMatch.exists)
        for name in ["widget-populated-current-month", "widget-populated-previous-month"] {
            let busyDay = home.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", 일정 5개,")).firstMatch
            XCTAssertTrue(busyDay.waitForExistence(timeout: 10))
            XCTAssertTrue(busyDay.label.hasSuffix(", 외 2개"), busyDay.label)
            let hierarchy = XCTAttachment(string: home.debugDescription)
            hierarchy.name = name + "-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            addReferenceScreenshot(named: name)
            if name == "widget-populated-current-month" {
                let originalMonth = try XCTUnwrap(month.value as? String)
                home.buttons["이전 달"].tap()
                let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", originalMonth), object: month)
                XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 20), .completed)
            }
        }
        month.tap()
        XCTAssertTrue(fixtureDate.waitForExistence(timeout: 20))
        #endif
    }

    @MainActor
    func testCalendarWidgetResizeLarge() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("감사용 시뮬레이터에 배치한 위젯만 크기를 변경합니다")
        #else
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let month = home.buttons["이번 달로 이동"]
        func visibleWidget() -> XCUIElement? {
            home.icons.matching(identifier: "PlanBase").allElementsBoundByIndex.first {
                $0.isHittable && ($0.value as? String) == "위젯"
            }
        }
        if visibleWidget() == nil { home.swipeLeft() }
        let widget = try XCTUnwrap(visibleWidget())
        widget.press(forDuration: 1.2)
        let menu = XCTAttachment(string: home.debugDescription)
        menu.name = "widget-resize-menu-hierarchy"
        menu.lifetime = .keepAlways
        add(menu)
        addReferenceScreenshot(named: "widget-resize-menu")
        XCTAssertTrue(home.buttons["큰 위젯"].waitForExistence(timeout: 5))
        home.buttons["큰 위젯"].tap()
        XCTAssertTrue(month.waitForExistence(timeout: 20))
        let large = home.icons.matching(identifier: "PlanBase").allElementsBoundByIndex
            .first { $0.isHittable && $0.frame.height > 250 }
        XCTAssertNotNil(large)
        month.tap()
        let hierarchy = XCTAttachment(string: home.debugDescription)
        hierarchy.name = "widget-large-current-month-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "widget-large-current-month")
        #endif
    }

    @MainActor
    func testCalendarWidgetResizeSmallAndOpenToday() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("감사용 시뮬레이터에 배치한 위젯만 크기를 변경합니다")
        #else
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if !home.buttons["이번 달로 이동"].waitForExistence(timeout: 3) { home.swipeLeft() }
        let widget = try XCTUnwrap(
            home.icons.matching(identifier: "PlanBase")
                .allElementsBoundByIndex.first { $0.isHittable && $0.frame.width > 200 })
        widget.press(forDuration: 1.2)
        XCTAssertTrue(home.buttons["작은 위젯"].waitForExistence(timeout: 5))
        home.buttons["작은 위젯"].tap()
        let small = home.icons.matching(identifier: "PlanBase").matching(
            NSPredicate(format: "value == %@", "위젯")
        ).firstMatch
        XCTAssertTrue(small.waitForExistence(timeout: 20))
        XCTAssertLessThan(small.frame.width, 200)
        let hierarchy = XCTAttachment(string: home.debugDescription)
        hierarchy.name = "widget-small-today-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "widget-small-today")
        small.tap()
        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["일정 추가"].firstMatch.waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "widget-small-today-route")
        #endif
    }

    @MainActor
    func testInspectFocusLiveActivityRunningAndBreak() throws {
        try requireWidgetAudit()
        #if !targetEnvironment(simulator)
        throw XCTSkip("감사용 시뮬레이터의 집중 표시만 점검합니다")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem"]
        app.terminate()
        app.launch()
        createFocusTask(in: app, title: "잠금 화면 집중과 휴식 확인", minutes: 30)
        app.buttons["잠금 화면 집중과 휴식 확인 집중 시작"].tap()
        let scroll = app.scrollViews["focus-content-scroll"]
        let start = app.buttons["focus-start"]
        XCTAssertTrue(scrollToHittable(start, in: scroll))
        start.tap()
        XCTAssertTrue(app.staticTexts["이번 집중 30분"].waitForExistence(timeout: 10))
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func captureNotificationCenter(_ name: String, phase: String) {
            XCUIDevice.shared.press(.home)
            home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
                .press(forDuration: 0.1, thenDragTo: home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
            let allow = home.buttons["허용"]
            if allow.waitForExistence(timeout: 2) { allow.tap() }
            let pause = home.buttons["\(phase) 일시정지"]
            XCTAssertTrue(pause.waitForExistence(timeout: 10))
            XCTAssertTrue(home.staticTexts["\(phase) 중"].exists)
            let hierarchy = XCTAttachment(string: home.debugDescription)
            hierarchy.name = name + "-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            addReferenceScreenshot(named: name)
            pause.tap()
            let resume = home.buttons[phase == "집중" ? "다시 집중" : "휴식 계속"]
            XCTAssertTrue(resume.waitForExistence(timeout: 10))
            XCTAssertTrue(home.staticTexts["\(phase) 일시정지"].exists)
            addReferenceScreenshot(named: name + "-paused")
            resume.tap()
            XCTAssertTrue(pause.waitForExistence(timeout: 10))
            if phase == "휴식" {
                home.buttons["휴식 건너뛰기"].tap()
                XCTAssertTrue(home.buttons["휴식 건너뛰기"].waitForNonExistence(timeout: 10))
                addReferenceScreenshot(named: "live-activity-break-stopped")
            }
            XCUIDevice.shared.press(.home)
            app.activate()
        }
        captureNotificationCenter("live-activity-focus-running", phase: "집중")
        let stop = app.buttons["focus-stop"]
        XCTAssertTrue(scrollToHittable(stop, in: scroll))
        stop.tap()
        app.alerts["집중을 마칠까요?"].buttons["집중 마치기"].tap()
        let rest = app.buttons["focus-start-break"]
        XCTAssertTrue(scrollToHittable(rest, in: scroll))
        rest.tap()
        XCTAssertTrue(app.staticTexts["이번 휴식 5분"].waitForExistence(timeout: 5))
        captureNotificationCenter("live-activity-break-running", phase: "휴식")
        XCTAssertTrue(app.staticTexts["이번 휴식 5분"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["focus-start"].waitForExistence(timeout: 5))
        #endif
    }

    @MainActor
    func testSavedTaskShortcutExactInputAndSuggestionsOnSelectedDay() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.launch()
        XCTAssertTrue(app.buttons["다음 날짜"].waitForExistence(timeout: 15))
        app.buttons["다음 날짜"].tap()
        let date = app.staticTexts["board-date-title"].label
        createShortcutFixture(in: app)
        let input = app.textFields["해당 날짜에 할 일 입력"]
        input.tap()
        input.typeText("/운\n")
        XCTAssertTrue(app.descendants(matching: .any)["quick-entry-error"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["/운 작업 편집"].exists)
        let result = app.buttons["빠른 입력 운동 /운동 추가"]
        XCTAssertTrue(scrollToHittable(result, in: app.scrollViews["board-accessibility-scroll"]))
        addReferenceScreenshot(named: "shortcut-partial-suggestion")
        result.tap()
        let created = app.buttons["빠른 입력 운동 작업 편집"]
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["board-date-title"].label, date)
        XCTAssertTrue(scrollToHittable(input, in: app.scrollViews["board-accessibility-scroll"]))
        input.tap()
        input.typeText("/운동\n")
        XCTAssertEqual(app.buttons.matching(identifier: "빠른 입력 운동 작업 편집").count, 2)
        XCTAssertTrue(scrollToHittable(input, in: app.scrollViews["board-accessibility-scroll"]))
        input.tap()
        input.typeText("/없는입력어\n")
        XCTAssertTrue(app.descendants(matching: .any)["quick-entry-error"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "/없는입력어")
        XCTAssertFalse(app.buttons["/없는입력어 작업 편집"].exists)
        addReferenceScreenshot(named: "shortcut-unknown-input")
        input.tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "/없는입력어".count))
        input.typeText("일반 작업\n")
        XCTAssertTrue(app.buttons["일반 작업 작업 편집"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSavedTaskShortcutLargeTextPickerAndDuplicateValidation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=midnightBlue", "--ui-testing-accessibility-text-size"]
        app.terminate()
        app.launch()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["해당 날짜에 할 일 입력"].waitForExistence(timeout: 15))
        createShortcutFixture(in: app)
        let input = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(scrollToHittable(input, in: app.scrollViews["board-accessibility-scroll"]))
        input.tap()
        input.typeText("/")
        let result = app.buttons["빠른 입력 운동 /운동 추가"]
        XCTAssertTrue(scrollToHittable(result, in: app.scrollViews["board-accessibility-scroll"]))
        XCTAssertTrue(isHorizontallyContained(result, in: app.windows.firstMatch))
        addReferenceScreenshot(named: "shortcut-dark-large-text-picker")
        result.tap()
        let library = app.buttons["saved-task-library-button"]
        XCTAssertTrue(scrollToHittable(library, in: app.scrollViews["board-accessibility-scroll"]))
        library.tap()
        app.buttons["saved-task-create"].tap()
        let title = app.textFields["saved-task-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("중복 입력어 작업")
        app.buttons["saved-task-keyboard-dismiss"].tap()
        let alias = app.textFields["saved-task-alias"]
        XCTAssertTrue(scrollToHittable(alias, in: app.collectionViews.firstMatch))
        alias.tap()
        alias.typeText("운동")
        app.buttons["saved-task-editor-save"].tap()
        let error = app.descendants(matching: .any)["saved-task-editor-error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "shortcut-duplicate-error-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "shortcut-duplicate-validation")
        XCTAssertTrue(error.label.contains("다른 작업"))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "saved-task-editor-error").count, 1)
    }

    @MainActor
    private func createShortcutFixture(in app: XCUIApplication) {
        let library = app.buttons["saved-task-library-button"]
        XCTAssertTrue(scrollToHittable(library, in: app.scrollViews["board-accessibility-scroll"]))
        library.tap()
        app.buttons["saved-task-create"].tap()
        let title = app.textFields["saved-task-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("빠른 입력 운동")
        app.buttons["saved-task-keyboard-dismiss"].tap()
        let estimate = app.textFields["saved-task-estimate"]
        XCTAssertTrue(scrollToHittable(estimate, in: app.collectionViews.firstMatch))
        estimate.tap()
        estimate.typeText("40")
        app.buttons["saved-task-keyboard-dismiss"].tap()
        let alias = app.textFields["saved-task-alias"]
        XCTAssertTrue(scrollToHittable(alias, in: app.collectionViews.firstMatch))
        alias.tap()
        alias.typeText("운동")
        addReferenceScreenshot(named: "shortcut-editor")
        app.buttons["saved-task-editor-save"].tap()
        let editorClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["새로 저장"])
        XCTAssertEqual(XCTWaiter.wait(for: [editorClosed], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["/운동"].waitForExistence(timeout: 5))
        app.navigationBars["저장한 작업"].buttons["닫기"].tap()
    }

    @MainActor
    func testKanbanStatusDestinationAndCompletionUndo() {
        let app = launchKanbanFlowApp()
        let title = "상태 이동과 완료 취소"
        addKanbanFlowTask(title, in: app)
        app.buttons["\(title) 진행 중 상태"].tap()
        XCTAssertTrue(waitForSelected(app.buttons["board-status-filter-todo"]))
        let destination = app.buttons["board-status-destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertEqual(destination.label, "진행 중 보기")
        destination.tap()
        XCTAssertTrue(waitForSelected(app.buttons["board-status-filter-doing"]))
        // A stopped task returns to todo; resuming starts a new recorded interval.
        let stop = app.buttons["\(title) 할 일 상태"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertEqual(destination.label, "할 일 보기")
        destination.tap()
        XCTAssertTrue(waitForSelected(app.buttons["board-status-filter-todo"]))
        app.buttons["\(title) 진행 중 상태"].tap()
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        XCTAssertTrue(waitForSelected(app.buttons["\(title) 진행 중 상태"]))
        addReferenceScreenshot(named: "kanban-stopped-and-resumed")
        let done = app.buttons["\(title) 완료 상태"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        addReferenceScreenshot(named: "kanban-status-destination")
        done.tap()
        let undo = app.buttons["board-completion-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(undo.frame.height, 44)
        addReferenceScreenshot(named: "kanban-completion-undo-offer")
        undo.tap()
        XCTAssertTrue(waitForSelected(app.buttons["board-status-filter-doing"]))
        XCTAssertTrue(app.buttons["\(title) 작업 편집"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSelected(app.buttons["\(title) 진행 중 상태"]))
        addReferenceScreenshot(named: "kanban-completion-undone")
        app.buttons["기록"].firstMatch.tap()
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "archive-task-", title)).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertFalse(record.label.contains("이날 완료"))
    }

    @MainActor
    func testKanbanPastDayCompletionDestinationAndUndo() {
        let app = launchKanbanFlowApp()
        app.buttons["이전 날짜"].tap()
        let originalDate = app.staticTexts["board-date-title"].label
        let title = "지난 날짜 완료 취소"
        addKanbanFlowTask(title, in: app)
        app.buttons["\(title) 완료 상태"].tap()
        let destination = app.buttons["board-status-destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertEqual(destination.label, "완료 보기")
        destination.tap()
        XCTAssertTrue(waitForSelected(app.buttons["board-status-filter-done"]))
        XCTAssertNotEqual(app.staticTexts["board-date-title"].label, originalDate)
        XCTAssertTrue(app.buttons["\(title) 작업 편집"].waitForExistence(timeout: 5))
        app.buttons["board-completion-undo"].tap()
        XCTAssertTrue(waitForSelected(app.buttons["board-status-filter-todo"]))
        XCTAssertEqual(app.staticTexts["board-date-title"].label, originalDate)
        XCTAssertTrue(app.buttons["\(title) 작업 편집"].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "kanban-past-day-undo")
    }

    @MainActor
    func testKanbanReopeningRetainsCompletionEvidence() {
        let app = launchKanbanFlowApp()
        let title = "완료 후 다시 진행"
        addKanbanFlowTask(title, in: app)
        app.buttons["\(title) 완료 상태"].tap()
        let destination = app.buttons["board-status-destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        let doing = app.buttons["\(title) 진행 중 상태"]
        XCTAssertTrue(doing.waitForExistence(timeout: 5))
        doing.tap()
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        XCTAssertTrue(app.buttons["\(title) 작업 편집"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["board-completion-undo"].exists)
        app.buttons["기록"].firstMatch.tap()
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "archive-task-", title)).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(record.label.contains("이날 완료"))
        XCTAssertTrue(record.label.contains("현재 진행 중 · 완료 이력 유지"))
        addReferenceScreenshot(named: "kanban-reopened-archive-evidence")
    }

    @MainActor
    func testKanbanCompletionUndoWithAccessibilityText() {
        let app = launchKanbanFlowApp(additionalArguments: ["--ui-testing-accessibility-text-size"])
        let title = "큰 글자에서 완료 취소"
        addKanbanFlowTask(title, in: app)
        let menu = app.buttons["\(title)-status-menu"]
        XCTAssertTrue(scrollToHittable(menu, in: app.scrollViews["board-accessibility-scroll"]))
        menu.tap()
        app.buttons["완료"].tap()
        let undo = app.buttons["board-completion-undo"]
        let destination = app.buttons["board-status-destination"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isHittable)
        XCTAssertTrue(destination.isHittable)
        XCTAssertGreaterThanOrEqual(undo.frame.height, 44)
        XCTAssertTrue(isHorizontallyContained(undo, in: app.windows.firstMatch))
        addReferenceScreenshot(named: "kanban-large-text-undo")
        undo.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.value as? String, "할 일")
    }

    @MainActor
    private func launchKanbanFlowApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-archive-collapsed", "--ui-testing-theme=appleSystem"] + additionalArguments
        // The first XCTest launch can omit the fixture arguments on this runtime.
        app.launch()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["해당 날짜에 할 일 입력"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func addKanbanFlowTask(_ title: String, in app: XCUIApplication) {
        let field = app.textFields["해당 날짜에 할 일 입력"]
        field.tap()
        field.typeText(title)
        app.buttons["작업 추가"].tap()
        XCTAssertTrue(app.buttons["\(title) 작업 편집"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testKanbanDeleteRequiresConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.launch()
        let title = "오늘 처리할 작업 빠르게 추가해보기"
        let menu = app.buttons["\(title) 작업 메뉴"]
        XCTAssertTrue(scrollToHittable(menu, in: app.scrollViews["board-accessibility-scroll"]))
        menu.tap()
        app.buttons["작업 삭제"].tap()
        let confirmation = app.alerts["작업을 삭제할까요?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["취소"].tap()
        XCTAssertTrue(app.buttons["\(title) 작업 편집"].exists)
        menu.tap()
        app.buttons["작업 삭제"].tap()
        confirmation.buttons["삭제"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["board-empty-todo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["\(title) 작업 편집"].exists)
        addReferenceScreenshot(named: "kanban-delete-empty-feedback")
    }

    @MainActor
    func testKanbanThemeChangePreservesDraftDateAndFilter() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.launch()
        XCTAssertTrue(app.buttons["다음 날짜"].waitForExistence(timeout: 15))
        app.buttons["다음 날짜"].tap()
        let date = app.staticTexts["board-date-title"].label
        app.buttons["board-status-filter-doing"].tap()
        let draft = "테마를 바꿔도 이어 쓰는 계획"
        let field = app.textFields["해당 날짜에 할 일 입력"]
        field.tap()
        field.typeText(draft)
        app.buttons["board-theme-button"].tap()
        let preset = app.buttons["theme-preset-midnightBlue"]
        XCTAssertTrue(scrollToHittable(preset, in: app.scrollViews.firstMatch))
        preset.tap()
        XCTAssertEqual(preset.value as? String, "선택됨")
        addReferenceScreenshot(named: "kanban-live-dark-theme-picker")
        app.navigationBars["테마"].buttons["완료"].tap()
        XCTAssertEqual(app.staticTexts["board-date-title"].label, date)
        XCTAssertEqual(field.value as? String, draft)
        XCTAssertTrue(waitForSelected(app.buttons["board-status-filter-doing"]))
        addReferenceScreenshot(named: "kanban-live-theme-preserved-draft")
        app.buttons["saved-task-library-button"].tap()
        app.buttons["saved-task-create"].tap()
        let savedTitle = app.textFields["saved-task-title"]
        XCTAssertTrue(savedTitle.waitForExistence(timeout: 5))
        savedTitle.tap()
        savedTitle.typeText("다크 테마에서 저장하는 작업")
        addReferenceScreenshot(named: "saved-task-editor-dark")
        app.buttons["saved-task-editor-save"].tap()
        XCTAssertTrue(app.buttons["다크 테마에서 저장하는 작업 추가"].waitForExistence(timeout: 5))
        app.buttons["닫기"].tap()
        XCTAssertEqual(field.value as? String, draft)
        app.buttons["작업 추가"].tap()
        XCTAssertTrue(waitForSelected(app.buttons["board-status-filter-todo"]))
        XCTAssertTrue(app.buttons["\(draft) 작업 편집"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["board-theme-button"].waitForExistence(timeout: 15))
        app.buttons["board-theme-button"].tap()
        XCTAssertEqual(app.staticTexts["theme-current-selection"].label, "Midnight Blue")
        let white = app.buttons["theme-preset-appleSystem"]
        XCTAssertTrue(scrollToHittable(white, in: app.scrollViews.firstMatch))
        white.tap()
        app.navigationBars["테마"].buttons["완료"].tap()
    }

    @MainActor
    func testKanbanEveryThemeVisuals() {
        let themes = [
            "appleSystem", "maroonEmber", "plumNight", "roseLilac",
            "forestCream", "tealPaper", "midnightBlue", "charcoalRose",
        ]
        for theme in themes {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--ui-testing-theme=\(theme)"]
            app.launch()
            let input = app.textFields["해당 날짜에 할 일 입력"]
            XCTAssertTrue(input.waitForExistence(timeout: 15))
            XCTAssertGreaterThanOrEqual(input.frame.width, 170)
            XCTAssertGreaterThanOrEqual(app.buttons["작업 추가"].frame.height + 0.001, 44)
            XCTAssertGreaterThanOrEqual(app.buttons["작업 추가"].frame.width + 0.001, 44)
            let title = app.buttons["오늘 처리할 작업 빠르게 추가해보기 작업 편집"]
            XCTAssertTrue(scrollToHittable(title, in: app.scrollViews["board-accessibility-scroll"]))
            XCTAssertTrue(isHorizontallyContained(title, in: app.windows.firstMatch))
            addReferenceScreenshot(named: "kanban-\(theme)-todo")
            if ["appleSystem", "midnightBlue", "charcoalRose"].contains(theme) {
                app.buttons["board-status-filter-doing"].tap()
                XCTAssertTrue(app.buttons["카드 상태 컨트롤 확인 작업 편집"].waitForExistence(timeout: 5))
                addReferenceScreenshot(named: "kanban-\(theme)-doing")
                app.buttons["board-status-filter-done"].tap()
                XCTAssertTrue(app.buttons["완료 영역 접힘 확인 작업 편집"].waitForExistence(timeout: 5))
                addReferenceScreenshot(named: "kanban-\(theme)-done")
                app.buttons["saved-task-library-button"].tap()
                XCTAssertTrue(app.navigationBars["저장한 작업"].waitForExistence(timeout: 5))
                addReferenceScreenshot(named: "kanban-\(theme)-saved-tasks")
            }
            app.terminate()
        }
    }

    @MainActor
    func testKanbanLandscapeKeepsActionsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.launch()
        XCTAssertTrue(app.buttons["board-theme-button"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let title = app.buttons["오늘 처리할 작업 빠르게 추가해보기 작업 편집"]
        XCTAssertTrue(scrollToHittable(title, in: app.scrollViews["board-accessibility-scroll"]))
        XCTAssertTrue(isHorizontallyContained(title, in: app.windows.firstMatch))
        addReferenceScreenshot(named: "kanban-landscape-card")
        title.tap()
        XCTAssertTrue(app.buttons["취소"].waitForExistence(timeout: 5))
        app.buttons["취소"].tap()
        let saved = app.buttons["saved-task-library-button"]
        XCTAssertTrue(scrollToHittable(saved, in: app.scrollViews["board-accessibility-scroll"]))
        saved.tap()
        XCTAssertTrue(app.navigationBars["저장한 작업"].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "kanban-landscape-saved-tasks")
    }

    @MainActor
    func testSavedTaskLibrarySaveReuseAndManage() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let title = "재사용할 주간 보고"
        let field = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText(title)
        app.buttons["작업 추가"].tap()
        let menu = app.buttons["\(title) 작업 메뉴"]
        XCTAssertTrue(scrollToHittable(menu, in: app))
        menu.tap()
        app.buttons["자주 쓰는 작업으로 저장"].tap()
        let library = app.buttons["saved-task-library-button"]
        XCTAssertTrue(scrollToHittable(library, in: app))
        library.tap()
        let add = app.buttons["\(title) 추가"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        let favorite = app.buttons["\(title) 즐겨찾기 추가"]
        let savedMenu = app.buttons["\(title) 저장 메뉴"]
        XCTAssertGreaterThanOrEqual(favorite.frame.width, 44)
        XCTAssertGreaterThanOrEqual(favorite.frame.height, 44)
        XCTAssertGreaterThanOrEqual(savedMenu.frame.width, 44)
        XCTAssertGreaterThanOrEqual(savedMenu.frame.height, 44)
        favorite.tap()
        savedMenu.tap()
        app.buttons["저장 내용 편집"].tap()
        let estimate = app.textFields["saved-task-estimate"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 5))
        estimate.tap()
        estimate.typeText("35")
        XCTAssertTrue(app.staticTexts["예상 시간"].exists)
        XCTAssertTrue(app.staticTexts["분"].exists)
        let checklist =
            app.textViews["saved-task-checklist"].exists
            ? app.textViews["saved-task-checklist"] : app.textFields["saved-task-checklist"]
        checklist.tap()
        checklist.typeText("자료 모으기\n초안 검토")
        addReferenceScreenshot(named: "saved-task-editor-ready")
        app.buttons["saved-task-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["체크리스트 2개"].waitForExistence(timeout: 5))
        let search = app.textFields["saved-task-search"]
        search.tap()
        search.typeText("초안")
        XCTAssertTrue(add.exists)
        add.tap()
        XCTAssertTrue(app.buttons["\(title) 추가됨"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["\(title) 추가됨"].isEnabled)
        addReferenceScreenshot(named: "saved-task-library-added")
        app.buttons["닫기"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "\(title) 작업 편집").count, 2)
        // The library survives reopening; removal does not delete placed tasks.
        library.tap()
        XCTAssertTrue(app.buttons["\(title) 저장 메뉴"].waitForExistence(timeout: 5))
        app.buttons["\(title) 저장 메뉴"].tap()
        app.buttons["저장 목록에서 삭제"].tap()
        app.alerts.buttons["삭제"].tap()
        XCTAssertFalse(app.buttons["\(title) 추가"].exists)
        app.buttons["닫기"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "\(title) 작업 편집").count, 2)
    }

    @MainActor
    func testTaskMenuLibrarySaveFailureCanRetry() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-empty-board",
            "--ui-testing-library-save-failure-once",
            "--ui-testing-theme=appleSystem"
        ]
        app.launch()

        let title = "실패 후 다시 저장할 작업"
        let input = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText(title)
        app.buttons["작업 추가"].tap()

        let menu = app.buttons["\(title) 작업 메뉴"]
        XCTAssertTrue(scrollToHittable(menu, in: app))
        menu.tap()
        XCTAssertTrue(app.buttons["작업 편집"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["자주 쓰는 작업으로 저장"].exists)
        XCTAssertTrue(app.buttons["작업 삭제"].exists)
        addReferenceScreenshot(named: "task-menu-library-actions")
        app.buttons["자주 쓰는 작업으로 저장"].tap()

        let failure = app.alerts["자주 쓰는 작업으로 저장하지 못했어요"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertTrue(
            failure.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "작업은 보드에 그대로 남아 있어요")
            ).firstMatch.exists
        )
        XCTAssertTrue(failure.buttons["취소"].exists)
        XCTAssertTrue(failure.buttons["다시 시도"].exists)
        XCTAssertGreaterThanOrEqual(failure.buttons["취소"].frame.height, 44)
        XCTAssertGreaterThanOrEqual(failure.buttons["다시 시도"].frame.height, 44)
        addReferenceScreenshot(named: "task-library-save-failure")
        failure.buttons["다시 시도"].tap()

        let notice = app.descendants(matching: .any)["board-status-notice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains(title))
        XCTAssertTrue(notice.label.contains("자주 쓰는 작업으로 저장했어요"))
        XCTAssertTrue(app.buttons["\(title) 작업 편집"].exists)
        let library = app.buttons["saved-task-library-button"]
        XCTAssertTrue(scrollToHittable(library, in: app))
        library.tap()
        XCTAssertTrue(app.buttons["\(title) 추가"].waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "task-library-save-retry-completed")
    }

    @MainActor
    func testSavedTaskLibraryLargeTextAndSelectedDate() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-accessibility-text-size"]
        app.terminate()
        app.launch()
        // Prepare the fixture before checking layout; cold launch is a separate test.
        app.terminate()
        app.launch()
        let nextDay = app.buttons["다음 날짜"]
        XCTAssertTrue(nextDay.waitForExistence(timeout: 15))
        nextDay.tap()
        let date = app.staticTexts["board-date-title"].label
        let library = app.buttons["saved-task-library-button"]
        XCTAssertTrue(scrollToHittable(library, in: app))
        library.tap()
        XCTAssertTrue(app.navigationBars["저장한 작업"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["saved-task-target-date"].firstMatch.label.contains(date))
        XCTAssertGreaterThan(app.descendants(matching: .any)["saved-task-target-date"].firstMatch.frame.height, 32)
        addReferenceScreenshot(named: "saved-task-library-large-text-date")
        app.buttons["saved-task-create"].tap()
        let title = "필요한 날에 꺼내 쓰는 충분히 긴 작업 제목"
        let titleField = app.textFields["saved-task-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(title)
        app.buttons["saved-task-keyboard-dismiss"].tap()
        let estimate = app.textFields["saved-task-estimate"]
        XCTAssertTrue(scrollToHittable(estimate, in: app))
        estimate.tap()
        estimate.typeText("35")
        app.buttons["saved-task-keyboard-dismiss"].tap()
        XCTAssertTrue(app.staticTexts["예상 시간"].exists)
        XCTAssertTrue(app.staticTexts["분"].exists)
        XCTAssertTrue(isHorizontallyContained(estimate, in: app.windows.firstMatch))
        addReferenceScreenshot(named: "saved-task-estimate-large-text")
        app.buttons["saved-task-editor-save"].tap()
        let add = app.buttons["\(title) 추가"]
        XCTAssertTrue(scrollToHittable(add, in: app.scrollViews["saved-task-list"]))
        XCTAssertTrue(isHorizontallyContained(add, in: app.windows.firstMatch))
        let favorite = app.buttons["\(title) 즐겨찾기 추가"]
        let savedMenu = app.buttons["\(title) 저장 메뉴"]
        XCTAssertGreaterThanOrEqual(favorite.frame.width, 44)
        XCTAssertGreaterThanOrEqual(favorite.frame.height, 44)
        XCTAssertGreaterThanOrEqual(savedMenu.frame.width, 44)
        XCTAssertGreaterThanOrEqual(savedMenu.frame.height, 44)
        addReferenceScreenshot(named: "saved-task-library-large-text")
        add.tap()
        app.buttons["닫기"].tap()
        XCTAssertEqual(app.staticTexts["board-date-title"].label, date)
        XCTAssertTrue(scrollToHittable(app.buttons["\(title) 작업 편집"], in: app))
    }

    @MainActor
    func testMemoPreservesEditsAcrossTabsAndBackgroundReturn() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.launch()
        let memoTab =
            UIDevice.current.userInterfaceIdiom == .pad
            ? app.buttons["메모"].firstMatch : app.tabBars.buttons["메모"]
        XCTAssertTrue(memoTab.waitForExistence(timeout: 15))
        memoTab.tap()
        createMemo(in: app)
        let editor = app.textViews["메모 내용"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let content = "복귀 검증 메모\n화면을 옮겨도 남는 내용"
        editor.tap()
        editor.typeText(content)
        // Backgrounding must flush the pending debounce without relying on a tab save.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, content)
        app.navigationBars.buttons["메모"].firstMatch.tap()
        app.buttons["칸반"].firstMatch.tap()
        memoTab.tap()
        let row = app.buttons["복귀 검증 메모"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertEqual(editor.value as? String, content)
        editor.tap()
        editor.typeText("\n추가로 저장한 내용")
        let revisedContent = editor.value as? String
        XCTAssertTrue(revisedContent?.contains("추가로 저장한 내용") == true)
        app.navigationBars.buttons["메모"].firstMatch.tap()
        app.buttons["캘린더"].firstMatch.tap()
        memoTab.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertEqual(editor.value as? String, revisedContent)
        addReferenceScreenshot(named: "memo-tab-and-background-return")
    }

    @MainActor
    func testPrimaryTabNavigation() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-archive-mode", "activity",
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
            "board-status-filter-done",
        ] {
            let statusFilter = app.buttons[identifier]
            XCTAssertTrue(statusFilter.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(statusFilter.frame.height, 44)
        }
        for identifier in [
            "board-status-filter-doing",
            "board-status-filter-done",
            "board-status-filter-todo",
        ] {
            let statusFilter = app.buttons[identifier]
            statusFilter.tap()
            XCTAssertTrue(waitForSelected(statusFilter))
        }

        calendarTab.tap()
        XCTAssertTrue(app.buttons["일정 추가"].waitForExistence(timeout: 10))

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

        XCTAssertTrue(app.buttons["archive-overview-disclosure"].label.hasPrefix("완료 활동 · "))
        XCTAssertTrue(app.buttons["archive-overview-disclosure"].label.hasSuffix("일 연속"))
        XCTAssertFalse(app.segmentedControls["archive-overview-mode"].exists)
        XCTAssertFalse(app.staticTexts["선택 기간 작업 요약"].exists)

        boardTab.tap()
        XCTAssertTrue(
            app.textFields["해당 날짜에 할 일 입력"]
                .waitForExistence(timeout: 10)
        )
    }

    @MainActor
    func testFocusEstimatePauseResumeAndBreakFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem"]
        app.launch()
        createFocusTask(in: app, title: "오늘 처리할 작업 빠르게 추가해보기", minutes: 30)
        let entry = app.buttons["오늘 처리할 작업 빠르게 추가해보기 집중 시작"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCTAssertTrue(scrollToHittable(entry, in: app.scrollViews["board-accessibility-scroll"]))
        entry.tap()
        let scroll = app.scrollViews["focus-content-scroll"]
        let duration = app.staticTexts["focus-duration-value"]
        XCTAssertTrue(duration.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["focus-selected-task"].label, "오늘 처리할 작업 빠르게 추가해보기")
        XCTAssertEqual(duration.label, "30분")
        addReferenceScreenshot(named: "focus-light-estimate-setup")
        let preset = app.buttons["focus-preset-15"]
        XCTAssertTrue(scrollToHittable(preset, in: scroll))
        preset.tap()
        XCTAssertEqual(duration.label, "15분")
        let estimate = app.buttons["focus-use-estimate"]
        XCTAssertTrue(scrollToHittable(estimate, in: scroll))
        estimate.tap()
        XCTAssertEqual(duration.label, "30분")
        let start = app.buttons["focus-start"]
        XCTAssertTrue(scrollToHittable(start, in: scroll))
        start.tap()
        let timer = app.descendants(matching: .any)["focus-timer"].firstMatch
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["이번 집중 30분"].exists)
        addReferenceScreenshot(named: "focus-light-running")
        let pause = app.buttons["focus-pause-resume"]
        XCTAssertTrue(scrollToHittable(pause, in: scroll))
        pause.tap()
        XCTAssertTrue(app.staticTexts["멈춘 시간은 집중 기록에 포함되지 않아요."].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "focus-light-paused")
        app.buttons["focus-close"].tap()
        let reopen = app.buttons["focus-active-launcher"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 10))
        reopen.tap()
        XCTAssertTrue(app.staticTexts["멈춘 시간은 집중 기록에 포함되지 않아요."].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(pause, in: scroll))
        pause.tap()
        let stop = app.buttons["focus-stop"]
        XCTAssertTrue(scrollToHittable(stop, in: scroll))
        stop.tap()
        XCTAssertTrue(app.alerts["집중을 마칠까요?"].waitForExistence(timeout: 5))
        app.alerts.buttons["계속 집중"].tap()
        XCTAssertTrue(timer.exists)
        stop.tap()
        app.alerts.buttons["집중 마치기"].tap()
        XCTAssertTrue(app.staticTexts["focus-completion-title"].waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "focus-light-completed")
        let rest = app.buttons["focus-start-break"]
        XCTAssertTrue(scrollToHittable(rest, in: scroll))
        rest.tap()
        XCTAssertTrue(app.staticTexts["이번 휴식 5분"].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "focus-light-break")
        XCTAssertTrue(scrollToHittable(stop, in: scroll))
        stop.tap()
        let again = app.buttons["focus-start-again"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertTrue(again.label.contains("30분"))
    }

    @MainActor
    func testFocusDarkLargeTextAndLandscape() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=midnightBlue", "--ui-testing-accessibility-text-size",
        ]
        app.launch()
        // Xcode's first target launch can omit the fixture arguments.
        // Relaunch so this case exercises an empty board at accessibility size.
        app.terminate()
        app.launch()
        createFocusTask(in: app, title: "오늘 처리할 작업 빠르게 추가해보기", minutes: 30)
        let entry = app.buttons["오늘 처리할 작업 빠르게 추가해보기 집중 시작"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCTAssertTrue(scrollToHittable(entry, in: app.scrollViews["board-accessibility-scroll"]))
        entry.tap()
        let scroll = app.scrollViews["focus-content-scroll"]
        XCTAssertTrue(app.staticTexts["focus-selected-task"].waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "focus-dark-AX5-setup")
        let start = app.buttons["focus-start"]
        XCTAssertTrue(scrollToHittable(start, in: scroll))
        XCTAssertTrue(isHorizontallyContained(start, in: app.windows.firstMatch))
        start.tap()
        let timer = app.descendants(matching: .any)["focus-timer"].firstMatch
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(
            timer.frame.minY, scroll.frame.minY - 1,
            "집중을 시작하면 화면 위쪽부터 타이머를 보여줘야 합니다")
        addReferenceScreenshot(named: "focus-dark-AX5-running")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let pause = app.buttons["focus-pause-resume"]
        XCTAssertTrue(scrollToHittable(pause, in: scroll))
        XCTAssertTrue(isHorizontallyContained(pause, in: app.windows.firstMatch))
        XCTAssertLessThanOrEqual(
            pause.frame.maxY, app.buttons["focus-stop"].frame.minY + 1,
            "큰 글자에서는 주요 버튼을 세로로 배치해야 합니다")
        pause.tap()
        XCTAssertTrue(pause.label.contains("다시 집중"))
        let labelTransition = expectation(description: "일시정지 라벨 전환 후 화면 확인")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { labelTransition.fulfill() }
        wait(for: [labelTransition], timeout: 2)
        addReferenceScreenshot(named: "focus-dark-AX5-landscape-paused")
        let complete = app.buttons["focus-complete-task"]
        XCTAssertTrue(scrollToHittable(complete, in: scroll))
        complete.tap()
        XCTAssertTrue(app.alerts["작업도 완료할까요?"].waitForExistence(timeout: 5))
        app.alerts.buttons["작업 완료"].tap()
        XCTAssertTrue(app.staticTexts["작업까지 완료했어요"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["focus-start-again"].exists)
        addReferenceScreenshot(named: "focus-dark-AX5-task-completed")
    }

    @MainActor
    func testFocusTaskPickerDefaultAndEstimateOverride() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=charcoalRose"]
        app.launch()
        let field = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("예상 없는 집중 작업")
        app.buttons["작업 추가"].tap()
        let entry = app.buttons["예상 없는 집중 작업 집중 시작"]
        XCTAssertTrue(scrollToHittable(entry, in: app.scrollViews["board-accessibility-scroll"]))
        entry.tap()
        let duration = app.staticTexts["focus-duration-value"]
        XCTAssertTrue(duration.waitForExistence(timeout: 10))
        XCTAssertEqual(duration.label, "25분")
        app.buttons["focus-change-task"].tap()
        let search = app.textFields["focus-task-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("카드 상태 컨트롤")
        let task = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "카드 상태 컨트롤 확인")).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "focus-task-picker-search")
        task.tap()
        XCTAssertEqual(duration.label, "45분")
        let scroll = app.scrollViews["focus-content-scroll"]
        let preset = app.buttons["focus-preset-15"]
        XCTAssertTrue(scrollToHittable(preset, in: scroll))
        preset.tap()
        XCTAssertTrue(scrollToHittable(app.buttons["focus-change-task"], in: scroll))
        app.buttons["focus-change-task"].tap()
        app.navigationBars["집중할 작업"].buttons["닫기"].tap()
        XCTAssertEqual(duration.label, "15분")
        addReferenceScreenshot(named: "focus-charcoal-custom-duration")
    }

    @MainActor
    func testInactiveFocusEntryLivesInsideDoingList() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-live-activity-two-doing",
        ]
        app.launch()

        let doingFilter = app.buttons["board-status-filter-doing"]
        XCTAssertTrue(doingFilter.waitForExistence(timeout: 15))
        doingFilter.tap()
        XCTAssertTrue(waitForSelected(doingFilter))

        let doingFocusLauncher = app.descendants(matching: .any)[
            "board-doing-focus-launcher"
        ]
        XCTAssertTrue(doingFocusLauncher.waitForExistence(timeout: 10))
        XCTAssertTrue(doingFocusLauncher.isHittable)
        XCTAssertFalse(app.buttons["집중 모드 열기"].exists)
        addReferenceScreenshot(named: "iPhone-Doing-Focus-Launcher")
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
            "--ui-testing-archive-mode", "activity",
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
        let addEventButton = app.buttons["일정 추가"]
        XCTAssertTrue(addEventButton.waitForExistence(timeout: 10))
        addEventButton.tap()
        let addEventNavigationBar = app.navigationBars["일정 추가"]
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
    func testIPadNarrowWindowKeepsSavedTaskEditorReachable() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad 창 크기 조절 검증")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem"]
        app.terminate()
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        let originalFrame = window.frame
        continueAfterFailure = true
        defer {
            app.terminate()
            app.launch()
            let currentFrame = window.frame
            if currentFrame.width < originalFrame.width - 100 {
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
                    .press(
                        forDuration: 0.3,
                        thenDragTo: window.coordinate(withNormalizedOffset: .zero)
                            .withOffset(
                                CGVector(
                                    dx: originalFrame.maxX - currentFrame.minX - 5,
                                    dy: originalFrame.maxY - currentFrame.minY - 5)))
            }
            XCUIDevice.shared.orientation = .portrait
            continueAfterFailure = false
        }
        addReferenceScreenshot(named: "iPad-window-before-resizing")
        if originalFrame.width > 600 {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
                .press(forDuration: 0.3, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.9)))
        }
        let narrowed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                window.frame.width <= 600
            }, object: window)
        let resizeResult = XCTWaiter.wait(for: [narrowed], timeout: 5)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "iPad-narrow-window-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        addReferenceScreenshot(named: "iPad-window-after-resizing")
        guard resizeResult == .completed else { return XCTFail("실제 창 너비가 줄었는지 확인하지 못했습니다") }
        let library = app.buttons["saved-task-library-button"]
        XCTAssertTrue(scrollToHittable(library, in: app))
        library.tap()
        app.buttons["saved-task-create"].tap()
        let title = app.textFields["saved-task-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("좁은 창에서도 제목과 예상 시간을 확인하는 작업")
        let estimate = app.textFields["saved-task-estimate"]
        let keyboardDismiss = app.buttons["saved-task-keyboard-dismiss"]
        // The keyboard accessory is a separate window. Its visible bounds
        // must be considered even when XCTest reports a covered field hittable.
        var lastScrollWasUp = true
        for step in 0..<8 {
            let visibleBottom = keyboardDismiss.exists ? keyboardDismiss.frame.minY - 8 : window.frame.maxY - 24
            let visibleTop = app.navigationBars["새로 저장"].frame.maxY + 12
            if estimate.exists,
                estimate.frame.minY > visibleTop,
                estimate.frame.maxY < visibleBottom
            {
                break
            }
            let form = app.collectionViews.firstMatch
            let scrollUp = estimate.exists ? estimate.frame.maxY >= visibleBottom : !lastScrollWasUp
            let distance =
                estimate.exists
                ? (scrollUp ? estimate.frame.maxY - visibleBottom + 24 : visibleTop - estimate.frame.minY + 24)
                : 60
            let delta = min(80, max(35, distance))
            let startY = scrollUp ? visibleBottom - 20 : visibleTop + 20
            let endY = scrollUp ? max(visibleTop + 20, startY - delta) : min(visibleBottom - 20, startY + delta)
            let estimateDescription = estimate.exists ? String(describing: estimate.frame) : "absent"
            let geometry = XCTAttachment(
                string: "step=\(step) estimate=\(estimateDescription) visible=\(visibleTop)...\(visibleBottom) gesture=\(startY)->\(endY)")
            geometry.name = "iPad-narrow-editor-scroll-\(step)"
            geometry.lifetime = .keepAlways
            add(geometry)
            form.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: form.frame.width / 2, dy: startY - form.frame.minY))
                .press(
                    forDuration: 0.1,
                    thenDragTo: form.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: form.frame.width / 2, dy: endY - form.frame.minY)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
            lastScrollWasUp = scrollUp
        }
        let visibleBottom = keyboardDismiss.exists ? keyboardDismiss.frame.minY - 8 : window.frame.maxY - 24
        let visibleTop = app.navigationBars["새로 저장"].frame.maxY + 12
        guard estimate.exists, estimate.frame.minY > visibleTop, estimate.frame.maxY < visibleBottom else {
            return XCTFail("예상 시간 입력란이 키보드 도구 위로 스크롤되지 않았습니다")
        }
        addReferenceScreenshot(named: "iPad-narrow-editor-keyboard-scroll")
        estimate.tap()
        estimate.typeText("35")
        guard estimate.value as? String == "35" else { return XCTFail("예상 시간 입력이 반영되지 않았습니다") }
        keyboardDismiss.tap()
        XCTAssertTrue(app.staticTexts["예상 시간"].exists)
        XCTAssertTrue(isHorizontallyContained(estimate, in: window))
        addReferenceScreenshot(named: "iPad-narrow-saved-task-editor")
        app.buttons["saved-task-editor-save"].tap()
        XCTAssertTrue(app.buttons["좁은 창에서도 제목과 예상 시간을 확인하는 작업 추가"].waitForExistence(timeout: 5))
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
            "--ui-testing-archive-mode", "activity",
        ]
        app.terminate()
        app.launch()
        // Xcode's first target launch can precede the fixture arguments.
        // This checks layout with a prepared fixture, not cold-start behavior.
        app.terminate()
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        let dateTitle = app.staticTexts["board-date-title"]
        XCTAssertTrue(dateTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(isHorizontallyContained(dateTitle, in: window))
        let eventSummary = app.staticTexts["board-event-summary"].firstMatch
        XCTAssertTrue(eventSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(isHorizontallyContained(eventSummary, in: window))
        XCTAssertTrue(
            app.buttons["board-status-filter-menu"].waitForExistence(timeout: 5)
        )
        addReferenceScreenshot(named: "iPhone-Board-Accessibility-Header")

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
        let monthTitle = app.staticTexts["calendar-month-title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(isHorizontallyContained(monthTitle, in: window))
        let addEventButton = app.buttons["일정 추가"]
        XCTAssertTrue(addEventButton.waitForExistence(timeout: 10))
        XCTAssertTrue(addEventButton.isHittable)
        addReferenceScreenshot(named: "iPhone-Calendar-Accessibility-Text")

        tabBar.buttons["기록"].tap()
        let archiveFilter = app.buttons["기록 필터"]
        XCTAssertTrue(archiveFilter.waitForExistence(timeout: 10))
        XCTAssertTrue(archiveFilter.isHittable)
        let boardButton = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "archive-open-day-"
            )
        ).firstMatch
        XCTAssertTrue(scrollToHittable(boardButton, in: app))
        XCTAssertTrue(boardButton.isHittable)
        addReferenceScreenshot(named: "iPhone-Archive-Accessibility-Text")

        tabBar.buttons["메모"].tap()
        let newMemoButton = app.buttons["새 메모"]
        XCTAssertTrue(newMemoButton.waitForExistence(timeout: 10))
        XCTAssertTrue(newMemoButton.isHittable)
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
    func testArchiveShowsTasksWithoutReviewAndOpensDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-event-history-fixtures", "--ui-testing-archive-collapsed"]
        app.launch()
        // Xcode's initial target launch can omit arguments; relaunch with the requested fixtures.
        app.terminate()
        app.launch()
        app.tabBars.firstMatch.buttons["기록"].tap()
        let overview = app.buttons["archive-overview-disclosure"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        let loadedSummary = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "완료 활동 · ", "일 연속"),
            object: overview
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loadedSummary], timeout: 10), .completed)
        let summary = overview.label
        let graph = app.descendants(matching: .any)["activity-graph"].firstMatch
        if overview.value as? String == "펼침" { overview.tap() }
        XCTAssertEqual(overview.value as? String, "접힘")
        XCTAssertFalse(graph.exists)
        addReferenceScreenshot(named: "archive-completion-summary-collapsed")
        overview.tap()
        XCTAssertTrue(graph.waitForExistence(timeout: 5))
        XCTAssertEqual(overview.label, summary)
        XCTAssertEqual(overview.value as? String, "펼침")
        addReferenceScreenshot(named: "archive-completion-summary-expanded")
        overview.tap()
        XCTAssertTrue(graph.waitForNonExistence(timeout: 5))
        XCTAssertEqual(overview.label, summary)

        let task = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "archive-task-", "UI 검증: 지연 완료"
            )
        ).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertTrue(task.isHittable, "회고나 펼치기 없이 작업이 보여야 합니다")
        let todayDayKey = localDayKey(Date())
        XCTAssertTrue(app.buttons["archive-add-review-\(todayDayKey)"].exists)
        addReferenceScreenshot(named: "archive-tasks-without-review")
        task.tap()
        XCTAssertTrue(app.navigationBars["작업 기록"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["task-record-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task-record-title"].label, "UI 검증: 지연 완료")
        XCTAssertTrue(app.staticTexts["task-record-created"].exists)
        XCTAssertFalse(app.textFields["제목"].exists)
        addReferenceScreenshot(named: "archive-task-record-read-only")
        app.navigationBars["작업 기록"].buttons["닫기"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))

        app.tabBars.firstMatch.buttons["칸반"].tap()
        app.tabBars.firstMatch.buttons["기록"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertEqual(overview.value as? String, "접힘")
    }

    @MainActor
    func testTaskRecordRevealsLongHistoryAndOpensRemainingActivityWithoutTask() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-daily-activity-fixtures",
            "--ui-testing-task-record-edge-fixtures",
            "--ui-testing-archive-collapsed",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["기록"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["기록"].firstMatch.tap()

        var search =
            app.textFields["archive-search-field"].exists
            ? app.textFields["archive-search-field"] : app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("긴 활동 이력 확인")
        let longHistory = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "archive-task-", "긴 활동 이력 확인"
            )
        ).firstMatch
        XCTAssertTrue(longHistory.waitForExistence(timeout: 10))
        longHistory.tap()

        XCTAssertTrue(app.navigationBars["작업 기록"].waitForExistence(timeout: 10))
        let events = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@", "task-record-event-"
            ))
        XCTAssertEqual(events.count, 20)
        let moreHistory = app.buttons["task-record-more-history"]
        XCTAssertTrue(scrollToHittable(moreHistory, in: app))
        addReferenceScreenshot(named: "task-record-long-history-before-more")
        moreHistory.tap()
        XCTAssertTrue(moreHistory.waitForNonExistence(timeout: 5))
        XCTAssertEqual(events.count, 26)
        addReferenceScreenshot(named: "task-record-long-history-after-more")
        app.navigationBars["작업 기록"].buttons["닫기"].tap()

        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-daily-activity-fixtures",
            "--ui-testing-archive-collapsed",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["기록"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["기록"].firstMatch.tap()
        search =
            app.textFields["archive-search-field"].exists
            ? app.textFields["archive-search-field"] : app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("현재 작업 정보 없음")
        let remainingActivity = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "archive-task-", "현재 작업 정보 없음"
            )
        ).firstMatch
        XCTAssertTrue(remainingActivity.waitForExistence(timeout: 10))
        XCTAssertTrue(remainingActivity.isEnabled)
        remainingActivity.tap()

        XCTAssertTrue(app.navigationBars["작업 기록"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task-record-title"].label, "현재 작업 정보 없음")
        XCTAssertTrue(app.staticTexts["task-record-missing-task"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["task-record-total-focus"].label.contains("15분"))
        XCTAssertFalse(app.textFields["제목"].exists)
        addReferenceScreenshot(named: "task-record-remaining-activity-without-task")
        app.navigationBars["작업 기록"].buttons["닫기"].tap()
    }

    @MainActor
    func testTaskRecordLoadFailureRetriesIntoReadOnlyRecord() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-daily-activity-fixtures",
            "--ui-testing-task-record-load-failure-once",
            "--ui-testing-archive-collapsed",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["기록"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["기록"].firstMatch.tap()

        let search =
            app.textFields["archive-search-field"].exists
            ? app.textFields["archive-search-field"] : app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("영어 공부")
        let english = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "archive-task-", "영어 공부"
            )
        ).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 10))
        english.tap()

        XCTAssertTrue(app.navigationBars["작업 기록"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["작업 기록을 불러오지 못했어요"].waitForExistence(timeout: 10))
        let retry = app.buttons["task-record-retry"]
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(retry.isHittable)
        XCTAssertFalse(app.staticTexts["task-record-title"].exists)
        addReferenceScreenshot(named: "task-record-load-failure")

        retry.tap()
        let title = app.staticTexts["task-record-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "영어 공부")
        XCTAssertFalse(app.textFields["제목"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["task-record-total-progress"].label.contains("30분"))
        XCTAssertTrue(app.descendants(matching: .any)["task-record-total-focus"].label.contains("25분"))
        addReferenceScreenshot(named: "task-record-after-load-retry")
        app.navigationBars["작업 기록"].buttons["닫기"].tap()
        XCTAssertTrue(english.waitForExistence(timeout: 5))
    }

    @MainActor
    func testDailyActivityWithoutReviewSearchAndDateNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-activity-fixtures", "--ui-testing-archive-collapsed"]
        app.launch()
        let tab = app.buttons["기록"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        let taskPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "archive-task-")
        let englishPredicate = NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "archive-task-", "영어 공부")
        let proposal = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "archive-task-", "기획서 초안 마무리"
            )
        ).firstMatch
        XCTAssertTrue(proposal.waitForExistence(timeout: 15))
        XCTAssertTrue(proposal.isHittable)
        let english = app.buttons.matching(englishPredicate).firstMatch
        XCTAssertTrue(english.exists)
        XCTAssertTrue(english.label.contains("진행 상태 30분"))
        XCTAssertTrue(english.label.contains("집중 25분"))
        addReferenceScreenshot(named: "daily-activity-no-review-list")

        let today = localDayKey(Date())
        app.buttons["archive-open-day-\(today)"].tap()
        let detail = app.descendants(matching: .any)["archive-day-detail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        let allTasks = detail.buttons.matching(taskPredicate)
        XCTAssertTrue(allTasks.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(allTasks.count, 4)
        addReferenceScreenshot(named: "daily-activity-day-detail")
        app.buttons["이전 날짜"].tap()
        let focusOnly = detail.buttons.matching(NSPredicate(format: "label CONTAINS %@", "집중해서 책 읽기")).firstMatch
        XCTAssertTrue(focusOnly.waitForExistence(timeout: 10))
        XCTAssertTrue(focusOnly.label.contains("집중 25분"))
        app.buttons["이전 날짜"].tap()
        let progressOnly = detail.buttons.matching(NSPredicate(format: "label CONTAINS %@", "디자인 초안")).firstMatch
        XCTAssertTrue(progressOnly.waitForExistence(timeout: 10))
        XCTAssertTrue(progressOnly.label.contains("진행 상태 45분"))
        addReferenceScreenshot(named: "daily-activity-progress-only-day")
        app.navigationBars["하루 기록"].buttons["닫기"].tap()

        let search =
            app.textFields["archive-search-field"].exists
            ? app.textFields["archive-search-field"] : app.searchFields.firstMatch
        search.tap()
        search.typeText("영어")
        XCTAssertTrue(app.staticTexts["듣기 연습과 새 표현 정리"].waitForExistence(timeout: 10))
        XCTAssertTrue(english.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(englishPredicate).count, 1)
        addReferenceScreenshot(named: "daily-activity-search")
        search.typeText("없는기록")
        XCTAssertTrue(app.staticTexts["검색 결과 없음"].waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "daily-activity-empty-search")
        app.buttons["검색 조건 초기화"].tap()
        XCTAssertTrue(proposal.waitForExistence(timeout: 10))
    }

    @MainActor
    func testDailyActivityOpensReadOnlyTaskRecordFromDayDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-activity-fixtures", "--ui-testing-archive-collapsed"]
        app.launch()
        app.buttons["기록"].firstMatch.tap()
        let day = app.buttons["archive-open-day-\(localDayKey(Date()))"]
        XCTAssertTrue(day.waitForExistence(timeout: 15))
        day.tap()
        let english = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "archive-task-", "영어 공부"))
            .firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 10))
        english.tap()
        XCTAssertTrue(app.navigationBars["작업 기록"].waitForExistence(timeout: 10))
        let dayProgress = app.descendants(matching: .any)["task-record-day-progress"].firstMatch
        let dayFocus = app.descendants(matching: .any)["task-record-day-focus"].firstMatch
        XCTAssertTrue(dayProgress.waitForExistence(timeout: 10))
        XCTAssertTrue(dayProgress.label.contains("30분"))
        XCTAssertTrue(dayFocus.label.contains("25분"))
        XCTAssertEqual(app.staticTexts["task-record-title"].label, "영어 공부")
        XCTAssertFalse(app.textFields["제목"].exists)
        XCTAssertFalse(app.buttons["이 작업으로 집중 시작"].exists)
        addReferenceScreenshot(named: "daily-activity-task-record-summary")
        XCTAssertTrue(scrollToHittable(app.staticTexts["활동 이력"], in: app))
        XCTAssertTrue(app.staticTexts["첫 진행 시작"].exists)
        addReferenceScreenshot(named: "daily-activity-task-record-history")
        app.navigationBars["작업 기록"].buttons["닫기"].tap()
        XCTAssertTrue(app.navigationBars["하루 기록"].exists)
        app.buttons["이전 날짜"].tap()
        let yesterdayTask = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "archive-task-", "집중해서 책 읽기"
            )
        ).firstMatch
        XCTAssertTrue(yesterdayTask.waitForExistence(timeout: 10))
        yesterdayTask.tap()
        XCTAssertTrue(dayFocus.waitForExistence(timeout: 10))
        XCTAssertTrue(dayFocus.label.contains("25분"), "이동한 날짜의 활동을 보여야 합니다")
        addReferenceScreenshot(named: "task-record-after-day-navigation")
        app.navigationBars["작업 기록"].buttons["닫기"].tap()
    }

    @MainActor
    func testDailyActivityLargeTextAndIPadLayout() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-daily-activity-fixtures", "--ui-testing-archive-collapsed",
            "--ui-testing-accessibility-text-size",
        ]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        app.buttons["기록"].firstMatch.tap()
        let overview = app.buttons["archive-overview-disclosure"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        XCTAssertTrue(isHorizontallyContained(overview, in: app.windows.firstMatch))
        XCTAssertGreaterThanOrEqual(overview.frame.height, 44)
        overview.tap()
        let graph = app.descendants(matching: .any)["activity-graph"].firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 10))
        addReferenceScreenshot(named: "archive-completion-summary-large-text-expanded")
        overview.tap()
        XCTAssertTrue(graph.waitForNonExistence(timeout: 5))
        let proposal = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "archive-task-", "기획서 초안 마무리")
        ).firstMatch
        XCTAssertTrue(proposal.waitForExistence(timeout: 15))
        XCTAssertTrue(isHorizontallyContained(proposal, in: app.windows.firstMatch))
        XCTAssertTrue(scrollToHittable(proposal, in: app))
        addReferenceScreenshot(named: "daily-activity-large-text-portrait")
        proposal.tap()
        XCTAssertTrue(app.navigationBars["작업 기록"].waitForExistence(timeout: 10))
        let recordTitle = app.staticTexts["task-record-title"]
        XCTAssertTrue(recordTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(isHorizontallyContained(recordTitle, in: app.windows.firstMatch))
        XCTAssertFalse(app.textFields["제목"].exists)
        addReferenceScreenshot(named: "task-record-large-text")
        app.navigationBars["작업 기록"].buttons["닫기"].tap()
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(proposal.waitForExistence(timeout: 10))
            XCTAssertTrue(isHorizontallyContained(proposal, in: app.windows.firstMatch))
            addReferenceScreenshot(named: "daily-activity-ipad-landscape")
        }
        let today = localDayKey(Date())
        XCTAssertTrue(scrollToHittable(app.buttons["archive-open-day-\(today)"], in: app))
        app.buttons["archive-open-day-\(today)"].tap()
        let detail = app.descendants(matching: .any)["archive-day-detail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        let next = app.buttons["다음 날짜"]
        XCTAssertTrue(next.isHittable)
        XCTAssertTrue(isHorizontallyContained(next, in: app.windows.firstMatch))
        addReferenceScreenshot(named: "daily-activity-large-text-detail")
    }

    @MainActor
    func testDailyActivityLoadFailureCanRetryWithoutShowingEmptyState() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-daily-activity-fixtures", "--ui-testing-archive-collapsed", "--ui-testing-archive-fail-once",
        ]
        app.launch()
        app.buttons["기록"].firstMatch.tap()
        let retry = app.buttons["다시 시도"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["보관된 기록 없음"].exists)
        XCTAssertFalse(app.buttons["이전 기록 더 보기"].exists)
        addReferenceScreenshot(named: "daily-activity-load-error")
        retry.tap()
        let task = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "archive-task-", "기획서 초안 마무리")
        ).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 10))
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

        XCTAssertTrue(app.buttons["board-theme-button"].isHittable)

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
    func testKanbanEmptyStateGuidanceAndQuickAdd() {
        let app = launchKanbanFlowApp()
        XCTAssertTrue(app.staticTexts["첫 할 일을 추가해 보세요"].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "kanban-empty-todo")
        for (status, title) in [("doing", "진행 중인 작업이 없어요"), ("done", "완료한 작업이 없어요")] {
            app.buttons["board-status-filter-\(status)"].tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["board-empty-add-task"].exists)
            addReferenceScreenshot(named: "kanban-empty-\(status)")
        }
        app.buttons["board-status-filter-todo"].tap()
        let add = app.buttons["board-empty-add-task"]
        XCTAssertTrue(scrollToHittable(add, in: app))
        add.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("빈 보드에서 시작한 작업")
        app.buttons["작업 추가"].tap()
        XCTAssertTrue(app.buttons["빈 보드에서 시작한 작업 작업 편집"].waitForExistence(timeout: 5))
        XCTAssertFalse(add.exists)
    }

    @MainActor
    func testKanbanEmptyColumnsAlignOnIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("세 열 배치는 iPad에서 확인")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchKanbanFlowApp()
        let titles = ["첫 할 일을 추가해 보세요", "진행 중인 작업이 없어요", "완료한 작업이 없어요"]
            .map { app.staticTexts[$0] }
        XCTAssertTrue(app.descendants(matching: .any)["board-column-todo"].waitForExistence(timeout: 5))
        for title in titles {
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertTrue(isHorizontallyContained(title, in: app.windows.firstMatch))
            XCTAssertEqual(title.frame.minY, titles[0].frame.minY, accuracy: 1)
        }
        addReferenceScreenshot(named: "kanban-empty-ipad-columns")
    }

    @MainActor
    func testKanbanEmptyStateLargeTextKeepsAddReachable() {
        let app = launchKanbanFlowApp(additionalArguments: ["--ui-testing-accessibility-text-size"])
        let title = app.staticTexts["첫 할 일을 추가해 보세요"]
        let add = app.buttons["board-empty-add-task"]
        XCTAssertTrue(scrollToHittable(add, in: app.scrollViews["board-accessibility-scroll"]))
        XCTAssertTrue(isHorizontallyContained(title, in: app.windows.firstMatch))
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        addReferenceScreenshot(named: "kanban-empty-large-text")
        add.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("큰 글자에서 추가")
        let input = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertEqual(input.value as? String, "큰 글자에서 추가")
    }

    @MainActor
    func testBoardChecklistsDefaultOpenIndependentlyAcrossStatuses() {
        let app = launchKanbanFlowApp()
        let scroll = app.scrollViews["board-accessibility-scroll"]
        for (title, item) in [("첫 체크 작업", "충전기 챙기기"), ("둘째 체크 작업", "티켓 확인하기")] {
            let input = app.textFields["해당 날짜에 할 일 입력"]
            XCTAssertTrue(scrollTowardTopToHittable(input, in: scroll))
            addKanbanFlowTask(title, in: app)
            let edit = app.buttons["\(title) 작업 편집"]
            XCTAssertTrue(scrollToHittable(edit, in: scroll))
            edit.tap()
            let field = app.textFields["새 체크리스트 항목"]
            XCTAssertTrue(scrollToHittable(field, in: app))
            field.tap()
            field.typeText(item)
            app.buttons["저장"].tap()
            XCTAssertTrue(app.buttons["\(item) 체크리스트 항목"].waitForExistence(timeout: 5))
        }
        let firstDisclosure = app.buttons["첫 체크 작업-checklist-progress"]
        let secondDisclosure = app.buttons["둘째 체크 작업-checklist-progress"]
        XCTAssertTrue(scrollToHittable(firstDisclosure, in: scroll))
        XCTAssertTrue((firstDisclosure.value as? String)?.contains("펼쳐짐") == true)
        firstDisclosure.tap()
        XCTAssertTrue((firstDisclosure.value as? String)?.contains("접힘") == true)
        XCTAssertTrue(scrollToHittable(secondDisclosure, in: scroll))
        XCTAssertTrue((secondDisclosure.value as? String)?.contains("펼쳐짐") == true)
        addReferenceScreenshot(named: "kanban-checklists-independent")

        let doing = app.buttons["첫 체크 작업 진행 중 상태"]
        XCTAssertTrue(scrollToHittable(doing, in: scroll))
        doing.tap()
        let filter = app.buttons["board-status-filter-doing"]
        XCTAssertTrue(scrollTowardTopToHittable(filter, in: scroll))
        filter.tap()
        let item = app.buttons["충전기 챙기기 체크리스트 항목"]
        XCTAssertTrue(scrollToHittable(item, in: scroll))
        XCTAssertTrue((firstDisclosure.value as? String)?.contains("펼쳐짐") == true)
        item.tap()
        XCTAssertEqual(item.value as? String, "완료")
        XCTAssertTrue(waitForSelected(app.buttons["첫 체크 작업 진행 중 상태"]))
        addReferenceScreenshot(named: "kanban-checklist-doing-default-open")

        let done = app.buttons["첫 체크 작업 완료 상태"]
        XCTAssertTrue(scrollToHittable(done, in: scroll))
        done.tap()
        let doneFilter = app.buttons["board-status-filter-done"]
        XCTAssertTrue(scrollTowardTopToHittable(doneFilter, in: scroll))
        doneFilter.tap()
        XCTAssertTrue(scrollToHittable(item, in: scroll))
        XCTAssertEqual(item.value as? String, "완료")
        XCTAssertTrue((firstDisclosure.value as? String)?.contains("펼쳐짐") == true)
        addReferenceScreenshot(named: "kanban-checklist-done-default-open")
        firstDisclosure.tap()
        XCTAssertFalse(item.exists)
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
        XCTAssertEqual(progressChip.value as? String, "1개 완료, 전체 2개, 펼쳐짐")

        XCTAssertTrue(scrollToHittable(editButton, in: app))
        editButton.tap()
        XCTAssertTrue(scrollToHittable(newChecklistField, in: app))
        newChecklistField.tap()
        newChecklistField.typeText(cancelledItemTitle)
        app.buttons["체크리스트 항목 추가"].tap()
        app.buttons["취소"].tap()
        let discard = app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.buttons["변경사항 버리기"].tap()

        XCTAssertTrue(scrollToHittable(progressChip, in: app))
        XCTAssertEqual(progressChip.value as? String, "1개 완료, 전체 2개, 펼쳐짐")

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
        XCTAssertTrue(
            scrollToHittable(
                checklistDisclosure,
                in: boardTaskList,
                attempts: 20,
                velocity: .fast
            ))
        XCTAssertTrue((checklistDisclosure.value as? String)?.contains("펼쳐짐") == true)

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
    func testChecklistLoadFailureRetryAndReorderPersists() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-empty-board",
            "--ui-testing-checklist-load-failure-once",
        ]
        app.launch()

        let taskTitle = "Checklist retry and reorder"
        let firstTitle = "First checklist item"
        let secondTitle = "Second checklist item"
        let quickAdd = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 15))
        quickAdd.tap()
        quickAdd.typeText(taskTitle)
        app.buttons["작업 추가"].tap()

        let edit = app.buttons["\(taskTitle) 작업 편집"]
        XCTAssertTrue(scrollToHittable(edit, in: app))
        edit.tap()

        let retry = app.buttons["체크리스트 다시 불러오기"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["체크리스트를 불러오지 못했습니다"].exists)
        XCTAssertFalse(app.buttons["저장"].isEnabled)
        addReferenceScreenshot(named: "checklist-load-error")
        retry.tap()

        let newItem = app.textFields["새 체크리스트 항목"]
        XCTAssertTrue(newItem.waitForExistence(timeout: 5))
        newItem.tap()
        newItem.typeText("\(firstTitle)\n")
        newItem.tap()
        newItem.typeText("\(secondTitle)\n")
        app.buttons["task-detail-keyboard-dismiss"].tap()

        let first = app.textFields.matching(
            NSPredicate(format: "value == %@", firstTitle)
        ).firstMatch
        let second = app.textFields.matching(
            NSPredicate(format: "value == %@", secondTitle)
        ).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertLessThan(first.frame.midY, second.frame.midY)

        app.buttons["체크리스트 순서 편집"].tap()
        let window = app.windows.firstMatch
        let reorderHandleX = min(
            window.frame.maxX - 24,
            max(first.frame.maxX, second.frame.maxX) + 24
        )
        let source = window.coordinate(
            withNormalizedOffset: CGVector(
                dx: reorderHandleX / max(window.frame.width, 1),
                dy: first.frame.midY / max(window.frame.height, 1)
            ))
        let destination = window.coordinate(
            withNormalizedOffset: CGVector(
                dx: reorderHandleX / max(window.frame.width, 1),
                dy: min((second.frame.maxY + 12) / max(window.frame.height, 1), 0.95)
            ))
        source.press(
            forDuration: 0.6,
            thenDragTo: destination,
            withVelocity: .slow,
            thenHoldForDuration: 0.4
        )
        XCTAssertGreaterThan(first.frame.midY, second.frame.midY)
        app.buttons["체크리스트 순서 편집 완료"].tap()
        addReferenceScreenshot(named: "checklist-reordered")
        app.buttons["저장"].tap()

        XCTAssertTrue(scrollToHittable(edit, in: app))
        edit.tap()
        XCTAssertTrue(scrollToHittable(first, in: app, attempts: 20, velocity: .fast))
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(first.frame.midY, second.frame.midY)
        app.buttons["취소"].tap()
    }

    @MainActor
    func testStaleCompletionLinkShowsFailureFeedback() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem"]
        app.launch()
        XCTAssertTrue(app.textFields["해당 날짜에 할 일 입력"].waitForExistence(timeout: 15))

        let missingTaskID = UUID().uuidString
        let url = try XCTUnwrap(
            URL(
                string:
                    "planbase://board?scope=today&action=confirm-completion&task=\(missingTaskID)"))
        app.open(url)

        let notice = app.descendants(matching: .any)["board-status-notice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        let message = notice.label
        let tone = notice.value as? String
        addReferenceScreenshot(named: "stale-completion-link-feedback")
        XCTAssertEqual(message, "작업이 변경되어 완료하지 못했습니다")
        XCTAssertEqual(tone, "오류", "실패한 완료 요청은 성공 표시를 사용하면 안 됩니다")
        XCTAssertFalse(app.alerts["예정된 알림이 있습니다"].exists)

        let taskTitle = "완료 피드백 확인"
        let input = app.textFields["해당 날짜에 할 일 입력"]
        input.tap()
        input.typeText(taskTitle + "\n")
        let done = app.buttons["\(taskTitle) 완료 상태"]
        XCTAssertTrue(scrollToHittable(done, in: app))
        done.tap()
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertTrue(notice.label.contains(taskTitle))
        XCTAssertEqual(notice.value as? String, "", "이후 성공한 동작에는 오류 표시가 남으면 안 됩니다")
        addReferenceScreenshot(named: "completion-feedback-after-error")
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
        XCTAssertTrue(
            alert.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "1개의 작업")
            ).firstMatch.exists)
        alert.buttons["취소"].tap()
    }

    @MainActor
    func testCarryoverLastItemKeepsFeedbackAndLargeTextLayout() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-empty-board", "--ui-testing-reminder-fixtures",
            "--ui-testing-theme=charcoalRose", "--ui-testing-accessibility-text-size",
        ]
        app.launch()
        // Xcode can relaunch an installed target without forwarding fixture arguments.
        app.terminate()
        app.launch()
        let entry = app.buttons["carryover-button"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCTAssertTrue(scrollToHittable(entry, in: app))
        entry.tap()
        let move = app.buttons["알림 완료 테스트: 이월 미래 알림, 오늘로 이월"]
        // The summary and section heading can leave this lazy row below the initial sheet viewport.
        XCTAssertTrue(scrollToHittable(move, in: app))
        XCTAssertTrue(scrollToFullyVisible(move, in: app, below: app.navigationBars["이월함"]))
        addReferenceScreenshot(named: "carryover-large-text-before-move")
        move.tap()
        addReferenceScreenshot(named: "carryover-after-move")
        let notice = app.descendants(matching: .any)["carryover-result-notice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("오늘로 이월"))
        XCTAssertFalse(move.exists)
        addReferenceScreenshot(named: "carryover-last-item-feedback")
        let empty = app.staticTexts["이월할 작업 없음"]
        XCTAssertTrue(scrollToHittable(empty, in: app))
        app.navigationBars["이월함"].buttons["닫기"].tap()
        let task = app.buttons["알림 완료 테스트: 이월 미래 알림 작업 편집"]
        XCTAssertTrue(scrollToHittable(task, in: app))
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
        app.launchArguments = ["--ui-testing", "--ui-testing-accessibility-text-size"]
        app.launch()

        let memoTab = app.buttons["메모"].firstMatch
        XCTAssertTrue(memoTab.waitForExistence(timeout: 15))
        memoTab.tap()

        let themeButton = app.buttons["테마 선택"].firstMatch
        XCTAssertTrue(themeButton.waitForExistence(timeout: 5))
        themeButton.tap()

        XCTAssertTrue(app.navigationBars["테마"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["theme-current-selection"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Theme picker current appearance"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let themeScrollView = app.scrollViews.firstMatch
        XCTAssertTrue(themeScrollView.exists)
        let presetNames = [
            "Clean White", "Apricot", "Lavender Cloud", "Blush Pink",
            "Mint Cream", "Aqua Mist", "Midnight Blue", "Charcoal Rose",
        ]
        for presetName in presetNames {
            let preset = app.buttons["\(presetName) 테마"]
            XCTAssertTrue(
                scrollToHittable(
                    preset,
                    in: themeScrollView,
                    attempts: 10
                )
            )
            XCTAssertGreaterThanOrEqual(preset.frame.width, 44)
            XCTAssertGreaterThanOrEqual(preset.frame.height, 44)
        }
        for retired in ["Apple 2020", "Peach Cream", "Sky Blue", "Sunny Apricot"] {
            XCTAssertFalse(app.buttons["\(retired) 테마"].exists)
        }
    }

    @MainActor
    func testLegacyThemeSelectionOpensCanonicalThemeAndPreview() {
        for (legacy, canonical, title) in [
            ("apple2020", "appleSystem", "Clean White"),
            ("navyBlush", "appleSystem", "Clean White"),
            ("solarBerry", "maroonEmber", "Apricot")
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--ui-testing-theme=\(legacy)"]
            app.launch()
            XCTAssertTrue(app.buttons["board-theme-button"].waitForExistence(timeout: 15))
            app.buttons["board-theme-button"].tap()
            XCTAssertEqual(app.staticTexts["theme-current-selection"].label, title)
            let preset = app.buttons["theme-preset-\(canonical)"]
            XCTAssertTrue(scrollToHittable(preset, in: app.scrollViews.firstMatch))
            XCTAssertEqual(preset.value as? String, "선택됨")
            addReferenceScreenshot(named: "theme-migration-\(legacy)")
            app.terminate()
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
            "--ui-testing-archive-collapsed",
        ]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))

        let archiveTab = tabBar.buttons["기록"]
        archiveTab.tap()
        XCTAssertTrue(app.buttons["기록 필터"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.buttons["archive-open-day-\(localDayKey(Date()))"]
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
        let addEventButton = app.buttons["일정 추가"]
        XCTAssertTrue(addEventButton.waitForExistence(timeout: 10))
        addEventButton.tap()
        XCTAssertTrue(app.navigationBars["일정 추가"].waitForExistence(timeout: 10))
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
        let app = launchEventHistoryFixtureApp()
        let tabBar = app.tabBars.firstMatch

        tabBar.buttons["기록"].tap()
        XCTAssertTrue(
            app.buttons["archive-open-day-\(localDayKey(Date()))"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.segmentedControls["archive-overview-mode"].exists)
        XCTAssertFalse(app.staticTexts["선택 기간 작업 요약"].exists)

        app.buttons["기록 필터"].tap()
        XCTAssertTrue(app.navigationBars["검색 필터"].waitForExistence(timeout: 5))
        app.segmentedControls["archive-content-mode-picker"].buttons["완료 작업"].tap()
        let dateBasisPicker = app.descendants(matching: .any)["archive-date-basis-picker"]
        XCTAssertTrue(dateBasisPicker.waitForExistence(timeout: 5))
        app.navigationBars["검색 필터"].buttons["완료"].tap()

        let delayed = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "archive-task-", "UI 검증: 지연 완료"
            )
        ).firstMatch
        XCTAssertTrue(scrollToHittable(delayed, in: app))
        XCTAssertTrue(delayed.label.contains("계획 9월") || delayed.label.contains("계획"))
        XCTAssertTrue(delayed.label.contains("완료"))

        app.buttons["적용된 기록 필터 변경"].tap()
        XCTAssertTrue(dateBasisPicker.waitForExistence(timeout: 5))
        app.buttons["계획일 기준"].firstMatch.tap()
        app.navigationBars["검색 필터"].buttons["완료"].tap()
        XCTAssertTrue(scrollToHittable(delayed, in: app))
        let plannedKey = localDayKey(Calendar.current.date(byAdding: .day, value: -2, to: Date())!)
        XCTAssertTrue(app.buttons["archive-open-day-\(plannedKey)"].exists)

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
        tapRootDestination("캘린더", in: app)

        let addEventButton = app.buttons["일정 추가"]
        XCTAssertTrue(addEventButton.waitForExistence(timeout: 10))
        addEventButton.tap()
        XCTAssertTrue(app.navigationBars["일정 추가"].waitForExistence(timeout: 5))

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
        app.navigationBars["일정 추가"].buttons["취소"].tap()
        let discard = app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.buttons["변경사항 버리기"].tap()

        let todayCell = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label BEGINSWITH %@ AND label CONTAINS %@",
                koreanDayDisplay(Date()),
                "일정"
            )
        ).firstMatch
        XCTAssertTrue(todayCell.waitForExistence(timeout: 15))
        todayCell.tap()

        let eventMenu = app.buttons["공장 출하 일정 메뉴"].firstMatch
        XCTAssertTrue(eventMenu.waitForExistence(timeout: 10))
        let originalCount = app.buttons.matching(identifier: "공장 출하 일정 메뉴").count
        eventMenu.tap()
        let duplicateAction = app.buttons["일정 복제"]
        XCTAssertTrue(duplicateAction.waitForExistence(timeout: 5))
        duplicateAction.tap()

        let duplicateNavigation = app.navigationBars["일정 복제"]
        XCTAssertTrue(duplicateNavigation.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["복제한 일정"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.textFields["event-title-field"].value as? String,
            "공장 출하"
        )
        duplicateNavigation.buttons["추가"].tap()
        XCTAssertTrue(
            app.staticTexts["독립된 복제 일정을 추가했어요"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertEqual(
            app.buttons.matching(identifier: "공장 출하 일정 메뉴").count,
            originalCount + 1, "복제는 원본을 유지하고 새 일정을 추가해야 합니다")
        addReferenceScreenshot(named: "calendar-duplicate-visible-feedback")
    }

    @MainActor
    func testCalendarDuplicateSaveFailureKeepsDraftAndRetries() {
        let app = launchEventHistoryFixtureApp(
            additionalArguments: ["--ui-testing-event-save-failure-once"]
        )
        tapRootDestination("캘린더", in: app)

        let todayCell = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label BEGINSWITH %@ AND label CONTAINS %@",
                koreanDayDisplay(Date()),
                "일정"
            )
        ).firstMatch
        XCTAssertTrue(todayCell.waitForExistence(timeout: 15))
        todayCell.tap()

        let eventMenus = app.buttons.matching(identifier: "공장 출하 일정 메뉴")
        XCTAssertTrue(eventMenus.firstMatch.waitForExistence(timeout: 10))
        let originalCount = eventMenus.count
        eventMenus.firstMatch.tap()
        let duplicateAction = app.buttons["일정 복제"]
        XCTAssertTrue(duplicateAction.waitForExistence(timeout: 5))
        duplicateAction.tap()

        let navigation = app.navigationBars["일정 복제"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        let title = app.textFields["event-title-field"]
        let note = app.textFields["event-note-field"]
        XCTAssertEqual(title.value as? String, "공장 출하")
        XCTAssertTrue(scrollToHittable(note, in: app))
        XCTAssertEqual(note.value as? String, "출하 메모")
        navigation.buttons["추가"].tap()

        let failure = app.descendants(matching: .any)["event-save-failure"].firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertTrue(failure.label.contains("복제 일정을 추가하지 못했어요"))
        XCTAssertTrue(failure.label.contains("입력한 내용은 이 화면에 그대로 남아 있어요"))
        let retry = app.buttons["event-save-retry"]
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(retry.isHittable)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        assertNoEnglishMonthNames(in: app)
        addReferenceScreenshot(named: "calendar-duplicate-save-failure-draft-retained")

        XCTAssertTrue(scrollToHittable(title, in: app))
        XCTAssertEqual(title.value as? String, "공장 출하")
        XCTAssertTrue(scrollToHittable(note, in: app))
        XCTAssertEqual(note.value as? String, "출하 메모")
        XCTAssertTrue(app.buttons["event-save-retry"].isHittable)
        app.buttons["event-save-retry"].tap()

        XCTAssertTrue(navigation.waitForNonExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts["독립된 복제 일정을 추가했어요"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertEqual(
            app.buttons.matching(identifier: "공장 출하 일정 메뉴").count,
            originalCount + 1,
            "복제 저장 재시도는 원본을 유지하고 새 일정을 한 개만 추가해야 합니다"
        )
        addReferenceScreenshot(named: "calendar-duplicate-save-retry-completed")
    }

    @MainActor
    func testCalendarExistingEventEditPersistsAfterReopening() {
        let app = launchEventHistoryFixtureApp()
        tapRootDestination("캘린더", in: app)
        let todayCell = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", koreanDayDisplay(Date()), "일정"
        )).firstMatch
        XCTAssertTrue(todayCell.waitForExistence(timeout: 15))
        todayCell.tap()
        let edit = app.buttons["일정 편집"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let navigation = app.navigationBars["일정 편집"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        let originalTitle = app.textFields["event-title-field"].value as? String
        XCTAssertNotNil(originalTitle)
        let note = app.descendants(matching: .any)["event-note-field"].firstMatch
        XCTAssertTrue(scrollToHittable(note, in: app))
        note.tap()
        note.typeText("수정한 메모 보존 확인")
        navigation.buttons["저장"].tap()
        XCTAssertTrue(navigation.waitForNonExistence(timeout: 8))
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["event-title-field"].value as? String, originalTitle)
        XCTAssertTrue(scrollToHittable(note, in: app))
        XCTAssertTrue((note.value as? String)?.contains("수정한 메모 보존 확인") == true)
        addReferenceScreenshot(named: "calendar-existing-edit-reopened")
    }

    @MainActor
    func testTaskEditorPreservesDraftAndSavesEstimateBeforeFocus() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem"]
        app.launch()
        let quickAdd = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 15))
        quickAdd.tap()
        quickAdd.typeText("초안과 집중 연결 확인")
        app.buttons["작업 추가"].tap()
        let edit = app.buttons["초안과 집중 연결 확인 작업 편집"]
        XCTAssertTrue(scrollToHittable(edit, in: app))
        edit.tap()
        let estimate = app.textFields["task-detail-estimate"]
        XCTAssertTrue(scrollToHittable(estimate, in: app))
        estimate.tap()
        estimate.typeText("45")
        app.buttons["task-detail-keyboard-dismiss"].tap()
        app.navigationBars["작업 상세"].buttons["취소"].tap()
        let discard = app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "task-draft-discard-confirmation")
        discard.buttons["계속 작성"].tap()
        XCTAssertEqual(estimate.value as? String, "45")
        let focus = app.buttons["task-detail-start-focus"]
        XCTAssertTrue(scrollToHittable(focus, in: app))
        XCTAssertEqual(focus.label, "저장 후 집중 시작")
        focus.tap()
        let duration = app.staticTexts["focus-duration-value"]
        XCTAssertTrue(duration.waitForExistence(timeout: 10))
        XCTAssertTrue(duration.label.contains("45"), duration.label)
        addReferenceScreenshot(named: "task-saved-estimate-focus")
    }

    @MainActor
    func testSavedTaskEditorSwipeAndCancelProtectDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=midnightBlue"]
        app.launch()
        let library = app.buttons["saved-task-library-button"]
        XCTAssertTrue(scrollToHittable(library, in: app))
        library.tap()
        app.buttons["saved-task-create"].tap()
        let title = app.textFields["saved-task-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("닫아도 확인할 초안")
        app.buttons["saved-task-keyboard-dismiss"].tap()
        let navigation = app.navigationBars["새로 저장"]
        navigation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        let discard = app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "saved-task-swipe-discard-confirmation")
        discard.buttons["계속 작성"].tap()
        XCTAssertEqual(title.value as? String, "닫아도 확인할 초안")
        navigation.buttons["취소"].tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.buttons["변경사항 버리기"].tap()
        XCTAssertTrue(app.navigationBars["저장한 작업"].waitForExistence(timeout: 5))
        app.buttons["saved-task-create"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertNotEqual(title.value as? String, "닫아도 확인할 초안")
        app.navigationBars["새로 저장"].buttons["취소"].tap()
        XCTAssertTrue(app.navigationBars["저장한 작업"].waitForExistence(timeout: 5))
        XCTAssertFalse(discard.exists)
    }

    @MainActor
    func testCalendarEditorProtectsDraftAndAddsWithoutRedundantConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=charcoalRose", "--ui-testing-accessibility-text-size"]
        app.launch()
        XCTAssertTrue(app.buttons["캘린더"].firstMatch.waitForExistence(timeout: 15))
        tapRootDestination("캘린더", in: app)
        let add = app.buttons["일정 추가"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let title = app.textFields["event-title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("긴 제목을 가진 일정의 저장 흐름 확인")
        let navigation = app.navigationBars["일정 추가"]
        navigation.buttons["취소"].tap()
        let discard = app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.buttons["계속 작성"].tap()
        XCTAssertEqual(title.value as? String, "긴 제목을 가진 일정의 저장 흐름 확인")
        let duration = app.buttons["event-duration-3"]
        XCTAssertTrue(scrollToHittable(duration, in: app))
        XCTAssertTrue(isHorizontallyContained(duration, in: app.windows.firstMatch))
        duration.tap()
        let customDuration = app.textFields["event-custom-duration"]
        XCTAssertTrue(scrollToHittable(customDuration, in: app))
        customDuration.tap()
        customDuration.typeText("12")
        let applyDuration = app.buttons["event-apply-duration"]
        XCTAssertTrue(isHorizontallyContained(applyDuration, in: app.windows.firstMatch))
        applyDuration.tap()
        XCTAssertEqual(customDuration.value as? String, "12")
        addReferenceScreenshot(named: "calendar-editor-dark-large-text")
        navigation.buttons["추가"].tap()
        XCTAssertTrue(navigation.waitForNonExistence(timeout: 8))
        XCTAssertFalse(app.alerts["일정을 추가할까요?"].exists)
        addReferenceScreenshot(named: "calendar-added-directly")
    }

    @MainActor
    func testCalendarSaveFailureKeepsDraftAndRetries() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-empty-board",
            "--ui-testing-event-save-failure-once",
            "--ui-testing-theme=appleSystem",
            "--ui-testing-accessibility-text-size"
        ]
        app.launch()

        XCTAssertTrue(app.textFields["해당 날짜에 할 일 입력"].waitForExistence(timeout: 15))
        tapRootDestination("캘린더", in: app)
        let addEvent = app.buttons["일정 추가"]
        XCTAssertTrue(addEvent.waitForExistence(timeout: 5))
        addEvent.tap()

        let navigation = app.navigationBars["일정 추가"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        let title = app.textFields["event-title-field"]
        title.tap()
        title.typeText("실패 뒤 초안을 지키는 일정")
        app.buttons["event-editor-keyboard-dismiss"].tap()

        let duration = app.buttons["event-duration-3"]
        XCTAssertTrue(scrollToHittable(duration, in: app))
        duration.tap()

        let note = app.textFields["event-note-field"]
        XCTAssertTrue(scrollToHittable(note, in: app))
        note.tap()
        note.typeText("다시 입력하지 않아도 되는 메모")
        app.buttons["event-editor-keyboard-dismiss"].tap()
        navigation.buttons["추가"].tap()

        let failure = app.descendants(matching: .any)["event-save-failure"].firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertTrue(failure.label.contains("일정을 추가하지 못했어요"))
        XCTAssertTrue(failure.label.contains("입력한 내용은 이 화면에 그대로 남아 있어요"))
        let retry = app.buttons["event-save-retry"]
        XCTAssertTrue(retry.exists)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        addReferenceScreenshot(named: "calendar-save-failure-draft-retained")

        XCTAssertTrue(scrollToHittable(title, in: app))
        XCTAssertEqual(title.value as? String, "실패 뒤 초안을 지키는 일정")
        XCTAssertTrue(scrollToHittable(note, in: app))
        XCTAssertEqual(note.value as? String, "다시 입력하지 않아도 되는 메모")
        let visibleRetry = app.buttons["event-save-retry"].firstMatch
        XCTAssertTrue(visibleRetry.waitForExistence(timeout: 2))
        XCTAssertTrue(visibleRetry.isHittable)
        visibleRetry.tap()

        XCTAssertTrue(navigation.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["일정을 추가했어요"].waitForExistence(timeout: 5))
        let todayCell = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", koreanDayDisplay(Date()))
        ).firstMatch
        XCTAssertTrue(todayCell.waitForExistence(timeout: 5))
        todayCell.tap()
        let eventMenu = app.buttons["실패 뒤 초안을 지키는 일정 일정 메뉴"]
        XCTAssertTrue(eventMenu.waitForExistence(timeout: 8))
        XCTAssertTrue(scrollToHittable(eventMenu, in: app))
        let eventDateRange = app.staticTexts["calendar-day-event-date-range"].firstMatch
        XCTAssertTrue(eventDateRange.waitForExistence(timeout: 3))
        let eventEnd = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        XCTAssertEqual(
            eventDateRange.label,
            "일정 기간 \(koreanDayDisplay(Date()))부터 \(koreanDayDisplay(eventEnd))까지"
        )
        addReferenceScreenshot(named: "calendar-save-retry-completed")
    }

    @MainActor
    func testTaskSaveIncludesPendingChecklistInput() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem"]
        app.launch()
        let quickAdd = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 15))
        quickAdd.tap()
        quickAdd.typeText("마지막 체크리스트 입력 저장")
        app.buttons["작업 추가"].tap()
        let edit = app.buttons["마지막 체크리스트 입력 저장 작업 편집"]
        XCTAssertTrue(scrollToHittable(edit, in: app))
        edit.tap()
        let field = app.textFields["새 체크리스트 항목"]
        XCTAssertTrue(scrollToHittable(field, in: app))
        field.tap()
        field.typeText("플러스 없이 저장한 항목")
        app.buttons["저장"].tap()
        let progress = app.descendants(matching: .any)["마지막 체크리스트 입력 저장-checklist-progress"].firstMatch
        XCTAssertTrue(scrollToHittable(progress, in: app))
        XCTAssertEqual(progress.value as? String, "0개 완료, 전체 1개, 펼쳐짐")
        edit.tap()
        let item = app.buttons["플러스 없이 저장한 항목 완료 상태"]
        XCTAssertTrue(scrollToHittable(item, in: app))
        XCTAssertEqual(app.buttons.matching(identifier: "플러스 없이 저장한 항목 완료 상태").count, 1)
        addReferenceScreenshot(named: "task-pending-checklist-saved")
        app.buttons["취소"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists)
    }

    @MainActor
    private func openRoutineLibrary(_ app: XCUIApplication) {
        let button = app.buttons["template-library-button"]
        XCTAssertTrue(scrollToHittable(button, in: app))
        button.tap()
        XCTAssertTrue(app.navigationBars["템플릿"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func createRoutineDraft(_ app: XCUIApplication, name: String, task: String) {
        let create = app.buttons["template-create-empty"]
        if create.exists { create.tap() }
        else {
            app.buttons["template-create-menu"].tap()
            app.buttons["직접 만들기"].tap()
        }
        let field = app.textFields["template-draft-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        let title = app.textFields["template-editor-task-title"].firstMatch
        title.tap()
        title.typeText(task)
        app.buttons["template-editor-keyboard-dismiss"].tap()
    }

    @MainActor
    func testTemplateLibraryShowsSavedRoutinesBeforeCreation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.launch()
        openRoutineLibrary(app)
        XCTAssertTrue(app.buttons["template-apply-아침 루틴"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["template-target-date"].exists)
        XCTAssertFalse(app.textFields["template-draft-name"].exists)
        XCTAssertFalse(app.staticTexts["현재 보드 저장"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["전체보기"].isSelected)
        addReferenceScreenshot(named: "routine-library-first-entry")
        app.buttons["template-detail-아침 루틴"].tap()
        XCTAssertTrue(app.navigationBars["루틴 상세"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["메일 확인"].exists)
        XCTAssertTrue(app.staticTexts["우선 작업 1개 정하기"].exists)
        addReferenceScreenshot(named: "routine-library-detail")
    }

    @MainActor
    func testTemplateSaveFailureKeepsDraftAndRetries() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem",
                               "--ui-testing-template-save-failure-once"]
        app.launch()
        openRoutineLibrary(app)
        createRoutineDraft(app, name: "저장 재시도 루틴", task: "원본 작업")
        app.buttons["template-draft-save"].tap()
        XCTAssertTrue(app.buttons["template-save-retry"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["template-draft-name"].value as? String, "저장 재시도 루틴")
        addReferenceScreenshot(named: "routine-save-failure-preserved")
        app.buttons["template-save-retry"].tap()
        XCTAssertTrue(app.buttons["template-apply-저장 재시도 루틴"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTemplateCreateEditDiscardAndApply() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem"]
        app.launch()
        openRoutineLibrary(app)
        createRoutineDraft(app, name: "나의 루틴", task: "순서 첫 작업")
        app.navigationBars["루틴 만들기"].buttons["취소"].tap()
        let discard = app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.buttons["계속 작성"].tap()
        XCTAssertEqual(app.textFields["template-draft-name"].value as? String, "나의 루틴")
        app.buttons["template-draft-save"].tap()
        XCTAssertTrue(app.buttons["template-apply-나의 루틴"].waitForExistence(timeout: 5))
        app.buttons["나의 루틴 관리"].tap()
        app.buttons["루틴 편집"].tap()
        XCTAssertTrue(app.navigationBars["루틴 편집"].waitForExistence(timeout: 5))
        app.buttons["template-editor-add-task"].tap()
        let second = app.textFields.matching(identifier: "template-editor-task-title").element(boundBy: 1)
        XCTAssertTrue(scrollToHittable(second, in: app))
        second.tap()
        second.typeText("순서 둘째 작업")
        app.buttons["template-editor-keyboard-dismiss"].tap()
        app.buttons["순서 둘째 작업 위로 이동"].tap()
        app.buttons["template-draft-save"].tap()
        XCTAssertTrue(app.buttons["template-apply-나의 루틴"].waitForExistence(timeout: 5))
        app.buttons["template-apply-나의 루틴"].tap()
        XCTAssertTrue(app.buttons["template-library-button"].waitForExistence(timeout: 5))
        let addedTask = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "순서 둘째 작업")).firstMatch
        XCTAssertTrue(scrollToHittable(addedTask, in: app))
        addReferenceScreenshot(named: "routine-edited-applied")
    }

    @MainActor
    func testTemplateBoardRepeatRequiresExplicitChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.launch()
        let done = app.buttons["board-status-filter-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15))
        done.tap()
        openRoutineLibrary(app)
        app.buttons["template-apply-아침 루틴"].tap()
        XCTAssertTrue(app.buttons["template-library-button"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["board-status-filter-todo"].value as? String, "선택됨")
        openRoutineLibrary(app)
        app.buttons["template-apply-아침 루틴"].tap()
        let options = app.alerts["추가할 작업을 선택하세요"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        XCTAssertTrue(options.buttons["전체 3개 다시 추가"].exists)
        XCTAssertFalse(options.buttons["새 작업 3개만 추가"].exists)
        addReferenceScreenshot(named: "routine-repeat-options")
        options.buttons["취소"].tap()
    }

    @MainActor
    func testTemplateCopyEditsAndAppliesIndependently() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem"]
        app.launch()
        openRoutineLibrary(app)
        createRoutineDraft(app, name: "복제 원본", task: "원본 항목")
        app.buttons["template-draft-save"].tap()
        XCTAssertTrue(app.buttons["복제 원본 관리"].waitForExistence(timeout: 5))
        app.buttons["복제 원본 관리"].tap()
        app.buttons["복제"].tap()
        let name = app.textFields["template-draft-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "복제 원본 복사본")
        app.buttons["template-editor-add-task"].tap()
        let second = app.textFields.matching(identifier: "template-editor-task-title").element(boundBy: 1)
        XCTAssertTrue(scrollToHittable(second, in: app))
        second.tap()
        second.typeText("복사본에만 추가")
        app.buttons["template-editor-keyboard-dismiss"].tap()
        app.buttons["template-draft-save"].tap()
        XCTAssertTrue(app.buttons["template-apply-복제 원본 복사본"].waitForExistence(timeout: 5))
        app.buttons["복제 원본 관리"].tap()
        app.buttons["루틴 편집"].tap()
        XCTAssertTrue(app.navigationBars["루틴 편집"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.matching(identifier: "template-editor-task-title").count, 1)
        app.navigationBars["루틴 편집"].buttons["취소"].tap()
        app.buttons["template-apply-복제 원본 복사본"].tap()
        XCTAssertTrue(app.buttons["template-library-button"].waitForExistence(timeout: 5))
        let copiedTask = app.buttons["복사본에만 추가 작업 편집"]
        XCTAssertTrue(scrollToHittable(copiedTask, in: app))
        addReferenceScreenshot(named: "routine-copy-independent-apply")
    }

    @MainActor
    func testTemplatePlacementKeepsAdjustmentAndChoosesDatesDirectly() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.launch()
        XCTAssertTrue(app.buttons["캘린더"].firstMatch.waitForExistence(timeout: 15))
        tapRootDestination("캘린더", in: app)
        app.buttons["캘린더 메뉴"].tap()
        app.buttons["템플릿 배치"].tap()
        XCTAssertTrue(app.buttons["template-detail-아침 루틴"].waitForExistence(timeout: 5))
        app.buttons["template-detail-아침 루틴"].tap()
        app.buttons["이번에만 조정"].tap()
        let first = app.textFields["template-editor-task-title"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        first.typeText(" 이번에만")
        app.buttons["template-editor-keyboard-dismiss"].tap()
        app.buttons["template-draft-save"].tap()
        XCTAssertTrue(app.navigationBars["날짜 선택"].waitForExistence(timeout: 5))
        let today = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", koreanDayDisplay(Date()))).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
        addReferenceScreenshot(named: "routine-calendar-date-summary")
        app.buttons["template-calendar-add"].tap()
        XCTAssertTrue(app.buttons["캘린더 메뉴"].waitForExistence(timeout: 5))
        tapRootDestination("칸반", in: app)
        let task = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "메일 확인 이번에만")).firstMatch
        XCTAssertTrue(scrollToHittable(task, in: app))
        openRoutineLibrary(app)
        app.buttons["template-detail-아침 루틴"].tap()
        XCTAssertTrue(app.staticTexts["메일 확인"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["메일 확인 이번에만"].exists)
    }

    @MainActor
    func testTemplateIconActionsReserveTouchTargetsAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem", "--ui-testing-accessibility-text-size"]
        app.launch()
        openRoutineLibrary(app)
        let apply = app.buttons["template-apply-아침 루틴"]
        XCTAssertTrue(scrollToHittable(apply, in: app))
        XCTAssertGreaterThanOrEqual(apply.frame.height, 44)
        let manage = app.buttons["아침 루틴 관리"]
        XCTAssertGreaterThanOrEqual(manage.frame.height, 44)
        XCTAssertGreaterThanOrEqual(manage.frame.width, 44)
        XCTAssertLessThanOrEqual(manage.frame.maxY, apply.frame.minY)
        addReferenceScreenshot(named: "routine-library-large-text")
    }

    @MainActor
    func testCalendarDayTemplatePlacementSummaryKeepsTasksAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-theme=charcoalRose",
            "--ui-testing-accessibility-text-size",
        ]
        // Xcode can prelaunch an installed UI-test target without forwarding
        // XCUIApplication options. The first launch is already isolated by the
        // automation-socket guard; relaunch once so visual fixtures are applied.
        app.launch()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["캘린더"].firstMatch.waitForExistence(timeout: 15))
        tapRootDestination("캘린더", in: app)

        app.buttons["캘린더 메뉴"].tap()
        app.buttons["템플릿 배치"].tap()
        let search = app.textFields["템플릿 검색"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("아침")
        app.buttons["template-editor-keyboard-dismiss"].tap()

        let morning = app.buttons["template-apply-아침 루틴"]
        XCTAssertTrue(scrollToHittable(morning, in: app))
        morning.tap()

        let placementNavigation = app.navigationBars["날짜 선택"]
        XCTAssertTrue(placementNavigation.waitForExistence(timeout: 5))
        let today = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", koreanDayDisplay(Date()))
        ).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
        app.buttons["template-calendar-add"].tap()

        let placedToday = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label BEGINSWITH %@ AND label CONTAINS %@",
                koreanDayDisplay(Date()),
                "템플릿 배치"
            )
        ).firstMatch
        XCTAssertTrue(placedToday.waitForExistence(timeout: 10))
        placedToday.tap()

        let dayList = app.collectionViews.firstMatch
        XCTAssertTrue(dayList.waitForExistence(timeout: 5))
        let placementTitle = app.staticTexts["아침 루틴"]
        let placementState = app.staticTexts["작업 3개 · 삭제 가능"]
        let placementTasks = app.staticTexts[
            "메일 확인 · 오늘 일정 훑기 · 우선 작업 1개 정하기"
        ]
        XCTAssertTrue(scrollToHittable(placementTasks, in: dayList))
        XCTAssertTrue(placementTitle.isHittable)
        XCTAssertTrue(placementState.isHittable)
        addReferenceScreenshot(named: "calendar-day-template-summary-large-text")

        let placementDelete = app.buttons["calendar-template-placement-delete"]
        XCTAssertTrue(scrollToHittable(placementDelete, in: dayList))
        XCTAssertGreaterThan(
            placementDelete.frame.width,
            88
        )
        XCTAssertGreaterThanOrEqual(placementDelete.frame.width, 44)
        XCTAssertGreaterThanOrEqual(placementDelete.frame.height, 44)
        addReferenceScreenshot(named: "calendar-day-template-delete-action-large-text")

        placementDelete.tap()
        let deletion = app.alerts["템플릿 배치를 삭제할까요?"]
        XCTAssertTrue(deletion.waitForExistence(timeout: 5))
        XCTAssertTrue(
            deletion.staticTexts[
                "이 배치와 연결된 작업 3개를 함께 삭제할 수 있습니다."
            ].exists
        )
        XCTAssertTrue(deletion.buttons["취소"].exists)
        XCTAssertTrue(deletion.buttons["작업 유지"].exists)
        XCTAssertTrue(deletion.buttons["작업 삭제"].exists)
        addReferenceScreenshot(named: "calendar-day-template-delete-choices-large-text")
        deletion.buttons["작업 유지"].tap()

        let notice = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "아침 루틴",
                "작업 3개에서 해제했어요"
            )
        ).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["배치 없음"].waitForExistence(timeout: 5))
        let openBoard = app.buttons["이 날짜 칸반보드 열기"]
        XCTAssertTrue(scrollToHittable(openBoard, in: app))
        openBoard.tap()

        for title in ["메일 확인", "오늘 일정 훑기", "우선 작업 1개 정하기"] {
            let task = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", title)
            ).firstMatch
            XCTAssertTrue(scrollToHittable(task, in: app))
        }
        addReferenceScreenshot(named: "calendar-day-template-keep-tasks-completed")
    }

    @MainActor
    func testTemplateDetailAndDeletionConfirmations() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem"]
        app.launch()
        openRoutineLibrary(app)
        app.buttons["template-apply-아침 루틴"].tap()
        XCTAssertTrue(app.buttons["template-library-button"].waitForExistence(timeout: 5))
        openRoutineLibrary(app)
        app.buttons["아침 루틴 관리"].tap()
        app.buttons["삭제"].tap()
        let confirmation = app.alerts["루틴을 삭제할까요?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "routine-delete-confirmation")
        confirmation.buttons["삭제"].tap()
        XCTAssertFalse(app.buttons["template-apply-아침 루틴"].exists)
        app.navigationBars["템플릿"].buttons["닫기"].tap()
        let task = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "메일 확인")).firstMatch
        XCTAssertTrue(scrollToHittable(task, in: app))
    }

    @MainActor
    func testArchiveReviewSaveFeedbackFromListAndDayDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-activity-fixtures", "--ui-testing-archive-collapsed"]
        app.terminate()
        app.launch()
        app.terminate()
        app.launch()
        let archiveTab = app.buttons["기록"].firstMatch
        XCTAssertTrue(archiveTab.waitForExistence(timeout: 15))
        archiveTab.tap()
        let today = localDayKey(Date())
        let compose = app.buttons["archive-add-review-\(today)"]
        XCTAssertTrue(scrollToHittable(compose, in: app))
        compose.tap()
        let title = app.textFields["review-title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText("기록에서 쓴 회고")
        app.buttons["review-save-button"].tap()
        let notice = app.descendants(matching: .any)["review-saved-notice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("회고가 저장됐어요"))
        addReferenceScreenshot(named: "archive-list-review-saved-feedback")
        let day = app.buttons["archive-open-day-\(today)"]
        XCTAssertTrue(scrollToHittable(day, in: app))
        day.tap()
        let edit = app.buttons["회고 수정"].firstMatch
        XCTAssertTrue(scrollToHittable(edit, in: app))
        XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
        edit.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.value as? String, "기록에서 쓴 회고")
        title.tap()
        title.typeText(" 수정")
        app.buttons["review-save-button"].tap()
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("회고가 저장됐어요"))
        XCTAssertTrue(app.navigationBars["하루 기록"].exists)
        addReferenceScreenshot(named: "archive-day-review-saved-feedback")
    }

    @MainActor
    func testReviewLoadFailurePreventsOverwritingAndCanRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-review-load-failure-once"]
        app.terminate()
        app.launch()
        let review = app.buttons["review-compose-button"]
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        review.tap()
        let title = app.textFields["review-title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("다시 불러와도 남아야 하는 회고")
        let save = app.buttons["review-save-button"]
        save.tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        let retry = app.buttons["review-load-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(title.exists)
        addReferenceScreenshot(named: "review-load-failure-save-disabled")
        retry.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "다시 불러와도 남아야 하는 회고")
        XCTAssertTrue(save.isEnabled)
        app.navigationBars["회고 수정"].buttons["취소"].tap()
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists)
    }

    @MainActor
    func testReviewPhotoPickerCancelPreservesDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.terminate()
        app.launch()
        let review = app.buttons["review-compose-button"]
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        review.tap()
        let title = app.textFields["review-title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("사진 선택을 취소해도 유지할 회고")
        app.buttons["키보드 닫기"].tap()
        let addImage = app.buttons["사진 추가"]
        XCTAssertTrue(scrollToHittable(addImage, in: app.scrollViews.firstMatch))
        addImage.tap()
        addReferenceScreenshot(named: "review-photo-picker")
        let pickerHierarchy = XCTAttachment(string: app.debugDescription)
        pickerHierarchy.name = "review-photo-picker-hierarchy"
        pickerHierarchy.lifetime = .keepAlways
        add(pickerHierarchy)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.095))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(app.navigationBars["회고 작성"].waitForExistence(timeout: 5))
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: app.buttons["review-save-button"])
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "사진 선택을 취소해도 유지할 회고")
        app.buttons["review-save-button"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
    }

    @MainActor
    func testReviewPhotoAttachmentSaveReopenAndRemove() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=appleSystem"]
        app.terminate()
        app.launch()
        let review = app.buttons["review-compose-button"]
        guard review.waitForExistence(timeout: 15) else {
            return XCTFail("회고 작성 진입 버튼이 없습니다")
        }
        review.tap()
        let title = app.textFields["review-title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("사진과 함께 보존할 회고")
        app.buttons["키보드 닫기"].tap()
        let addImage = app.buttons["사진 추가"]
        XCTAssertTrue(scrollToHittable(addImage, in: app.scrollViews.firstMatch))
        addImage.tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        let loaded = photo.waitForExistence(timeout: 30)
        let pickerHierarchy = XCTAttachment(string: app.debugDescription)
        pickerHierarchy.name = "review-loaded-photo-picker-hierarchy"
        pickerHierarchy.lifetime = .keepAlways
        add(pickerHierarchy)
        addReferenceScreenshot(named: "review-loaded-photo-picker")
        guard loaded else { return XCTFail("격리된 시뮬레이터의 샘플 사진을 불러오지 못했습니다") }
        // The system picker exposes visible photos as non-hittable AX images.
        // Use the observed image bounds, then verify selection/import below.
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let selectedHierarchy = XCTAttachment(string: app.debugDescription)
        selectedHierarchy.name = "review-selected-photo-picker-hierarchy"
        selectedHierarchy.lifetime = .keepAlways
        add(selectedHierarchy)
        let confirm = app.buttons["완료"].firstMatch
        guard confirm.waitForExistence(timeout: 5) else { return XCTFail("사진 선택 완료 버튼을 찾지 못했습니다") }
        confirm.tap()
        let remove = app.buttons["회고 사진 1 삭제"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 20))
        XCTAssertTrue(scrollToHittable(remove, in: app.scrollViews.firstMatch))
        XCTAssertEqual(app.staticTexts["첨부한 사진"].value as? String, "1장, 최대 10장")
        addReferenceScreenshot(named: "review-photo-imported")
        app.buttons["review-save-button"].tap()

        app.buttons["기록"].firstMatch.tap()
        let savedReview = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "사진과 함께 보존할 회고")).firstMatch
        XCTAssertTrue(scrollToHittable(savedReview, in: app))
        savedReview.tap()
        let editReview = app.buttons["회고 수정"].firstMatch
        XCTAssertTrue(scrollToHittable(editReview, in: app))
        let editGeometry = XCTAttachment(string: String(describing: editReview.frame))
        editGeometry.name = "archive-review-edit-target"
        editGeometry.lifetime = .keepAlways
        add(editGeometry)
        addReferenceScreenshot(named: "archive-review-edit-action")
        XCTAssertGreaterThanOrEqual(editReview.frame.height, 44)
        editReview.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "사진과 함께 보존할 회고")
        app.navigationBars["회고 수정"].buttons["취소"].tap()
        let recordPhoto = app.images["회고 사진 1"].firstMatch
        XCTAssertTrue(scrollToHittable(recordPhoto, in: app))
        recordPhoto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let closePhoto = app.buttons["전체 화면 사진 닫기"]
        guard closePhoto.waitForExistence(timeout: 5) else { return XCTFail("기록 사진 전체 화면이 열리지 않았습니다") }
        addReferenceScreenshot(named: "review-saved-photo-full-screen")
        closePhoto.tap()
        app.buttons["칸반"].firstMatch.tap()

        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "사진과 함께 보존할 회고")
        XCTAssertTrue(scrollToHittable(remove, in: app.scrollViews.firstMatch))
        XCTAssertEqual(app.staticTexts["첨부한 사진"].value as? String, "1장, 최대 10장")
        addReferenceScreenshot(named: "review-photo-reopened")
        remove.tap()
        XCTAssertEqual(app.staticTexts["첨부한 사진"].value as? String, "0장, 최대 10장")
        app.navigationBars["회고 수정"].buttons["취소"].tap()
        let discard = app.alerts["변경사항을 버릴까요?"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.buttons["변경사항 버리기"].tap()

        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        XCTAssertTrue(scrollToHittable(remove, in: app.scrollViews.firstMatch))
        XCTAssertEqual(app.staticTexts["첨부한 사진"].value as? String, "1장, 최대 10장")
        remove.tap()
        app.buttons["review-save-button"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "사진과 함께 보존할 회고")
        XCTAssertTrue(scrollToHittable(addImage, in: app.scrollViews.firstMatch))
        XCTAssertEqual(app.staticTexts["첨부한 사진"].value as? String, "0장, 최대 10장")
        XCTAssertFalse(remove.exists)
        addReferenceScreenshot(named: "review-photo-removed-text-retained")
    }

    @MainActor
    func testArchiveReviewImageCarouselShowsCanonicalLegacyAndMissingStates() {
        verifyArchiveReviewImageCarousel(accessibilityTextSize: false)
    }

    @MainActor
    func testArchiveReviewImageCarouselAdaptsToAccessibilityTextSize() {
        verifyArchiveReviewImageCarousel(accessibilityTextSize: true)
    }

    @MainActor
    private func verifyArchiveReviewImageCarousel(accessibilityTextSize: Bool) {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-empty-board",
            "--ui-testing-archive-collapsed",
            "--ui-testing-review-image-fixtures",
            "--ui-testing-theme=appleSystem"
        ]
        if accessibilityTextSize {
            app.launchArguments.append("--ui-testing-accessibility-text-size")
        }
        app.terminate()
        app.launch()
        tapRootDestination("기록", in: app)
        let screenshotSuffix = accessibilityTextSize ? "-accessibility" : ""

        let reviewTitle = "UI 검증: 여러 회고 사진"
        let reviewDisclosure = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", reviewTitle)
        ).firstMatch
        XCTAssertTrue(reviewDisclosure.waitForExistence(timeout: 15))
        XCTAssertTrue(scrollToHittable(reviewDisclosure, in: app))
        reviewDisclosure.tap()

        let counter = app.staticTexts["사진 위치"].firstMatch
        let firstImage = app.images["회고 사진 1"].firstMatch
        XCTAssertTrue(firstImage.waitForExistence(timeout: 10))
        XCTAssertTrue(scrollToHittable(firstImage, in: app))
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.value as? String, "4장 중 1번째")
        addReferenceScreenshot(named: "archive-review-carousel-canonical-wide\(screenshotSuffix)")

        firstImage.swipeLeft()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == %@", "4장 중 2번째"),
                    object: counter
                )],
                timeout: 5
            ),
            .completed
        )
        let secondImage = app.images["회고 사진 2"].firstMatch
        XCTAssertTrue(secondImage.exists)
        addReferenceScreenshot(named: "archive-review-carousel-canonical-tall\(screenshotSuffix)")

        secondImage.swipeLeft()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == %@", "4장 중 3번째"),
                    object: counter
                )],
                timeout: 5
            ),
            .completed
        )
        let legacyImage = app.images["회고 사진 3"].firstMatch
        XCTAssertTrue(legacyImage.exists)
        addReferenceScreenshot(named: "archive-review-carousel-legacy-image\(screenshotSuffix)")

        legacyImage.swipeLeft()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == %@", "4장 중 4번째"),
                    object: counter
                )],
                timeout: 5
            ),
            .completed
        )
        let missing = app.staticTexts["사진을 불러올 수 없습니다."].firstMatch
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "archive-review-carousel-missing-image\(screenshotSuffix)")

        missing.tap()
        let close = app.buttons["전체 화면 사진 닫기"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let viewerCounter = app.staticTexts["사진 위치"].firstMatch
        XCTAssertEqual(viewerCounter.value as? String, "4장 중 4번째")
        XCTAssertTrue(app.staticTexts["사진을 불러올 수 없습니다."].firstMatch.exists)
        addReferenceScreenshot(named: "archive-review-full-screen-missing-image\(screenshotSuffix)")

        app.staticTexts["사진을 불러올 수 없습니다."].firstMatch.swipeRight()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == %@", "4장 중 3번째"),
                    object: viewerCounter
                )],
                timeout: 5
            ),
            .completed
        )
        XCTAssertTrue(app.images["회고 사진 3"].firstMatch.exists)
        addReferenceScreenshot(named: "archive-review-full-screen-legacy-image\(screenshotSuffix)")
        close.tap()
        XCTAssertTrue(reviewDisclosure.waitForExistence(timeout: 5))

        let editReview = app.buttons["회고 수정"].firstMatch
        XCTAssertTrue(scrollToHittable(editReview, in: app))
        editReview.tap()

        let attachmentCount = app.staticTexts["첨부한 사진"]
        XCTAssertTrue(attachmentCount.waitForExistence(timeout: 5))
        XCTAssertEqual(attachmentCount.value as? String, "4장, 최대 10장")
        let addImage = app.buttons["사진 추가"]
        XCTAssertTrue(scrollToHittable(addImage, in: app))
        XCTAssertFalse(addImage.isEnabled)
        XCTAssertTrue(
            app.staticTexts[
                "이전 사진을 정리하면 새 사진 추가와 삭제를 사용할 수 있어요."
            ].exists
        )

        let composerCounter = app.staticTexts["사진 위치"].firstMatch
        let composerFirstImage = app.images["회고 사진 1"].firstMatch
        XCTAssertTrue(scrollToHittable(composerFirstImage, in: app))
        XCTAssertEqual(composerCounter.value as? String, "4장 중 1번째")
        XCTAssertFalse(app.buttons["회고 사진 1 삭제"].exists)
        addReferenceScreenshot(named: "review-composer-mixed-images\(screenshotSuffix)")

        composerFirstImage.swipeLeft()
        app.images["회고 사진 2"].firstMatch.swipeLeft()
        app.images["회고 사진 3"].firstMatch.swipeLeft()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == %@", "4장 중 4번째"),
                    object: composerCounter
                )],
                timeout: 5
            ),
            .completed
        )
        XCTAssertTrue(app.staticTexts["이전 사진을 불러올 수 없음"].exists)
        let removeMissingLegacy = app.buttons["회고 사진 4 삭제"]
        XCTAssertTrue(removeMissingLegacy.exists)
        XCTAssertGreaterThanOrEqual(removeMissingLegacy.frame.width, 44)
        XCTAssertGreaterThanOrEqual(removeMissingLegacy.frame.height, 44)
        addReferenceScreenshot(named: "review-composer-missing-legacy\(screenshotSuffix)")
        app.navigationBars["회고 수정"].buttons["취소"].tap()
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists)
        XCTAssertTrue(reviewDisclosure.waitForExistence(timeout: 5))
    }

    @MainActor
    func testBackupPickersCanCancelAndReturnToRecords() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-archive-collapsed"]
        app.terminate()
        app.launch()
        tapRootDestination("기록", in: app)
        let menu = app.buttons["기록 및 백업 메뉴"]
        for action in ["백업 내보내기", "백업 가져오기"] {
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            menu.tap()
            app.buttons[action].tap()
            let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
            XCTAssertTrue(picker.waitForExistence(timeout: 15))
            addReferenceScreenshot(named: action + "-picker")
            let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["취소", "Cancel"])).firstMatch
            if cancel.exists {
                cancel.tap()
            } else {
                picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            }
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            XCTAssertTrue(menu.isEnabled)
            XCTAssertFalse(app.alerts["백업 실패"].exists)
        }
    }

    @MainActor
    func testBackupExportAndImportCompleteOnLocalDevice() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-archive-collapsed"]
        app.terminate()
        app.launch()
        tapRootDestination("기록", in: app)

        let menu = app.buttons["기록 및 백업 메뉴"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["백업 내보내기"].tap()

        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        let save = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["저장", "Save"])
        ).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let replace = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["대치", "교체", "Replace"])
        ).firstMatch
        if replace.waitForExistence(timeout: 2) {
            replace.tap()
        }

        let exportComplete = app.alerts["백업 완료"]
        XCTAssertTrue(exportComplete.waitForExistence(timeout: 15))
        XCTAssertTrue(exportComplete.staticTexts["이미지 원본을 포함한 백업을 내보냈습니다."].exists)
        addReferenceScreenshot(named: "backup-export-completed")
        exportComplete.buttons["확인"].tap()

        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["백업 가져오기"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 15))

        let exportedFile = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "planbase-backup-")
        ).firstMatch
        XCTAssertTrue(exportedFile.waitForExistence(timeout: 10))
        let exportedFileCell = app.cells.containing(
            .staticText,
            identifier: exportedFile.label
        ).firstMatch
        if exportedFileCell.exists {
            exportedFileCell.tap()
        } else {
            exportedFile.tap()
        }

        XCTAssertTrue(picker.waitForNonExistence(timeout: 5), app.debugDescription)

        let importComplete = app.alerts["백업 완료"]
        let importFailure = app.alerts["백업 실패"]
        let importDeadline = Date().addingTimeInterval(20)
        while Date() < importDeadline,
              !importComplete.exists,
              !importFailure.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertFalse(importFailure.exists, importFailure.debugDescription)
        XCTAssertTrue(importComplete.exists, app.debugDescription)
        XCTAssertTrue(
            importComplete.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "백업을 병합했습니다")
            ).firstMatch.exists
        )
        addReferenceScreenshot(named: "backup-import-completed")
        importComplete.buttons["확인"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.isEnabled)
    }

    @MainActor
    func testCorruptedBackupShowsFailureAndReturnsToRecords() throws {
        let fileName = "planbase-backup-"
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-archive-collapsed"]
        app.terminate()
        app.launch()
        tapRootDestination("기록", in: app)

        let menu = app.buttons["기록 및 백업 메뉴"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["백업 가져오기"].tap()

        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        let fileLabel = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", fileName)
        ).firstMatch
        guard fileLabel.waitForExistence(timeout: 10) else {
            throw XCTSkip("손상 백업 감사 파일이 준비된 시뮬레이터에서 실행합니다")
        }
        let fileCell = app.cells.containing(
            .staticText,
            identifier: fileLabel.label
        ).firstMatch
        XCTAssertTrue(fileCell.exists, app.debugDescription)
        fileCell.tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5), app.debugDescription)

        let failure = app.alerts["백업 실패"]
        XCTAssertTrue(failure.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(
            failure.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "백업 파일 형식이 올바르지 않거나 손상되었습니다")
            ).firstMatch.exists,
            failure.debugDescription
        )
        addReferenceScreenshot(named: "backup-corrupted-file-failure")
        failure.buttons["확인"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.isEnabled)
    }

    @MainActor
    func testMemoCreationChoiceAndEmptyDraftLeaveNoRows() {
        let app = launchKanbanFlowApp()
        tapRootDestination("메모", in: app)
        app.buttons["새 메모"].tap()
        for type in ["text", "checklist", "drawing"] {
            XCTAssertTrue(app.buttons["memo-create-\(type)"].waitForExistence(timeout: 5))
        }
        addReferenceScreenshot(named: "memo-type-creation-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.65)).tap()
        XCTAssertTrue(app.buttons["memo-create-text"].waitForNonExistence(timeout: 5))
        for type in ["text", "checklist", "drawing"] {
            createMemo(in: app, type: type)
            XCTAssertFalse(app.descendants(matching: .any)["memo-editor-mode"].firstMatch.exists)
            let change = app.buttons["memo-change-type"]
            XCTAssertTrue(change.waitForExistence(timeout: 5))
            change.tap()
            app.buttons["memo-change-type-checklist"].tap()
            app.buttons["항목 추가"].tap()
            app.buttons["memo-checklist-keyboard-dismiss"].tap()
            app.buttons["memo-editor-back"].tap()
            XCTAssertTrue(app.staticTexts["메모 없음"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testMemoTypedTextAndChecklistPersistAcrossRelaunch() {
        let app = launchKanbanFlowApp(additionalArguments: ["--ui-testing-memo-store=\(UUID().uuidString)"])
        tapRootDestination("메모", in: app)
        createMemo(in: app)
        let text = app.textViews["메모 내용"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("유형별 글 메모\n재실행 뒤에도 남는 본문")
        XCTAssertFalse(app.buttons["memo-change-type"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["memo-editor-mode"].firstMatch.exists)
        app.buttons["memo-editor-back"].tap()
        createMemo(in: app, type: "checklist")
        app.buttons["항목 추가"].tap()
        app.typeText("첫 번째 확인")
        app.buttons["memo-checklist-keyboard-dismiss"].tap()
        app.buttons["항목 추가"].tap()
        app.typeText("두 번째 확인")
        app.buttons["memo-checklist-keyboard-dismiss"].tap()
        app.buttons["첫 번째 확인 완료"].tap()
        app.buttons["두 번째 확인 항목 이동"].tap()
        app.buttons["위로 이동"].tap()
        let fields = app.textFields.matching(identifier: "memo-checklist-title")
        XCTAssertEqual(fields.element(boundBy: 0).value as? String, "두 번째 확인")
        XCTAssertTrue(app.buttons["첫 번째 확인 완료 해제"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["memo-editor-mode"].firstMatch.exists)
        addReferenceScreenshot(named: "memo-typed-checklist-reordered")
        app.buttons["memo-editor-back"].tap()
        XCTAssertTrue(app.buttons["두 번째 확인"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        tapRootDestination("메모", in: app)
        app.buttons["두 번째 확인"].tap()
        XCTAssertEqual(fields.element(boundBy: 0).value as? String, "두 번째 확인")
        XCTAssertTrue(app.buttons["첫 번째 확인 완료 해제"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["memo-editor-mode"].firstMatch.exists)
        app.buttons["상단에 고정"].tap()
        app.buttons["memo-editor-back"].tap()
        XCTAssertTrue(app.staticTexts["고정됨"].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "memo-typed-list-previews")
        let search = app.searchFields.firstMatch
        for _ in 0..<2 where !search.exists {
            app.collectionViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap()
        search.typeText("재실행\n")
        let row = app.buttons["유형별 글 메모"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertEqual(text.value as? String, "유형별 글 메모\n재실행 뒤에도 남는 본문")
        XCTAssertFalse(app.descendants(matching: .any)["memo-editor-mode"].firstMatch.exists)
        addReferenceScreenshot(named: "memo-typed-text-reopened")
        app.buttons["메모 삭제"].tap()
        app.alerts["메모 삭제"].buttons["삭제"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testMemoTypedDrawingPersistsAndClearKeepsItsType() {
        let app = launchKanbanFlowApp(additionalArguments: ["--ui-testing-memo-store=\(UUID().uuidString)"])
        tapRootDestination("메모", in: app)
        createMemo(in: app, type: "drawing")
        let canvas = app.descendants(matching: .any)["memo-drawing-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        let clear = app.buttons["memo-clear-drawing"]
        XCTAssertTrue(clear.isEnabled)
        XCTAssertFalse(app.buttons["memo-change-type"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["memo-editor-mode"].firstMatch.exists)
        addReferenceScreenshot(named: "memo-typed-drawing")
        app.buttons["memo-editor-back"].tap()
        let row = app.buttons["필기·그림"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "memo-typed-drawing-thumbnail")
        app.terminate()
        app.launch()
        tapRootDestination("메모", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertTrue(clear.isEnabled)
        clear.tap()
        app.buttons["취소"].tap()
        XCTAssertTrue(clear.isEnabled)
        clear.tap()
        app.buttons["필기 모두 지우기"].tap()
        XCTAssertFalse(clear.isEnabled)
        app.buttons["memo-editor-back"].tap()
        row.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertFalse(clear.isEnabled)
        XCTAssertFalse(app.buttons["memo-change-type"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["memo-editor-mode"].firstMatch.exists)
    }

    @MainActor
    private func createMemo(in app: XCUIApplication, type: String = "text") {
        app.buttons["새 메모"].tap()
        let choice = app.buttons["memo-create-\(type)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
    }

    @MainActor
    func testMemoInitialLoadFailureShowsRetryInsteadOfEmptyList() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-empty-board", "--ui-testing-memo-load-failure-once",
            "--ui-testing-accessibility-text-size", "--ui-testing-theme=midnightBlue",
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["메모"].tap()
        let retry = app.buttons["memo-load-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["메모 없음"].exists)
        XCTAssertTrue(scrollToHittable(retry, in: app))
        addReferenceScreenshot(named: "memo-initial-load-error-retry")
        retry.tap()
        XCTAssertTrue(app.staticTexts["메모 없음"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
        createMemo(in: app)
        let text = app.textViews["메모 내용"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("오류 복구 후 메모")
        app.navigationBars.buttons["메모"].firstMatch.tap()
        app.tabBars.buttons["칸반"].tap()
        app.tabBars.buttons["메모"].tap()
        let savedMemo = app.buttons["오류 복구 후 메모"]
        XCTAssertTrue(savedMemo.waitForExistence(timeout: 5))
        savedMemo.tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.value as? String, "오류 복구 후 메모")
    }

    @MainActor
    func testMemoSaveFailureKeepsDraftAndRetries() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-empty-board",
            "--ui-testing-memo-save-failure-once",
            "--ui-testing-theme=appleSystem",
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["메모"].tap()
        createMemo(in: app)

        let editor = app.textViews["메모 내용"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let content = "자동 저장 실패 복구\n작성한 내용은 사라지지 않아야 합니다"
        editor.tap()
        editor.typeText(content)
        let saveState = app.descendants(matching: .any)["memo-save-state"].firstMatch
        let failed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "저장 실패"),
            object: saveState
        )
        XCTAssertEqual(XCTWaiter.wait(for: [failed], timeout: 10), .completed)
        XCTAssertEqual(editor.value as? String, content)
        let retry = app.buttons["memo-save-retry"]
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(retry.isHittable)
        addReferenceScreenshot(named: "memo-save-failure-draft-preserved")

        retry.tap()
        let saved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "저장됨"),
            object: saveState
        )
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        XCTAssertTrue(retry.waitForNonExistence(timeout: 5))
        addReferenceScreenshot(named: "memo-save-retry-succeeded")

        app.navigationBars.buttons["메모"].firstMatch.tap()
        let row = app.buttons["자동 저장 실패 복구"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, content)
    }

    @MainActor
    func testMemoBackKeepsDraftWhenSaveFailsAgain() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board",
            "--ui-testing-memo-save-failure-twice", "--ui-testing-theme=appleSystem"]
        app.launch()
        tapRootDestination("메모", in: app)
        createMemo(in: app)
        let editor = app.textViews["메모 내용"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("화면 이탈 실패에도 보존")
        let retry = app.buttons["memo-save-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        app.buttons["memo-editor-back"].tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "화면 이탈 실패에도 보존")
        addReferenceScreenshot(named: "memo-back-failed-save-keeps-draft")
        retry.tap()
        XCTAssertTrue(retry.waitForNonExistence(timeout: 5))
        app.buttons["memo-editor-back"].tap()
        XCTAssertTrue(app.buttons["화면 이탈 실패에도 보존"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testMemoContentLoadFailurePreventsEditingUntilRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board",
            "--ui-testing-memo-content-load-failure-once", "--ui-testing-theme=appleSystem"]
        app.launch()
        tapRootDestination("메모", in: app)
        createMemo(in: app)
        let editor = app.textViews["메모 내용"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("불러오기 실패에도 보존")
        app.buttons["memo-editor-back"].tap()
        let row = app.buttons["불러오기 실패에도 보존"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let retry = app.buttons["memo-content-load-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertFalse(editor.exists)
        XCTAssertFalse(app.buttons["상단에 고정"].isEnabled)
        addReferenceScreenshot(named: "memo-content-load-failure-protects-data")
        retry.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "불러오기 실패에도 보존")
    }

    @MainActor
    func testMemoChecklistLargeTextPreservesTitlesAndCompletion() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-empty-board", "--ui-testing-theme=midnightBlue",
            "--ui-testing-accessibility-text-size",
        ]
        app.terminate()
        app.launch()
        tapRootDestination("메모", in: app)
        createMemo(in: app, type: "checklist")
        app.buttons["항목 추가"].tap()
        let field = app.descendants(matching: .any)["memo-checklist-title"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let title = "내일 출근 전에 노트북 충전기와 회의 자료를 함께 챙기기"
        app.typeText(title)
        app.buttons["memo-checklist-keyboard-dismiss"].tap()
        XCTAssertEqual(field.value as? String, title)
        let complete = app.buttons["\(title) 완료"]
        XCTAssertTrue(scrollToHittable(complete, in: app))
        XCTAssertTrue(isHorizontallyContained(field, in: app.windows.firstMatch))
        complete.tap()
        XCTAssertTrue(app.buttons["\(title) 완료 해제"].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "memo-checklist-AX5-completed")
        app.navigationBars.buttons["메모"].firstMatch.tap()
        let row = app.buttons[title]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        tapRootDestination("칸반", in: app)
        tapRootDestination("메모", in: app)
        row.tap()
        XCTAssertTrue(app.buttons["\(title) 완료 해제"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, title)
        let saved = app.descendants(matching: .any)["memo-save-state"].firstMatch
        XCTAssertTrue(isHorizontallyContained(saved, in: app.windows.firstMatch))
    }

    @MainActor
    func testMemoDrawingClearRequiresConfirmationAndKeepsText() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-board", "--ui-testing-legacy-memo", "--ui-testing-theme=appleSystem"]
        app.terminate()
        app.launch()
        tapRootDestination("메모", in: app)
        app.buttons["기존 복합 메모"].tap()
        let text = app.textViews["메모 내용"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText(" 추가 기록")
        app.buttons["필기"].tap()
        let canvas = app.descendants(matching: .any)["memo-drawing-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        let clear = app.buttons["memo-clear-drawing"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertTrue(clear.isEnabled)
        addReferenceScreenshot(named: "memo-drawing-before-clear")
        clear.tap()
        XCTAssertTrue(app.buttons["필기 모두 지우기"].waitForExistence(timeout: 5))
        addReferenceScreenshot(named: "memo-drawing-clear-confirmation")
        app.buttons["취소"].tap()
        XCTAssertTrue(clear.isEnabled)
        clear.tap()
        app.buttons["필기 모두 지우기"].tap()
        XCTAssertFalse(clear.isEnabled)
        app.buttons["텍스트"].tap()
        XCTAssertEqual(text.value as? String, "기존 복합 메모 추가 기록")
    }

    @MainActor
    func testSavedTaskLibraryLoadFailureCanRetry() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-empty-board",
            "--ui-testing-saved-task-load-failure-once",
            "--ui-testing-accessibility-text-size",
            "--ui-testing-theme=appleSystem",
        ]
        app.terminate()
        app.launch()
        let library = app.buttons["saved-task-library-button"]
        XCTAssertTrue(scrollToHittable(library, in: app))
        library.tap()
        let retry = app.buttons["saved-task-load-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["자주 쓰는 일을 저장해 보세요"].exists)
        addReferenceScreenshot(named: "saved-task-load-error-retry")
        retry.tap()
        XCTAssertTrue(app.staticTexts["자주 쓰는 일을 저장해 보세요"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
        app.buttons["saved-task-create"].tap()
        let title = app.textFields["saved-task-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("불러오기 복구 후 저장한 작업")
        app.buttons["saved-task-editor-save"].tap()
        XCTAssertTrue(scrollToHittable(app.buttons["불러오기 복구 후 저장한 작업 추가"], in: app))
    }

    @MainActor
    func testThemeEmojiLargeTextValidationAndSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-accessibility-text-size", "--ui-testing-theme=midnightBlue"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["메모"].tap()
        app.buttons["테마 선택"].tap()
        app.buttons["theme-section-picker"].tap()
        app.buttons["활동 그래프"].tap()
        app.buttons["activity-heatmap-style-picker"].tap()
        app.buttons["이모지"].tap()
        let emoji = app.textFields["activity-heatmap-emoji-field"]
        XCTAssertTrue(scrollToFullyVisible(emoji, in: app, below: app.navigationBars["테마"]))
        emoji.tap()
        let existing = emoji.value as? String ?? ""
        emoji.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        emoji.typeText("abc")
        XCTAssertTrue((emoji.value as? String)?.contains("abc") == true)
        app.buttons["activity-emoji-keyboard-dismiss"].tap()
        let validation = app.descendants(matching: .any)["activity-emoji-validation"].firstMatch
        XCTAssertTrue(validation.waitForExistence(timeout: 5))
        let suggestion = app.buttons["✨ 이모지 사용"]
        XCTAssertTrue(scrollToFullyVisible(suggestion, in: app, below: app.navigationBars["테마"]))
        XCTAssertGreaterThanOrEqual(suggestion.frame.height, 44)
        suggestion.tap()
        XCTAssertEqual(emoji.value as? String, "✨")
        XCTAssertFalse(validation.exists)
        addReferenceScreenshot(named: "theme-emoji-AX5-selection")
        app.navigationBars["테마"].buttons["완료"].tap()
    }

    @MainActor
    func testReviewSummaryLargeTextWithReducedMotion() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let reduceMotion = settings.switches.matching(NSPredicate(format: "label IN %@", ["동작 줄이기", "Reduce Motion"])).firstMatch
        if !reduceMotion.exists {
            let motion = settings.staticTexts.matching(NSPredicate(format: "label IN %@", ["동작", "Motion"])).firstMatch
            if !motion.exists {
                let accessibility = settings.staticTexts.matching(NSPredicate(format: "label IN %@", ["손쉬운 사용", "Accessibility"]))
                    .firstMatch
                XCTAssertTrue(scrollToHittable(accessibility, in: settings, attempts: 12))
                accessibility.tap()
            }
            XCTAssertTrue(scrollToHittable(motion, in: settings))
            motion.tap()
        }
        XCTAssertTrue(reduceMotion.waitForExistence(timeout: 5))
        let wasEnabled = reduceMotion.value as? String == "1"
        defer {
            settings.activate()
            if !wasEnabled, reduceMotion.value as? String == "1" {
                reduceMotion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
        }
        if !wasEnabled {
            reduceMotion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertTrue(reduceMotion.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: reduceMotion)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-accessibility-text-size",
            "--ui-testing-theme=charcoalRose",
        ]
        app.terminate()
        app.launch()
        let review = app.buttons["review-compose-button"]
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        XCTAssertTrue(scrollToHittable(review, in: app))
        review.tap()
        let summary = app.buttons["작업 요약"]
        XCTAssertTrue(scrollToFullyVisible(summary, in: app, below: app.navigationBars["회고 작성"]))
        summary.tap()
        XCTAssertEqual(summary.value as? String, "펼쳐짐")
        let planned = app.staticTexts["그날 계획한 일"]
        XCTAssertTrue(scrollToFullyVisible(planned, in: app, below: app.navigationBars["회고 작성"]))
        addReferenceScreenshot(named: "review-summary-AX5-reduced-motion")
        app.navigationBars["회고 작성"].buttons["취소"].tap()
        XCTAssertFalse(app.alerts["변경사항을 버릴까요?"].exists)
    }

    @MainActor
    func testCollectPrimaryScreenAccessibilityAuditFindings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-theme=appleSystem", "--ui-testing-archive-collapsed"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["칸반"].firstMatch.waitForExistence(timeout: 15))
        for tab in ["칸반", "캘린더", "기록", "메모"] {
            tapRootDestination(tab, in: app)
            var findings: [String] = []
            try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped]) { issue in
                let element = issue.element
                findings.append(
                    "종류: \(issue.auditType.rawValue)\n요소: \(element?.identifier ?? "")\n이름: \(element?.label ?? "")\n영역: \(element.map { String(describing: $0.frame) } ?? "")\n\(issue.detailedDescription)"
                )
                // Preserve every finding for review; this test verifies collection, not audit compliance.
                return true
            }
            let attachment = XCTAttachment(string: "\(tab): \(findings.count)개 지적\n\n" + findings.joined(separator: "\n\n"))
            attachment.name = "accessibility-findings-\(tab)"
            attachment.lifetime = .keepAlways
            add(attachment)
            addReferenceScreenshot(named: "accessibility-audit-\(tab)")
        }
    }

    @MainActor
    func testRecoveryLargeTextKeepsRetryReachableAndUsesIsolatedStore() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-recovery-once", "--ui-testing-accessibility-text-size"]
        app.launch()
        let retry = app.buttons["persistence-recovery-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertTrue(isHorizontallyContained(retry, in: app.windows.firstMatch))
        XCTAssertTrue(scrollToHittable(retry, in: app))
        addReferenceScreenshot(named: "recovery-large-text-retry")
        let details = app.buttons["persistence-recovery-details"]
        XCTAssertTrue(scrollToHittable(details, in: app))
        details.tap()
        let diagnostic = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "UI 검증용 저장소 열기 실패입니다.")).firstMatch
        XCTAssertTrue(scrollToHittable(diagnostic, in: app))
        addReferenceScreenshot(named: "recovery-large-text-expanded-details")
        XCTAssertTrue(scrollToHittable(retry, in: app, attempts: 3))
        retry.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["persistence-recovery-retry"].exists)
    }

    @MainActor
    func testSyncAndArchiveFilterSheetsRespectLargeText() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-accessibility-text-size", "--ui-testing-theme=charcoalRose", "--ui-testing-archive-collapsed",
        ]
        app.launch()
        tapRootDestination("메모", in: app)
        app.buttons["cloud-sync-status-button"].tap()
        XCTAssertTrue(app.navigationBars["iCloud 동기화"].waitForExistence(timeout: 5))
        let bannerToggle = app.switches["상단 경고 배너"]
        XCTAssertTrue(scrollToHittable(bannerToggle, in: app.collectionViews.firstMatch))
        XCTAssertTrue(isHorizontallyContained(bannerToggle, in: app.windows.firstMatch))
        XCTAssertGreaterThan(bannerToggle.frame.height, 60, "부모의 접근성 글자 크기를 sheet 본문에도 적용해야 합니다")
        addReferenceScreenshot(named: "sync-large-text-controls")
        app.navigationBars["iCloud 동기화"].buttons["완료"].tap()
        tapRootDestination("기록", in: app)
        app.buttons["기록 필터"].tap()
        XCTAssertTrue(app.navigationBars["검색 필터"].waitForExistence(timeout: 5))
        let mode = app.buttons["archive-content-mode-picker"]
        XCTAssertTrue(scrollToHittable(mode, in: app.collectionViews.firstMatch))
        mode.tap()
        let completed = app.buttons["완료 작업"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        completed.tap()
        XCTAssertTrue(mode.label.contains("완료 작업") || (mode.value as? String)?.contains("완료 작업") == true)
        addReferenceScreenshot(named: "archive-filter-large-text")
        XCTAssertTrue(app.navigationBars["검색 필터"].buttons["완료"].isHittable)
        app.navigationBars["검색 필터"].buttons["완료"].tap()
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
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-event-history-fixtures",
            "--ui-testing-archive-collapsed",
        ] + additionalArguments
        app.launch()
        XCTAssertTrue(app.buttons["칸반"].firstMatch.waitForExistence(timeout: 15))
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

    private func assertNoEnglishMonthNames(in app: XCUIApplication) {
        for month in [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ] {
            XCTAssertEqual(
                app.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", month)
                ).count,
                0,
                "한국어 일정 편집 화면에 영어 월 이름 \(month)이 표시되면 안 됩니다"
            )
        }
    }

    private func localDayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    @MainActor
    private func createFocusTask(in app: XCUIApplication, title: String, minutes: Int) {
        let field = app.textFields["해당 날짜에 할 일 입력"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText(title)
        app.buttons["작업 추가"].tap()
        let edit = app.buttons["\(title) 작업 편집"]
        XCTAssertTrue(scrollToHittable(edit, in: app.scrollViews["board-accessibility-scroll"]))
        edit.tap()
        let estimate = app.textFields["task-detail-estimate"]
        XCTAssertTrue(scrollToHittable(estimate, in: app))
        estimate.tap()
        estimate.typeText(String(minutes))
        app.buttons["task-detail-keyboard-dismiss"].tap()
        app.navigationBars["작업 상세"].buttons["저장"].tap()
    }

    @MainActor
    private func tapRootDestination(_ name: String, in app: XCUIApplication) {
        let tabButton = app.tabBars.buttons[name].firstMatch
        if tabButton.waitForExistence(timeout: 0.5) {
            tabButton.tap()
            return
        }

        let adaptiveButton = app.buttons[name].firstMatch
        XCTAssertTrue(adaptiveButton.waitForExistence(timeout: 5))
        adaptiveButton.tap()
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
    private func scrollTowardTopToHittable(
        _ element: XCUIElement,
        in scrollable: XCUIElement,
        attempts: Int = 14,
        velocity: XCUIGestureVelocity = .slow
    ) -> Bool {
        for _ in 0..<attempts {
            if element.waitForExistence(timeout: 0.5), element.isHittable {
                return true
            }
            scrollable.swipeDown(velocity: velocity)
        }
        return element.exists && element.isHittable
    }

    @MainActor
    private func scrollToFullyVisible(_ element: XCUIElement, in app: XCUIApplication, below navigationBar: XCUIElement) -> Bool {
        for _ in 0..<12 {
            if element.exists {
                let upperEdge = navigationBar.frame.maxY + 8
                let lowerEdge = app.windows.firstMatch.frame.maxY - 48
                if element.isHittable, element.frame.minY >= upperEdge, element.frame.maxY <= lowerEdge {
                    return true
                }
                if element.frame.minY < upperEdge { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
            } else {
                app.swipeDown(velocity: .slow)
            }
        }
        return false
    }

    @MainActor
    private func isHorizontallyContained(
        _ element: XCUIElement,
        in container: XCUIElement,
        tolerance: CGFloat = 1
    ) -> Bool {
        guard element.exists, container.exists else { return false }
        return element.frame.minX >= container.frame.minX - tolerance && element.frame.maxX <= container.frame.maxX + tolerance
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

/// Run separately with -only-testing:PlanBaseLaunchUITests/PlanBaseResponsivenessTests.
/// Wall-clock metrics include XCTest IPC and idle waiting; they are not input latency.
final class PlanBaseResponsivenessTests: XCTestCase {
    @MainActor
    private func launchFixture() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-performance", "--ui-testing-theme=appleSystem"]
        app.launch()
        XCTAssertTrue(app.textFields["해당 날짜에 할 일 입력"].waitForExistence(timeout: 90))
        return app
    }

    @MainActor
    func testRepeatedTabNavigation() {
        let app = launchFixture()
        // Warm all four tabs before measuring repeat navigation.
        for name in ["캘린더", "기록", "메모", "칸반"] {
            app.tabBars.buttons[name].tap()
            XCTAssertTrue(app.tabBars.buttons[name].isSelected)
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        var metrics: [any XCTMetric] = [
            XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app),
            XCTOSSignpostMetric(subsystem: "com.soraul2.easytask.performance", category: "PointsOfInterest", name: "TabArchive"),
        ]
        if #available(iOS 26.0, *) { metrics.append(XCTHitchMetric(application: app)) }
        measure(metrics: metrics, options: options) {
            for name in ["캘린더", "기록", "메모", "칸반"] {
                app.tabBars.buttons[name].tap()
                XCTAssertTrue(app.tabBars.buttons[name].isSelected)
            }
        }
    }

    @MainActor
    func testPreparedStoreLaunch() {
        let app = launchFixture()
        app.terminate()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
            XCTAssertTrue(app.textFields["해당 날짜에 할 일 입력"].waitForExistence(timeout: 30))
            app.terminate()
        }
    }

    @MainActor
    func testBoardScrolling() {
        let app = launchFixture()
        let scroll = app.scrollViews["board-accessibility-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        var metrics: [any XCTMetric] = [
            XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app),
            XCTOSSignpostMetric.scrollingAndDecelerationMetric,
        ]
        if #available(iOS 26.0, *) { metrics.append(XCTHitchMetric(application: app)) }
        measure(metrics: metrics, options: options) {
            scroll.swipeUp(velocity: .slow)
            scroll.swipeDown(velocity: .slow)
        }
    }

    @MainActor
    func testTaskDetailAndFocusEntry() {
        let app = launchFixture()
        let scroll = app.scrollViews["board-accessibility-scroll"]
        let edit = app.buttons["성능 작업 0000 작업 편집"]
        let focus = app.buttons["성능 작업 0000 집중 시작"]
        for _ in 0..<5 where !focus.isHittable {
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(edit.isHittable)
        XCTAssertTrue(focus.isHittable)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            edit.tap()
            XCTAssertTrue(app.navigationBars["작업 상세"].waitForExistence(timeout: 10))
            app.navigationBars["작업 상세"].buttons["취소"].tap()
            focus.tap()
            XCTAssertTrue(app.staticTexts["focus-duration-value"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["focus-duration-value"].label, "30분")
            app.buttons["focus-close"].tap()
        }
    }

    @MainActor
    func testLargeLibraryShortcutSuggestions() {
        let app = launchFixture()
        let input = app.textFields["해당 날짜에 할 일 입력"]
        input.tap()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            input.typeText("/perf12")
            XCTAssertTrue(app.buttons["성능 보관 0012 /perf12 추가"].waitForExistence(timeout: 10))
            XCTAssertEqual(input.value as? String, "/perf12")
            input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        }
    }
}

/// An unmeasured driver for a separate Instruments recording on an isolated fixture.
/// Do not run alongside the XCTest metric suite or a build.
final class PlanBaseResponsivenessTraceTests: XCTestCase {
    @MainActor
    func testInstrumentedInteractions() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-performance", "--ui-testing-theme=appleSystem"]
        app.launch()
        XCTAssertTrue(app.textFields["해당 날짜에 할 일 입력"].waitForExistence(timeout: 90))
        var phases: [[String: Any]] = []

        // Give an external profiler time to attach to this specific test process.
        // The optional idle interval is outside all recorded interaction phases.
        if let value = ProcessInfo.processInfo.environment["PLANBASE_TRACE_ATTACH_DELAY_SECONDS"],
            let delay = Double(value), delay > 0, delay <= 30
        {
            FileHandle.standardOutput.write(Data("PLANBASE_TRACE_ATTACH_READY\n".utf8))
            let attachWindow = XCTestExpectation(description: "Instruments attach window")
            attachWindow.isInverted = true
            _ = XCTWaiter.wait(for: [attachWindow], timeout: delay)
        }

        func phase(_ name: String, _ action: () -> Void) {
            let start = Date().timeIntervalSince1970
            XCTContext.runActivity(named: name) { _ in action() }
            phases.append(["name": name, "startUnix": start, "endUnix": Date().timeIntervalSince1970])
        }

        for iteration in 0..<3 {
            for name in ["캘린더", "기록", "메모", "칸반"] {
                phase("tab-\(iteration)-\(name)") {
                    app.tabBars.buttons[name].tap()
                    XCTAssertTrue(app.tabBars.buttons[name].isSelected)
                    let content: XCUIElement
                    switch name {
                    case "캘린더":
                        content = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "성능 일정 ")).firstMatch
                    case "기록":
                        content = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "archive-open-day-")).firstMatch
                    case "메모":
                        content = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "성능 메모 ")).firstMatch
                    default:
                        content = app.buttons["성능 작업 0000 작업 편집"]
                    }
                    XCTAssertTrue(content.waitForExistence(timeout: 15), "\(name) fixture content must load")
                }
            }
        }
        let input = app.textFields["해당 날짜에 할 일 입력"]
        let scroll = app.scrollViews["board-accessibility-scroll"]
        for iteration in 0..<5 {
            phase("scroll-\(iteration)") {
                scroll.swipeUp(velocity: .slow)
                scroll.swipeDown(velocity: .slow)
            }
        }
        let edit = app.buttons["성능 작업 0000 작업 편집"]
        let focus = app.buttons["성능 작업 0000 집중 시작"]
        for _ in 0..<8 where !input.isHittable { scroll.swipeDown(velocity: .fast) }
        XCTAssertTrue(input.isHittable)
        for _ in 0..<5 where !focus.isHittable { scroll.swipeUp(velocity: .slow) }
        XCTAssertTrue(edit.isHittable)
        XCTAssertTrue(focus.isHittable)
        phase("detail") {
            edit.tap()
            XCTAssertTrue(app.navigationBars["작업 상세"].waitForExistence(timeout: 10))
            app.navigationBars["작업 상세"].buttons["취소"].tap()
        }
        phase("focus") {
            focus.tap()
            XCTAssertTrue(app.staticTexts["focus-duration-value"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["focus-duration-value"].label, "30분")
            app.buttons["focus-close"].tap()
        }
        phase("background-return") {
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(app.tabBars.buttons["칸반"].isSelected)
        }
        // Run input last so an overloaded baseline cannot leave the following
        // scroll measurement inside the inline suggestions or keyboard.
        for _ in 0..<8 where !input.isHittable { scroll.swipeDown(velocity: .fast) }
        XCTAssertTrue(input.isHittable)
        var shortcutInputAfterDeletion = ""
        phase("shortcut") {
            input.tap()
            input.typeText("/perf12")
            XCTAssertTrue(app.buttons["성능 보관 0012 /perf12 추가"].waitForExistence(timeout: 10))
            XCTAssertEqual(input.value as? String, "/perf12")
            input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
            shortcutInputAfterDeletion = input.value as? String ?? ""
            if shortcutInputAfterDeletion == input.placeholderValue {
                shortcutInputAfterDeletion = ""
            }
        }
        let data = try JSONSerialization.data(
            withJSONObject: [
                "interpretation":
                    "Driver/AX intervals include automation waiting; use Instruments HID and presentation events for input feedback. These are not touch latency samples.",
                "phases": phases,
                "shortcutInputAfterDeletion": shortcutInputAfterDeletion,
                "shortcutDeletionCompleted": shortcutInputAfterDeletion.isEmpty,
            ], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Instruments interaction phases"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Let the external profiler finish transferring while its target is alive.
        if ProcessInfo.processInfo.environment["PLANBASE_TRACE_KEEP_ALIVE"] == "1" {
            let transferWindow = XCTestExpectation(description: "Instruments transfer window")
            transferWindow.isInverted = true
            _ = XCTWaiter.wait(for: [transferWindow], timeout: 60)
        }
        app.terminate()
    }
}
