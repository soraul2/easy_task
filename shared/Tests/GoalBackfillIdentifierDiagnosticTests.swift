import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Unmeasured SDK control, separate from production safety regressions. A pass
/// would justify evaluating an identifier-only reader; production still uses
/// the independently isolated ModelContext until that evaluation is complete.
@Test @MainActor
func goalBackfillSavedIdentifiersAndRegisteredLookupPreserveDirtyFields() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let date = Date(timeIntervalSince1970: 1_791_241_200)
    let tasks = (0..<5).map { index in
        let task = Task(id: goalIdentifierID(1, index), instanceID: goalIdentifierID(2, index),
            title: "Saved \(index)", status: .done, plannedAt: date, order: Double(index),
            createdAt: date, updatedAt: date)
        task.completedAt = date.addingTimeInterval(Double(index) * 60)
        task.completedDayKey = "2026-10-01"
        context.insert(task)
        return task
    }
    let day = TaskActivityRules.legacyDayKey(for: date)
    let activity = TaskCompletionActivity(id: TaskActivityRules.logicalID(taskID: tasks[0].id, activityDayKey: day),
        instanceID: goalIdentifierID(3, 0), taskId: tasks[0].id, activityDayKey: day,
        occurredAt: date, origin: .captured, createdAt: date, updatedAt: date)
    context.insert(activity)
    try context.save()
    let savedIDs = Set(tasks.map(\.persistentModelID))

    tasks[0].completedAt = date.addingTimeInterval(86_400)
    tasks[0].title = "Pending completion"
    tasks[1].status = TaskStatus.todo.rawValue
    tasks[1].completedAt = nil
    tasks[2].supersededAt = date.addingTimeInterval(86_400)
    context.delete(tasks[3])
    activity.activityDayKey = TaskActivityRules.legacyDayKey(for: date.addingTimeInterval(86_400))
    let inserted = Task(id: goalIdentifierID(1, 5), instanceID: goalIdentifierID(2, 5),
        title: "Pending insertion", status: .done, plannedAt: date, order: 5)
    inserted.completedAt = date
    context.insert(inserted)
    let pendingIDs = Set((context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray)
        .compactMap { ($0 as? Task)?.persistentModelID })
    let fieldsBefore = (tasks + [inserted]).filter { !$0.isDeleted }.map(goalIdentifierTaskValue)
    let activityBefore = goalIdentifierActivityValue(activity)
    let changedBefore = Set(context.changedModelsArray.map(\.persistentModelID))
    let insertedBefore = Set(context.insertedModelsArray.map(\.persistentModelID))
    let deletedBefore = Set(context.deletedModelsArray.map(\.persistentModelID))
    let done = TaskStatus.done.rawValue
    var descriptor = FetchDescriptor<Task>(predicate: #Predicate {
        $0.status == done && $0.supersededAt == nil && $0.completedAt != nil
    }, sortBy: [SortDescriptor(\Task.instanceID)])
    descriptor.fetchLimit = TaskActivityBackfillService.batchSize
    descriptor.fetchOffset = 0
    descriptor.includePendingChanges = false

    let identifiers = try context.fetchIdentifiers(descriptor)
    #expect(Set(identifiers) == savedIDs)
    #expect((tasks + [inserted]).filter { !$0.isDeleted }.map(goalIdentifierTaskValue) == fieldsBefore)
    #expect(goalIdentifierActivityValue(activity) == activityBefore)
    #expect(Set(context.changedModelsArray.map(\.persistentModelID)) == changedBefore)
    #expect(Set(context.insertedModelsArray.map(\.persistentModelID)) == insertedBefore)
    #expect(Set(context.deletedModelsArray.map(\.persistentModelID)) == deletedBefore)

    let eligibleIdentifiers = identifiers.filter { !pendingIDs.contains($0) }
    #expect(eligibleIdentifiers == [tasks[4].persistentModelID])
    let registered: Task? = context.registeredModel(for: try #require(eligibleIdentifiers.first))
    #expect(registered === tasks[4])
    #expect((tasks + [inserted]).filter { !$0.isDeleted }.map(goalIdentifierTaskValue) == fieldsBefore)
    #expect(goalIdentifierActivityValue(activity) == activityBefore)
    #expect(Set(context.changedModelsArray.map(\.persistentModelID)) == changedBefore)
    #expect(Set(context.insertedModelsArray.map(\.persistentModelID)) == insertedBefore)
    #expect(Set(context.deletedModelsArray.map(\.persistentModelID)) == deletedBefore)
    #expect(context.hasChanges)
}

private func goalIdentifierTaskValue(_ task: Task) -> String {
    [task.id.uuidString, task.instanceID.uuidString, task.title, task.status,
     goalIdentifierDate(task.completedAt), task.completedDayKey ?? "nil", goalIdentifierDate(task.supersededAt),
     goalIdentifierDate(task.updatedAt)].joined(separator: "|")
}

private func goalIdentifierActivityValue(_ activity: TaskCompletionActivity) -> String {
    [activity.id.uuidString, activity.instanceID.uuidString, activity.taskId.uuidString,
     activity.activityDayKey, goalIdentifierDate(activity.occurredAt), activity.originRawValue,
     goalIdentifierDate(activity.createdAt), goalIdentifierDate(activity.updatedAt),
     goalIdentifierDate(activity.supersededAt)].joined(separator: "|")
}

private func goalIdentifierDate(_ date: Date?) -> String { date.map { String($0.timeIntervalSince1970) } ?? "nil" }

private func goalIdentifierID(_ namespace: Int, _ index: Int) -> UUID {
    UUID(uuidString: String(format: "50000000-0000-0000-%04X-%012X", namespace, index + 1))!
}
