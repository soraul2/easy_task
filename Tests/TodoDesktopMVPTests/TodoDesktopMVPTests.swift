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
