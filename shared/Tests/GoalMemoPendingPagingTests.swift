import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test(arguments: ["body", "order", "pin-moves", "insert", "delete", "superseded",
                  "same-logical", "physical-change", "ties", "excluded-full-batch", "mixed"]) @MainActor
func goalMemoPendingMergedAllPagesMatchValueOracle(kind: String) throws {
    let fixture = try GoalMemoPendingPagingFixture(count: 245, pins: 73, equalDates: kind == "ties")
    let rows = fixture.parents
    switch kind {
    case "body": rows[3].content += "\n두 번째 미저장 값"
    case "order":
        rows[160].updatedAt = fixture.reference.addingTimeInterval(20)
        rows[161].updatedAt = rows[160].updatedAt
        rows[161].createdAt = fixture.reference.addingTimeInterval(10)
    case "pin-moves": rows[3].isPinned = false; rows[160].isPinned = true
    case "insert":
        fixture.insertParent(index: 300, pinned: true)
        fixture.insertParent(index: 301, pinned: false)
    case "delete": fixture.deleteParent(rows[3]); fixture.deleteParent(rows[160])
    case "superseded": rows[3].supersededAt = fixture.reference; rows[160].supersededAt = fixture.reference
    case "same-logical": fixture.insertParent(index: 300, pinned: rows[3].isPinned, logicalID: rows[3].id)
    case "physical-change": rows[3].instanceID = goalMemoPendingPagingID(2, 500); rows[160].instanceID = goalMemoPendingPagingID(2, 501)
    case "ties": rows[3].content += "\n동일 날짜"; rows[160].content += "\n동일 날짜"
    case "excluded-full-batch":
        // A saved batch can contain zero retained rows but still be far from raw EOF.
        for row in rows.prefix(180) { row.content += "\n미저장" }
    default:
        rows[3].isPinned = false
        rows[160].isPinned = true
        rows[160].updatedAt = fixture.reference.addingTimeInterval(20)
        rows[161].createdAt = fixture.reference.addingTimeInterval(40)
        rows[161].updatedAt = rows[160].updatedAt
        rows[162].supersededAt = fixture.reference
        fixture.deleteParent(rows[4])
        fixture.deleteParent(rows[163])
        fixture.insertParent(index: 300, pinned: true)
        fixture.insertParent(index: 301, pinned: false)
    }
    #expect(fixture.context.hasChanges)
    // Two fixed-version passes, including misses: no current draft is saved or flushed.
    try goalMemoPendingPagingExpectAllPages(fixture, query: "")
    try goalMemoPendingPagingExpectAllPages(fixture, query: "선택 표식")
}

@Test(arguments: ["insert", "change", "move", "delete", "superseded",
                  "drawing-move", "drawing-insert", "drawing-delete"]) @MainActor
func goalMemoPendingChildrenAndDrawingMetadataMatchValueOracle(kind: String) throws {
    let fixture = try GoalMemoPendingPagingFixture(count: 130, pins: 13)
    let item = MemoChecklistItem(memoId: fixture.parents[3].id, title: "자식만 표식", order: 100)
    fixture.children.append(item)
    fixture.context.insert(item)
    let drawing = MemoDrawing(memoId: fixture.parents[3].id, drawingData: Data([1, 2, 3]),
                              createdAt: fixture.reference, updatedAt: fixture.reference)
    fixture.drawings.append(drawing)
    fixture.context.insert(drawing)
    try fixture.context.save()
    switch kind {
    case "insert":
        let inserted = MemoChecklistItem(memoId: fixture.parents[102].id, title: "자식만 표식 새 항목", order: 50)
        fixture.children.append(inserted)
        fixture.context.insert(inserted)
    case "change": item.title += " 최신 내용"; item.order = 50; item.isCompleted = true
    case "move": item.memoId = fixture.parents[102].id
    case "delete": fixture.deletedChildren.insert(item.persistentModelID); fixture.context.delete(item)
    case "superseded": item.supersededAt = fixture.reference
    case "drawing-move": drawing.memoId = fixture.parents[102].id; drawing.updatedAt = fixture.reference.addingTimeInterval(30)
    case "drawing-insert":
        let inserted = MemoDrawing(memoId: fixture.parents[102].id, drawingData: Data([4, 5]),
                                  createdAt: fixture.reference, updatedAt: fixture.reference.addingTimeInterval(40))
        fixture.drawings.append(inserted)
        fixture.context.insert(inserted)
    default: fixture.deletedDrawings.insert(drawing.persistentModelID); fixture.context.delete(drawing)
    }
    #expect(fixture.context.changedModelsArray.compactMap { $0 as? Memo }.isEmpty)
    try goalMemoPendingPagingExpectAllPages(fixture, query: "")
    try goalMemoPendingPagingExpectAllPages(fixture, query: "자식만 표식")
}

@Test @MainActor
func goalMemoPendingChecklistOrderPreservesCrossLineSearch() throws {
    let fixture = try GoalMemoPendingPagingFixture(count: 110, pins: 0)
    let parent = fixture.parents[103]
    let first = MemoChecklistItem(memoId: parent.id, title: "앞 순서", order: 200)
    let last = MemoChecklistItem(memoId: parent.id, title: "뒤 순서", order: 300)
    fixture.children += [last, first]
    fixture.context.insert(last)
    fixture.context.insert(first)
    try fixture.context.save()
    let pending = MemoChecklistItem(memoId: parent.id, title: "새 앞", order: 100)
    fixture.children.append(pending)
    fixture.context.insert(pending)
    try goalMemoPendingPagingExpectAllPages(fixture, query: "새 앞\n앞 순서")
    let page = try MemoService.page(in: fixture.context, query: "새 앞\n앞 순서")
    #expect(page.memos.count == 1 && page.memos.first === parent)
}

@Test @MainActor
func goalMemoDirtyDrawingMetadataPreservesOriginalCanvasAndIdentity() throws {
    let fixture = try GoalMemoPendingPagingFixture(count: 130, pins: 13)
    let savedBytes = Data(repeating: 0x41, count: 256 * 1_024)
    let pendingBytes = Data(repeating: 0x42, count: 384 * 1_024)
    let dirty = MemoDrawing(memoId: fixture.parents[3].id, drawingData: savedBytes,
                            createdAt: fixture.reference, updatedAt: fixture.reference)
    let clean = MemoDrawing(memoId: fixture.parents[102].id, drawingData: savedBytes,
                            createdAt: fixture.reference, updatedAt: fixture.reference)
    fixture.drawings += [dirty, clean]
    fixture.context.insert(dirty)
    fixture.context.insert(clean)
    try fixture.context.save()
    dirty.drawingData = pendingBytes
    dirty.updatedAt = fixture.reference.addingTimeInterval(70)
    fixture.parents[3].content += "\n미저장 본문"
    try goalMemoPendingPagingExpectAllPages(fixture, query: "")
    let registeredDirty: MemoDrawing? = fixture.context.registeredModel(for: dirty.persistentModelID)
    let registeredClean: MemoDrawing? = fixture.context.registeredModel(for: clean.persistentModelID)
    #expect(registeredDirty === dirty && registeredClean === clean)
    // Test-only byte checks are outside production's metadata lookup.
    #expect(dirty.drawingData == pendingBytes && clean.drawingData == savedBytes)
    #expect(dirty.updatedAt == fixture.reference.addingTimeInterval(70))
    #expect(fixture.context.hasChanges)
}

@MainActor
private final class GoalMemoPendingPagingFixture {
    let container: ModelContainer
    let context: ModelContext
    let reference = Date(timeIntervalSince1970: 1_790_899_200)
    var parents: [Memo] = []
    var children: [MemoChecklistItem] = []
    var drawings: [MemoDrawing] = []
    var deletedParents: Set<PersistentIdentifier> = []
    var deletedChildren: Set<PersistentIdentifier> = []
    var deletedDrawings: Set<PersistentIdentifier> = []

    init(count: Int, pins: Int, equalDates: Bool = false) throws {
        let container = try PlanBaseContainerFactory.makeInMemory()
        self.container = container
        let context = container.mainContext
        self.context = context
        context.autosaveEnabled = false
        for index in 0..<count {
            let row = Memo(id: goalMemoPendingPagingID(1, count - index),
                instanceID: goalMemoPendingPagingID(2, index),
                content: "본문 \(index)" + (index.isMultiple(of: 3) ? "\n선택 표식" : ""),
                isPinned: index < pins, createdAt: equalDates ? reference : reference.addingTimeInterval(-Double(2 * count + index)),
                updatedAt: equalDates ? reference : reference.addingTimeInterval(-Double(index)))
            parents.append(row)
        }
        for row in parents.reversed() { context.insert(row) }
        try context.save()
    }

    func insertParent(index: Int, pinned: Bool, logicalID: UUID? = nil) {
        let row = Memo(id: logicalID ?? goalMemoPendingPagingID(1, index),
            instanceID: goalMemoPendingPagingID(2, index), content: "미저장 \(index)\n선택 표식",
            isPinned: pinned, createdAt: reference, updatedAt: reference.addingTimeInterval(10))
        parents.append(row)
        context.insert(row)
    }

    func deleteParent(_ parent: Memo) {
        deletedParents.insert(parent.persistentModelID)
        context.delete(parent)
    }
}

/// Oracle uses the fixture's explicit current values, never a descriptor or MemoService page.
/// Page size/cursor describe rows inspected in pins-first updated/created/physical order.
@MainActor
private func goalMemoPendingPagingExpectAllPages(_ fixture: GoalMemoPendingPagingFixture, query: String) throws {
    let context = fixture.context
    let pendingBefore = Set((context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray).map(\.persistentModelID))
    let ordered = fixture.parents.filter {
        !fixture.deletedParents.contains($0.persistentModelID) && $0.supersededAt == nil
    }.sorted {
        if $0.isPinned != $1.isPinned { return $0.isPinned }
        if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
        if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
        return $0.instanceID.uuidString < $1.instanceID.uuidString
    }
    var expectedMatches: [Bool] = []
    var expectedSummaries: [MemoListSummary] = []
    let expectedBodies = ordered.map(\.content)
    let expectedPhysicalIDs = ordered.map(\.instanceID)
    let expectedUpdatedDates = ordered.map(\.updatedAt)
    let expectedCreatedDates = ordered.map(\.createdAt)
    let expectedPins = ordered.map(\.isPinned)
    for row in ordered {
        let children = fixture.children.filter {
            !fixture.deletedChildren.contains($0.persistentModelID) && $0.supersededAt == nil && $0.memoId == row.id
        }.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.instanceID.uuidString < $1.instanceID.uuidString
        }
        expectedMatches.append(MemoRules.matches(row, checklistTitles: children.map(\.title), query: query))
        let drawingDates = fixture.drawings.filter {
            !fixture.deletedDrawings.contains($0.persistentModelID) && $0.supersededAt == nil && $0.memoId == row.id
        }.map(\.updatedAt)
        expectedSummaries.append(MemoListSummary(content: row.content, preferred: MemoRules.mode(for: row),
            checklist: children.map(MemoChecklistDraft.init(item:)), drawingUpdatedAt: drawingDates.max()))
    }
    let pins = ordered.filter(\.isPinned).count
    var position = 0
    var cursor: MemoQueryCursor?
    var seen: Set<UUID> = []
    var pageNumber = 0
    repeat {
        var indices: [Int] = []
        while position < ordered.count && indices.count < MemoService.pageSize {
            if expectedMatches[position] { indices.append(position) }
            position += 1
        }
        let expectedCursor: MemoQueryCursor? = indices.count == MemoService.pageSize
            ? MemoQueryCursor(scansPinned: position <= pins,
                              pinnedOffset: min(position, pins), regularOffset: max(0, position - pins)) : nil
        let page = try MemoService.page(in: context, query: query, cursor: cursor)
        #expect(page.memos.map(\.instanceID) == indices.map { expectedPhysicalIDs[$0] })
        #expect(page.nextCursor == expectedCursor)
        #expect(page.hasMore == (expectedCursor != nil))
        #expect(Set(page.summaries.keys) == Set(indices.map { expectedPhysicalIDs[$0] }))
        for (row, index) in zip(page.memos, indices) {
            #expect(row === ordered[index])
            #expect(seen.insert(row.instanceID).inserted)
            let actual = try #require(page.summaries[row.instanceID])
            let expected = expectedSummaries[index]
            #expect(actual.title == expected.title && actual.preview == expected.preview)
            #expect(actual.mode == expected.mode && actual.isComposite == expected.isComposite)
            #expect(actual.drawingUpdatedAt == expected.drawingUpdatedAt)
        }
        cursor = page.nextCursor
        pageNumber += 1
        #expect(pageNumber <= 20)
    } while cursor != nil && pageNumber <= 20
    #expect(seen == Set(ordered.indices.filter { expectedMatches[$0] }.map { expectedPhysicalIDs[$0] }))
    #expect(ordered.map(\.content) == expectedBodies)
    #expect(ordered.map(\.instanceID) == expectedPhysicalIDs)
    #expect(ordered.map(\.updatedAt) == expectedUpdatedDates)
    #expect(ordered.map(\.createdAt) == expectedCreatedDates)
    #expect(ordered.map(\.isPinned) == expectedPins)
    #expect(Set((context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray).map(\.persistentModelID)) == pendingBefore)
    #expect(context.hasChanges)
}

private func goalMemoPendingPagingID(_ namespace: Int, _ index: Int) -> UUID {
    let suffix = String(format: "%012x", index)
    return UUID(uuidString: "0000000\(namespace)-0000-4000-8000-\(suffix)")!
}
