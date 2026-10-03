import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

enum GoalDailyActivityInterleaveMutation: String, CaseIterable, Sendable {
    case movedOutsideWindow, superseded
}

/// Actual default service/progress reader and its real 256-row activity batch yield.
/// The source is dirty before the read, so a raw activity edit does not change
/// hasChanges=false→true and masquerade as an expected progress-source invalidation.
@Test(arguments: GoalDailyActivityInterleaveMutation.allCases) @MainActor
func goalDailyActivityRechecksSecondPageWindowPredicateAfterYield(
    mutation: GoalDailyActivityInterleaveMutation
) async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let writer = container.mainContext
    writer.autosaveEnabled = false
    let day = try #require(DayKey.date(from: "2026-10-02"))
    let outsideDay = DayKey.addingDays(-1, to: day)
    let key = DayKey.key(for: day)
    let outsideKey = DayKey.key(for: outsideDay)
    let base = day.addingTimeInterval(12 * 3_600)
    var activities: [TaskCompletionActivity] = []
    for index in 0..<257 {
        let taskID = goalDailyInterleaveID(namespace: 1, index: index)
        let row = TaskCompletionActivity(id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: key),
            instanceID: goalDailyInterleaveID(namespace: 2, index: index), taskId: taskID,
            activityDayKey: key, occurredAt: base.addingTimeInterval(Double(index)),
            createdAt: base, updatedAt: base)
        activities.append(row)
        writer.insert(row)
    }
    // Exactly two fixture days. A stable outside-day sentinel is uniquely earliest;
    // activityFirst/sourceLower cannot accidentally register the watched middle row.
    let sentinelTask = goalDailyInterleaveID(namespace: 1, index: 999)
    writer.insert(TaskCompletionActivity(id: TaskActivityRules.logicalID(taskID: sentinelTask, activityDayKey: outsideKey),
        instanceID: goalDailyInterleaveID(namespace: 2, index: 999), taskId: sentinelTask,
        activityDayKey: outsideKey, occurredAt: outsideDay.addingTimeInterval(12 * 3_600),
        createdAt: base, updatedAt: base))
    try writer.save()

    let context = ModelContext(container)
    context.autosaveEnabled = false
    let targetInstance = activities[256].instanceID
    let target = try #require(context.fetch(FetchDescriptor<TaskCompletionActivity>(
        predicate: #Predicate { $0.instanceID == targetInstance })).first)
    let watchID = activities[128].persistentModelID
    let initiallyRegistered: TaskCompletionActivity? = context.registeredModel(for: watchID)
    try #require(initiallyRegistered == nil, "middle first-batch watch must start unregistered")
    let targetTaskID = target.taskId
    let expectedTaskIDs = Set(activities.prefix(256).map(\.taskId))
    let draft = Memo(content: "하루 활동 조회 중 보존할 미저장 draft", isPinned: true,
                     createdAt: base, updatedAt: base)
    context.insert(draft)
    let draftBody = draft.content
    let draftID = draft.persistentModelID
    #expect(context.hasChanges)
    #expect(context.changedModelsArray.compactMap { $0 as? TaskCompletionActivity }.isEmpty)
    #expect(context.insertedModelsArray.compactMap { $0 as? TaskProgressEvent }.isEmpty)
    let filter = ArchiveFilter(contentMode: .dailyActivity, period: .custom,
        scope: .tasks, customStartDate: day, customEndDate: day)
    let service = DailyActivityQueryService(context: context)
    var finished = false
    var mutatedDuringYield = false
    var page: ArchiveQueryPage?
    var readError: String?
    // Keep the non-Sendable page on MainActor; the Task's success value is Void.
    let read = Swift.Task { @MainActor in
        defer { finished = true }
        do { page = try await service.page(filter: filter, referenceDate: day) }
        catch { readError = String(reflecting: error) }
    }
    let edit = Swift.Task { @MainActor in
        while !finished, !Swift.Task.isCancelled {
            let middle: TaskCompletionActivity? = context.registeredModel(for: watchID)
            if middle != nil {
                switch mutation {
                case .movedOutsideWindow:
                    target.activityDayKey = outsideKey
                    target.occurredAt = outsideDay.addingTimeInterval(12 * 3_600)
                case .superseded:
                    target.supersededAt = base.addingTimeInterval(2_000)
                    target.occurredAt = base.addingTimeInterval(240)
                }
                target.updatedAt = base.addingTimeInterval(2_000)
                mutatedDuringYield = true
                return
            }
            await Swift.Task.yield()
        }
    }
    defer { read.cancel(); edit.cancel() }
    await read.value
    await edit.value
    try #require(mutatedDuringYield, "actual first 256-row activity batch yield was not observed; no race evidence")
    print("GOAL_DAILY_ACTIVITY_INTERLEAVE mutation=\(mutation.rawValue) actualYield=true readError=\(readError ?? "none")")
    switch mutation {
    case .movedOutsideWindow:
        #expect(target.activityDayKey == outsideKey)
        #expect(target.occurredAt == outsideDay.addingTimeInterval(12 * 3_600))
    case .superseded:
        #expect(target.supersededAt == base.addingTimeInterval(2_000))
        #expect(target.occurredAt == base.addingTimeInterval(240))
    }
    #expect(target.updatedAt == base.addingTimeInterval(2_000))
    #expect(context.changedModelsArray.contains { $0.persistentModelID == target.persistentModelID })
    let registeredDraft: Memo? = context.registeredModel(for: draftID)
    #expect(registeredDraft === draft)
    #expect(draft.content == draftBody && draft.isPinned)
    #expect(draft.createdAt == base && draft.updatedAt == base)
    #expect(context.insertedModelsArray.contains { $0.persistentModelID == draftID })
    #expect(context.hasChanges)
    #expect(readError == nil)
    let result = try #require(page)
    #expect(result.records.map(\.dayKey) == [key])
    let entries = result.records.flatMap { $0.activityEntries ?? [] }
    #expect(Set(entries.map(\.id)) == expectedTaskIDs)
    #expect(!entries.contains { $0.id == targetTaskID })
    #expect(entries.count == 256 && entries.allSatisfy { $0.evidence.completed })
    #expect(!result.hasMore && result.nextBeforeDayKey == nil)
    withExtendedLifetime(container) {}
}

private func goalDailyInterleaveID(namespace: Int, index: Int) -> UUID {
    UUID(uuidString: String(format: "%08x-0000-4000-8000-%012x", namespace, index))!
}
