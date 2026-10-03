import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

enum GoalPendingPageMutation: String, CaseIterable, Sendable { case moved, deleted }

private func goalPendingPageID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

private struct GoalPendingActivityState: Equatable {
    let physicalID: PersistentIdentifier
    let day: String
    let occurredAt: Date
    let updatedAt: Date
}

@MainActor
private func goalPendingActivityPages(
    mutation: GoalPendingPageMutation, keepFinalClean: Bool
) throws -> (ModelContainer, Date, [TaskCompletionActivity], [GoalPendingActivityState]) {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let day = try #require(DayKey.date(from: "2026-10-02"))
    // First limit-1 read and the next full 256 saved-ID page are all excluded.
    let count = BoundedQueryService.taskActivityBatchSize + 3
    let activities = (0..<count).map { index in
        let date = DayKey.addingDays(-index - 1, to: day)
        let key = DayKey.key(for: date)
        let taskID = goalPendingPageID(1000 + index)
        let activity = TaskCompletionActivity(
            id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: key),
            instanceID: goalPendingPageID(2000 + index), taskId: taskID, activityDayKey: key,
            occurredAt: date.addingTimeInterval(12 * 3600), origin: .captured,
            createdAt: date, updatedAt: date)
        context.insert(activity)
        return activity
    }
    try context.save()
    for activity in activities.prefix(keepFinalClean ? count - 1 : count) {
        switch mutation {
        case .moved:
            activity.activityDayKey = DayKey.key(for: DayKey.addingDays(1, to: day))
            activity.occurredAt = DayKey.addingDays(1, to: day).addingTimeInterval(12 * 3600)
            activity.updatedAt = day.addingTimeInterval(13 * 3600)
        case .deleted:
            context.delete(activity)
        }
    }
    let values = activities.map {
        GoalPendingActivityState(physicalID: $0.persistentModelID, day: $0.activityDayKey,
                                 occurredAt: $0.occurredAt, updatedAt: $0.updatedAt)
    }
    return (container, day, activities, values)
}

@Test(arguments: GoalPendingPageMutation.allCases)
@MainActor
func goalPendingActivityExistsBeyondFullExcludedSavedPages(mutation: GoalPendingPageMutation) throws {
    let (container, day, activities, before) = try goalPendingActivityPages(
        mutation: mutation, keepFinalClean: true)
    let context = container.mainContext
    let deleted = Set(context.deletedModelsArray.map(\.persistentModelID))
    #expect(try BoundedQueryService.hasTaskActivity(before: DayKey.key(for: day), in: context))
    let snapshots = try BoundedQueryService.taskActivitySnapshots(
        from: DayKey.key(for: DayKey.addingDays(-activities.count, to: day)),
        through: DayKey.key(for: DayKey.addingDays(-1, to: day)), in: context)
    let clean = try #require(activities.last)
    #expect(snapshots == [TaskActivitySnapshot(taskID: clean.taskId, activityDayKey: clean.activityDayKey)])
    #expect(activities.map {
        GoalPendingActivityState(physicalID: $0.persistentModelID, day: $0.activityDayKey,
                                 occurredAt: $0.occurredAt, updatedAt: $0.updatedAt)
    } == before)
    #expect(Set(context.deletedModelsArray.map(\.persistentModelID)) == deleted)
    #expect(context.hasChanges)
}

@Test(arguments: GoalPendingPageMutation.allCases)
@MainActor
func goalPendingActivityExcludedSavedPagesReachEOF(mutation: GoalPendingPageMutation) throws {
    let (container, day, activities, before) = try goalPendingActivityPages(
        mutation: mutation, keepFinalClean: false)
    let context = container.mainContext
    #expect(try !BoundedQueryService.hasTaskActivity(before: DayKey.key(for: day), in: context))
    #expect(try BoundedQueryService.taskActivitySnapshots(
        from: DayKey.key(for: DayKey.addingDays(-activities.count, to: day)),
        through: DayKey.key(for: DayKey.addingDays(-1, to: day)), in: context).isEmpty)
    #expect(activities.map {
        GoalPendingActivityState(physicalID: $0.persistentModelID, day: $0.activityDayKey,
                                 occurredAt: $0.occurredAt, updatedAt: $0.updatedAt)
    } == before)
    #expect(context.hasChanges)
}

@MainActor
private func goalPendingFocusPageFixture() throws -> (ModelContainer, FocusSession, FocusSession) {
    let container = try PlanBaseContainerFactory.makeInMemory()
    container.mainContext.autosaveEnabled = false
    let date = try #require(DayKey.date(from: "2026-10-02"))
    func make(_ value: Int) -> FocusSession {
        FocusSession(id: goalPendingPageID(value), instanceID: goalPendingPageID(value + 100),
                     taskId: goalPendingPageID(900), startedAt: date,
                     endedAt: date.addingTimeInterval(1500), plannedDurationSeconds: 1500,
                     focusedDurationSeconds: 300, outcome: .stopped, createdAt: date, updatedAt: date)
    }
    let dirty = make(1)
    let clean = make(2)
    container.mainContext.insert(dirty)
    container.mainContext.insert(clean)
    try container.mainContext.save()
    return (container, dirty, clean)
}

@Test @MainActor
func goalPendingSavedPageRawCountKeepsOffsetsAndCleanIdentity() throws {
    let (container, dirty, clean) = try goalPendingFocusPageFixture()
    let context = container.mainContext
    dirty.focusedDurationSeconds = 900
    var descriptor = FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\FocusSession.id)])
    descriptor.fetchLimit = 1
    let excluded: Set<PersistentIdentifier> = [dirty.persistentModelID]
    let first = try SavedModelPageReader.read(descriptor, in: context, excluding: excluded)
    #expect(first.fetchedCount == 1)
    #expect(first.rows.isEmpty)
    descriptor.fetchOffset = first.fetchedCount
    let second = try SavedModelPageReader.read(descriptor, in: context, excluding: excluded)
    #expect(second.fetchedCount == 1)
    #expect(second.rows.count == 1)
    #expect(second.rows.first === clean)
    descriptor.fetchOffset = first.fetchedCount + second.fetchedCount
    let end = try SavedModelPageReader.read(descriptor, in: context, excluding: excluded)
    #expect(end.fetchedCount == 0 && end.rows.isEmpty)
    #expect(dirty.focusedDurationSeconds == 900)
    let registered: FocusSession? = context.registeredModel(for: dirty.persistentModelID)
    #expect(registered === dirty)
    #expect(context.hasChanges)
}

@Test @MainActor
func goalPendingIntegrityCancellationAfterExcludedPageKeepsDraft() throws {
    let (container, dirty, clean) = try goalPendingFocusPageFixture()
    let context = container.mainContext
    dirty.focusedDurationSeconds = 900
    var checks = 0
    do {
        _ = try FocusSessionIntegrityService.reconcile(in: context, pageSize: 1, isCancelled: {
            checks += 1
            // Read the excluded first saved page, then cancel before normalizing
            // the clean second row. The offset must advance despite zero rows.
            return checks >= 3
        })
        Issue.record("CancellationError가 발생해야 합니다")
    } catch is CancellationError {
        #expect(checks == 3)
    }
    #expect(dirty.focusedDurationSeconds == 900)
    #expect(clean.focusedDurationSeconds == 300)
    #expect(dirty.supersededAt == nil && clean.supersededAt == nil)
    #expect(context.hasChanges)
}

private enum GoalPendingMutationFailure: Error { case intentional }

@Test @MainActor
func goalPendingAtomicFailureRollsBackOnlyMutationAfterIdentifierRead() throws {
    let (container, dirty, clean) = try goalPendingFocusPageFixture()
    let context = container.mainContext
    // This unrelated valid edit belongs to the command's pre-save baseline.
    clean.focusedDurationSeconds = 600
    do {
        try PersistenceCommandService.perform(in: context) {
            dirty.focusedDurationSeconds = 900
            _ = try FocusSessionIntegrityService.reconcile(in: context, pageSize: 1)
            #expect(dirty.focusedDurationSeconds == 900)
            throw GoalPendingMutationFailure.intentional
        }
        Issue.record("주입한 명령 실패가 전달되어야 합니다")
    } catch GoalPendingMutationFailure.intentional {}
    #expect(!context.hasChanges)
    #expect(dirty.focusedDurationSeconds == 300)
    #expect(clean.focusedDurationSeconds == 600)
    let reader = ModelContext(container)
    reader.autosaveEnabled = false
    let saved = try reader.fetch(FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\FocusSession.id)]))
    #expect(saved.map(\.focusedDurationSeconds) == [300, 600])
}
