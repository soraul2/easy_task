import Foundation
import SwiftData

public enum TaskLiveActivitySelectionError: Error {
    case staleSelection
    case noOtherTask
    case completionNeedsConfirmation
}

public struct TaskLiveActivitySelection: Codable, Equatable, Sendable {
    public var dayKey: String
    public var taskID: UUID
    public var revision: UUID
    public var status: String
    public var taskUpdatedAt: Date
    public var token: String { "selection:\(revision.uuidString.lowercased())" }
}

public enum TaskLiveActivitySelectionRules {
    @MainActor
    public static func candidates(from tasks: [Task], dayKey: String) -> [Task] {
        TodayTaskWidgetRules.eligibleRepresentatives(from: tasks, dayKey: dayKey)
            .filter { $0.status == TaskStatus.todo.rawValue || $0.status == TaskStatus.doing.rawValue }
    }

    @MainActor
    public static func next(after id: UUID, from tasks: [Task], dayKey: String) -> Task? {
        let candidates = candidates(from: tasks, dayKey: dayKey)
        guard candidates.count > 1, let index = candidates.firstIndex(where: { $0.id == id }) else { return nil }
        return candidates[(index + 1) % candidates.count]
    }

    @MainActor
    public static func fetchTodayTasks(in context: ModelContext, dayKey: String) throws -> [Task] {
        let seed = try context.fetch(BoundedQueryService.widgetPlannedTasksDescriptor(from: dayKey, through: dayKey))
        let ids = Array(Set(seed.map(\.id)))
        var rows: [Task] = []
        for offset in stride(from: 0, to: ids.count, by: 128) {
            let batch = Array(ids[offset..<min(offset + 128, ids.count)])
            rows += try context.fetch(FetchDescriptor<Task>(predicate: #Predicate {
                $0.supersededAt == nil && batch.contains($0.id)
            }))
        }
        return TodayTaskWidgetRules.eligibleRepresentatives(from: rows, dayKey: dayKey)
    }
}

/// Device-local presentation state. Browsing never changes a task or its progress events.
@MainActor
public final class TaskLiveActivitySelectionStore {
    private let defaults: UserDefaults
    private let key = "PlanBaseTaskLiveActivitySelection.v1"

    public init(defaults: UserDefaults = PlanBaseLocalPreferences.current) { self.defaults = defaults }

    public func selection(tasks: [Task], dayKey: String) -> TaskLiveActivitySelection? {
        let candidates = TaskLiveActivitySelectionRules.candidates(from: tasks, dayKey: dayKey)
        let previous = read()
        guard let task = candidates.first(where: { previous?.dayKey == dayKey && $0.id == previous?.taskID })
            ?? candidates.first else {
            defaults.removeObject(forKey: key)
            return nil
        }
        if let previous, previous.dayKey == dayKey, previous.taskID == task.id,
           previous.status == task.status, previous.taskUpdatedAt == task.updatedAt { return previous }
        return write(task: task, dayKey: dayKey)
    }

    @discardableResult
    public func select(taskID: UUID, tasks: [Task], dayKey: String) throws -> TaskLiveActivitySelection {
        guard let task = TaskLiveActivitySelectionRules.candidates(from: tasks, dayKey: dayKey)
            .first(where: { $0.id == taskID }) else { throw TaskLiveActivitySelectionError.staleSelection }
        return write(task: task, dayKey: dayKey)
    }

    public func validatedTask(
        taskID: UUID, token: String, tasks: [Task], dayKey: String, status: TaskStatus? = nil
    ) throws -> Task {
        guard let selection = selection(tasks: tasks, dayKey: dayKey), selection.taskID == taskID,
              selection.token == token,
              let task = TaskLiveActivitySelectionRules.candidates(from: tasks, dayKey: dayKey).first(where: { $0.id == taskID && $0.supersededAt == nil
                  && $0.status == selection.status && $0.updatedAt == selection.taskUpdatedAt }),
              status == nil || task.status == status?.rawValue else { throw TaskLiveActivitySelectionError.staleSelection }
        return task
    }

    @discardableResult
    public func advance(taskID: UUID, token: String, tasks: [Task], dayKey: String) throws -> TaskLiveActivitySelection {
        _ = try validatedTask(taskID: taskID, token: token, tasks: tasks, dayKey: dayKey)
        guard let next = TaskLiveActivitySelectionRules.next(after: taskID, from: tasks, dayKey: dayKey) else {
            throw TaskLiveActivitySelectionError.noOtherTask
        }
        return write(task: next, dayKey: dayKey)
    }

    private func read() -> TaskLiveActivitySelection? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(TaskLiveActivitySelection.self, from: $0) }
    }

    private func write(task: Task, dayKey: String) -> TaskLiveActivitySelection {
        let selection = TaskLiveActivitySelection(dayKey: dayKey, taskID: task.id, revision: UUID(),
                                                  status: task.status, taskUpdatedAt: task.updatedAt)
        if let data = try? JSONEncoder().encode(selection) { defaults.set(data, forKey: key) }
        return selection
    }
}

@MainActor
public enum TaskLiveActivityCommandService {
    public static func browse(
        taskID: UUID, token: String, in context: ModelContext,
        selectionStore: TaskLiveActivitySelectionStore, now: Date = Date()
    ) throws {
        let dayKey = DayKey.key(for: now)
        let tasks = try TaskLiveActivitySelectionRules.fetchTodayTasks(in: context, dayKey: dayKey)
        try selectionStore.advance(taskID: taskID, token: token, tasks: tasks, dayKey: dayKey)
    }

    public static func start(
        taskID: UUID, token: String?, in context: ModelContext,
        selectionStore: TaskLiveActivitySelectionStore, now: Date = Date()
    ) throws {
        let dayKey = DayKey.key(for: now)
        let tasks = try TaskLiveActivitySelectionRules.fetchTodayTasks(in: context, dayKey: dayKey)
        let task: Task
        if let token {
            task = try selectionStore.validatedTask(taskID: taskID, token: token, tasks: tasks, dayKey: dayKey, status: .todo)
        } else {
            // The existing static widget offers Start only when nothing is running.
            guard !tasks.contains(where: { $0.status == TaskStatus.doing.rawValue }),
                  let candidate = tasks.first(where: { $0.id == taskID && $0.status == TaskStatus.todo.rawValue }) else {
                throw TaskLiveActivitySelectionError.staleSelection
            }
            task = candidate
        }
        try PersistenceCommandService.perform(in: context) {
            try TaskLifecycleService.applyStatus(.doing, to: task, in: context, now: now)
        }
        try selectionStore.select(taskID: task.id, tasks: tasks, dayKey: dayKey)
    }

    public static func complete(
        taskID: UUID, token: String, in context: ModelContext,
        selectionStore: TaskLiveActivitySelectionStore, now: Date = Date()
    ) throws {
        let dayKey = DayKey.key(for: now)
        let tasks = try TaskLiveActivitySelectionRules.fetchTodayTasks(in: context, dayKey: dayKey)
        let task = try selectionStore.validatedTask(taskID: taskID, token: token, tasks: tasks, dayKey: dayKey, status: .doing)
        guard !TaskReminderRules.hasUpcomingReminder(task, now: now) else {
            throw TaskLiveActivitySelectionError.completionNeedsConfirmation
        }
        try PersistenceCommandService.perform(in: context) {
            try TaskLifecycleService.applyStatus(.done, to: task, in: context, now: now)
        }
        _ = selectionStore.selection(tasks: tasks, dayKey: dayKey)
    }
}
