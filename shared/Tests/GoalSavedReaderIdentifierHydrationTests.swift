import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// SDK primitive control, independent of SavedModelPageReader and candidate Core APIs.
/// The generic predicate is intentionally the exact proposed targeted hydration boundary.
@MainActor
private func goalHydrateSavedCleanIDs<Model: PersistentModel>(
    _ type: Model.Type, savedIDs: [PersistentIdentifier], in context: ModelContext
) throws -> (rows: [Model], cleanIDs: [PersistentIdentifier]) {
    let unsafeIDs = Set((context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray)
        .compactMap { $0 as? Model }.map(\.persistentModelID))
    let savedCleanIDs = savedIDs.filter { !unsafeIDs.contains($0) }
    guard !savedCleanIDs.isEmpty else { return ([], []) }
    var descriptor = FetchDescriptor<Model>(predicate: #Predicate<Model> {
        savedCleanIDs.contains($0.persistentModelID)
    })
    descriptor.includePendingChanges = false
    descriptor.fetchLimit = savedCleanIDs.count
    return (try context.fetch(descriptor), savedCleanIDs)
}

@Test @MainActor
func goalSavedCleanMemoIdentifierHydrationRefreshesExternalSaveAndExcludesDrafts() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let source = container.mainContext
    source.autosaveEnabled = false
    let base = Date(timeIntervalSince1970: 1_790_899_200)
    let clean = Memo(content: "외부 저장 전", createdAt: base, updatedAt: base)
    let dirty = Memo(content: "저장된 dirty 부모", createdAt: base, updatedAt: base)
    let deleted = Memo(content: "삭제할 부모", createdAt: base, updatedAt: base)
    source.insert(clean)
    source.insert(dirty)
    source.insert(deleted)
    try source.save()
    let savedIDs = [clean.persistentModelID, dirty.persistentModelID, deleted.persistentModelID]
    let registeredClean: Memo? = source.registeredModel(for: clean.persistentModelID)
    #expect(registeredClean === clean)
    dirty.content = "절대 덮어쓰면 안 되는 미저장 부모"
    dirty.isPinned = true
    source.delete(deleted)
    let unrelated = Memo(content: "무관한 새 미저장 draft", createdAt: base, updatedAt: base)
    source.insert(unrelated)
    let dirtyBefore = GoalHydrationMemoValue(dirty)
    let unrelatedBefore = GoalHydrationMemoValue(unrelated)

    let writer = ModelContext(container)
    writer.autosaveEnabled = false
    let logicalID = clean.id
    let external = try #require(writer.fetch(FetchDescriptor<Memo>(
        predicate: #Predicate { $0.id == logicalID })).first)
    let latestBody = "외부에서 저장한 최신 본문"
    let latestDate = base.addingTimeInterval(2_000)
    external.content = latestBody
    external.updatedAt = latestDate
    try writer.save()
    #expect(!writer.hasChanges)
    #expect(GoalHydrationMemoValue(dirty) == dirtyBefore)
    #expect(GoalHydrationMemoValue(unrelated) == unrelatedBefore)
    let pendingBefore = goalHydrationPendingIDs(source)
    print("GOAL_IDENTIFIER_HYDRATION_BEFORE model=Memo registeredLatest=\(clean.content == latestBody) cleanPending=\(pendingBefore.contains(clean.persistentModelID))")

    let result = try goalHydrateSavedCleanIDs(Memo.self, savedIDs: savedIDs, in: source)
    #expect(result.cleanIDs == [clean.persistentModelID])
    #expect(result.rows.map(\.persistentModelID) == [clean.persistentModelID])
    #expect(GoalHydrationMemoValue(dirty) == dirtyBefore)
    #expect(GoalHydrationMemoValue(unrelated) == unrelatedBefore)
    #expect(goalHydrationPendingIDs(source) == pendingBefore)
    #expect(source.hasChanges)
    #expect(source.deletedModelsArray.contains { $0.persistentModelID == deleted.persistentModelID })
    let refreshed = try #require(result.rows.first)
    #expect(refreshed === clean)
    #expect(refreshed.content == latestBody && refreshed.updatedAt == latestDate)
    let registeredDirty: Memo? = source.registeredModel(for: dirty.persistentModelID)
    let registeredDraft: Memo? = source.registeredModel(for: unrelated.persistentModelID)
    #expect(registeredDirty === dirty && registeredDraft === unrelated)
    withExtendedLifetime(container) {}
}

@Test @MainActor
func goalSavedCleanActivityIdentifierHydrationRefreshesExternalDayAndTask() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let source = container.mainContext
    source.autosaveEnabled = false
    let base = Date(timeIntervalSince1970: 1_790_899_200)
    let day1 = DayKey.key(for: base)
    let day2Date = DayKey.addingDays(1, to: base)
    let day2 = DayKey.key(for: day2Date)
    let task1 = UUID(uuidString: "00000001-0000-4000-8000-000000000001")!
    let task2 = UUID(uuidString: "00000001-0000-4000-8000-000000000002")!
    let activity = TaskCompletionActivity(id: UUID(), taskId: task1, activityDayKey: day1,
        occurredAt: base, createdAt: base, updatedAt: base)
    source.insert(activity)
    try source.save()
    let registered: TaskCompletionActivity? = source.registeredModel(for: activity.persistentModelID)
    #expect(registered === activity)
    let draft = Memo(content: "무관한 미저장 draft", createdAt: base, updatedAt: base)
    source.insert(draft)
    let draftBefore = GoalHydrationMemoValue(draft)

    let writer = ModelContext(container)
    writer.autosaveEnabled = false
    let logicalID = activity.id
    let external = try #require(writer.fetch(FetchDescriptor<TaskCompletionActivity>(
        predicate: #Predicate { $0.id == logicalID })).first)
    let latestDate = base.addingTimeInterval(2_000)
    external.activityDayKey = day2
    external.taskId = task2
    external.occurredAt = day2Date
    external.updatedAt = latestDate
    try writer.save()
    #expect(!writer.hasChanges)
    #expect(GoalHydrationMemoValue(draft) == draftBefore)
    let pendingBefore = goalHydrationPendingIDs(source)
    print("GOAL_IDENTIFIER_HYDRATION_BEFORE model=TaskCompletionActivity registeredDay=\(activity.activityDayKey) activityPending=\(pendingBefore.contains(activity.persistentModelID))")

    let result = try goalHydrateSavedCleanIDs(TaskCompletionActivity.self,
        savedIDs: [activity.persistentModelID], in: source)
    #expect(result.cleanIDs == [activity.persistentModelID])
    #expect(result.rows.map(\.persistentModelID) == [activity.persistentModelID])
    #expect(GoalHydrationMemoValue(draft) == draftBefore)
    #expect(goalHydrationPendingIDs(source) == pendingBefore && source.hasChanges)
    let refreshed = try #require(result.rows.first)
    #expect(refreshed === activity)
    #expect(refreshed.activityDayKey == day2 && refreshed.taskId == task2)
    #expect(refreshed.occurredAt == day2Date && refreshed.updatedAt == latestDate)
    let registeredDraft: Memo? = source.registeredModel(for: draft.persistentModelID)
    #expect(registeredDraft === draft)
    withExtendedLifetime(container) {}
}

@MainActor
private func goalHydrationPendingIDs(_ context: ModelContext) -> Set<PersistentIdentifier> {
    Set((context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray).map(\.persistentModelID))
}

private struct GoalHydrationMemoValue: Equatable {
    let content: String
    let pinned: Bool
    let id: UUID
    let instanceID: UUID
    let createdAt: Date
    let updatedAt: Date

    init(_ memo: Memo) {
        content = memo.content
        pinned = memo.isPinned
        id = memo.id
        instanceID = memo.instanceID
        createdAt = memo.createdAt
        updatedAt = memo.updatedAt
    }
}
