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
        let storeExtent = try archiveDayKeyExtent(in: context)
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
        in context: ModelContext
    ) throws -> [Task] {
        let doneStatus = TaskStatus.done.rawValue
        let descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.status == doneStatus &&
                    (task.completedDayKey ?? task.archivedDayKey ?? task.plannedDayKey) >= startDayKey &&
                    (task.completedDayKey ?? task.archivedDayKey ?? task.plannedDayKey) <= endDayKey
            }
        )
        return try context.fetch(descriptor)
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

        var archivedAscending = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.status == doneStatus &&
                    task.archivedDayKey != nil
            },
            sortBy: [SortDescriptor(\Task.archivedDayKey)]
        )
        archivedAscending.fetchLimit = 1
        var archivedDescending = archivedAscending
        archivedDescending.sortBy = [SortDescriptor(\Task.archivedDayKey, order: .reverse)]

        var plannedAscending = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.status == doneStatus
            },
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

        let keys = [
            try context.fetch(completedAscending).first?.completedDayKey,
            try context.fetch(completedDescending).first?.completedDayKey,
            try context.fetch(archivedAscending).first?.archivedDayKey,
            try context.fetch(archivedDescending).first?.archivedDayKey,
            try context.fetch(plannedAscending).first?.plannedDayKey,
            try context.fetch(plannedDescending).first?.plannedDayKey,
            try context.fetch(reviewsAscending).first?.dayKey,
            try context.fetch(reviewsDescending).first?.dayKey
        ].compactMap { $0 }.filter {
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
}
