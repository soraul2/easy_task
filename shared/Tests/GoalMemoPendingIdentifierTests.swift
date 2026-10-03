import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// API control only: no MemoService, cooperative reader, save, or pending flush during the read.
/// A duplicate identifier is an assertion failure rather than a summary-dictionary fatal.
@MainActor
private func goalMemoIdentifierPagingControl(includePending: Bool, nextLimit: Int, dirty: Bool) throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let reference = Date(timeIntervalSince1970: 1_790_899_200)
    let memos: [Memo] = (0..<190).map { index in
        let suffix = String(format: "%012x", index)
        return Memo(id: UUID(uuidString: "00000001-0000-4000-8000-\(suffix)")!,
            instanceID: UUID(uuidString: "00000002-0000-4000-8000-\(suffix)")!,
            content: "저장된 본문 \(index)", createdAt: reference.addingTimeInterval(-Double(index)),
            updatedAt: reference.addingTimeInterval(-Double(index)))
    }
    for memo in memos.reversed() { context.insert(memo) }
    try context.save()
    // Unique timestamps make this the full expected saved order, independent of insertion order.
    let expectedIDs = memos.map(\.persistentModelID)
    #expect(Set(expectedIDs).count == 190)
    let target = memos[3]
    let timestamp = target.updatedAt
    if dirty {
        target.content = "첫 미저장 값"
        target.content = "두번째 미저장 본문 — ID·정렬 값 동일"
    }
    let expectedBodies = memos.map(\.content)
    let pendingIDs = Set(context.changedModelsArray.map(\.persistentModelID))
    let expectedPendingIDs: Set<PersistentIdentifier> = dirty ? [target.persistentModelID] : []
    #expect(context.hasChanges == dirty)
    #expect(pendingIDs == expectedPendingIDs)

    func identifiers(pinned: Bool, offset: Int, limit: Int) throws -> [PersistentIdentifier] {
        var descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate { $0.supersededAt == nil && $0.isPinned == pinned },
            sortBy: [SortDescriptor(\Memo.updatedAt, order: .reverse),
                     SortDescriptor(\Memo.createdAt, order: .reverse), SortDescriptor(\Memo.instanceID)])
        descriptor.includePendingChanges = includePending
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try context.fetchIdentifiers(descriptor)
    }

    // Pin/body are independent: a body edit must not appear in the empty pinned phase.
    #expect(try identifiers(pinned: true, offset: 0, limit: 100).isEmpty)
    let first = try identifiers(pinned: false, offset: 0, limit: 100)
    let second = try identifiers(pinned: false, offset: 100, limit: nextLimit)
    let eof = try identifiers(pinned: false, offset: 190, limit: nextLimit)
    let all = first + second
    print("GOAL_MEMO_IDENTIFIER_CONTROL includePending=\(includePending) dirty=\(dirty) nextLimit=\(nextLimit) first=\(first.count) second=\(second.count) eof=\(eof.count) unique=\(Set(all).count) targetPositions=\(all.indices.filter { all[$0] == target.persistentModelID })")
    #expect(first == Array(expectedIDs.prefix(100)))
    #expect(second == Array(expectedIDs.dropFirst(100)))
    #expect(eof.isEmpty)
    #expect(all == expectedIDs)
    #expect(Set(all).count == all.count)
    #expect(target.content == expectedBodies[3]) // Check before registeredModel lookups too.
    #expect(Set(context.changedModelsArray.map(\.persistentModelID)) == pendingIDs)

    // Resolve in the original editing context. Every returned saved ID must retain its object.
    for id in all {
        let index = try #require(expectedIDs.firstIndex(of: id))
        let registered: Memo? = context.registeredModel(for: id)
        let memo = try #require(registered)
        #expect(memo === memos[index])
        #expect(memo.content == expectedBodies[index])
    }
    let registeredTarget: Memo? = context.registeredModel(for: target.persistentModelID)
    #expect(registeredTarget === target)
    #expect(target.content == expectedBodies[3])
    #expect(target.updatedAt == timestamp)
    #expect(context.hasChanges == dirty)
    #expect(Set(context.changedModelsArray.map(\.persistentModelID)) == pendingIDs)
    #expect(context.insertedModelsArray.isEmpty && context.deletedModelsArray.isEmpty)
    context.rollback()
}

// SwiftData may reject includePendingChanges=true for identifier sorting altogether.
// That API restriction is a characterizer, not a MemoService correctness requirement.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_MEMO_IDENTIFIER_DIAGNOSTIC"] == "1"),
      arguments: [100, 512]) @MainActor
func goalMemoPendingIdentifiersIncludedOffsetControl(nextLimit: Int) throws {
    do {
        try goalMemoIdentifierPagingControl(includePending: true, nextLimit: nextLimit, dirty: true)
    } catch {
        print("GOAL_MEMO_IDENTIFIER_API_RESTRICTION includePending=true dirty=true nextLimit=\(nextLimit) error=\(error)")
    }
}

@Test(arguments: [100, 512]) @MainActor
func goalMemoPendingIdentifiersExcludedPreservesEditingContext(nextLimit: Int) throws {
    try goalMemoIdentifierPagingControl(includePending: false, nextLimit: nextLimit, dirty: true)
}

@Test @MainActor
func goalMemoCleanIdentifiersOffsetControl() throws {
    try goalMemoIdentifierPagingControl(includePending: false, nextLimit: 100, dirty: false)
}
