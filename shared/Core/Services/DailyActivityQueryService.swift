import Foundation
import SwiftData

/// A disposable, value-only progress index supplies intervals that span an entire query window.
/// All persistent reads stay on the owning context; batches yield so newer requests can cancel.
@MainActor
public final class DailyActivityQueryService {
    private let context: ModelContext
    private var progressIndex: [UUID: TaskProgressProjection]?
    private var progressCoverageStart: Date?
    private let batchSize = 256

    public init(context: ModelContext) { self.context = context }

    public func invalidate() {
        progressIndex = nil
        progressCoverageStart = nil
    }

    public func page(
        filter: ArchiveFilter,
        beforeDayKey: String? = nil,
        referenceDate: Date = Date()
    ) async throws -> ArchiveQueryPage {
        try Swift.Task.checkCancellation()
        let range = ArchiveQueryRules.dayKeyRange(for: filter, referenceDate: referenceDate)
        let extent = try BoundedQueryService.archiveDayKeyExtent(basis: .completed, in: context)
        var activityFirst = FetchDescriptor<TaskCompletionActivity>(
            predicate: #Predicate { $0.supersededAt == nil },
            sortBy: [SortDescriptor(\TaskCompletionActivity.activityDayKey)]
        )
        activityFirst.fetchLimit = 1
        var focusFirst = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.supersededAt == nil },
            sortBy: [SortDescriptor(\FocusSession.endedAt)]
        )
        focusFirst.fetchLimit = 1
        let startedKind = TaskProgressEventKind.started.rawValue
        var progressFirst = FetchDescriptor<TaskProgressEvent>(
            predicate: #Predicate { $0.supersededAt == nil && $0.kindRawValue == startedKind },
            sortBy: [SortDescriptor(\TaskProgressEvent.occurredAt)]
        )
        progressFirst.fetchLimit = 1
        let earliestProgress = try context.fetch(progressFirst).first?.occurredAt
        let sourceLower = [
            extent?.lowerBound,
            try context.fetch(activityFirst).first?.activityDayKey,
            try context.fetch(focusFirst).first.map { DayKey.key(for: $0.endedAt) },
            earliestProgress.map { DayKey.key(for: $0) },
        ].compactMap { $0 }.min()

        guard let lowerKey = range.lowerBound ?? sourceLower,
            let lowerDate = DayKey.date(from: lowerKey),
            var upperDate = DayKey.date(from: range.upperBound)
        else { return emptyPage }
        if let beforeDayKey, let before = DayKey.date(from: beforeDayKey) {
            upperDate = min(upperDate, DayKey.addingDays(-1, to: before))
        }
        var records: [ArchiveDayRecord] = []
        var attachments: [DiaryAttachment] = []
        var blocks: [DiaryBlock] = []
        while upperDate >= lowerDate, records.count < BoundedQueryService.archivePageSize {
            try Swift.Task.checkCancellation()
            let windowStart = max(lowerDate, DayKey.addingDays(-29, to: upperDate))
            let window = try await window(from: windowStart, through: upperDate, filter: filter)
            let selected = Array(window.records.prefix(BoundedQueryService.archivePageSize - records.count))
            records += selected
            let reviewIDs = Set(selected.compactMap { $0.review?.id })
            attachments += window.attachments.filter { reviewIDs.contains($0.reviewId) }
            blocks += window.blocks.filter { reviewIDs.contains($0.reviewId) }
            upperDate = DayKey.addingDays(-1, to: windowStart)
            await Swift.Task.yield()
        }
        let last = records.last?.dayKey
        let hasMore = records.count == BoundedQueryService.archivePageSize && (last ?? lowerKey) > lowerKey
        return ArchiveQueryPage(
            records: records, attachments: attachments, blocks: blocks,
            nextBeforeDayKey: hasMore ? last : nil, hasMore: hasMore
        )
    }

    private var emptyPage: ArchiveQueryPage {
        ArchiveQueryPage(records: [], attachments: [], blocks: [], nextBeforeDayKey: nil, hasMore: false)
    }

    private func prepareProgressIndex(from lowerDate: Date) async throws {
        if let progressCoverageStart, progressCoverageStart <= lowerDate { return }
        try Swift.Task.checkCancellation()
        let pendingModels =
            context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray
        let excludedIDs = Set(pendingModels.compactMap { ($0 as? TaskProgressEvent)?.persistentModelID })
        let deletedIDs = Set(context.deletedModelsArray.map(\.persistentModelID))
        var seen = Set<PersistentIdentifier>()
        let pending = pendingModels.compactMap { $0 as? TaskProgressEvent }.filter {
            !deletedIDs.contains($0.persistentModelID) && seen.insert($0.persistentModelID).inserted
        }.map(TaskProgressEventSnapshot.init)
        let container = context.container
        let existingTaskIDs = Set(progressIndex?.keys.map { $0 } ?? [])
        // A dedicated context enumerates once instead of repeatedly offset-scanning the same history.
        // Only immutable projections cross back to the UI's actor.
        let read = Swift.Task.detached(priority: .userInitiated) {
            let reader = DailyProgressIndexReader(modelContainer: container)
            return try await reader.read(
                from: lowerDate, existingTaskIDs: existingTaskIDs,
                excluding: excludedIDs, pending: pending)
        }
        let index = try await withTaskCancellationHandler {
            try await read.value
        } onCancel: {
            read.cancel()
        }
        try Swift.Task.checkCancellation()
        progressIndex = (progressIndex ?? [:]).merging(index) { _, new in new }
        progressCoverageStart = lowerDate
    }

    private func window(from start: Date, through end: Date, filter: ArchiveFilter) async throws
        -> ArchiveQueryPage
    {
        try await prepareProgressIndex(from: start)
        let lower = DayKey.key(for: start)
        let upper = DayKey.key(for: end)
        let endExclusive = DayKey.addingDays(1, to: end)
        var facts: [String: [UUID: DailyActivityEvidence]] = [:]
        let activities = try await fetch(
            FetchDescriptor<TaskCompletionActivity>(
                predicate: #Predicate {
                    $0.supersededAt == nil && $0.activityDayKey >= lower && $0.activityDayKey <= upper
                }, sortBy: [SortDescriptor(\TaskCompletionActivity.instanceID)]
            ))
        for activity in activities {
            guard let origin = TaskCompletionActivityOrigin(rawValue: activity.originRawValue) else {
                continue
            }
            if origin == .captured {
                facts[activity.activityDayKey, default: [:]][activity.taskId, default: .init()].completed =
                    true
            } else {
                facts[activity.activityDayKey, default: [:]][activity.taskId, default: .init()]
                    .legacyCompletion = true
            }
        }

        for (taskID, projection) in progressIndex ?? [:] {
            try Swift.Task.checkCancellation()
            let overlaps =
                projection.recordedStarts.contains { start <= $0 && $0 < endExclusive }
                || projection.intervals.contains { $0.startedAt < endExclusive && $0.stoppedAt > start }
            guard overlaps else { continue }
            var date = start
            while date <= end {
                let evidence = DailyActivityRules.progressEvidence(projection, on: date)
                if evidence.hasActivity {
                    let key = DayKey.key(for: date)
                    var combined = facts[key, default: [:]][taskID, default: .init()]
                    combined.started = evidence.started
                    combined.progressSeconds = evidence.progressSeconds
                    combined.unknownProgress = evidence.unknownProgress
                    facts[key, default: [:]][taskID] = combined
                }
                date = DayKey.addingDays(1, to: date)
            }
            await Swift.Task.yield()
        }

        let focusCandidates = try await fetch(
            FetchDescriptor<FocusSession>(
                predicate: #Predicate {
                    $0.supersededAt == nil && $0.endedAt >= start && $0.endedAt < endExclusive
                },
                sortBy: [SortDescriptor(\FocusSession.instanceID)]
            ))
        var focusVersions: [FocusSession] = []
        for ids in chunks(Array(Set(focusCandidates.map(\.id)))) {
            focusVersions += try await fetch(
                FetchDescriptor<FocusSession>(
                    predicate: #Predicate { $0.supersededAt == nil && ids.contains($0.id) },
                    sortBy: [SortDescriptor(\FocusSession.instanceID)]
                ))
        }
        let focusRepresentatives = Dictionary(grouping: focusVersions, by: \.id).values.compactMap { rows in
            rows.max {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
        }
        for session in focusRepresentatives where session.endedAt >= start && session.endedAt < endExclusive {
            guard session.focusedDurationSeconds > 0,
                session.endedAt >= session.startedAt,
                FocusSessionOutcome(rawValue: session.outcomeRawValue) != nil
            else { continue }
            let key = DayKey.key(for: session.endedAt)
            facts[key, default: [:]][session.taskId, default: .init()].focusSeconds +=
                session.focusedDurationSeconds
            facts[key, default: [:]][session.taskId, default: .init()].focusSessionCount += 1
        }

        // Old records remain findable, but only if no canonical activity exists on any date.
        let fallbackTasks = try BoundedQueryService.archiveTasks(
            from: lower, through: upper, basis: .completed, in: context)
        var IDsWithActivity = Set<UUID>()
        for ids in chunks(fallbackTasks.map(\.id)) {
            let rows = try await fetch(
                FetchDescriptor<TaskCompletionActivity>(
                    predicate: #Predicate { $0.supersededAt == nil && ids.contains($0.taskId) },
                    sortBy: [SortDescriptor(\TaskCompletionActivity.instanceID)]
                ))
            IDsWithActivity.formUnion(rows.map(\.taskId))
        }
        for task in fallbackTasks where !IDsWithActivity.contains(task.id) {
            let key = TaskHistoryDateRules.completionDate(for: task).dayKey
            facts[key, default: [:]][task.id, default: .init()].legacyCompletion = true
        }

        let taskIDs = Set(facts.values.flatMap { $0.keys })
        var taskRows: [Task] = []
        for ids in chunks(Array(taskIDs)) {
            taskRows += try await fetch(
                FetchDescriptor<Task>(
                    predicate: #Predicate { $0.supersededAt == nil && ids.contains($0.id) },
                    sortBy: [SortDescriptor(\Task.instanceID)]
                ))
        }
        let tasks = Dictionary(
            uniqueKeysWithValues: ArchiveQueryRules.representativeTasks(taskRows).map { ($0.id, $0) })
        let checklist = try TaskChecklistService.items(for: Array(taskIDs), in: context)
        let checklistByTask = Dictionary(grouping: checklist, by: \.taskId)
        let reviews = try BoundedQueryService.archiveReviews(from: lower, through: upper, in: context)
        let attachments = try BoundedQueryService.archiveAttachments(
            reviewIDs: reviews.map(\.id), in: context)
        let blocks = try BoundedQueryService.archiveBlocks(reviewIDs: reviews.map(\.id), in: context)
        let contentIDs = Set(attachments.map(\.reviewId)).union(
            blocks.filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !($0.imageFileName ?? "").isEmpty
            }.map(\.reviewId))
        let reviewsByDay = Dictionary(
            grouping: reviews.filter {
                DailyReviewRules.hasContent($0) || contentIDs.contains($0.id)
            }, by: \.dayKey
        ).compactMapValues { rows in
            rows.max {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
        }

        let query = filter.normalizedSearchText
        let hasSearch = !query.isEmpty
        var records: [ArchiveDayRecord] = []
        for day in Set(facts.keys).union(reviewsByDay.keys).sorted(by: >) {
            let dayFacts = facts[day] ?? [:]
            let review = reviewsByDay[day]
            let matchedTaskIDs = Set(
                dayFacts.keys.filter { id in
                    guard hasSearch, filter.scope.includesTasks else { return false }
                    if let task = tasks[id] {
                        return ArchiveQueryRules.matchesSearch(
                            task, checklistItems: checklistByTask[id] ?? [], query: query)
                    }
                    return ArchiveQueryRules.contains("작업 정보를 찾을 수 없음", query: query)
                })
            let reviewMatch =
                hasSearch && filter.scope.includesReviews
                && (review.map { ArchiveQueryRules.matchesSearch($0, query: query) } ?? false)
            let matches =
                hasSearch
                ? (!matchedTaskIDs.isEmpty || reviewMatch)
                : ((filter.scope.includesTasks && !dayFacts.isEmpty)
                    || (filter.scope.includesReviews && review != nil))
            guard matches else { continue }
            let entries = dayFacts.map { id, evidence in
                DailyActivityEntry(
                    id: id, title: tasks[id]?.title ?? "작업 정보를 찾을 수 없음", note: tasks[id]?.note,
                    evidence: evidence, canOpenTask: tasks[id] != nil,
                    matchingChecklistTitles: hasSearch
                        ? (checklistByTask[id] ?? []).filter {
                            ArchiveQueryRules.contains($0.title, query: query)
                        }.map(\.title) : [], searchQuery: query
                )
            }.sorted {
                if matchedTaskIDs.contains($0.id) != matchedTaskIDs.contains($1.id) {
                    return matchedTaskIDs.contains($0.id)
                }
                if $0.evidence.completed != $1.evidence.completed { return $0.evidence.completed }
                if $0.title != $1.title {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            records.append(
                ArchiveDayRecord(
                    dayKey: day, tasks: entries.compactMap { tasks[$0.id] }, review: review,
                    matchedTaskIDs: matchedTaskIDs, reviewMatchesSearch: reviewMatch,
                    hasSearchQuery: hasSearch, activityEntries: entries
                ))
        }
        return ArchiveQueryPage(
            records: records, attachments: attachments, blocks: blocks, nextBeforeDayKey: nil, hasMore: false)
    }

    private func chunks(_ ids: [UUID]) -> [[UUID]] {
        stride(from: 0, to: ids.count, by: 100).map { Array(ids[$0..<min($0 + 100, ids.count)]) }
    }

    private func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) async throws -> [Model] {
        var result: [Model] = []
        try await batches(descriptor) { result += $0 }
        return result
    }

    private func batches<Model: PersistentModel>(
        _ source: FetchDescriptor<Model>,
        consume: ([Model]) -> Void
    ) async throws {
        let pending = context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray
        let pendingIDs = Set(pending.compactMap { ($0 as? Model)?.persistentModelID })
        let deletedIDs = Set(context.deletedModelsArray.map(\.persistentModelID))
        var descriptor = source
        descriptor.includePendingChanges = false
        descriptor.fetchLimit = batchSize
        var offset = 0
        while true {
            try Swift.Task.checkCancellation()
            descriptor.fetchOffset = offset
            let rows = try context.fetch(descriptor)
            consume(rows.filter { !pendingIDs.contains($0.persistentModelID) })
            if rows.count < batchSize { break }
            offset += rows.count
            await Swift.Task.yield()
        }
        var seen = Set<PersistentIdentifier>()
        let pendingRows = try pending.compactMap { $0 as? Model }.filter {
            guard !deletedIDs.contains($0.persistentModelID), seen.insert($0.persistentModelID).inserted
            else { return false }
            return try source.predicate?.evaluate($0) ?? true
        }
        consume(pendingRows)
        try Swift.Task.checkCancellation()
    }
}

@ModelActor
private actor DailyProgressIndexReader {
    func read(
        from lowerDate: Date,
        existingTaskIDs: Set<UUID>,
        excluding identifiers: Set<PersistentIdentifier>,
        pending: [TaskProgressEventSnapshot]
    ) throws -> [UUID: TaskProgressProjection] {
        // Any closed interval overlapping this range has a stop on/after its lower bound.
        // Open intervals contribute only their start day. Do not impose an upper bound here:
        // a stop after the requested window can close an interval spanning the whole window.
        let candidates = FetchDescriptor<TaskProgressEvent>(
            predicate: #Predicate {
                $0.supersededAt == nil && $0.occurredAt >= lowerDate
            })
        var taskIDs = Set<UUID>()
        try modelContext.enumerate(candidates, batchSize: 256) { event in
            try Swift.Task.checkCancellation()
            if !identifiers.contains(event.persistentModelID) { taskIDs.insert(event.taskId) }
        }
        taskIDs.formUnion(
            pending.filter { $0.supersededAt == nil && $0.occurredAt >= lowerDate }.map(\.taskId))
        taskIDs.subtract(existingTaskIDs)
        let ids = Array(taskIDs)
        var groups: [UUID: [TaskProgressEventSnapshot]] = [:]
        for offset in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[offset..<min(offset + 100, ids.count)])
            let descriptor = FetchDescriptor<TaskProgressEvent>(
                predicate: #Predicate {
                    $0.supersededAt == nil && batch.contains($0.taskId)
                })
            try modelContext.enumerate(descriptor, batchSize: 256) { event in
                try Swift.Task.checkCancellation()
                guard !identifiers.contains(event.persistentModelID) else { return }
                groups[event.taskId, default: []].append(TaskProgressEventSnapshot(event))
            }
        }
        for event in pending where taskIDs.contains(event.taskId) {
            groups[event.taskId, default: []].append(event)
        }
        var index: [UUID: TaskProgressProjection] = [:]
        for taskID in taskIDs {
            try Swift.Task.checkCancellation()
            index[taskID] = TaskProgressEventRules.projection(snapshots: groups[taskID] ?? [])
        }
        return index
    }
}
