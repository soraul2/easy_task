import Foundation
import Testing
import SwiftData
@testable import EasyTaskCore

@Test
func applyingSameDoneStatusPreservesCompletionMetadata() throws {
    let plannedDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let firstCompletionDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let secondCompletionDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
    let task = Task(title: "완료 날짜 보존", plannedAt: plannedDate, order: 100)

    TaskRules.applyStatus(.done, to: task, now: firstCompletionDate)
    let completedAt = task.completedAt
    let completedDayKey = task.completedDayKey
    let updatedAt = task.updatedAt

    TaskRules.applyStatus(.done, to: task, now: secondCompletionDate)

    #expect(task.completedAt == completedAt)
    #expect(task.completedDayKey == completedDayKey)
    #expect(task.updatedAt == updatedAt)
}

@Test
func backupUnsupportedVersionErrorIncludesVersion() {
    let error = BackupServiceError.unsupportedVersion(99)

    #expect(error.errorDescription?.contains("99") == true)
}

@Test
func dayKeyRoundTripsDateString() throws {
    let date = try #require(DayKey.date(from: "2026-07-06"))

    #expect(DayKey.key(for: date) == "2026-07-06")
}

@Test
func carryoverTasksAreOpenPastTasksSortedByDayAndOrder() throws {
    let olderDay = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let laterPastDay = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
    let today = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9)))

    let olderSecond = Task(title: "오래된 두 번째", plannedAt: olderDay, order: 200)
    let olderFirst = Task(title: "오래된 첫 번째", plannedAt: olderDay, order: 100)
    let laterDoing = Task(title: "진행 중 과거 작업", status: .doing, plannedAt: laterPastDay, order: 100)
    let todayTask = Task(title: "오늘 작업", plannedAt: today, order: 100)
    let donePast = Task(title: "완료된 과거 작업", plannedAt: olderDay, order: 300)
    let archivedPast = Task(title: "보관된 과거 작업", plannedAt: olderDay, order: 400)

    TaskRules.applyStatus(.done, to: donePast, now: now)
    archivedPast.archivedAt = now

    let result = TaskRules.carryoverTasks(
        [todayTask, olderSecond, laterDoing, donePast, archivedPast, olderFirst],
        before: DayKey.key(for: today)
    )

    #expect(result.map(\.title) == ["오래된 첫 번째", "오래된 두 번째", "진행 중 과거 작업"])
}

@Test
func movingTaskToDateUpdatesDayKeyOrderAndTimestamp() throws {
    let originalDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let targetDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 15)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 10)))
    let task = Task(title: "날짜 이동", plannedAt: originalDate, order: 100)

    TaskRules.move(task, to: targetDate, order: 500, now: now)

    #expect(task.plannedAt == DayKey.startOfDay(for: targetDate))
    #expect(task.plannedDayKey == "2026-07-08")
    #expect(task.order == 500)
    #expect(task.updatedAt == now)
}

@Test
func completingAllTasksUsesSharedStatusRule() throws {
    let plannedDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let first = Task(title: "첫 번째", plannedAt: plannedDate, order: 100)
    let second = Task(title: "두 번째", status: .doing, plannedAt: plannedDate, order: 200)

    TaskRules.completeAll([first, second], now: now)

    #expect(first.status == TaskStatus.done.rawValue)
    #expect(first.completedAt == now)
    #expect(first.completedDayKey == "2026-07-07")
    #expect(second.status == TaskStatus.done.rawValue)
    #expect(second.completedAt == now)
    #expect(second.completedDayKey == "2026-07-07")
}

@Test
func boardQueryRulesPreserveDesktopAndMobileCarryoverPolicies() throws {
    let yesterday = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
    let today = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let todayKey = DayKey.key(for: today)
    let completionTime = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 11)))

    let todayTask = Task(title: "오늘 작업", plannedAt: today, order: 100)
    let carryoverTask = Task(title: "이월 작업", plannedAt: yesterday, order: 100)
    let doneToday = Task(title: "오늘 완료", plannedAt: yesterday, order: 200)
    TaskRules.applyStatus(.done, to: doneToday, now: completionTime)

    let tasks = [carryoverTask, doneToday, todayTask]
    let desktopBoard = BoardQueryRules.tasksForBoard(
        tasks,
        selectedDayKey: todayKey,
        todayKey: todayKey
    )
    let mobileBoard = BoardQueryRules.tasksForBoard(
        tasks,
        selectedDayKey: todayKey,
        todayKey: todayKey,
        includeCarryoverOnToday: true
    )

    #expect(Set(desktopBoard.map(\.title)) == Set(["오늘 완료", "오늘 작업"]))
    #expect(Set(mobileBoard.map(\.title)) == Set(["오늘 완료", "이월 작업", "오늘 작업"]))
    #expect(BoardQueryRules.tasks(mobileBoard, matching: .todo).map(\.title) == ["이월 작업", "오늘 작업"])
    #expect(BoardQueryRules.tasks(mobileBoard, matching: .done).map(\.title) == ["오늘 완료"])
}

@Test
func boardNextOrderUsesOnlyTargetDayAndStatus() throws {
    let targetDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let otherDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let targetKey = DayKey.key(for: targetDate)

    let targetTodo = Task(title: "대상 날짜", plannedAt: targetDate, order: 300)
    let targetDoing = Task(title: "진행 중", status: .doing, plannedAt: targetDate, order: 900)
    let otherTodo = Task(title: "다른 날짜", plannedAt: otherDate, order: 9_000)

    let nextTodoOrder = BoardQueryRules.nextOrder(
        in: [targetTodo, targetDoing, otherTodo],
        dayKey: targetKey,
        status: .todo
    )
    let nextDoingOrder = BoardQueryRules.nextOrder(
        in: [targetTodo, targetDoing, otherTodo],
        dayKey: targetKey,
        status: .doing
    )

    #expect(nextTodoOrder == 400)
    #expect(nextDoingOrder == 1_000)
}

@Test
@MainActor
func calendarTemplatePlacementSkipsDuplicateTitles() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let targetDate = DayKey.startOfDay(for: Date())
    let targetDayKey = DayKey.key(for: targetDate)
    let template = TaskTemplate(name: "운동 루틴")
    let duplicateItem = TaskTemplateItem(templateId: template.id, title: "스트레칭 10분", order: 100)
    let newItem = TaskTemplateItem(
        templateId: template.id,
        title: "근력 운동 30분",
        estimatedMinutes: 30,
        order: 200
    )
    let existingTask = Task(
        title: "스트레칭 10분",
        plannedAt: targetDate,
        order: 100
    )

    context.insert(template)
    context.insert(duplicateItem)
    context.insert(newItem)
    context.insert(existingTask)

    let createdCount = TemplateService.applyTemplate(
        template,
        items: [duplicateItem, newItem],
        selectedDates: [targetDate],
        existingTasks: [existingTask],
        in: context
    )

    let tasks = try context.fetch(FetchDescriptor<Task>())
        .filter { $0.plannedDayKey == targetDayKey }

    #expect(createdCount == 1)
    #expect(tasks.count == 2)
    #expect(tasks.contains { $0.title == "근력 운동 30분" })
    #expect(tasks.first { $0.title == "근력 운동 30분" }?.estimatedMinutes == 30)
}

@Test
@MainActor
func singleDateTemplatePlacementUsesTargetDayOrderAndSkipsBlankTitles() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let targetDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
    let otherDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 9)))
    let template = TaskTemplate(name: "아침 루틴")
    let blankItem = TaskTemplateItem(templateId: template.id, title: "   ", order: 100)
    let newItem = TaskTemplateItem(templateId: template.id, title: "  물 마시기  ", order: 200)
    let existingSameDay = Task(title: "기존 작업", plannedAt: targetDate, order: 400)
    let existingOtherDay = Task(title: "다른 날 작업", plannedAt: otherDate, order: 9_000)

    context.insert(template)
    context.insert(blankItem)
    context.insert(newItem)
    context.insert(existingSameDay)
    context.insert(existingOtherDay)

    let createdCount = TemplateService.applyTemplate(
        template,
        items: [newItem, blankItem],
        selectedDate: targetDate,
        existingTasks: [existingSameDay, existingOtherDay],
        in: context
    )

    let tasks = try context.fetch(FetchDescriptor<Task>())
        .filter { $0.plannedDayKey == "2026-07-08" }

    #expect(createdCount == 1)
    #expect(tasks.count == 2)
    #expect(tasks.first { $0.title == "물 마시기" }?.order == 500)
}

@Test
func templateListRulesSearchAndSortFavoritesFirst() {
    let work = TaskTemplate(name: "업무 정리 루틴", isFavorite: false)
    let workout = TaskTemplate(name: "운동 루틴", isFavorite: true)
    let review = TaskTemplate(name: "주간 회고 루틴", isFavorite: false)
    let items = [
        TaskTemplateItem(templateId: work.id, title: "막힌 이슈 정리", order: 100),
        TaskTemplateItem(templateId: workout.id, title: "스트레칭 10분", order: 100),
        TaskTemplateItem(templateId: review.id, title: "완료 작업 확인", order: 100)
    ]

    let sorted = TemplateListRules.filterAndSort([work, review, workout], items: items, query: "")
    let favoritesOnly = TemplateListRules.filterAndSort(
        [work, review, workout],
        items: items,
        query: "",
        scope: .favorites
    )
    let searchedByItem = TemplateListRules.filterAndSort([work, review, workout], items: items, query: "스트레칭")

    #expect(sorted.map(\.name) == ["운동 루틴", "업무 정리 루틴", "주간 회고 루틴"])
    #expect(favoritesOnly.map(\.name) == ["운동 루틴"])
    #expect(searchedByItem.map(\.name) == ["운동 루틴"])
    #expect(TemplateListRules.preferredScope(for: [work, review]) == .all)
    #expect(TemplateListRules.preferredScope(for: [workout, work, review]) == .favorites)
}

@Test
func calendarEventTimelineBadgeText() throws {
    let today = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let tomorrow = DayKey.addingDays(1, to: today)
    let afterTwoDays = DayKey.addingDays(2, to: today)

    let activeEvent = CalendarEvent(title: "TodoApp MVP 설계", startAt: today, endAt: afterTwoDays)
    let futureEvent = CalendarEvent(title: "다음 릴리즈", startAt: tomorrow, endAt: afterTwoDays)
    let endingTodayEvent = CalendarEvent(title: "테스트 일정", startAt: DayKey.addingDays(-2, to: today), endAt: today)
    let singleDayEvent = CalendarEvent(title: "하루 일정", startAt: today, endAt: today)

    #expect(CalendarEventTimeline.badgeText(for: activeEvent, today: today) == "종료 D-2")
    #expect(CalendarEventTimeline.badgeText(for: futureEvent, today: today) == "시작 D-1")
    #expect(CalendarEventTimeline.badgeText(for: endingTodayEvent, today: today) == "오늘 종료")
    #expect(CalendarEventTimeline.badgeText(for: singleDayEvent, today: today) == "오늘")
}

@Test
func specialDayStoreLoadsBundledKoreanSpecialDays() {
    let store = SpecialDayStore.load()
    let liberationDay = store.days(on: "2026-08-15")
    let overlappingDay = store.days(on: "2028-10-03")

    #expect(liberationDay.contains { $0.name == "광복절" && $0.isPublicHoliday })
    #expect(overlappingDay.contains { $0.name == "개천절" })
    #expect(overlappingDay.contains { $0.name == "추석" })
}

@Test
func dailyReviewContentRuleDetectsTextMetadataAndImages() {
    let emptyReview = DailyReview(dayKey: "2026-07-06", content: "   ")
    let titleOnlyReview = DailyReview(dayKey: "2026-07-06", title: "회고", content: "")
    let weatherOnlyReview = DailyReview(dayKey: "2026-07-06", weather: "맑음", content: "")
    let moodOnlyReview = DailyReview(dayKey: "2026-07-06", mood: "좋음", content: "")
    let imageOnlyReview = DailyReview(dayKey: "2026-07-06", content: "", imageFileNames: ["sample.jpg"])

    #expect(DailyReviewRules.hasContent(emptyReview) == false)
    #expect(DailyReviewRules.hasContent(titleOnlyReview))
    #expect(DailyReviewRules.hasContent(weatherOnlyReview))
    #expect(DailyReviewRules.hasContent(moodOnlyReview))
    #expect(DailyReviewRules.hasContent(imageOnlyReview))
}

@Test
@MainActor
func dailyReviewServiceSavesReviewAndSynchronizesDiaryBlocks() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let dayKey = "2026-07-06"

    let emptyDraft = DailyReviewService.save(
        review: nil,
        dayKey: dayKey,
        content: "   ",
        in: context
    )
    #expect(emptyDraft == nil)

    let review = try #require(DailyReviewService.save(
        review: nil,
        dayKey: dayKey,
        title: "  회고  ",
        content: "  오늘 메모  ",
        imageFileNames: ["first.jpg"],
        in: context
    ))
    var blocks = try context.fetch(FetchDescriptor<DiaryBlock>())
        .filter { $0.reviewId == review.id }
        .sorted { $0.order < $1.order }

    #expect(review.title == "회고")
    #expect(review.content == "오늘 메모")
    #expect(review.imageFileNames == ["first.jpg"])
    #expect(blocks.map(\.type) == [DiaryBlockType.text.rawValue, DiaryBlockType.image.rawValue])
    #expect(blocks.first?.text == "오늘 메모")
    #expect(blocks.last?.imageFileName == "first.jpg")

    DailyReviewService.save(
        review: review,
        dayKey: dayKey,
        title: "",
        content: "수정된 메모",
        imageFileNames: [],
        in: context
    )
    blocks = try context.fetch(FetchDescriptor<DiaryBlock>())
        .filter { $0.reviewId == review.id }
        .sorted { $0.order < $1.order }

    #expect(review.title == "")
    #expect(review.content == "수정된 메모")
    #expect(review.imageFileNames.isEmpty)
    #expect(blocks.count == 1)
    #expect(blocks.first?.type == DiaryBlockType.text.rawValue)
    #expect(blocks.first?.text == "수정된 메모")
}

@Test
func dailyReviewServiceMigratesLegacyDiaryBlocksIntoSummaryFields() {
    let review = DailyReview(dayKey: "2026-07-06", content: "")
    let textBlock = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .text,
        text: "첫 번째 줄",
        order: 100
    )
    let imageBlock = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .image,
        imageFileName: "legacy.jpg",
        order: 200
    )

    let didMigrate = DailyReviewService.migrateBlockSummaryIfNeeded(
        for: review,
        blocks: [imageBlock, textBlock]
    )

    #expect(didMigrate)
    #expect(review.content == "첫 번째 줄")
    #expect(review.imageFileNames == ["legacy.jpg"])
}

@Test
func appThemePresetsMeetTextContrastTarget() {
    #expect(AppThemePreset.defaultID == "appleSystem")
    #expect(AppThemePreset.all.first?.id == AppThemePreset.defaultID)

    for preset in AppThemePreset.all {
        for appearance in AppThemeAppearance.allCases {
            let colors = preset.colorSet(for: appearance)
            let sharedSurfaces = [
                colors.backgroundTop,
                colors.backgroundBottom,
                colors.panel,
                colors.input,
                colors.floatingBar,
                colors.selectedTab,
                colors.columnTodo,
                colors.columnDoing,
                colors.columnDone
            ]

            for surface in sharedSurfaces {
                #expect(colors.primaryText.contrastRatio(to: surface) >= 4.5)
                #expect(colors.secondaryText.contrastRatio(to: surface) >= 4.5)
            }

            for cardSurface in [colors.todo, colors.doing, colors.done] {
                #expect(colors.cardText.contrastRatio(to: cardSurface) >= 4.5)
                #expect(colors.cardMutedText.contrastRatio(to: cardSurface) >= 4.5)
            }

            for eventColor in colors.eventPalette {
                #expect(colors.eventText.contrastRatio(to: eventColor) >= 4.5)
            }
        }
    }
}

@Test
func lightThemeStatusColorsAreDistinctWithinEachPreset() {
    func distance(_ lhs: ThemeColorToken, _ rhs: ThemeColorToken) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        return (red * red + green * green + blue * blue).squareRoot()
    }

    for preset in AppThemePreset.all {
        let colors = preset.colorSet(for: .light)

        #expect(distance(colors.columnTodo, colors.columnDoing) >= 0.06)
        #expect(distance(colors.columnTodo, colors.columnDone) >= 0.06)
        #expect(distance(colors.columnDoing, colors.columnDone) >= 0.06)
        #expect(distance(colors.todo, colors.doing) >= 0.06)
        #expect(distance(colors.todo, colors.done) >= 0.06)
        #expect(distance(colors.doing, colors.done) >= 0.06)
    }
}
