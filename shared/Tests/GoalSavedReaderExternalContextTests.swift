import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Public production query only; no SavedModelPageReader or new candidate API reference.
/// Registration before the external save is deliberate, but SDK auto-merge timing is not assumed.
@Test(arguments: ["inserted-draft", "edited-draft"]) @MainActor
func goalSavedActivityExternalSaveRemainsFreshWithUnrelatedMemoDraft(kind: String) throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let source = container.mainContext
    source.autosaveEnabled = false
    let base = Date(timeIntervalSince1970: 1_790_899_200)
    let day1 = DayKey.key(for: base)
    let day2Date = DayKey.addingDays(1, to: base)
    let day2 = DayKey.key(for: day2Date)
    let oldTaskID = UUID(uuidString: "00000001-0000-4000-8000-000000000001")!
    let newTaskID = UUID(uuidString: "00000001-0000-4000-8000-000000000002")!
    let activity = TaskCompletionActivity(
        id: UUID(uuidString: "00000002-0000-4000-8000-000000000001")!,
        instanceID: UUID(uuidString: "00000003-0000-4000-8000-000000000001")!,
        taskId: oldTaskID, activityDayKey: day1, occurredAt: base,
        createdAt: base, updatedAt: base)
    source.insert(activity)
    try source.save()
    let registeredBefore: TaskCompletionActivity? = source.registeredModel(for: activity.persistentModelID)
    #expect(registeredBefore === activity)
    #expect(activity.activityDayKey == day1 && activity.taskId == oldTaskID)
    let draft = try goalExternalReaderDraft(in: source, kind: kind, at: base)
    let draftBefore = GoalExternalDraftValue(draft)
    #expect(source.changedModelsArray.compactMap { $0 as? TaskCompletionActivity }.isEmpty)

    let writer = ModelContext(container)
    writer.autosaveEnabled = false
    let logicalID = activity.id
    let external = try #require(writer.fetch(FetchDescriptor<TaskCompletionActivity>(
        predicate: #Predicate { $0.id == logicalID })).first)
    external.activityDayKey = day2
    external.taskId = newTaskID
    external.occurredAt = day2Date
    external.updatedAt = base.addingTimeInterval(2_000)
    try writer.save()
    #expect(!writer.hasChanges)
    #expect(external.updatedAt == base.addingTimeInterval(2_000))

    // Classify SDK behavior without requiring the original registered clean row to stay stale.
    // No source-context model fetch, refresh, save, processPendingChanges, or yield intervenes.
    let activityPending = source.changedModelsArray.contains { $0.persistentModelID == activity.persistentModelID }
    print("GOAL_EXTERNAL_ACTIVITY_BEFORE_QUERY kind=\(kind) registeredDay=\(activity.activityDayKey) registeredTask=\(activity.taskId) registeredUpdated=\(activity.updatedAt.timeIntervalSince1970) activityPending=\(activityPending)")
    #expect(GoalExternalDraftValue(draft) == draftBefore)
    let pendingBefore = goalExternalPendingIDs(source)
    #expect(pendingBefore.contains(draft.persistentModelID))
    #expect(source.hasChanges)

    let latest = try BoundedQueryService.taskActivitySnapshots(from: day2, through: day2, in: source)
    #expect(latest == [TaskActivitySnapshot(taskID: newTaskID, activityDayKey: day2)])
    let oldDay = try BoundedQueryService.taskActivitySnapshots(from: day1, through: day1, in: source)
    #expect(oldDay.isEmpty)
    let wholeRange = try BoundedQueryService.taskActivitySnapshots(from: day1, through: day2, in: source)
    #expect(wholeRange == [TaskActivitySnapshot(taskID: newTaskID, activityDayKey: day2)])
    let registeredDraft: Memo? = source.registeredModel(for: draft.persistentModelID)
    #expect(registeredDraft === draft)
    #expect(GoalExternalDraftValue(draft) == draftBefore)
    #expect(goalExternalPendingIDs(source) == pendingBefore)
    #expect(source.hasChanges)
    withExtendedLifetime(container) {}
}

/// Same saved-clean versus unrelated-dirty boundary, including actual search matching/summary.
@Test(arguments: ["inserted-draft", "edited-draft"]) @MainActor
func goalSavedMemoExternalBodySaveRemainsSearchableWithUnrelatedDraft(kind: String) throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let source = container.mainContext
    source.autosaveEnabled = false
    let base = Date(timeIntervalSince1970: 1_790_899_200)
    let target = Memo(id: UUID(uuidString: "00000004-0000-4000-8000-000000000001")!,
        instanceID: UUID(uuidString: "00000005-0000-4000-8000-000000000001")!,
        content: "외부 저장 전 본문", createdAt: base, updatedAt: base)
    source.insert(target)
    try source.save()
    let registeredBefore: Memo? = source.registeredModel(for: target.persistentModelID)
    #expect(registeredBefore === target)
    let targetPhysicalID = target.instanceID
    let draft = try goalExternalReaderDraft(in: source, kind: kind, at: base)
    let draftBefore = GoalExternalDraftValue(draft)
    #expect(!source.changedModelsArray.contains { $0.persistentModelID == target.persistentModelID })

    let writer = ModelContext(container)
    writer.autosaveEnabled = false
    let logicalID = target.id
    let external = try #require(writer.fetch(FetchDescriptor<Memo>(
        predicate: #Predicate { $0.id == logicalID })).first)
    let latestBody = "외부수정최신토큰\n새로 저장된 본문"
    let latestDate = base.addingTimeInterval(2_000)
    external.content = latestBody
    external.updatedAt = latestDate
    try writer.save()
    #expect(!writer.hasChanges)
    #expect(external.content == latestBody && external.updatedAt == latestDate)
    let targetPending = source.changedModelsArray.contains { $0.persistentModelID == target.persistentModelID }
    print("GOAL_EXTERNAL_MEMO_BEFORE_QUERY kind=\(kind) registeredLatestBody=\(target.content == latestBody) registeredUpdated=\(target.updatedAt.timeIntervalSince1970) targetPending=\(targetPending)")
    #expect(GoalExternalDraftValue(draft) == draftBefore)
    let pendingBefore = goalExternalPendingIDs(source)
    #expect(pendingBefore.contains(draft.persistentModelID))

    let page = try MemoService.page(in: source, query: "외부수정최신토큰")
    #expect(GoalExternalDraftValue(draft) == draftBefore)
    #expect(goalExternalPendingIDs(source) == pendingBefore)
    #expect(source.hasChanges)
    #expect(page.memos.map(\.instanceID) == [targetPhysicalID])
    let returned = try #require(page.memos.first)
    #expect(returned.content == latestBody && returned.updatedAt == latestDate)
    #expect(page.summaries[targetPhysicalID]?.title == "외부수정최신토큰")
    #expect(page.nextCursor == nil && !page.hasMore)
    let oldBody = try MemoService.page(in: source, query: "외부 저장 전 본문")
    #expect(oldBody.memos.isEmpty && oldBody.nextCursor == nil && !oldBody.hasMore)
    let registeredDraft: Memo? = source.registeredModel(for: draft.persistentModelID)
    #expect(registeredDraft === draft)
    #expect(GoalExternalDraftValue(draft) == draftBefore)
    #expect(goalExternalPendingIDs(source) == pendingBefore)
    #expect(source.hasChanges)
    withExtendedLifetime(container) {}
}

@MainActor
private func goalExternalReaderDraft(in context: ModelContext, kind: String, at date: Date) throws -> Memo {
    let draft = Memo(id: UUID(uuidString: "00000006-0000-4000-8000-000000000001")!,
        instanceID: UUID(uuidString: "00000007-0000-4000-8000-000000000001")!,
        content: "기존 draft", createdAt: date, updatedAt: date)
    context.insert(draft)
    if kind == "edited-draft" { try context.save() }
    draft.content = "외부 조회와 무관한 미저장 본문"
    draft.isPinned = true
    #expect(context.hasChanges)
    return draft
}

@MainActor
private func goalExternalPendingIDs(_ context: ModelContext) -> Set<PersistentIdentifier> {
    Set((context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray).map(\.persistentModelID))
}

private struct GoalExternalDraftValue: Equatable {
    let id: UUID
    let instanceID: UUID
    let content: String
    let pinned: Bool
    let preferredMode: String
    let createdAt: Date
    let updatedAt: Date

    init(_ memo: Memo) {
        id = memo.id
        instanceID = memo.instanceID
        content = memo.content
        pinned = memo.isPinned
        preferredMode = memo.preferredModeRawValue
        createdAt = memo.createdAt
        updatedAt = memo.updatedAt
    }
}
