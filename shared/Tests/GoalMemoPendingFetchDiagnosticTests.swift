import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

private let goalMemoPendingNeedle = "M2-PENDING-UNIQUE-NEEDLE"

@MainActor
private struct GoalMemoPendingFixture {
    let container: ModelContainer
    let context: ModelContext
    let memos: [Memo]
    let target: Memo
    let child: MemoChecklistItem?
    let kind: String

    init(kind: String) throws {
        self.kind = kind
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        context.autosaveEnabled = false
        let reference = Date(timeIntervalSince1970: 1_790_899_200)
        let rows: [Memo] = (0..<190).map { index in
            let suffix = String(format: "%012x", index)
            let content = (index == 3 && (kind == "pin" || kind == "clean"))
                ? goalMemoPendingNeedle : "항목 \(index) 공통 본문"
            return Memo(id: UUID(uuidString: "00000001-0000-4000-8000-\(suffix)")!,
                instanceID: UUID(uuidString: "00000002-0000-4000-8000-\(suffix)")!,
                content: content, createdAt: reference.addingTimeInterval(-Double(index)),
                updatedAt: reference.addingTimeInterval(-Double(index)))
        }
        for row in rows.reversed() { context.insert(row) }
        var child: MemoChecklistItem?
        if kind == "checklist" {
            let item = MemoChecklistItem(memoId: rows[3].id, title: "기존 자식", order: 100)
            context.insert(item)
            child = item
        }
        try context.save()
        var target = rows[3]
        switch kind {
        case "body":
            target.content = "첫 미저장 값"
            target.content = goalMemoPendingNeedle
        case "pin": target.isPinned = true
        case "checklist": child?.title = goalMemoPendingNeedle
        case "insert":
            let inserted = Memo(id: UUID(uuidString: "00000001-0000-4000-8000-000000000190")!,
                instanceID: UUID(uuidString: "00000002-0000-4000-8000-000000000190")!,
                content: goalMemoPendingNeedle, createdAt: reference, updatedAt: reference)
            context.insert(inserted)
            target = inserted
        default: break
        }
        self.container = container
        self.context = context
        self.memos = rows
        self.target = target
        self.child = child
    }
}

/// Ordinary product contract; this synchronous repro can run on original baseline production.
/// A trap is retained as evidence if the scanner appends the same physical memo twice.
@MainActor
private func goalMemoPendingSparseSearchContract(kind: String) throws {
    let fixture = try GoalMemoPendingFixture(kind: kind)
    #expect(Set(fixture.memos.map(\.instanceID)).count == 190)
    let pendingIDs = Set((fixture.context.insertedModelsArray + fixture.context.changedModelsArray)
        .map(\.persistentModelID))
    let timestamp = fixture.target.updatedAt
    #expect(fixture.context.hasChanges == (kind != "clean"))
    if kind == "checklist" {
        #expect(fixture.context.changedModelsArray.compactMap { $0 as? Memo }.isEmpty)
    }
    print("GOAL_MEMO_PENDING_REPRO scenario=\(kind) target=\(fixture.target.instanceID) pendingIDs=\(pendingIDs.count)")
    let page = try MemoService.page(in: fixture.context, query: goalMemoPendingNeedle)
    #expect(page.memos.count == 1)
    #expect(page.memos.first === fixture.target)
    #expect(page.summaries.count == 1 && page.summaries[fixture.target.instanceID] != nil)
    #expect(page.nextCursor == nil && !page.hasMore)
    #expect(fixture.target.updatedAt == timestamp)
    #expect(Set((fixture.context.insertedModelsArray + fixture.context.changedModelsArray)
        .map(\.persistentModelID)) == pendingIDs)
    #expect(fixture.context.hasChanges == (kind != "clean"))
    fixture.context.rollback()
}

@Test @MainActor
func goalMemoPendingSameIDBodySparseRepro() throws { try goalMemoPendingSparseSearchContract(kind: "body") }

@Test @MainActor
func goalMemoPendingPinSparseRepro() throws { try goalMemoPendingSparseSearchContract(kind: "pin") }

@Test @MainActor
func goalMemoPendingChecklistOnlySparseControl() throws { try goalMemoPendingSparseSearchContract(kind: "checklist") }

@Test @MainActor
func goalMemoPendingInsertedParentSparseRepro() throws { try goalMemoPendingSparseSearchContract(kind: "insert") }

@Test @MainActor
func goalMemoPendingCleanSparseControl() throws { try goalMemoPendingSparseSearchContract(kind: "clean") }

/// SDK characterization only: it prints physical provenance before any summary dictionary exists.
/// Repeated SDK rows are diagnostic evidence, not an expected product result or a waived assertion.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_MEMO_PENDING_DIAGNOSTIC"] == "1"),
      arguments: ["body", "pin", "checklist", "insert", "clean"]) @MainActor
func goalMemoPendingRawFetchDiagnostic(kind: String) throws {
    let fixture = try GoalMemoPendingFixture(kind: kind)
    #expect(Set(fixture.memos.map(\.instanceID)).count == 190)
    for includePending in [true, false] {
        var matched: [Memo] = []
        var inspected = 0
        var calls = 0
        for pinned in [true, false] {
            var offset = 0
            while calls < 8 {
                let limit = inspected >= 100 ? 512 : 100
                var descriptor = FetchDescriptor<Memo>(
                    predicate: #Predicate { $0.supersededAt == nil && $0.isPinned == pinned },
                    sortBy: [SortDescriptor(\Memo.updatedAt, order: .reverse),
                             SortDescriptor(\Memo.createdAt, order: .reverse), SortDescriptor(\Memo.instanceID)])
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                descriptor.includePendingChanges = includePending
                let rows = try fixture.context.fetch(descriptor)
                let sameTarget = rows.enumerated().filter { $0.element.instanceID == fixture.target.instanceID }
                let grouped = Dictionary(grouping: rows, by: \.persistentModelID)
                let duplicatePhysical = grouped.values.filter { $0.count > 1 }.map { group in
                    ["instanceID": group[0].instanceID.uuidString, "count": String(group.count),
                     "sameObject": String(group.dropFirst().allSatisfy { $0 === group[0] })]
                }
                let items = try fixture.context.fetch(MemoChecklistService.descriptor(memoIDs: rows.map(\.id)))
                let titles = Dictionary(grouping: items, by: \.memoId).mapValues { $0.map(\.title) }
                matched += rows.filter { MemoRules.matches($0, checklistTitles: titles[$0.id] ?? [], query: goalMemoPendingNeedle) }
                let record: [String: Any] = [
                    "scenario": kind, "includePending": includePending, "pinnedPhase": pinned,
                    "offset": offset, "limit": limit, "rawCount": rows.count,
                    "physicalUniqueCount": grouped.count, "withinBatchDuplicates": duplicatePhysical,
                    "targetPositions": sameTarget.map { $0.offset },
                    "targetSameObject": sameTarget.allSatisfy { $0.element === fixture.target },
                    "predicateMismatchInstanceIDs": rows.filter { $0.isPinned != pinned }.map { $0.instanceID.uuidString },
                ]
                let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                print("GOAL_MEMO_PENDING_RAW \(String(decoding: data, as: UTF8.self))")
                calls += 1
                inspected += rows.count
                offset += rows.count
                if rows.count < limit { break }
            }
        }
        let result: [String: Any] = [
            "scenario": kind, "includePending": includePending, "scans": calls,
            "matchingRows": matched.count, "matchingPhysicalUnique": Set(matched.map(\.persistentModelID)).count,
            "matchingInstanceIDs": matched.map { $0.instanceID.uuidString },
            "sameTargetObject": matched.allSatisfy { $0 === fixture.target },
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("GOAL_MEMO_PENDING_RAW_RESULT \(String(decoding: data, as: UTF8.self))")
        #expect(calls < 8)
    }
    #expect(fixture.context.hasChanges == (kind != "clean"))
    fixture.context.rollback()
}
