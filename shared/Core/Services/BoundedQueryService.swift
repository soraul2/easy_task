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


    public static func taskDescriptor(id: UUID) -> FetchDescriptor<Task> {
        var descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil && task.id == id
            }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    public static func taskCandidatesDescriptor(id: UUID) -> FetchDescriptor<Task> {
        FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil && task.id == id
            },
            sortBy: [
                SortDescriptor(\Task.updatedAt, order: .reverse),
                SortDescriptor(\Task.instanceID, order: .reverse)
            ]
        )
    }

    @MainActor
    public static func representativeTask(from candidates: [Task]) -> Task? {
        candidates
            .filter { $0.supersededAt == nil }
            .max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.instanceID.uuidString < rhs.instanceID.uuidString
            }
    }

    public static func taskDescriptor(instanceID: UUID) -> FetchDescriptor<Task> {
        var descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil && task.instanceID == instanceID
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
}
