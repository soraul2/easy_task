import Foundation
import SwiftData

/// A short-lived receipt for one completion on this device. Resuming a task is a
/// separate lifecycle action and deliberately retains its completion history.
public struct TaskCompletionUndoToken: Sendable {
    public let id: UUID
    public let taskID: UUID
    public var previousStatus: TaskStatus { TaskStatus(rawValue: previousStatusRawValue) ?? .todo }
    fileprivate let previousStatusRawValue: String
    public let boardDate: Date
    public let expiresAt: Date
    fileprivate let instanceID: UUID
    fileprivate let completedAt: Date
    fileprivate let previousOrder: Double
    fileprivate let completedOrder: Double
    fileprivate let previousCompletedAt: Date?
    fileprivate let previousCompletedDayKey: String?
    fileprivate let previousArchivedAt: Date?
    fileprivate let previousArchivedDayKey: String?
    fileprivate let activityDayKeys: [String]
    fileprivate let previousActivityIDs: Set<UUID>
    fileprivate let previousProgressIDs: Set<UUID>
    fileprivate let activities: [UUID: CompletionUndoRecordVersion]
    fileprivate let progress: [UUID: CompletionUndoRecordVersion]
}

fileprivate struct CompletionUndoRecordVersion: Equatable, Sendable {
    let id: UUID
    let type: String
    let dayKey: String
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date

    init(_ activity: TaskCompletionActivity) {
        id = activity.id
        type = activity.originRawValue
        dayKey = activity.activityDayKey
        occurredAt = activity.occurredAt
        createdAt = activity.createdAt
        updatedAt = activity.updatedAt
    }

    init(_ event: TaskProgressEvent) {
        id = event.id
        type = event.kindRawValue + ":" + event.originRawValue
        dayKey = ""
        occurredAt = event.occurredAt
        createdAt = event.createdAt
        updatedAt = event.updatedAt
    }
}

public enum TaskCompletionUndoService {
    public static let availabilityDuration: TimeInterval = 15

    @MainActor
    public static func complete(
        _ task: Task,
        in context: ModelContext,
        order: Double? = nil,
        now: Date = Date()
    ) throws -> TaskCompletionUndoToken? {
        try PersistenceCommandService.perform(in: context) {
            guard task.supersededAt == nil,
                  let previousStatus = TaskStatus(rawValue: task.status),
                  previousStatus != .done else { return nil }
            let dayKeys = Array(Set([
                DayKey.key(for: now), TaskActivityRules.legacyDayKey(for: now)
            ]))
            let previousActivities = try activities(for: task.id, dayKeys: dayKeys, in: context)
            let previousProgress = try progress(for: task.id, in: context)
            let previousOrder = task.order
            let previousCompletedAt = task.completedAt
            let previousCompletedDayKey = task.completedDayKey
            let previousArchivedAt = task.archivedAt
            let previousArchivedDayKey = task.archivedDayKey

            try TaskLifecycleService.applyStatus(.done, to: task, in: context, now: now)
            if let order { task.order = order }
            return TaskCompletionUndoToken(
                id: UUID(), taskID: task.id, previousStatusRawValue: previousStatus.rawValue,
                boardDate: task.plannedAt,
                expiresAt: now.addingTimeInterval(availabilityDuration),
                instanceID: task.instanceID, completedAt: now,
                previousOrder: previousOrder, completedOrder: task.order,
                previousCompletedAt: previousCompletedAt,
                previousCompletedDayKey: previousCompletedDayKey,
                previousArchivedAt: previousArchivedAt,
                previousArchivedDayKey: previousArchivedDayKey,
                activityDayKeys: dayKeys,
                previousActivityIDs: Set(previousActivities.map(\.instanceID)),
                previousProgressIDs: Set(previousProgress.map(\.instanceID)),
                activities: activityVersions(try activities(for: task.id, dayKeys: dayKeys, in: context)),
                progress: progressVersions(try progress(for: task.id, in: context))
            )
        }
    }

    @MainActor
    @discardableResult
    public static func undo(
        _ token: TaskCompletionUndoToken,
        in context: ModelContext,
        now: Date = Date()
    ) throws -> Bool {
        try PersistenceCommandService.perform(in: context) {
            try applyUndo(token, in: context, now: now)
        }
    }

    // Kept inside the same save/rollback boundary as the state restoration.
    @MainActor
    static func applyUndo(
        _ token: TaskCompletionUndoToken,
        in context: ModelContext,
        now: Date
    ) throws -> Bool {
        guard now >= token.completedAt, now < token.expiresAt else { return false }
        let candidates = try context.fetch(BoundedQueryService.taskCandidatesDescriptor(id: token.taskID))
            .filter { $0.supersededAt == nil }
        guard candidates.count == 1, let task = candidates.first,
              task.instanceID == token.instanceID,
              task.status == TaskStatus.done.rawValue,
              task.updatedAt == token.completedAt,
              task.completedAt == token.completedAt,
              task.completedDayKey == DayKey.key(for: token.completedAt),
              task.plannedAt == token.boardDate,
              task.archivedAt == token.previousArchivedAt,
              task.archivedDayKey == token.previousArchivedDayKey,
              task.order == token.completedOrder else { return false }

        let activities = try activities(for: token.taskID, dayKeys: token.activityDayKeys, in: context)
        let events = try progress(for: token.taskID, in: context)
        // An import, reconciliation or later edit invalidates the receipt. Do not
        // overwrite records that were changed after the user completed the task.
        guard activityVersions(activities) == token.activities,
              progressVersions(events) == token.progress else { return false }

        for activity in activities where !token.previousActivityIDs.contains(activity.instanceID) {
            activity.supersededAt = now
            activity.updatedAt = now
        }
        for event in events where !token.previousProgressIDs.contains(event.instanceID) {
            event.supersededAt = now
            event.updatedAt = now
        }
        // Removing only this completion's stop restores the original open
        // interval; an undo must not invent a second start or discard elapsed time.
        TaskRules.applyStatus(token.previousStatus, to: task, now: now)
        task.order = token.previousOrder
        task.completedAt = token.previousCompletedAt
        task.completedDayKey = token.previousCompletedDayKey
        task.archivedAt = token.previousArchivedAt
        task.archivedDayKey = token.previousArchivedDayKey
        return true
    }

    @MainActor
    private static func activities(
        for taskID: UUID, dayKeys: [String], in context: ModelContext
    ) throws -> [TaskCompletionActivity] {
        try context.fetch(FetchDescriptor<TaskCompletionActivity>(predicate: #Predicate { activity in
            activity.taskId == taskID && activity.supersededAt == nil &&
                dayKeys.contains(activity.activityDayKey)
        }))
    }

    @MainActor
    private static func progress(for taskID: UUID, in context: ModelContext) throws -> [TaskProgressEvent] {
        try TaskProgressEventService.events(forTaskIDs: [taskID], in: context)
            .filter { $0.supersededAt == nil }
    }

    private static func activityVersions(_ records: [TaskCompletionActivity]) -> [UUID: CompletionUndoRecordVersion] {
        records.reduce(into: [:]) { $0[$1.instanceID] = CompletionUndoRecordVersion($1) }
    }

    private static func progressVersions(_ records: [TaskProgressEvent]) -> [UUID: CompletionUndoRecordVersion] {
        records.reduce(into: [:]) { $0[$1.instanceID] = CompletionUndoRecordVersion($1) }
    }
}
