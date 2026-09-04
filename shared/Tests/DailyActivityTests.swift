import Foundation
import SwiftData
import Testing

@testable import EasyTaskCore

private func activityDate(_ key: String, hour: Int = 0, minute: Int = 0) throws -> Date {
    let date = try #require(DayKey.date(from: key))
    return try #require(DayKey.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date))
}

private func dailyFilter(_ day: Date) -> ArchiveFilter {
    ArchiveFilter(contentMode: .dailyActivity, period: .custom, customStartDate: day, customEndDate: day)
}

@Test @MainActor
func dailyActivityRefreshIncludesPendingEditsAndLateHistoricalImport() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let day = try activityDate("2020-01-01")
    let task = Task(title: "과거 작업", plannedAt: day, order: 100)
    context.insert(task)
    let start = TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: day)
    context.insert(start)
    try context.save()
    let service = DailyActivityQueryService(context: context)
    let first = try await service.page(filter: dailyFilter(day))
    #expect(first.records.first?.activityEntries?.first?.evidence.progressSeconds == 0)
    // User edits use the normal save boundary; imported progress can still be pending.
    let editable = try #require(context.fetch(BoundedQueryService.taskCandidatesDescriptor(id: task.id)).first)
    try PersistenceCommandService.perform(in: context) {
        editable.title = "제목 변경"
        editable.updatedAt = day.addingTimeInterval(1)
    }
    context.insert(TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: day.addingTimeInterval(600)))
    service.invalidate()
    let refreshed = try await service.page(filter: dailyFilter(day))
    #expect(refreshed.records.first?.activityEntries?.first?.evidence.progressSeconds == 600)
    #expect(refreshed.records.first?.activityEntries?.first?.title == "제목 변경")
    try context.save()
    service.invalidate()
    let all = try await service.page(filter: ArchiveFilter(contentMode: .dailyActivity), referenceDate: day.addingTimeInterval(86400 * 365))
    #expect(all.records.map(\.dayKey) == ["2020-01-01"])
}

@Test
func dailyActivityRespectsShortAndLongCalendarDays() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
        let end = try #require(calendar.date(byAdding: .day, value: 1, to: date))
        let projection = TaskProgressProjection(intervals: [.init(startedAt: date, stoppedAt: end)])
        #expect(DailyActivityRules.progressEvidence(projection, on: date, calendar: calendar).progressSeconds == Double(hours * 3600))
    }
}

@Test @MainActor
func dailyActivityCombinesWorkWithoutReviewAndKeepsCompletionAfterReopening() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try activityDate("2026-09-04")
    let task = Task(title: "기획서", status: .todo, plannedAt: try activityDate("2026-09-02"), order: 100)
    context.insert(task)
    try TaskActivityService.recordCapturedCompletion(taskID: task.id, occurredAt: day, in: context)
    context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: day))
    context.insert(
        TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: day.addingTimeInterval(2400)))
    context.insert(
        FocusSession(
            taskId: task.id, startedAt: day, endedAt: day.addingTimeInterval(1500),
            plannedDurationSeconds: 1500, focusedDurationSeconds: 1200, outcome: .completed))
    try context.save()
    let page = try await DailyActivityQueryService(context: context).page(filter: dailyFilter(day))
    let record = try #require(page.records.first)
    let entry = try #require(record.activityEntries?.first)
    #expect(record.review == nil)
    #expect(record.activityEntries?.count == 1)
    #expect(entry.title == "기획서")
    #expect(entry.evidence.completed)
    #expect(entry.evidence.progressSeconds == 2400)
    #expect(entry.evidence.focusSeconds == 1200)
    #expect(entry.evidence.focusSessionCount == 1)
    #expect(task.status == TaskStatus.todo.rawValue)
}

@Test @MainActor
func dailyActivityClipsClosedProgressButAttributesFocusToEndDay() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let start = try activityDate("2026-09-03", hour: 23, minute: 50)
    let end = try activityDate("2026-09-04", hour: 0, minute: 20)
    let task = Task(title: "읽기", plannedAt: start, order: 100)
    context.insert(task)
    context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: start))
    context.insert(TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: end))
    context.insert(
        FocusSession(
            taskId: task.id, startedAt: start, endedAt: end,
            plannedDurationSeconds: 1800, focusedDurationSeconds: 1500, outcome: .stopped))
    try context.save()
    let service = DailyActivityQueryService(context: context)
    let first = try await service.page(filter: dailyFilter(start))
    let second = try await service.page(filter: dailyFilter(end))
    #expect(first.records.first?.activityEntries?.first?.evidence.progressSeconds == 600)
    #expect(first.records.first?.activityEntries?.first?.evidence.focusSeconds == 0)
    #expect(second.records.first?.activityEntries?.first?.evidence.progressSeconds == 1200)
    #expect(second.records.first?.activityEntries?.first?.evidence.focusSeconds == 1500)
}

@Test @MainActor
func dailyActivityFindsIntervalsWithBothBoundariesOutsideWindow() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let task = Task(title: "장기 진행", plannedAt: try activityDate("2026-08-01"), order: 100)
    context.insert(task)
    context.insert(
        TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: try activityDate("2026-08-01")))
    context.insert(
        TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: try activityDate("2026-09-04")))
    try context.save()
    let page = try await DailyActivityQueryService(context: context).page(
        filter: dailyFilter(try activityDate("2026-08-20")))
    #expect(page.records.first?.dayKey == "2026-08-20")
    #expect(page.records.first?.activityEntries?.first?.evidence.progressSeconds == 86400)
}

@Test @MainActor
func dailyActivityDoesNotInventOpenOrCompatibilityDuration() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let start = try activityDate("2026-09-01", hour: 10)
    let task = Task(title: "열린 시작", plannedAt: start, order: 100)
    context.insert(task)
    context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: start))
    context.insert(TaskProgressEvent(taskId: UUID(), kind: .stopped, occurredAt: start))
    try context.save()
    let service = DailyActivityQueryService(context: context)
    let first = try await service.page(filter: dailyFilter(start))
    let later = try await service.page(filter: dailyFilter(try activityDate("2026-09-03")))
    #expect(first.records.first?.activityEntries?.first?.evidence.started == true)
    #expect(first.records.first?.activityEntries?.first?.evidence.progressSeconds == 0)
    #expect(later.records.isEmpty)
    context.insert(
        TaskProgressEvent(
            taskId: task.id, kind: .stopped, origin: .compatibilityBoundary,
            occurredAt: try activityDate("2026-09-02")))
    try context.save()
    service.invalidate()
    let unknown = try await service.page(filter: dailyFilter(start))
    #expect(unknown.records.first?.activityEntries?.first?.evidence.unknownProgress == true)
    #expect(unknown.records.first?.activityEntries?.first?.evidence.progressSeconds == 0)
}

@Test @MainActor
func dailyActivityPreservesMissingTaskAndDeduplicatesFocusVersions() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try activityDate("2026-09-04")
    let taskID = UUID()
    let sessionID = UUID()
    for update in 0..<2 {
        context.insert(
            FocusSession(
                id: sessionID, taskId: taskID, startedAt: day, endedAt: day.addingTimeInterval(1000),
                plannedDurationSeconds: 1500, focusedDurationSeconds: 600 + update * 300,
                outcome: .stopped, updatedAt: day.addingTimeInterval(Double(update))))
    }
    try context.save()
    let page = try await DailyActivityQueryService(context: context).page(filter: dailyFilter(day))
    let entry = try #require(page.records.first?.activityEntries?.first)
    #expect(entry.canOpenTask == false)
    #expect(entry.evidence.focusSeconds == 900)
    #expect(entry.evidence.focusSessionCount == 1)
    #expect(page.records.first?.tasks.isEmpty == true)
}

@Test @MainActor
func dailyActivityFallbackDoesNotDuplicateCapturedActivityOnAnotherDate() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let planned = try activityDate("2026-09-02")
    let actual = try activityDate("2026-09-04")
    let delayed = Task(title: "나중에 완료", status: .done, plannedAt: planned, order: 100)
    delayed.completedDayKey = "2026-09-02"
    let legacy = Task(title: "이전 완료", status: .done, plannedAt: planned, order: 200)
    legacy.completedDayKey = "2026-09-02"
    context.insert(delayed)
    context.insert(legacy)
    try TaskActivityService.recordCapturedCompletion(taskID: delayed.id, occurredAt: actual, in: context)
    try context.save()
    let service = DailyActivityQueryService(context: context)
    let oldDay = try await service.page(filter: dailyFilter(planned))
    let newDay = try await service.page(filter: dailyFilter(actual))
    #expect(oldDay.records.first?.activityEntries?.map(\.id) == [legacy.id])
    #expect(oldDay.records.first?.activityEntries?.first?.evidence.legacyCompletion == true)
    #expect(newDay.records.first?.activityEntries?.map(\.id) == [delayed.id])
}

@Test @MainActor
func dailyActivitySearchAndPaginationIncludeProgressOnlyDays() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let today = try activityDate("2026-09-04")
    for offset in 0..<35 {
        let date = DayKey.addingDays(-offset, to: today)
        let task = Task(title: "진행 \(offset)", plannedAt: date, order: 100)
        context.insert(task)
        context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: date))
    }
    try context.save()
    let service = DailyActivityQueryService(context: context)
    let filter = ArchiveFilter(contentMode: .dailyActivity)
    let first = try await service.page(filter: filter, referenceDate: today)
    let second = try await service.page(
        filter: filter, beforeDayKey: first.nextBeforeDayKey, referenceDate: today)
    #expect(first.records.count == 30)
    #expect(first.hasMore)
    #expect(second.records.count == 5)
    #expect(!second.hasMore)
    #expect(Set((first.records + second.records).map(\.dayKey)).count == 35)
    var search = filter
    search.searchText = "진행 34"
    let result = try await service.page(filter: search, referenceDate: today)
    #expect(result.records.count == 1)
    #expect(result.records.first?.activityEntries?.first?.title == "진행 34")
}

@Test @MainActor
func dailyActivityLegacyFallbackUsesLatestTaskVersionAcrossStatuses() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try activityDate("2026-09-04")
    let id = UUID()
    let old = Task(id: id, title: "이전 완료", status: .done, plannedAt: day, order: 100)
    old.completedDayKey = "2026-09-04"
    old.updatedAt = day
    let current = Task(id: id, title: "다시 진행", status: .todo, plannedAt: day, order: 100)
    current.updatedAt = day.addingTimeInterval(1)
    context.insert(old)
    context.insert(current)
    try context.save()
    let page = try await DailyActivityQueryService(context: context).page(filter: dailyFilter(day))
    #expect(page.records.isEmpty)
    #expect(try BoundedQueryService.archiveTasks(from: "2026-09-04", through: "2026-09-04", basis: .completed, in: context).isEmpty)
}
