import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

private typealias GoalSavedReaderTask = EasyTaskCore.Task

@Test @MainActor
func goalSavedReaderColdDirtyFallbackPreservesOtherModelChangesAndIdentity() throws {
    let fixture = try GoalSavedReaderFixture()
    let reader = ModelContext(fixture.container)
    reader.autosaveEnabled = false
    let changed = try #require(reader.model(for: fixture.memos[0].persistentModelID) as? Memo)
    let deleted = try #require(reader.model(for: fixture.memos[1].persistentModelID) as? Memo)
    changed.content = "저장하지 않은 다른 모델 편집"
    reader.delete(deleted)
    let inserted = Memo(content: "다른 모델 새 메모")
    reader.insert(inserted)
    let pending = goalSavedReaderPendingIDs(reader)
    let body = changed.content
    let expectedIDs = fixture.tasks.map(\.persistentModelID)
    let expectedValues = fixture.tasks.map(goalSavedReaderTaskValue)
    for id in expectedIDs {
        let registered: GoalSavedReaderTask? = reader.registeredModel(for: id)
        #expect(registered == nil) // Task models were never fetched in this reader.
    }
    #expect(reader.hasChanges)
    var rows: [GoalSavedReaderTask] = []
    var counts: [Int] = []
    var offset = 0
    while true {
        let page = try SavedModelPageReader.read(goalSavedReaderDescriptor(offset: offset), in: reader)
        counts.append(page.fetchedCount)
        rows += page.rows
        for row in page.rows {
            let registered: GoalSavedReaderTask? = reader.registeredModel(for: row.persistentModelID)
            #expect(registered === row)
        }
        if page.fetchedCount < 3 { break }
        offset += page.fetchedCount
    }
    #expect(counts == [3, 3, 3, 0])
    #expect(rows.map(\.persistentModelID) == expectedIDs)
    #expect(rows.map(goalSavedReaderTaskValue) == expectedValues)
    #expect(Set(rows.map(\.persistentModelID)).count == 9)
    #expect(goalSavedReaderPendingIDs(reader) == pending)
    #expect(changed.content == body && inserted.content == "다른 모델 새 메모")
    #expect(reader.hasChanges)
    let verification = ModelContext(fixture.container)
    verification.autosaveEnabled = false
    #expect(try verification.fetchCount(FetchDescriptor<Memo>()) == 2)
    #expect(try verification.fetch(FetchDescriptor<Memo>()).first { $0.id == changed.id }?.content == "Saved memo 0")
}

@Test @MainActor
func goalSavedReaderExcludedAndDeletedEmptyPagePreservesSavedOffset() throws {
    let fixture = try GoalSavedReaderFixture()
    let context = fixture.context
    fixture.tasks[0].title = "Pending title"
    fixture.tasks[0].status = TaskStatus.todo.rawValue
    fixture.tasks[0].completedAt = nil
    fixture.tasks[1].supersededAt = fixture.date
    context.delete(fixture.tasks[2])
    let inserted = GoalSavedReaderTask(id: goalSavedReaderID(1, 9), instanceID: goalSavedReaderID(2, 9),
        title: "Pending insertion", status: .done, plannedAt: fixture.date, order: 9)
    inserted.completedAt = fixture.date
    context.insert(inserted)
    let excluded = Set([fixture.tasks[0].persistentModelID, fixture.tasks[1].persistentModelID,
                        inserted.persistentModelID]) // Helper itself excludes the deleted Task.
    let pending = goalSavedReaderPendingIDs(context)
    let editedValues = [fixture.tasks[0], fixture.tasks[1], inserted].map(goalSavedReaderTaskValue)
    var rows: [GoalSavedReaderTask] = []
    var counts: [Int] = []
    var offset = 0
    while true {
        let page = try SavedModelPageReader.read(goalSavedReaderDescriptor(offset: offset),
            in: context, excluding: excluded)
        counts.append(page.fetchedCount)
        if offset == 0 { #expect(page.rows.isEmpty && page.fetchedCount == 3) }
        rows += page.rows
        if page.fetchedCount < 3 { break }
        offset += page.fetchedCount
    }
    #expect(counts == [3, 3, 3, 0])
    #expect(rows.map(\.persistentModelID) == fixture.tasks.dropFirst(3).map(\.persistentModelID))
    for (row, original) in zip(rows, fixture.tasks.dropFirst(3)) { #expect(row === original) }
    #expect(goalSavedReaderPendingIDs(context) == pending)
    #expect([fixture.tasks[0], fixture.tasks[1], inserted].map(goalSavedReaderTaskValue) == editedValues)
    #expect(context.hasChanges)
}

@Test @MainActor
func goalSavedReaderRechecksCleanThenDirtyOnNextPage() throws {
    let fixture = try GoalSavedReaderFixture()
    let context = fixture.context
    #expect(!context.hasChanges)
    let first = try SavedModelPageReader.read(goalSavedReaderDescriptor(offset: 0), in: context)
    #expect(first.rows.map(\.persistentModelID) == fixture.tasks.prefix(3).map(\.persistentModelID))
    #expect(first.fetchedCount == 3 && !context.hasChanges)
    fixture.tasks[0].title = "첫 페이지 이후 미저장 편집"
    fixture.tasks[7].supersededAt = fixture.date
    context.delete(fixture.tasks[8])
    let pending = goalSavedReaderPendingIDs(context)
    let excluded = Set([fixture.tasks[0].persistentModelID, fixture.tasks[7].persistentModelID])
    let edited = [fixture.tasks[0], fixture.tasks[7]].map(goalSavedReaderTaskValue)
    let second = try SavedModelPageReader.read(goalSavedReaderDescriptor(offset: 3), in: context, excluding: excluded)
    let third = try SavedModelPageReader.read(goalSavedReaderDescriptor(offset: 6), in: context, excluding: excluded)
    let eof = try SavedModelPageReader.read(goalSavedReaderDescriptor(offset: 9), in: context, excluding: excluded)
    let savedCounts: [Int] = [second.fetchedCount, third.fetchedCount, eof.fetchedCount]
    #expect(savedCounts == [3, 3, 0])
    #expect(third.rows.map(\.persistentModelID) == [fixture.tasks[6].persistentModelID])
    let all = first.rows + second.rows + third.rows
    #expect(all.map(\.persistentModelID) == fixture.tasks.prefix(7).map(\.persistentModelID))
    for (row, original) in zip(all, fixture.tasks.prefix(7)) { #expect(row === original) }
    #expect([fixture.tasks[0], fixture.tasks[7]].map(goalSavedReaderTaskValue) == edited)
    #expect(goalSavedReaderPendingIDs(context) == pending && context.hasChanges)
}

@MainActor
private struct GoalSavedReaderFixture {
    let container: ModelContainer
    let context: ModelContext
    let tasks: [GoalSavedReaderTask]
    let memos: [Memo]
    let date: Date

    init() throws {
        let reference = Date(timeIntervalSince1970: 1_791_241_200)
        date = reference
        container = try PlanBaseContainerFactory.makeInMemory()
        context = container.mainContext
        context.autosaveEnabled = false
        tasks = (0..<9).map { index in
            let task = GoalSavedReaderTask(id: goalSavedReaderID(1, index), instanceID: goalSavedReaderID(2, index),
                title: "Saved \(index)", status: .done, plannedAt: reference, order: Double(index),
                createdAt: reference, updatedAt: reference.addingTimeInterval(Double(index)))
            task.completedAt = reference.addingTimeInterval(Double(index))
            task.completedDayKey = TaskActivityRules.legacyDayKey(for: task.completedAt!)
            return task
        }
        memos = (0..<2).map { index in
            Memo(id: goalSavedReaderID(3, index), instanceID: goalSavedReaderID(4, index),
                content: "Saved memo \(index)", createdAt: reference, updatedAt: reference)
        }
        for task in tasks.reversed() { context.insert(task) }
        for memo in memos { context.insert(memo) }
        try context.save()
    }
}

private func goalSavedReaderDescriptor(offset: Int) -> FetchDescriptor<GoalSavedReaderTask> {
    let done = TaskStatus.done.rawValue
    var descriptor = FetchDescriptor<GoalSavedReaderTask>(predicate: #Predicate {
        $0.status == done && $0.supersededAt == nil && $0.completedAt != nil
    }, sortBy: [SortDescriptor(\GoalSavedReaderTask.instanceID)])
    descriptor.fetchOffset = offset
    descriptor.fetchLimit = 3
    descriptor.includePendingChanges = false
    return descriptor
}

private struct GoalSavedReaderPendingIDs: Equatable {
    let inserted: Set<PersistentIdentifier>
    let changed: Set<PersistentIdentifier>
    let deleted: Set<PersistentIdentifier>
}

@MainActor
private func goalSavedReaderPendingIDs(_ context: ModelContext) -> GoalSavedReaderPendingIDs {
    GoalSavedReaderPendingIDs(inserted: Set(context.insertedModelsArray.map(\.persistentModelID)),
        changed: Set(context.changedModelsArray.map(\.persistentModelID)),
        deleted: Set(context.deletedModelsArray.map(\.persistentModelID)))
}

private func goalSavedReaderTaskValue(_ task: GoalSavedReaderTask) -> String {
    [task.id.uuidString, task.instanceID.uuidString, task.title, task.status,
     task.plannedDayKey, String(task.plannedAt.timeIntervalSinceReferenceDate), String(task.order),
     task.completedDayKey ?? "nil", task.completedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "nil",
     String(task.createdAt.timeIntervalSinceReferenceDate), String(task.updatedAt.timeIntervalSinceReferenceDate),
     task.supersededAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "nil"].joined(separator: "|")
}

private func goalSavedReaderID(_ namespace: Int, _ index: Int) -> UUID {
    UUID(uuidString: String(format: "60000000-0000-0000-%04X-%012X", namespace, index + 1))!
}
