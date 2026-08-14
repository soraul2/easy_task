import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func startupIntegrityBackfillsLegacyActivityAndSavesIt() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let completedAt = Date(timeIntervalSince1970: 1_786_752_000)
    let task = Task(title: "기존 완료", plannedAt: completedAt, order: 100)
    TaskRules.applyStatus(
        .done,
        to: task,
        now: completedAt,
        completionDayKey: "2026-08-14"
    )
    context.insert(task)
    try context.save()

    let report = try DataIntegrityService.reconcile(context: context)
    let activities = try context.fetch(FetchDescriptor<TaskCompletionActivity>())

    #expect(report.insertedRecords == 1)
    #expect(report.hasChanges)
    #expect(activities.count == 1)
    #expect(activities[0].taskId == task.id)
    #expect(
        activities[0].originRawValue ==
            TaskCompletionActivityOrigin.legacyBackfill.rawValue
    )

    let second = try DataIntegrityService.reconcile(context: context)
    #expect(second.insertedRecords == 0)
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 1)
}

@Test
@MainActor
func immediateCloudIntegrityCanDeferLegacyActivityBackfill() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let completedAt = Date(timeIntervalSince1970: 1_786_752_000)
    let task = Task(title: "가져온 기존 완료", plannedAt: completedAt, order: 100)
    TaskRules.applyStatus(
        .done,
        to: task,
        now: completedAt,
        completionDayKey: "2026-08-14"
    )
    context.insert(task)
    try context.save()

    let report = try DataIntegrityService.reconcile(
        context: context,
        backfillLegacyTaskActivity: false
    )

    #expect(report.insertedRecords == 0)
    #expect(try context.fetch(FetchDescriptor<TaskCompletionActivity>()).isEmpty)
}

@Test
@MainActor
func legacyBackfillIsBoundedIdempotentAndUsesNormalizedCompletionEvidence() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let plannedAt = try #require(DayKey.date(from: "2026-08-10"))
    let completedAt = try #require(ISO8601DateFormatter().date(
        from: "2026-08-14T23:30:00Z"
    ))
    let explicit = Task(title: "기존 완료", status: .done, plannedAt: plannedAt, order: 100)
    explicit.completedAt = completedAt
    explicit.completedDayKey = "2026-08-14"
    let normalized = Task(
        title: "정규화 완료",
        status: .done,
        plannedAt: plannedAt,
        order: 200,
        updatedAt: completedAt.addingTimeInterval(60)
    )
    context.insert(explicit)
    context.insert(normalized)
    try context.save()

    _ = try DataIntegrityService.reconcile(
        context: context,
        backfillLegacyTaskActivity: false
    )
    let first = try PersistenceCommandService.perform(in: context) {
        try TaskActivityBackfillService.backfillLegacyCompletions(
            in: context,
            createdAt: completedAt.addingTimeInterval(120)
        )
    }
    let second = try PersistenceCommandService.perform(in: context) {
        try TaskActivityBackfillService.backfillLegacyCompletions(
            in: context,
            createdAt: completedAt.addingTimeInterval(180)
        )
    }
    let activities = try context.fetch(FetchDescriptor<TaskCompletionActivity>())

    #expect(first.scannedTasks == 2)
    #expect(first.insertedActivities == 2)
    #expect(second.scannedTasks == 2)
    #expect(second.insertedActivities == 0)
    #expect(activities.count == 2)
    #expect(activities.allSatisfy {
        $0.originRawValue == TaskCompletionActivityOrigin.legacyBackfill.rawValue
    })
    #expect(activities.first { $0.taskId == explicit.id }?.activityDayKey == "2026-08-14")
    #expect(normalized.completedAt != nil)
}

@Test
@MainActor
func legacyBackfillHonorsCancellationBeforeMutation() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let task = Task(title: "취소", status: .done, plannedAt: Date(), order: 100)
    task.completedAt = Date()
    context.insert(task)
    try context.save()

    #expect(throws: CancellationError.self) {
        try TaskActivityBackfillService.backfillLegacyCompletions(
            in: context,
            isCancelled: { true }
        )
    }
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 0)
}
