import Foundation
import SwiftData

/// Read-only, task-scoped history. No editing or repair occurs when a record is opened.
@MainActor
enum TaskRecordQueryService {
    static func load(selection: TaskRecordSelection, in context: ModelContext) async throws -> TaskRecord {
        let taskID = selection.taskID
        let task = BoundedQueryService.representativeTask(
            from: try context.fetch(BoundedQueryService.taskCandidatesDescriptor(id: taskID)))
        let events = try await fetch(
            FetchDescriptor<TaskProgressEvent>(
                predicate: #Predicate { $0.supersededAt == nil && $0.taskId == taskID },
                sortBy: [SortDescriptor(\TaskProgressEvent.instanceID)]), in: context)
        let projection = TaskProgressEventRules.projection(for: events)
        let focusRows = try await fetch(
            FetchDescriptor<FocusSession>(
                predicate: #Predicate { $0.supersededAt == nil && $0.taskId == taskID },
                sortBy: [SortDescriptor(\FocusSession.instanceID)]), in: context)
        let focus = Dictionary(grouping: focusRows, by: \.id).values.compactMap { rows in
            rows.max {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
        }.filter {
            knownDate($0.startedAt) != nil && knownDate($0.endedAt) != nil
                && $0.endedAt >= $0.startedAt && $0.focusedDurationSeconds > 0
                && FocusSessionOutcome(rawValue: $0.outcomeRawValue) != nil
        }
        let activityRows = try await fetch(
            FetchDescriptor<TaskCompletionActivity>(
                predicate: #Predicate { $0.supersededAt == nil && $0.taskId == taskID },
                sortBy: [SortDescriptor(\TaskCompletionActivity.instanceID)]), in: context)
        let validActivities = activityRows.filter {
            DayKey.date(from: $0.activityDayKey) != nil
                && TaskActivityRules.origin(for: $0.originRawValue) != nil
        }
        // Completion identity is a task/day pair; captured evidence wins over a legacy backfill.
        let representatives = Dictionary(grouping: validActivities, by: \.activityDayKey).values.compactMap {
            rows in
            rows.max {
                if $0.originRawValue != $1.originRawValue {
                    return $0.originRawValue == TaskCompletionActivityOrigin.legacyBackfill.rawValue
                }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
        }
        let captured = representatives.filter {
            $0.originRawValue == TaskCompletionActivityOrigin.captured.rawValue
        }
        let activities = representatives.filter { activity in
            activity.originRawValue == TaskCompletionActivityOrigin.captured.rawValue
                || !captured.contains {
                    TaskActivityRules.representsSameCompletion($0.occurredAt, activity.occurredAt)
                }
        }
        let selectedDate = DayKey.date(from: selection.dayKey)
        var selectedDay =
            selectedDate.map { DailyActivityRules.progressEvidence(projection, on: $0) }
            ?? DailyActivityEvidence()
        let dayFocus = focus.filter { DayKey.key(for: $0.endedAt) == selection.dayKey }
        selectedDay.focusSeconds = dayFocus.reduce(0) { $0 + $1.focusedDurationSeconds }
        selectedDay.focusSessionCount = dayFocus.count
        for activity in activities where activity.activityDayKey == selection.dayKey {
            if activity.originRawValue == TaskCompletionActivityOrigin.captured.rawValue {
                selectedDay.completed = true
            } else {
                selectedDay.legacyCompletion = true
            }
        }

        var timeline = projection.intervals.enumerated().map { index, interval in
            TaskRecordEvent(
                id: "progress-\(index)", kind: .progress, dayKey: DayKey.key(for: interval.stoppedAt),
                startedAt: interval.startedAt, endedAt: interval.stoppedAt, duration: interval.duration)
        }
        for (index, start) in projection.unknownIntervalStarts.enumerated() {
            timeline.append(
                TaskRecordEvent(
                    id: "unknown-\(index)", kind: .unknownProgress, dayKey: DayKey.key(for: start),
                    startedAt: start))
        }
        if let start = projection.currentStartedAt {
            timeline.append(
                TaskRecordEvent(
                    id: "open", kind: .openProgress, dayKey: DayKey.key(for: start), startedAt: start))
        }
        timeline += focus.map {
            TaskRecordEvent(
                id: "focus-\($0.id)", kind: .focus, dayKey: DayKey.key(for: $0.endedAt),
                startedAt: $0.startedAt, endedAt: $0.endedAt,
                duration: TimeInterval($0.focusedDurationSeconds),
                focusOutcome: FocusSessionOutcome(rawValue: $0.outcomeRawValue))
        }
        timeline += activities.map {
            let captured = $0.originRawValue == TaskCompletionActivityOrigin.captured.rawValue
            return TaskRecordEvent(
                id: "completion-\($0.activityDayKey)", kind: captured ? .completed : .legacyCompletion,
                dayKey: $0.activityDayKey, startedAt: captured ? knownDate($0.occurredAt) : nil)
        }
        if activities.isEmpty, let task, task.status == TaskStatus.done.rawValue {
            let key = TaskHistoryDateRules.completionDate(for: task).dayKey
            timeline.append(TaskRecordEvent(id: "legacy", kind: .legacyCompletion, dayKey: key))
            if key == selection.dayKey { selectedDay.legacyCompletion = true }
        }
        let createdAt = task.flatMap { knownDate($0.createdAt) }
        if let createdAt {
            timeline.append(
                TaskRecordEvent(
                    id: "created", kind: .created, dayKey: DayKey.key(for: createdAt), startedAt: createdAt))
        }
        timeline.sort {
            if $0.sortDate != $1.sortDate { return $0.sortDate > $1.sortDate }
            return $0.id < $1.id
        }
        let checklist = TaskChecklistService.progress(
            in: try TaskChecklistService.items(for: taskID, in: context))
        try Swift.Task.checkCancellation()
        return TaskRecord(
            title: task?.title ?? "현재 작업 정보 없음", hasCurrentTask: task != nil,
            currentStatus: task?.status,
            createdAt: createdAt, plannedDayKey: task?.plannedDayKey,
            recordedCompletionDayKey: task.flatMap {
                $0.status == TaskStatus.done.rawValue
                    ? TaskHistoryDateRules.recordedCompletionDayKey(for: $0) : nil
            },
            firstStartedAt: projection.recordedStarts.min(),
            latestCompletedAt: captured.compactMap { knownDate($0.occurredAt) }.max(),
            selectedDay: selectedDay, progress: projection,
            focusedSeconds: focus.reduce(0) { $0 + $1.focusedDurationSeconds },
            focusSessionCount: focus.count,
            checklist: checklist, note: task?.note, timeline: timeline)
    }

    private static func knownDate(_ date: Date) -> Date? {
        date > .distantPast && date < .distantFuture && date.timeIntervalSinceReferenceDate.isFinite
            ? date : nil
    }

    /// Yield between task-scoped batches and overlay pending edits without saving them.
    private static func fetch<Model: PersistentModel>(
        _ source: FetchDescriptor<Model>, in context: ModelContext
    ) async throws -> [Model] {
        let pending = context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray
        let pendingIDs = Set(pending.map(\.persistentModelID))
        let deletedIDs = Set(context.deletedModelsArray.map(\.persistentModelID))
        var descriptor = source
        descriptor.includePendingChanges = false
        descriptor.fetchLimit = 256
        var rows: [Model] = []
        var offset = 0
        while true {
            try Swift.Task.checkCancellation()
            descriptor.fetchOffset = offset
            let batch = try context.fetch(descriptor)
            rows += batch.filter { !pendingIDs.contains($0.persistentModelID) }
            if batch.count < 256 { break }
            offset += batch.count
            await Swift.Task.yield()
        }
        var seen = Set<PersistentIdentifier>()
        rows += try pending.compactMap { $0 as? Model }.filter {
            guard !deletedIDs.contains($0.persistentModelID), seen.insert($0.persistentModelID).inserted
            else { return false }
            return try source.predicate?.evaluate($0) ?? true
        }
        try Swift.Task.checkCancellation()
        return rows
    }
}
