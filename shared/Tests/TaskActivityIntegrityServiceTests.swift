import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func activityIntegrityCanonicalizesIDsAndPrefersCapturedOrigin() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let taskID = UUID()
    let occurredAt = Date(timeIntervalSince1970: 1_786_752_000)
    let dayKey = "2026-08-14"
    let legacy = TaskCompletionActivity(
        id: UUID(),
        instanceID: activityTestUUID(1),
        taskId: taskID,
        activityDayKey: dayKey,
        occurredAt: occurredAt,
        origin: .legacyBackfill,
        createdAt: activityTestDate(10),
        updatedAt: activityTestDate(50)
    )
    let captured = TaskCompletionActivity(
        id: UUID(),
        instanceID: activityTestUUID(2),
        taskId: taskID,
        activityDayKey: dayKey,
        occurredAt: occurredAt,
        origin: .captured,
        createdAt: activityTestDate(20),
        updatedAt: activityTestDate(40)
    )
    context.insert(legacy)
    context.insert(captured)
    try context.save()

    let report = try DataIntegrityService.reconcile(context: context)
    let activities = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
    let active = try #require(activities.first { $0.supersededAt == nil })

    #expect(report.mergedRecords == 1)
    #expect(report.supersededRecords == 1)
    #expect(active.instanceID == captured.instanceID)
    #expect(active.id == TaskActivityRules.logicalID(
        taskID: taskID,
        activityDayKey: dayKey
    ))
    #expect(active.createdAt == legacy.createdAt)
    #expect(legacy.supersededAt == captured.updatedAt)

    let second = try DataIntegrityService.reconcile(context: context)
    #expect(!second.hasChanges)
}

@Test
@MainActor
func activityIntegritySupersedesInvalidSemanticRecords() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let invalidDay = TaskCompletionActivity(
        id: UUID(),
        taskId: UUID(),
        activityDayKey: "2026-02-30",
        occurredAt: activityTestDate(10),
        origin: .captured,
        createdAt: activityTestDate(10),
        updatedAt: activityTestDate(20)
    )
    let invalidOrigin = TaskCompletionActivity(
        id: UUID(),
        taskId: UUID(),
        activityDayKey: "2026-08-14",
        occurredAt: activityTestDate(10),
        origin: .captured,
        createdAt: activityTestDate(10),
        updatedAt: activityTestDate(30)
    )
    invalidOrigin.originRawValue = "future-origin"
    context.insert(invalidDay)
    context.insert(invalidOrigin)
    try context.save()

    let report = try TaskActivityIntegrityService.reconcile(in: context)

    #expect(report.supersededRecords == 2)
    #expect(invalidDay.supersededAt == invalidDay.updatedAt)
    #expect(invalidOrigin.supersededAt == invalidOrigin.updatedAt)
}

@Test
@MainActor
func activityIntegrityFindsCrossDayCapturedCandidateAcrossPages() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let taskID = UUID()
    let occurredAt = Date(timeIntervalSince1970: 1_786_752_000)
    let legacy = TaskCompletionActivity(
        id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: "2026-08-14"),
        instanceID: activityTestUUID(10),
        taskId: taskID,
        activityDayKey: "2026-08-14",
        occurredAt: occurredAt,
        origin: .legacyBackfill,
        createdAt: activityTestDate(10),
        updatedAt: activityTestDate(20)
    )
    let captured = TaskCompletionActivity(
        id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: "2026-08-15"),
        instanceID: activityTestUUID(20),
        taskId: taskID,
        activityDayKey: "2026-08-15",
        occurredAt: occurredAt.addingTimeInterval(0.5),
        origin: .captured,
        createdAt: activityTestDate(30),
        updatedAt: activityTestDate(40)
    )
    context.insert(legacy)
    context.insert(captured)
    try context.save()

    let report = try TaskActivityIntegrityService.reconcile(
        in: context,
        pageSize: 1
    )

    #expect(report.mergedRecords == 1)
    #expect(legacy.supersededAt == captured.updatedAt)
    #expect(captured.supersededAt == nil)
}

@Test
@MainActor
func invalidCrossDayCapturedCandidateDoesNotSupersedeLegacyEvidence() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let taskID = UUID()
    let occurredAt = Date(timeIntervalSince1970: 1_786_752_000)
    let legacy = TaskCompletionActivity(
        id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: "2026-08-14"),
        instanceID: activityTestUUID(20),
        taskId: taskID,
        activityDayKey: "2026-08-14",
        occurredAt: occurredAt,
        origin: .legacyBackfill,
        createdAt: activityTestDate(10),
        updatedAt: activityTestDate(20)
    )
    let invalidCaptured = TaskCompletionActivity(
        id: UUID(),
        instanceID: activityTestUUID(21),
        taskId: taskID,
        activityDayKey: "2026-02-30",
        occurredAt: occurredAt.addingTimeInterval(0.5),
        origin: .captured,
        createdAt: activityTestDate(30),
        updatedAt: activityTestDate(40)
    )
    context.insert(legacy)
    context.insert(invalidCaptured)
    try context.save()

    let report = try TaskActivityIntegrityService.reconcile(
        in: context,
        pageSize: 1
    )

    #expect(report.mergedRecords == 0)
    #expect(legacy.supersededAt == nil)
    #expect(invalidCaptured.supersededAt == invalidCaptured.updatedAt)
}

@Test
@MainActor
func activityIntegrityIncludesPendingInsertionsWithoutBreakingPaging() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let taskID = UUID()
    let occurredAt = Date(timeIntervalSince1970: 1_786_752_000)
    let legacy = TaskCompletionActivity(
        id: UUID(),
        taskId: taskID,
        activityDayKey: "2026-08-14",
        occurredAt: occurredAt,
        origin: .legacyBackfill,
        createdAt: activityTestDate(10),
        updatedAt: activityTestDate(20)
    )
    context.insert(legacy)
    try context.save()

    let captured = TaskCompletionActivity(
        id: UUID(),
        taskId: taskID,
        activityDayKey: "2026-08-15",
        occurredAt: occurredAt.addingTimeInterval(0.5),
        origin: .captured,
        createdAt: activityTestDate(30),
        updatedAt: activityTestDate(40)
    )
    context.insert(captured)

    let report = try TaskActivityIntegrityService.reconcile(
        in: context,
        pageSize: 1
    )

    #expect(report.scannedRecords == 2)
    #expect(report.mergedRecords == 1)
    #expect(legacy.supersededAt == captured.updatedAt)
    #expect(captured.supersededAt == nil)
    #expect(captured.id == TaskActivityRules.logicalID(
        taskID: taskID,
        activityDayKey: "2026-08-15"
    ))
}

private func activityTestDate(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_786_752_000 + offset)
}

private func activityTestUUID(_ value: UInt64) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llX", value))!
}
