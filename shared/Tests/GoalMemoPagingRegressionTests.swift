import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func goalMemoSparseSearchCrossesOldAndNewBatchBoundaries() throws {
    let matched = Set([99, 100, 511, 512, 519, 619, 620, 1_031, 1_032, 1_543, 1_544, 1_619])
    let longBody = String(repeating: "내용 👨‍👩‍👧‍👦 · 감사 · 검토\n", count: 120)
    let store = try goalMemoPagingStore(count: 1_620, pinnedCount: 520) { index in
        "제목 \(index)\n" + (matched.contains(index) ? longBody : "다른 본문 👨‍👩‍👧‍👦\n")
            + (matched.contains(index) && index != 1_619 ? "끝의 Ｃａｆｅ\u{301} 표식" : "")
    }
    let checklistTarget = store.memos[1_619]
    store.context.insert(MemoChecklistItem(
        memoId: checklistTarget.id, title: "Ｃａｆｅ\u{301} 표식", order: 100
    ))
    try store.context.save()
    #expect(!MemoRules.matches(checklistTarget, query: "CAFE 표식"))

    let page = try MemoService.page(in: store.context, query: "CAFE 표식")
    #expect(page.memos.map(\.instanceID) == matched.sorted().map { store.memos[$0].instanceID })
    #expect(!page.hasMore)
    #expect(page.nextCursor == nil)
    #expect(Set(page.summaries.keys) == Set(page.memos.map(\.instanceID)))
    #expect(page.summaries[checklistTarget.instanceID]?.isComposite == true)
}

@Test @MainActor
func goalMemoAllPagesPreservePinnedTransitionAndConsumedOffsets() throws {
    let store = try goalMemoPagingStore(count: 1_400, pinnedCount: 205)
    var cursor: MemoQueryCursor?
    var rows: [UUID] = []
    var pageCount = 0
    repeat {
        let page = try MemoService.page(in: store.context, query: "공통 표식", cursor: cursor)
        pageCount += 1
        #expect(page.memos.count <= MemoService.pageSize)
        #expect(Set(page.summaries.keys) == Set(page.memos.map(\.instanceID)))
        rows += page.memos.map(\.instanceID)
        cursor = page.nextCursor
        if let cursor {
            #expect(cursor.pinnedOffset + cursor.regularOffset == rows.count)
            if rows.count < 205 {
                #expect(cursor.scansPinned)
                #expect(cursor.regularOffset == 0)
            } else {
                #expect(cursor.pinnedOffset == 205)
            }
        }
        if pageCount == 6 {
            #expect(cursor == MemoQueryCursor(scansPinned: false, pinnedOffset: 205, regularOffset: 35))
        }
        #expect(page.hasMore == (cursor != nil))
        #expect(pageCount <= 36)
    } while cursor != nil && pageCount <= 36

    #expect(rows == store.memos.map(\.instanceID))
    #expect(Set(rows).count == 1_400)
    // An exactly full final page retains hasMore until the next EOF read, as before.
    #expect(pageCount == 36)
}

@Test @MainActor
func goalMemoCursorStopsAtFortiethMatchWithinFetchedBatch() throws {
    let store = try goalMemoPagingStore(count: 700, pinnedCount: 0) { index in
        "제목 \(index)\n" + (index < 40 || index >= 511 ? "선택 표식" : "일반 본문")
    }
    let first = try MemoService.page(in: store.context, query: "선택 표식")
    #expect(first.memos.map(\.instanceID) == Array(store.memos.prefix(40)).map(\.instanceID))
    #expect(first.nextCursor == MemoQueryCursor(scansPinned: false, pinnedOffset: 0, regularOffset: 40))
    #expect(first.hasMore)

    let second = try MemoService.page(in: store.context, query: "선택 표식", cursor: first.nextCursor)
    #expect(second.memos.map(\.instanceID) == Array(store.memos[511..<551]).map(\.instanceID))
    #expect(second.nextCursor == MemoQueryCursor(scansPinned: false, pinnedOffset: 0, regularOffset: 551))
    #expect(second.hasMore)
}

@Test(arguments: [99, 100, 101, 512, 612, 613, 1_024, 1_124, 1_125]) @MainActor
func goalMemoExactScanBoundaryFindsLastMatchAndEOF(count: Int) throws {
    let store = try goalMemoPagingStore(count: count) { index in
        index == count - 1 ? "마지막 전용 표식" : "일반 내용 \(index)"
    }
    let last = try MemoService.page(in: store.context, query: "마지막 전용")
    #expect(last.memos.map(\.instanceID) == [store.memos[count - 1].instanceID])
    #expect(!last.hasMore)
    #expect(last.nextCursor == nil)
    let absent = try MemoService.page(in: store.context, query: "없는 검색어")
    #expect(absent.memos.isEmpty)
    #expect(absent.summaries.isEmpty)
    #expect(!absent.hasMore)
    #expect(absent.nextCursor == nil)
}

@Test(arguments: [0, 73, 100, 137]) @MainActor
func goalMemoSparsePagesKeepOffsetsAcrossEmptyShortAndFullPinnedPhases(pinnedCount: Int) throws {
    let regularCount = 1_230
    let regularMatches = Array(stride(from: 0, to: regularCount, by: 17))
    let matched = Set(regularMatches)
    let store = try goalMemoPagingStore(count: pinnedCount + regularCount, pinnedCount: pinnedCount) { index in
        let regularIndex = index - pinnedCount
        return index >= pinnedCount && matched.contains(regularIndex)
            ? "선택 표식 \(regularIndex)" : "일반 내용 \(index)"
    }

    let first = try MemoService.page(in: store.context, query: "선택 표식")
    #expect(first.memos.map(\.instanceID) == regularMatches.prefix(40).map {
        store.memos[pinnedCount + $0].instanceID
    })
    // Offsets represent inspected rows, including misses and pins, rather than
    // returned matches or the unused remainder of a fetched batch.
    #expect(first.nextCursor == MemoQueryCursor(
        scansPinned: false, pinnedOffset: pinnedCount, regularOffset: regularMatches[39] + 1
    ))
    #expect(first.hasMore)
    #expect(Set(first.summaries.keys) == Set(first.memos.map(\.instanceID)))

    let second = try MemoService.page(in: store.context, query: "선택 표식", cursor: first.nextCursor)
    #expect(second.memos.map(\.instanceID) == regularMatches.dropFirst(40).map {
        store.memos[pinnedCount + $0].instanceID
    })
    #expect(!second.hasMore)
    #expect(second.nextCursor == nil)
    #expect(Set(second.summaries.keys) == Set(second.memos.map(\.instanceID)))
    #expect(first.memos.count + second.memos.count == regularMatches.count)
}

@Test @MainActor
func goalMemoEqualTimestampsAndEmptyQueryKeepPhysicalIDOrder() throws {
    let store = try goalMemoPagingStore(count: 620, pinnedCount: 115, equalTimestamps: true)
    let searched = try goalMemoPagingAllIDs(context: store.context, query: "공통 표식")
    let empty = try goalMemoPagingAllIDs(context: store.context, query: "")
    let whitespace = try goalMemoPagingAllIDs(context: store.context, query: " \t\n")
    let expected = store.memos.map(\.instanceID)
    #expect(searched == expected)
    #expect(empty == expected)
    #expect(whitespace == expected)
}

@Test @MainActor
func goalMemoSearchDoesNotCountSupersededParentsOrChecklistChildren() throws {
    let store = try goalMemoPagingStore(count: 530, pinnedCount: 1) { index in "일반 내용 \(index)" }
    let childOnly = store.memos[512]
    store.context.insert(MemoChecklistItem(memoId: childOnly.id, title: "활성 자식 표식", order: 100))
    store.context.insert(MemoChecklistItem(
        memoId: store.memos[100].id, title: "활성 자식 표식", order: 100, supersededAt: Date()
    ))
    store.context.insert(Memo(
        content: "활성 자식 표식", isPinned: true, supersededAt: Date()
    ))
    try store.context.save()
    let page = try MemoService.page(in: store.context, query: "활성 자식 표식")
    #expect(page.memos.map(\.instanceID) == [childOnly.instanceID])
    #expect(!page.hasMore)
    #expect(page.nextCursor == nil)
}

@MainActor
private struct GoalMemoPagingStore {
    let container: ModelContainer
    let context: ModelContext
    /// Independent fixture order: pins first, then newest/created/physical-ID order.
    let memos: [Memo]
}

@MainActor
private func goalMemoPagingStore(
    count: Int, pinnedCount: Int = 0, equalTimestamps: Bool = false,
    content: (Int) -> String = { "제목 \($0)\n공통 표식" }
) throws -> GoalMemoPagingStore {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let reference = Date(timeIntervalSince1970: 1_790_899_200)
    let memos = (0..<count).map { index in
        let physicalIndex = index < pinnedCount ? count + index : index - pinnedCount
        let updatedOffset = index < pinnedCount ? count + index : index - pinnedCount
        // Logical IDs run in reverse so accidentally sorting by id cannot pass.
        return Memo(id: goalMemoPagingID(namespace: 1, index: count - index),
             // Regular IDs precede pinned IDs, independently of their required display order.
             instanceID: goalMemoPagingID(namespace: 2, index: physicalIndex),
             content: content(index), isPinned: index < pinnedCount,
             createdAt: equalTimestamps ? reference : reference.addingTimeInterval(-Double(2 * count + index)),
             // Every regular row is newer than every pin; pinned precedence must still win.
             updatedAt: equalTimestamps ? reference : reference.addingTimeInterval(-Double(updatedOffset)))
    }
    for memo in memos.reversed() { context.insert(memo) }
    try context.save()
    return GoalMemoPagingStore(container: container, context: context, memos: memos)
}

@MainActor
private func goalMemoPagingAllIDs(context: ModelContext, query: String) throws -> [UUID] {
    var ids: [UUID] = []
    var cursor: MemoQueryCursor?
    var pageCount = 0
    repeat {
        let page = try MemoService.page(in: context, query: query, cursor: cursor)
        ids += page.memos.map(\.instanceID)
        cursor = page.nextCursor
        #expect(page.hasMore == (cursor != nil))
        #expect(Set(page.summaries.keys) == Set(page.memos.map(\.instanceID)))
        pageCount += 1
        #expect(pageCount <= 100)
    } while cursor != nil && pageCount <= 100
    return ids
}

private func goalMemoPagingID(namespace: Int, index: Int) -> UUID {
    let suffix = String(index, radix: 16)
    let padded = String(repeating: "0", count: 12 - suffix.count) + suffix
    return UUID(uuidString: "0000000\(namespace)-0000-4000-8000-\(padded)")!
}
