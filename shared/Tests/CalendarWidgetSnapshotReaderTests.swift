import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func calendarWidgetReaderMatchesCallerContextSnapshotIncludingTaskSummariesAndTheme() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let date = try #require(DayKey.date(from: "2026-10-12"))
    let tomorrow = DayKey.addingDays(1, to: date)
    context.insert(CalendarEvent(title: "오늘 회의", startAt: date, endAt: tomorrow,
                                 color: CalendarEventColor.red.rawValue))
    context.insert(Task(title: "진행 작업", status: .doing, plannedAt: date, order: 200))
    context.insert(Task(title: "할 일", plannedAt: date, order: 100))
    let completed = Task(title: "완료한 작업", status: .done, plannedAt: tomorrow, order: 100)
    completed.completedDayKey = DayKey.key(for: date)
    context.insert(completed)
    try context.save()

    let expected = try CalendarWidgetSnapshotReader.makeSnapshot(in: context, referenceDate: date, themeID: "roseLilac")
    let actual = try await freshCalendarWidgetReaderSnapshot(container: container, date: date, themeID: "roseLilac")
    #expect(actual == expected)
    #expect(actual.themeID == "roseLilac")
    #expect(actual.lockScreenSummary(onDayKey: DayKey.key(for: date))?.doingCount == 1)
    #expect(actual.plannerTaskPreviews(onDayKey: DayKey.key(for: date))?.map(\.title) == ["진행 작업", "할 일"])
}

@Test @MainActor
func calendarWidgetReaderSelectsLatestEventBeforeRangeOrBlankFiltering() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let date = try #require(DayKey.date(from: "2026-10-12"))
    let outside = DayKey.addingMonths(8, to: date)
    let movedID = UUID()
    context.insert(CalendarEvent(id: movedID, title: "날짜 변경 전", startAt: date, endAt: date,
                                 createdAt: date, updatedAt: date))
    context.insert(CalendarEvent(id: movedID, title: "범위 밖 최신 일정", startAt: outside, endAt: outside,
                                 createdAt: date, updatedAt: date.addingTimeInterval(1)))
    let blankID = UUID()
    context.insert(CalendarEvent(id: blankID, title: "제목 변경 전", startAt: date, endAt: date,
                                 createdAt: date, updatedAt: date))
    context.insert(CalendarEvent(id: blankID, title: " \n ", startAt: date, endAt: date,
                                 createdAt: date, updatedAt: date.addingTimeInterval(1)))
    let newerID = UUID()
    context.insert(CalendarEvent(id: newerID, title: "이전 제목", startAt: date, endAt: date,
                                 createdAt: date, updatedAt: date))
    let newer = CalendarEvent(id: newerID, title: "최신 제목", startAt: date, endAt: date,
                              createdAt: date, updatedAt: date.addingTimeInterval(1))
    let renderID = newer.instanceID
    context.insert(newer)
    try context.save()

    let actual = try await freshCalendarWidgetReaderSnapshot(container: container, date: date)
    let expected = try CalendarWidgetSnapshotReader.makeSnapshot(in: context, referenceDate: date)
    #expect(actual == expected)
    #expect(actual.events.map(\.id) == [newerID])
    #expect(actual.events.map(\.title) == ["최신 제목"] && actual.events.first?.renderID == renderID)
    #expect(actual.totalEventCount(onDayKey: DayKey.key(for: date)) == 1)
}

@Test @MainActor
func calendarWidgetFreshReaderSeesSavedUpdatesAndDeletionAcrossPublications() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PlanBaseWidgetReader-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makePersistent(storeURL: directory.appendingPathComponent("fixture.store"), mode: .local)
    let context = container.mainContext
    context.autosaveEnabled = false
    let date = try #require(DayKey.date(from: "2026-10-12"))
    let event = CalendarEvent(title: "저장 전 제목", startAt: date, endAt: date)
    let task = Task(title: "할 일", plannedAt: date, order: 100)
    context.insert(event)
    context.insert(task)
    try context.save()
    let first = try await freshCalendarWidgetReaderSnapshot(container: container, date: date)
    #expect(first.events.first?.title == "저장 전 제목")
    event.title = "저장한 최신 제목"
    task.status = TaskStatus.doing.rawValue
    try context.save()
    let second = try await freshCalendarWidgetReaderSnapshot(container: container, date: date)
    #expect(second.events.first?.title == "저장한 최신 제목")
    #expect(second.lockScreenSummary(onDayKey: DayKey.key(for: date))?.doingCount == 1)
    context.delete(event)
    context.delete(task)
    try context.save()
    let third = try await freshCalendarWidgetReaderSnapshot(container: container, date: date)
    #expect(third.events.isEmpty)
    #expect(third.plannerTaskPreviews(onDayKey: DayKey.key(for: date))?.isEmpty == true)
}

@Test @MainActor
func calendarWidgetCallerContextPathKeepsPendingEditsOutOfSavedReader() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let date = try #require(DayKey.date(from: "2026-10-12"))
    let task = Task(title: "저장한 할 일", plannedAt: date, order: 100)
    context.insert(task)
    try context.save()
    task.title = "현재 편집한 제목"
    let pending = try CalendarWidgetSnapshotReader.makeSnapshot(in: context, referenceDate: date)
    let saved = try await freshCalendarWidgetReaderSnapshot(container: container, date: date)
    #expect(pending.plannerTaskPreviews(onDayKey: DayKey.key(for: date))?.first?.title == "현재 편집한 제목")
    #expect(saved.plannerTaskPreviews(onDayKey: DayKey.key(for: date))?.first?.title == "저장한 할 일")
    #expect(context.hasChanges)
}

@Test @MainActor
func calendarWidgetReaderTaskQueryFailurePreservesCalendarWithoutClaimingTaskCoverage() throws {
    let date = try #require(DayKey.date(from: "2026-10-12"))
    let event = CalendarEvent(title: "일정 유지", startAt: date, endAt: date)
    let snapshot = try CalendarWidgetSnapshotReader.makeSnapshot(
        referenceDate: date,
        themeID: "roseLilac",
        fetchEvents: { [event] },
        fetchTasks: { throw CalendarWidgetReaderInjectedFailure.query }
    )
    #expect(snapshot.events.map(\.title) == ["일정 유지"])
    #expect(snapshot.totalEventCount(onDayKey: DayKey.key(for: date)) == 1)
    #expect(snapshot.lockScreenDaySummaries == nil && snapshot.plannerTaskPreviewsByDayKey == nil)
    #expect(!snapshot.hasLockScreenCoverage(dayKey: DayKey.key(for: date)))
}

@Test @MainActor
func calendarWidgetReaderEventQueryFailurePropagatesBeforeTaskQuery() throws {
    let date = try #require(DayKey.date(from: "2026-10-12"))
    var taskQueries = 0
    #expect(throws: CalendarWidgetReaderInjectedFailure.query) {
        _ = try CalendarWidgetSnapshotReader.makeSnapshot(
            referenceDate: date,
            themeID: AppThemePreset.defaultID,
            fetchEvents: { throw CalendarWidgetReaderInjectedFailure.query },
            fetchTasks: { taskQueries += 1; return [] }
        )
    }
    #expect(taskQueries == 0)
}

private enum CalendarWidgetReaderInjectedFailure: Error, Equatable { case query }

private func freshCalendarWidgetReaderSnapshot(
    container: ModelContainer,
    date: Date,
    themeID: String = AppThemePreset.defaultID
) async throws -> CalendarWidgetSnapshot {
    try await Swift.Task.detached {
        let reader = CalendarWidgetSnapshotReader(modelContainer: container)
        return try await reader.loadSnapshot(referenceDate: date, themeID: themeID)
    }.value
}
