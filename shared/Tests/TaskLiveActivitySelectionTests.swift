import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@MainActor
private func selectionTask(_ title: String, status: TaskStatus = .todo, order: Double = 0,
                           day: Date, in context: ModelContext) -> Task {
    let task = Task(title: title, status: status, plannedAt: day, order: order)
    context.insert(task)
    return task
}

@Test @MainActor
func taskLiveActivitySelectionCyclesEveryUnfinishedTaskWithoutChangingModels() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = ModelContext(container)
    let today = try #require(DayKey.date(from: "2026-09-17"))
    let a = selectionTask("A", day: today, in: context)
    let b = selectionTask("B", order: 1, day: today, in: context)
    let c = selectionTask("C", status: .doing, day: today, in: context)
    let d = selectionTask("D", status: .doing, order: 1, day: today, in: context)
    _ = selectionTask("완료", status: .done, day: today, in: context)
    _ = selectionTask("이월", day: DayKey.addingDays(-1, to: today), in: context)
    try context.save()
    let suite = "LiveSelectionTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TaskLiveActivitySelectionStore(defaults: defaults)
    let tasks = try TaskLiveActivitySelectionRules.fetchTodayTasks(in: context, dayKey: "2026-09-17")
    let originalDates = tasks.map(\.updatedAt)
    let originalStatuses = tasks.map(\.status)
    var selected = try #require(store.selection(tasks: tasks, dayKey: "2026-09-17"))
    #expect(selected.taskID == c.id)
    for expected in [d.id, a.id, b.id, c.id] {
        let old = selected
        try TaskLiveActivityCommandService.browse(taskID: old.taskID, token: old.token, in: context,
                                                selectionStore: store, now: today)
        selected = try #require(store.selection(tasks: tasks, dayKey: "2026-09-17"))
        #expect(selected.taskID == expected)
        #expect(selected.token != old.token)
        #expect(throws: TaskLiveActivitySelectionError.staleSelection) {
            try store.advance(taskID: old.taskID, token: old.token, tasks: tasks, dayKey: "2026-09-17")
        }
    }
    #expect(tasks.map(\.updatedAt) == originalDates)
    #expect(tasks.map(\.status) == originalStatuses)
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 0)
    #expect(!context.hasChanges)
}

@Test @MainActor
func taskLiveActivitySelectedTodoStartsImmediatelyAfterBrowseAndDoesNotStopOtherDoing() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = ModelContext(container)
    let today = try #require(DayKey.date(from: "2026-09-17"))
    let running = selectionTask("이미 진행", status: .doing, day: today, in: context)
    let todo = selectionTask("선택할 할 일", day: today, in: context)
    try context.save()
    let suite = "LiveSelectionTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TaskLiveActivitySelectionStore(defaults: defaults)
    let tasks = [running, todo]
    let initial = try #require(store.selection(tasks: tasks, dayKey: "2026-09-17"))
    let selected = try store.advance(taskID: initial.taskID, token: initial.token, tasks: tasks, dayKey: initial.dayKey)
    try TaskLiveActivityCommandService.start(taskID: todo.id, token: selected.token, in: context, selectionStore: store, now: today)
    #expect(todo.status == TaskStatus.doing.rawValue)
    #expect(running.status == TaskStatus.doing.rawValue)
    #expect(throws: TaskLiveActivitySelectionError.staleSelection) {
        try TaskLiveActivityCommandService.start(taskID: todo.id, token: selected.token, in: context, selectionStore: store, now: today)
    }
    let events = try context.fetch(FetchDescriptor<TaskProgressEvent>())
    #expect(events.count == 1)
    #expect(events.first?.taskId == todo.id)
    #expect(events.first?.kindRawValue == TaskProgressEventKind.started.rawValue)
}

@Test @MainActor
func taskLiveActivityCompletionSelectsTodoThenRemovesLastCandidateAndRejectsRepeatedTap() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = ModelContext(container)
    let now = try #require(DayKey.date(from: "2026-09-17"))
    let first = selectionTask("진행", status: .doing, day: now, in: context)
    let next = selectionTask("남은 할 일", day: now, in: context)
    try context.save()
    let suite = "LiveSelectionTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TaskLiveActivitySelectionStore(defaults: defaults)
    let tasks = [first, next]
    let initial = try #require(store.selection(tasks: tasks, dayKey: "2026-09-17"))
    try TaskLiveActivityCommandService.complete(taskID: first.id, token: initial.token, in: context, selectionStore: store, now: now)
    let pending = try #require(store.selection(tasks: tasks, dayKey: "2026-09-17"))
    #expect(pending.taskID == next.id)
    #expect(pending.status == TaskStatus.todo.rawValue)
    #expect(TaskLiveActivitySelectionRules.next(after: next.id, from: tasks, dayKey: pending.dayKey) == nil)
    #expect(throws: TaskLiveActivitySelectionError.staleSelection) {
        try TaskLiveActivityCommandService.complete(taskID: first.id, token: initial.token, in: context, selectionStore: store, now: now)
    }
    try TaskLiveActivityCommandService.start(taskID: next.id, token: pending.token, in: context, selectionStore: store, now: now)
    let started = try #require(store.selection(tasks: tasks, dayKey: "2026-09-17"))
    try TaskLiveActivityCommandService.complete(taskID: next.id, token: started.token, in: context, selectionStore: store, now: now)
    #expect(store.selection(tasks: tasks, dayKey: "2026-09-17") == nil)
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 2)
}

@Test @MainActor
func taskLiveActivitySelectionPersistsAndInvalidatesMovedOrChangedTaskAndReminderCompletion() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = ModelContext(container)
    let now = try #require(DayKey.date(from: "2026-09-17"))
    let task = selectionTask("오늘", day: now, in: context)
    try context.save()
    let suite = "LiveSelectionTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TaskLiveActivitySelectionStore(defaults: defaults)
    let first = try #require(store.selection(tasks: [task], dayKey: "2026-09-17"))
    let relaunched = TaskLiveActivitySelectionStore(defaults: defaults)
    #expect(relaunched.selection(tasks: [task], dayKey: first.dayKey) == first)
    task.reminderAt = now.addingTimeInterval(3600)
    try TaskLiveActivityCommandService.start(taskID: task.id, token: first.token, in: context, selectionStore: store, now: now)
    let running = try #require(store.selection(tasks: [task], dayKey: first.dayKey))
    #expect(throws: TaskLiveActivitySelectionError.completionNeedsConfirmation) {
        try TaskLiveActivityCommandService.complete(taskID: task.id, token: running.token, in: context, selectionStore: store, now: now)
    }
    #expect(task.status == TaskStatus.doing.rawValue)
    let newer = Task(id: task.id, title: "다른 날짜로 이동", plannedAt: DayKey.addingDays(1, to: now), order: 0,
                     updatedAt: Date())
    context.insert(newer)
    try context.save()
    #expect(try TaskLiveActivitySelectionRules.fetchTodayTasks(in: context, dayKey: first.dayKey).isEmpty)
    #expect(store.selection(tasks: [task, newer], dayKey: first.dayKey) == nil)
    #expect(throws: TaskLiveActivitySelectionError.staleSelection) {
        try TaskLiveActivityCommandService.complete(taskID: task.id, token: running.token, in: context, selectionStore: store, now: now)
    }
}

@Test @MainActor
func taskLiveActivityStaticWidgetStartKeepsExistingRunningGuard() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let now = try #require(DayKey.date(from: "2026-09-17"))
    let first = selectionTask("첫 작업", day: now, in: context)
    let second = selectionTask("다음 작업", day: now, in: context)
    let future = selectionTask("내일 작업", day: DayKey.addingDays(1, to: now), in: context)
    let archived = selectionTask("보관 작업", day: now, in: context)
    archived.archivedAt = now
    try context.save()
    let suite = "LiveSelectionTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TaskLiveActivitySelectionStore(defaults: defaults)
    for invalid in [future, archived] {
        #expect(throws: TaskLiveActivitySelectionError.staleSelection) {
            try TaskLiveActivityCommandService.start(taskID: invalid.id, token: nil, in: context, selectionStore: store, now: now)
        }
    }
    try TaskLiveActivityCommandService.start(taskID: first.id, token: nil, in: context, selectionStore: store, now: now)
    #expect(first.status == TaskStatus.doing.rawValue)
    #expect(throws: TaskLiveActivitySelectionError.staleSelection) {
        try TaskLiveActivityCommandService.start(taskID: second.id, token: nil, in: context, selectionStore: store, now: now)
    }
    #expect(second.status == TaskStatus.todo.rawValue)
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 1)
}

@Test @MainActor
func taskLiveActivitySelectionAfterFailedLifecycleCommandKeepsSavedState() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let now = try #require(DayKey.date(from: "2026-09-17"))
    let task = selectionTask("저장 실패", day: now, in: context)
    try context.save()
    let suite = "LiveSelectionTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TaskLiveActivitySelectionStore(defaults: defaults)
    let before = try #require(store.selection(tasks: [task], dayKey: "2026-09-17"))
    enum Failure: Error { case save }
    do {
        try PersistenceCommandService.perform(in: context) {
            try TaskLifecycleService.applyStatus(.doing, to: task, in: context, now: now)
            throw Failure.save
        }
        Issue.record("상태 저장 실패가 성공으로 반환됨")
    } catch Failure.save { }
    let saved = try TaskLiveActivitySelectionRules.fetchTodayTasks(in: context, dayKey: "2026-09-17")
    #expect(store.selection(tasks: saved, dayKey: "2026-09-17") == before)
    #expect(saved.first?.status == TaskStatus.todo.rawValue)
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 0)
}
