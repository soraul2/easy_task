import Foundation
import SwiftData

public struct ArchiveQueryPage {
    public var records: [ArchiveDayRecord]
    public var attachments: [DiaryAttachment]
    public var blocks: [DiaryBlock]
    public var nextBeforeDayKey: String?
    public var hasMore: Bool

    public init(
        records: [ArchiveDayRecord],
        attachments: [DiaryAttachment],
        blocks: [DiaryBlock],
        nextBeforeDayKey: String?,
        hasMore: Bool
    ) {
        self.records = records
        self.attachments = attachments
        self.blocks = blocks
        self.nextBeforeDayKey = nextBeforeDayKey
        self.hasMore = hasMore
    }
}

public enum BoundedQueryService {
    public static let archivePageSize = 30
    public static let taskHistoryStatisticsBatchSize = 200
    public static let taskActivityBatchSize = 256
    public static let eventRecommendationScanLimit = 200
    private static let archiveScanWindowDays = 30

    public static func boardTasksDescriptor(
        selectedDayKey: String
    ) -> FetchDescriptor<Task> {
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil && (
                    task.plannedDayKey == selectedDayKey ||
                    task.completedDayKey == selectedDayKey
                )
            },
            sortBy: [
                SortDescriptor(\Task.plannedDayKey),
                SortDescriptor(\Task.order),
                SortDescriptor(\Task.title)
            ]
        )
    }

    public static func dailyReviewCompletedAtTasksDescriptor(
        dayKey: String
    ) -> FetchDescriptor<Task> {
        let startDate = DayKey.date(from: dayKey) ?? .distantPast
        let endExclusive = DayKey.addingDays(1, to: startDate)
        let distantPast = Date.distantPast
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                (task.completedAt ?? distantPast) >= startDate &&
                    (task.completedAt ?? distantPast) < endExclusive
            },
            sortBy: [
                SortDescriptor(\Task.completedAt, order: .reverse),
                SortDescriptor(\Task.instanceID)
            ]
        )
    }

    public static func dailyReviewArchivedFallbackTasksDescriptor(
        dayKey: String
    ) -> FetchDescriptor<Task> {
        FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.archivedDayKey == dayKey
            },
            sortBy: [
                SortDescriptor(\Task.archivedAt, order: .reverse),
                SortDescriptor(\Task.instanceID)
            ]
        )
    }

    @MainActor
    public static func dailyReviewTasks(
        dayKey: String,
        in context: ModelContext
    ) throws -> [Task] {
        let rows = try context.fetch(boardTasksDescriptor(
            selectedDayKey: dayKey
        )) + context.fetch(dailyReviewCompletedAtTasksDescriptor(
            dayKey: dayKey
        )) + context.fetch(dailyReviewArchivedFallbackTasksDescriptor(
            dayKey: dayKey
        ))
        return deduplicated(rows, by: \.instanceID)
    }

    public static func carryoverTasksDescriptor(
        before dayKey: String
    ) -> FetchDescriptor<Task> {
        let doneStatus = TaskStatus.done.rawValue
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.archivedAt == nil &&
                    task.status != doneStatus &&
                    task.plannedDayKey < dayKey
            },
            sortBy: [
                SortDescriptor(\Task.plannedDayKey),
                SortDescriptor(\Task.order),
                SortDescriptor(\Task.title)
            ]
        )
    }

    public static func eventsDescriptor(
        overlappingStartDayKey startDayKey: String,
        endDayKey: String
    ) -> FetchDescriptor<CalendarEvent> {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        return FetchDescriptor(
            predicate: #Predicate<CalendarEvent> { event in
                event.supersededAt == nil &&
                    event.startDayKey <= upperBound &&
                    event.endDayKey >= lowerBound
            },
            sortBy: [
                SortDescriptor(\CalendarEvent.startDayKey),
                SortDescriptor(\CalendarEvent.endDayKey, order: .reverse),
                SortDescriptor(\CalendarEvent.title)
            ]
        )
    }

    public static func recentCalendarEventsDescriptor()
        -> FetchDescriptor<CalendarEvent> {
        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate<CalendarEvent> { event in
                event.supersededAt == nil
            },
            sortBy: [
                SortDescriptor(\CalendarEvent.updatedAt, order: .reverse),
                SortDescriptor(\CalendarEvent.instanceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = eventRecommendationScanLimit
        return descriptor
    }

    public static func calendarTasksDescriptor(
        from startDayKey: String,
        through endDayKey: String
    ) -> FetchDescriptor<Task> {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.plannedDayKey >= lowerBound &&
                    task.plannedDayKey <= upperBound
            },
            sortBy: [
                SortDescriptor(\Task.plannedDayKey),
                SortDescriptor(\Task.order),
                SortDescriptor(\Task.title)
            ]
        )
    }

    public static func widgetPlannedTasksDescriptor(
        from startDayKey: String,
        through endDayKey: String
    ) -> FetchDescriptor<Task> {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.archivedAt == nil &&
                    task.plannedDayKey >= lowerBound &&
                    task.plannedDayKey <= upperBound
            },
            sortBy: [
                SortDescriptor(\Task.plannedDayKey),
                SortDescriptor(\Task.order),
                SortDescriptor(\Task.title)
            ]
        )
    }

    public static func widgetCompletedTasksDescriptor(
        from startDayKey: String,
        through endDayKey: String
    ) -> FetchDescriptor<Task> {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.archivedAt == nil &&
                    (task.completedDayKey ?? "") >= lowerBound &&
                    (task.completedDayKey ?? "") <= upperBound
            },
            sortBy: [
                SortDescriptor(\Task.completedDayKey),
                SortDescriptor(\Task.updatedAt),
                SortDescriptor(\Task.title)
            ]
        )
    }

    public static func templatePlacementsDescriptor(
        from startDayKey: String,
        through endDayKey: String
    ) -> FetchDescriptor<TemplatePlacement> {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        return FetchDescriptor(
            predicate: #Predicate<TemplatePlacement> { placement in
                placement.supersededAt == nil &&
                    placement.dayKey >= lowerBound &&
                    placement.dayKey <= upperBound
            },
            sortBy: [
                SortDescriptor(\TemplatePlacement.dayKey),
                SortDescriptor(\TemplatePlacement.createdAt)
            ]
        )
    }

    public static func taskDescriptor(id: UUID) -> FetchDescriptor<Task> {
        var descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil && task.id == id
            }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    public static func activeReminderTasksDescriptor() -> FetchDescriptor<Task> {
        let doneStatus = TaskStatus.done.rawValue
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.status != doneStatus &&
                    task.reminderAt != nil
            },
            sortBy: [
                SortDescriptor(\Task.reminderAt),
                SortDescriptor(\Task.id)
            ]
        )
    }

    public static func dailyReviewsDescriptor(
        dayKey: String
    ) -> FetchDescriptor<DailyReview> {
        FetchDescriptor(
            predicate: #Predicate<DailyReview> { review in
                review.supersededAt == nil && review.dayKey == dayKey
            },
            sortBy: [
                SortDescriptor(\DailyReview.updatedAt, order: .reverse),
                SortDescriptor(\DailyReview.instanceID, order: .reverse)
            ]
        )
    }

    public static func dailyReviewDescriptor(
        id: UUID
    ) -> FetchDescriptor<DailyReview> {
        var descriptor = FetchDescriptor<DailyReview>(
            predicate: #Predicate<DailyReview> { review in
                review.supersededAt == nil && review.id == id
            }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    public static func diaryBlocksDescriptor(
        reviewID: UUID
    ) -> FetchDescriptor<DiaryBlock> {
        FetchDescriptor(
            predicate: #Predicate<DiaryBlock> { block in
                block.supersededAt == nil && block.reviewId == reviewID
            },
            sortBy: [SortDescriptor(\DiaryBlock.order)]
        )
    }

    public static func diaryAttachmentsDescriptor(
        reviewID: UUID
    ) -> FetchDescriptor<DiaryAttachment> {
        FetchDescriptor(
            predicate: #Predicate<DiaryAttachment> { attachment in
                attachment.supersededAt == nil && attachment.reviewId == reviewID
            },
            sortBy: [SortDescriptor(\DiaryAttachment.order)]
        )
    }

    public static func tasksNeedingArchiveDescriptor(
        before dayKey: String
    ) -> FetchDescriptor<Task> {
        let doneStatus = TaskStatus.done.rawValue
        return FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.status == doneStatus &&
                    task.archivedAt == nil &&
                    (task.completedDayKey ?? dayKey) < dayKey
            }
        )
    }

    @MainActor
    public static func nextOrder(
        in context: ModelContext,
        dayKey: String,
        status: TaskStatus
    ) throws -> Double {
        let statusValue = status.rawValue
        var descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.archivedAt == nil &&
                    task.plannedDayKey == dayKey &&
                    task.status == statusValue
            },
            sortBy: [SortDescriptor(\Task.order, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.order ?? 0) + 100
    }

    @MainActor
    public static func nextOrder(
        in context: ModelContext,
        status: TaskStatus
    ) throws -> Double {
        let statusValue = status.rawValue
        var descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.archivedAt == nil &&
                    task.status == statusValue
            },
            sortBy: [SortDescriptor(\Task.order, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.order ?? 0) + 100
    }

    @MainActor
    public static func tasksLinked(
        toEventID eventID: UUID,
        in context: ModelContext
    ) throws -> [Task] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil && task.eventId == eventID
            }
        ))
    }

    @MainActor
    public static func tasksLinked(
        toTemplatePlacementID placementID: UUID,
        in context: ModelContext
    ) throws -> [Task] {
        try context.fetch(tasksLinkedToTemplatePlacementDescriptor(
            placementID: placementID
        ))
    }

    public static func tasksLinkedToTemplatePlacementDescriptor(
        placementID: UUID
    ) -> FetchDescriptor<Task> {
        FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil && task.templatePlacementId == placementID
            },
            sortBy: [
                SortDescriptor(\Task.plannedDayKey),
                SortDescriptor(\Task.order),
                SortDescriptor(\Task.title)
            ]
        )
    }

    @MainActor
    public static func tasks(
        from startDayKey: String,
        through endDayKey: String,
        in context: ModelContext
    ) throws -> [Task] {
        try context.fetch(calendarTasksDescriptor(
            from: startDayKey,
            through: endDayKey
        ))
    }

    @MainActor
    public static func taskHistoryStatisticsCandidates(
        from startDayKey: String,
        through endDayKey: String,
        in context: ModelContext,
        isCancelled: () -> Bool = { false }
    ) throws -> [Task] {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        guard let startDate = DayKey.date(from: lowerBound),
              let endDate = DayKey.date(from: upperBound) else {
            return []
        }
        let endExclusive = DayKey.addingDays(1, to: endDate)
        let distantPast = Date.distantPast

        let plannedDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.plannedDayKey >= lowerBound &&
                    task.plannedDayKey <= upperBound
            },
            sortBy: [SortDescriptor(\Task.instanceID)]
        )
        let completedDayDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                (task.completedDayKey ?? "") >= lowerBound &&
                    (task.completedDayKey ?? "") <= upperBound
            },
            sortBy: [SortDescriptor(\Task.instanceID)]
        )
        let completedAtDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                (task.completedAt ?? distantPast) >= startDate &&
                    (task.completedAt ?? distantPast) < endExclusive
            },
            sortBy: [SortDescriptor(\Task.instanceID)]
        )
        let archivedDayDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                (task.archivedDayKey ?? "") >= lowerBound &&
                    (task.archivedDayKey ?? "") <= upperBound
            },
            sortBy: [SortDescriptor(\Task.instanceID)]
        )

        var candidates = try fetchInBatches(
            plannedDescriptor,
            in: context,
            isCancelled: isCancelled
        ).filter { $0.supersededAt == nil }
        candidates += try fetchInBatches(
            completedDayDescriptor,
            in: context,
            isCancelled: isCancelled
        ).filter {
            $0.supersededAt == nil &&
                $0.status == TaskStatus.done.rawValue &&
                $0.completedDayKey != nil
        }
        candidates += try fetchInBatches(
            completedAtDescriptor,
            in: context,
            isCancelled: isCancelled
        ).filter {
            $0.supersededAt == nil &&
                $0.status == TaskStatus.done.rawValue &&
                $0.completedDayKey == nil &&
                $0.completedAt != nil
        }
        candidates += try fetchInBatches(
            archivedDayDescriptor,
            in: context,
            isCancelled: isCancelled
        ).filter {
            $0.supersededAt == nil &&
                $0.status == TaskStatus.done.rawValue &&
                $0.completedDayKey == nil &&
                $0.completedAt == nil &&
                $0.archivedDayKey != nil
        }

        let candidateIDs = Array(Set(candidates.map(\.id)))
        var activeVersions: [Task] = []
        for startIndex in stride(
            from: 0,
            to: candidateIDs.count,
            by: taskHistoryStatisticsBatchSize
        ) {
            if isCancelled() { throw CancellationError() }
            let endIndex = min(
                startIndex + taskHistoryStatisticsBatchSize,
                candidateIDs.count
            )
            let ids = Array(candidateIDs[startIndex..<endIndex])
            activeVersions += try context.fetch(FetchDescriptor(
                predicate: #Predicate<Task> { task in
                    task.supersededAt == nil && ids.contains(task.id)
                }
            ))
        }
        return deduplicated(activeVersions, by: \.instanceID)
    }


    @MainActor
    public static func archivePage(
        in context: ModelContext,
        filter: ArchiveFilter,
        beforeDayKey: String? = nil,
        referenceDate: Date = Date()
    ) throws -> ArchiveQueryPage {
        let periodRange = ArchiveQueryRules.dayKeyRange(
            for: filter,
            referenceDate: referenceDate
        )
        let storeExtent = try archiveDayKeyExtent(
            basis: filter.dateBasis,
            in: context
        )
        let effectiveLowerBound = periodRange.lowerBound ?? storeExtent?.lowerBound

        var effectiveUpperBound = periodRange.upperBound
        if filter.period == .all, let latestStoreDay = storeExtent?.upperBound {
            effectiveUpperBound = max(effectiveUpperBound, latestStoreDay)
        }
        if let beforeDayKey,
           let beforeDate = DayKey.date(from: beforeDayKey) {
            effectiveUpperBound = min(
                effectiveUpperBound,
                DayKey.key(for: DayKey.addingDays(-1, to: beforeDate))
            )
        }

        guard let effectiveLowerBound,
              effectiveLowerBound <= effectiveUpperBound,
              var scanUpperDate = DayKey.date(from: effectiveUpperBound),
              let lowerDate = DayKey.date(from: effectiveLowerBound) else {
            return ArchiveQueryPage(
                records: [],
                attachments: [],
                blocks: [],
                nextBeforeDayKey: nil,
                hasMore: false
            )
        }

        var matchedRecords: [ArchiveDayRecord] = []
        var fetchedAttachments: [DiaryAttachment] = []
        var fetchedBlocks: [DiaryBlock] = []
        var exhaustedRange = false

        while matchedRecords.count < archivePageSize {
            let candidateLowerDate = DayKey.addingDays(
                -(archiveScanWindowDays - 1),
                to: scanUpperDate
            )
            let scanLowerDate = max(candidateLowerDate, lowerDate)
            let scanLowerKey = DayKey.key(for: scanLowerDate)
            let scanUpperKey = DayKey.key(for: scanUpperDate)

            let tasks = try archiveTasks(
                from: scanLowerKey,
                through: scanUpperKey,
                basis: filter.dateBasis,
                in: context
            )
            let checklistItems = try archiveChecklistItems(
                taskIDs: tasks.map(\.id),
                in: context
            )
            let reviews = try archiveReviews(
                from: scanLowerKey,
                through: scanUpperKey,
                in: context
            )
            let reviewIDs = reviews.map(\.id)
            let attachments = try archiveAttachments(
                reviewIDs: reviewIDs,
                in: context
            )
            let blocks = try archiveBlocks(
                reviewIDs: reviewIDs,
                in: context
            )
            let reviewIDsWithContent = Set(attachments.map(\.reviewId)).union(
                blocks.compactMap { block in
                    let hasText = !block.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                    let hasImage = !(block.imageFileName ?? "").isEmpty
                    return hasText || hasImage ? block.reviewId : nil
                }
            )

            let windowRecords = ArchiveQueryRules.records(
                tasks: tasks,
                reviews: reviews,
                filter: filter,
                checklistItems: checklistItems,
                reviewIDsWithContent: reviewIDsWithContent,
                referenceDate: referenceDate
            )
            let remainingCount = archivePageSize - matchedRecords.count
            let selectedWindowRecords = Array(windowRecords.prefix(remainingCount))
            let selectedReviewIDs = Set(selectedWindowRecords.compactMap { $0.review?.id })

            matchedRecords.append(contentsOf: selectedWindowRecords)
            fetchedAttachments.append(contentsOf: attachments.filter {
                selectedReviewIDs.contains($0.reviewId)
            })
            fetchedBlocks.append(contentsOf: blocks.filter {
                selectedReviewIDs.contains($0.reviewId)
            })

            if matchedRecords.count >= archivePageSize {
                break
            }
            if scanLowerDate <= lowerDate {
                exhaustedRange = true
                break
            }
            scanUpperDate = DayKey.addingDays(-1, to: scanLowerDate)
        }

        let oldestLoadedDayKey = matchedRecords.last?.dayKey
        let hasPotentialOlderDay = oldestLoadedDayKey.map {
            $0 > effectiveLowerBound
        } ?? false
        let hasMore = !exhaustedRange &&
            matchedRecords.count == archivePageSize &&
            hasPotentialOlderDay

        return ArchiveQueryPage(
            records: matchedRecords,
            attachments: deduplicated(fetchedAttachments, by: \.instanceID),
            blocks: deduplicated(fetchedBlocks, by: \.instanceID),
            nextBeforeDayKey: hasMore ? oldestLoadedDayKey : nil,
            hasMore: hasMore
        )
    }

    @MainActor
    public static func taskActivitySnapshots(
        from startDayKey: String,
        through endDayKey: String,
        in context: ModelContext,
        isCancelled: () -> Bool = { false }
    ) throws -> [TaskActivitySnapshot] {
        let lowerBound = min(startDayKey, endDayKey)
        let upperBound = max(startDayKey, endDayKey)
        let pendingModels = context.insertedModelsArray +
            context.changedModelsArray +
            context.deletedModelsArray
        let pendingIdentifiers = Set(
            pendingModels.compactMap {
                ($0 as? TaskCompletionActivity)?.persistentModelID
            }
        )
        var seenPending: Set<PersistentIdentifier> = []
        let pendingActivities = (context.insertedModelsArray + context.changedModelsArray)
            .compactMap { $0 as? TaskCompletionActivity }
            .filter { seenPending.insert($0.persistentModelID).inserted }

        var snapshots: [TaskActivitySnapshot] = []
        var offset = 0
        while true {
            if isCancelled() { throw CancellationError() }
            var descriptor = FetchDescriptor<TaskCompletionActivity>(
                predicate: #Predicate<TaskCompletionActivity> { activity in
                    activity.supersededAt == nil &&
                        activity.activityDayKey >= lowerBound &&
                        activity.activityDayKey <= upperBound
                },
                sortBy: [
                    SortDescriptor(\TaskCompletionActivity.activityDayKey),
                    SortDescriptor(\TaskCompletionActivity.taskId),
                    SortDescriptor(\TaskCompletionActivity.instanceID)
                ]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = taskActivityBatchSize
            descriptor.includePendingChanges = false
            let batch = try context.fetch(descriptor)

            snapshots.append(contentsOf: batch.compactMap { activity in
                guard activity.supersededAt == nil,
                      lowerBound <= activity.activityDayKey,
                      activity.activityDayKey <= upperBound,
                      !pendingIdentifiers.contains(activity.persistentModelID) else {
                    return nil
                }
                return TaskActivitySnapshot(
                    taskID: activity.taskId,
                    activityDayKey: activity.activityDayKey
                )
            })
            guard batch.count == taskActivityBatchSize else { break }
            offset += batch.count
        }

        snapshots.append(contentsOf: pendingActivities.compactMap { activity in
            guard activity.supersededAt == nil,
                  lowerBound <= activity.activityDayKey,
                  activity.activityDayKey <= upperBound else {
                return nil
            }
            return TaskActivitySnapshot(
                taskID: activity.taskId,
                activityDayKey: activity.activityDayKey
            )
        })
        return Array(Set(snapshots)).sorted {
            if $0.activityDayKey != $1.activityDayKey {
                return $0.activityDayKey < $1.activityDayKey
            }
            return $0.taskID.uuidString < $1.taskID.uuidString
        }
    }

    @MainActor
    public static func hasTaskActivity(
        before dayKey: String,
        in context: ModelContext
    ) throws -> Bool {
        if (context.insertedModelsArray + context.changedModelsArray)
            .compactMap({ $0 as? TaskCompletionActivity })
            .contains(where: {
                $0.supersededAt == nil && $0.activityDayKey < dayKey
            }) {
            return true
        }
        var descriptor = FetchDescriptor<TaskCompletionActivity>(
            predicate: #Predicate<TaskCompletionActivity> { activity in
                activity.supersededAt == nil && activity.activityDayKey < dayKey
            },
            sortBy: [SortDescriptor(\TaskCompletionActivity.activityDayKey, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = false
        return try context.fetch(descriptor).contains { activity in
            activity.supersededAt == nil && activity.activityDayKey < dayKey
        }
    }
}

private extension BoundedQueryService {
    struct ArchiveDayKeyExtent {
        var lowerBound: String
        var upperBound: String
    }

    @MainActor
    static func archiveTasks(
        from startDayKey: String,
        through endDayKey: String,
        basis: TaskHistoryDateBasis,
        in context: ModelContext
    ) throws -> [Task] {
        let doneStatus = TaskStatus.done.rawValue
        let candidates: [Task]
        switch basis {
        case .planned:
            candidates = try context.fetch(FetchDescriptor<Task>(
                predicate: #Predicate<Task> { task in
                    task.supersededAt == nil &&
                        task.status == doneStatus &&
                        task.plannedDayKey >= startDayKey &&
                        task.plannedDayKey <= endDayKey
                }
            ))
        case .completed:
            guard let startDate = DayKey.date(from: startDayKey),
                  let endDate = DayKey.date(from: endDayKey) else {
                return []
            }
            let endExclusive = DayKey.addingDays(1, to: endDate)
            let completedDayPredicate = #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.status == doneStatus &&
                    (task.completedDayKey ?? "") != "" &&
                    (task.completedDayKey ?? "") >= startDayKey &&
                    (task.completedDayKey ?? "") <= endDayKey
            }
            let completedDayDescriptor = FetchDescriptor<Task>(
                predicate: completedDayPredicate
            )
            let completedDayTasks: [Task] = try context.fetch(completedDayDescriptor)
            let distantPast = Date.distantPast
            let completedAtPredicate = #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.status == doneStatus &&
                    task.completedDayKey == nil &&
                    (task.completedAt ?? distantPast) >= startDate &&
                    (task.completedAt ?? distantPast) < endExclusive
            }
            let completedAtDescriptor = FetchDescriptor<Task>(
                predicate: completedAtPredicate
            )
            let completedAtTasks: [Task] = try context.fetch(completedAtDescriptor)

            let archivedDayPredicate = #Predicate<Task> { task in
                (task.archivedDayKey ?? "") >= startDayKey &&
                    (task.archivedDayKey ?? "") <= endDayKey
            }
            let archivedDayDescriptor = FetchDescriptor<Task>(
                predicate: archivedDayPredicate
            )
            let archivedDayTasks: [Task] = try context.fetch(archivedDayDescriptor)
                .filter {
                    $0.supersededAt == nil &&
                        $0.status == doneStatus &&
                        $0.completedDayKey == nil &&
                        $0.completedAt == nil &&
                        $0.archivedDayKey != nil
                }

            let plannedDayPredicate = #Predicate<Task> { task in
                task.plannedDayKey >= startDayKey &&
                    task.plannedDayKey <= endDayKey
            }
            let plannedDayDescriptor = FetchDescriptor<Task>(
                predicate: plannedDayPredicate
            )
            let plannedDayTasks: [Task] = try context.fetch(plannedDayDescriptor)
                .filter {
                    $0.supersededAt == nil &&
                        $0.status == doneStatus &&
                        $0.completedDayKey == nil &&
                        $0.completedAt == nil &&
                        $0.archivedDayKey == nil
                }
            candidates = completedDayTasks +
                completedAtTasks +
                archivedDayTasks +
                plannedDayTasks
        }

        let candidateIDs = Array(Set(candidates.map(\.id)))
        guard !candidateIDs.isEmpty else { return [] }
        let activeVersions = try context.fetch(FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.status == doneStatus &&
                    candidateIDs.contains(task.id)
            }
        ))
        var representatives: [UUID: Task] = [:]
        for task in activeVersions {
            guard let existing = representatives[task.id] else {
                representatives[task.id] = task
                continue
            }
            if task.updatedAt > existing.updatedAt ||
                (task.updatedAt == existing.updatedAt &&
                    task.instanceID.uuidString > existing.instanceID.uuidString) {
                representatives[task.id] = task
            }
        }
        return Array(representatives.values).filter {
            let key = TaskHistoryDateRules.dayKey(for: $0, basis: basis)
            return startDayKey <= key && key <= endDayKey
        }
    }

    @MainActor
    static func archiveReviews(
        from startDayKey: String,
        through endDayKey: String,
        in context: ModelContext
    ) throws -> [DailyReview] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<DailyReview> { review in
                review.supersededAt == nil &&
                    review.dayKey >= startDayKey &&
                    review.dayKey <= endDayKey
            }
        ))
    }

    @MainActor
    static func archiveChecklistItems(
        taskIDs: [UUID],
        in context: ModelContext
    ) throws -> [TaskChecklistItem] {
        try TaskChecklistService.items(for: taskIDs, in: context)
    }

    @MainActor
    static func archiveAttachments(
        reviewIDs: [UUID],
        in context: ModelContext
    ) throws -> [DiaryAttachment] {
        guard !reviewIDs.isEmpty else { return [] }
        return try context.fetch(FetchDescriptor(
            predicate: #Predicate<DiaryAttachment> { attachment in
                attachment.supersededAt == nil && reviewIDs.contains(attachment.reviewId)
            },
            sortBy: [SortDescriptor(\DiaryAttachment.order)]
        ))
    }

    @MainActor
    static func archiveBlocks(
        reviewIDs: [UUID],
        in context: ModelContext
    ) throws -> [DiaryBlock] {
        guard !reviewIDs.isEmpty else { return [] }
        return try context.fetch(FetchDescriptor(
            predicate: #Predicate<DiaryBlock> { block in
                block.supersededAt == nil && reviewIDs.contains(block.reviewId)
            },
            sortBy: [SortDescriptor(\DiaryBlock.order)]
        ))
    }

    @MainActor
    static func archiveDayKeyExtent(
        basis: TaskHistoryDateBasis,
        in context: ModelContext
    ) throws -> ArchiveDayKeyExtent? {
        let doneStatus = TaskStatus.done.rawValue
        var completedAscending = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.status == doneStatus &&
                    task.completedDayKey != nil
            },
            sortBy: [SortDescriptor(\Task.completedDayKey)]
        )
        completedAscending.fetchLimit = 1
        var completedDescending = completedAscending
        completedDescending.sortBy = [SortDescriptor(\Task.completedDayKey, order: .reverse)]

        let completedAtExtentPredicate = #Predicate<Task> { task in
            task.supersededAt == nil &&
                task.status == doneStatus &&
                task.completedAt != nil
        }
        var completedAtAscending = FetchDescriptor<Task>(
            predicate: completedAtExtentPredicate,
            sortBy: [SortDescriptor(\Task.completedAt)]
        )
        completedAtAscending.fetchLimit = 1
        var completedAtDescending = completedAtAscending
        completedAtDescending.sortBy = [SortDescriptor(\Task.completedAt, order: .reverse)]

        let archivedExtentPredicate = #Predicate<Task> { task in
            task.supersededAt == nil &&
                task.status == doneStatus &&
                task.archivedDayKey != nil
        }
        var archivedAscending = FetchDescriptor<Task>(
            predicate: archivedExtentPredicate,
            sortBy: [SortDescriptor(\Task.archivedDayKey)]
        )
        archivedAscending.fetchLimit = 1
        var archivedDescending = archivedAscending
        archivedDescending.sortBy = [SortDescriptor(\Task.archivedDayKey, order: .reverse)]

        let plannedPredicate = #Predicate<Task> { task in
            task.supersededAt == nil && task.status == doneStatus
        }
        var plannedAscending = FetchDescriptor<Task>(
            predicate: plannedPredicate,
            sortBy: [SortDescriptor(\Task.plannedDayKey)]
        )
        plannedAscending.fetchLimit = 1
        var plannedDescending = plannedAscending
        plannedDescending.sortBy = [SortDescriptor(\Task.plannedDayKey, order: .reverse)]

        var reviewsAscending = FetchDescriptor<DailyReview>(
            predicate: #Predicate<DailyReview> { review in
                review.supersededAt == nil
            },
            sortBy: [SortDescriptor(\DailyReview.dayKey)]
        )
        reviewsAscending.fetchLimit = 1
        var reviewsDescending = reviewsAscending
        reviewsDescending.sortBy = [SortDescriptor(\DailyReview.dayKey, order: .reverse)]

        let earliestPlanned = try context.fetch(plannedAscending).first?.plannedDayKey
        let latestPlanned = try context.fetch(plannedDescending).first?.plannedDayKey
        var taskKeys: [String?]
        switch basis {
        case .planned:
            taskKeys = [earliestPlanned, latestPlanned]
        case .completed:
            let earliestCompletedAtTasks: [Task] = try context.fetch(
                completedAtAscending
            )
            let latestCompletedAtTasks: [Task] = try context.fetch(
                completedAtDescending
            )
            let earliestArchivedTasks: [Task] = try context.fetch(
                archivedAscending
            )
            let latestArchivedTasks: [Task] = try context.fetch(
                archivedDescending
            )
            let earliestCompletedAt = earliestCompletedAtTasks.first?.completedAt
            let latestCompletedAt = latestCompletedAtTasks.first?.completedAt
            taskKeys = [
                try context.fetch(completedAscending).first?.completedDayKey,
                try context.fetch(completedDescending).first?.completedDayKey,
                earliestCompletedAt.map(DayKey.key(for:)),
                latestCompletedAt.map(DayKey.key(for:)),
                earliestArchivedTasks.first?.archivedDayKey,
                latestArchivedTasks.first?.archivedDayKey,
                earliestPlanned,
                latestPlanned
            ]
        }
        let reviewKeys: [String?] = [
            try context.fetch(reviewsAscending).first?.dayKey,
            try context.fetch(reviewsDescending).first?.dayKey
        ]
        let keys = (taskKeys + reviewKeys).compactMap { $0 }.filter {
            DayKey.date(from: $0) != nil
        }
        guard let lowerBound = keys.min(), let upperBound = keys.max() else {
            return nil
        }
        return ArchiveDayKeyExtent(
            lowerBound: lowerBound,
            upperBound: upperBound
        )
    }

    static func deduplicated<Model, Key: Hashable>(
        _ models: [Model],
        by keyPath: KeyPath<Model, Key>
    ) -> [Model] {
        var seen: Set<Key> = []
        return models.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }

    @MainActor
    static func fetchInBatches<Model: PersistentModel>(
        _ sourceDescriptor: FetchDescriptor<Model>,
        in context: ModelContext,
        isCancelled: () -> Bool
    ) throws -> [Model] {
        var offset = 0
        var results: [Model] = []

        while true {
            if isCancelled() { throw CancellationError() }
            var descriptor = sourceDescriptor
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = taskHistoryStatisticsBatchSize
            let batch = try context.fetch(descriptor)
            results.append(contentsOf: batch)
            guard batch.count == taskHistoryStatisticsBatchSize else { break }
            offset += batch.count
        }
        return results
    }
}
