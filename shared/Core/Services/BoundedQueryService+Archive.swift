import Foundation
import SwiftData

extension BoundedQueryService {
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
}
extension BoundedQueryService {
    static let archiveScanWindowDays = 30

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
            return $0.status == doneStatus && startDayKey <= key && key <= endDayKey
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
}
