import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

enum GoalTaskRecordInterleaveMutation: String, CaseIterable, Sendable {
    case changedTask, superseded
}

private func goalTaskRecordInterleaveID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

// This is an actual TaskRecord scanner race probe. It uses no fake PageLoader,
// sleeps, private selector or production gate: a second MainActor task watches
// a previously unregistered first-page model, then edits the registered saved
// row on page two at the scanner's existing Task.yield checkpoint.
@Test(arguments: GoalTaskRecordInterleaveMutation.allCases)
@MainActor
func goalTaskRecordRechecksSecondPageSourcePredicateAfterYield(
    mutation: GoalTaskRecordInterleaveMutation
) async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let writer = container.mainContext
    writer.autosaveEnabled = false
    let day = try #require(DayKey.date(from: "2026-10-02"))
    let base = day.addingTimeInterval(12 * 3600)
    let taskID = goalTaskRecordInterleaveID(1)
    let otherTaskID = goalTaskRecordInterleaveID(2)
    let task = EasyTaskCore.Task(id: taskID, instanceID: goalTaskRecordInterleaveID(10),
                                 title: "페이지 경계 기록", plannedAt: day, order: 0,
                                 createdAt: base, updatedAt: base)
    writer.insert(task)
    var activities: [TaskCompletionActivity] = []
    for index in 0..<257 {
        let activity = TaskCompletionActivity(
            id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: DayKey.key(for: day)),
            instanceID: goalTaskRecordInterleaveID(1000 + index), taskId: taskID,
            activityDayKey: DayKey.key(for: day),
            occurredAt: base.addingTimeInterval(index == 256 ? 600 : 60), origin: .captured,
            createdAt: base, updatedAt: base.addingTimeInterval(TimeInterval(index)))
        writer.insert(activity)
        activities.append(activity)
    }
    try writer.save()

    // A fresh loader context lets registeredModel report when the scanner has
    // reached its first real activity page. Only the second-page target is read
    // beforehand, making the pending edit an existing SAVED registered model.
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let targetInstance = try #require(activities.last).instanceID
    let target = try #require(context.fetch(FetchDescriptor<TaskCompletionActivity>(
        predicate: #Predicate { $0.instanceID == targetInstance })).first)
    let firstID = activities[0].persistentModelID
    let initiallyRegistered: TaskCompletionActivity? = context.registeredModel(for: firstID)
    #expect(initiallyRegistered == nil)
    #expect(!context.hasChanges)

    var finished = false
    var mutatedDuringYield = false
    let read = Swift.Task { @MainActor in
        defer { finished = true }
        return try await TaskRecordQueryService.load(
            selection: TaskRecordSelection(taskID: taskID, dayKey: DayKey.key(for: day)), in: context)
    }
    let edit = Swift.Task { @MainActor in
        while !finished, !Swift.Task.isCancelled {
            let first: TaskCompletionActivity? = context.registeredModel(for: firstID)
            if first != nil {
                switch mutation {
                case .changedTask:
                    target.taskId = otherTaskID
                    target.occurredAt = base.addingTimeInterval(240)
                case .superseded:
                    target.supersededAt = base.addingTimeInterval(2000)
                }
                target.updatedAt = base.addingTimeInterval(2000)
                mutatedDuringYield = true
                return
            }
            await Swift.Task.yield()
        }
    }
    defer { read.cancel(); edit.cancel() }
    let record = try await read.value
    await edit.value
    // A scheduler that never ran the mutation at a scanner yield cannot supply
    // product-race evidence. Keep that prerequisite separate from the assertions.
    try #require(mutatedDuringYield, "실제 첫 페이지 yield에서 변경하지 못했으므로 race 증거가 없습니다")
    switch mutation {
    case .changedTask:
        #expect(target.taskId == otherTaskID)
        #expect(target.occurredAt == base.addingTimeInterval(240))
    case .superseded:
        #expect(target.supersededAt == base.addingTimeInterval(2000))
    }
    #expect(target.updatedAt == base.addingTimeInterval(2000))
    #expect(context.hasChanges)
    #expect(record.latestCompletedAt == base.addingTimeInterval(60),
            "A 기록에는 다른 작업으로 옮기거나 superseded된 두 번째 페이지 행을 넣을 수 없습니다")
}
