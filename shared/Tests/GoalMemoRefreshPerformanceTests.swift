#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Measures the unchanged synchronous page/session paths; seeding and editing are untimed.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_MEMO_REFRESH_PERFORMANCE"] == "1"))
@MainActor
func goalMemoRefreshPerformance() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseGoalMemoRefresh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = try GoalMemoRefreshFixture(storeURL: directory.appendingPathComponent("memos.store"))
    let context = ModelContext(fixture.container)
    context.autosaveEnabled = false
    let selectedID = fixture.seeds[30].id // A pin in the first page, retained across all refreshes.
    var selectedDescriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == selectedID })
    selectedDescriptor.fetchLimit = 1
    let selected = try #require(context.fetch(selectedDescriptor).first)
    var savedContent = fixture.seeds[30].content
    var savedUpdatedAt = fixture.seeds[30].updatedAt
    var editSequence = 0

    for queryCase in [(name: "empty", query: ""), (name: "dense", query: "CAFE")] {
        // A first-page query control is reported separately from session refresh.
        let recorder = GoalMemoRefreshRecorder()
        let pageWarmup = try recorder.read(context, queryCase.query, nil)
        try goalMemoRefreshValidate(
            [pageWarmup], traces: recorder.traces, fixture: fixture,
            selected: selected, selectedContent: savedContent, selectedUpdatedAt: savedUpdatedAt
        )
        var pageSamples: [Double] = []
        var pageCalls: [Int] = []
        var pageDigests: [String] = []
        for _ in 0..<30 {
            recorder.reset()
            let start = DispatchTime.now().uptimeNanoseconds
            let page = try recorder.read(context, queryCase.query, nil)
            pageSamples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            pageCalls.append(recorder.calls)
            try goalMemoRefreshValidate(
                [page], traces: recorder.traces, fixture: fixture,
                selected: selected, selectedContent: savedContent, selectedUpdatedAt: savedUpdatedAt
            )
            #expect(recorder.calls == 1)
            pageDigests.append(try goalMemoRefreshDigest(pages: [page], traces: recorder.traces))
        }
        try goalMemoRefreshPrint(kind: "query-first-page", query: queryCase.name, depth: 1,
                                 samples: pageSamples, calls: pageCalls, digests: pageDigests)

        for depth in [1, 5, 10] {
            let recorder = GoalMemoRefreshRecorder()
            let session = MemoQuerySession(context: context) { context, query, cursor in
                try recorder.read(context, query, cursor)
            }
            session.apply(query: queryCase.query, debounce: false)
            for _ in 1..<depth { session.loadNextPage() }
            #expect(session.memos.count == depth * MemoService.pageSize)

            // One unmeasured refresh after an ordinary saved text edit warms this scenario.
            editSequence += 1
            savedContent = fixture.seeds[30].content + "\n작성 차례 \(editSequence)"
            savedUpdatedAt = fixture.reference.addingTimeInterval(Double(editSequence))
            _ = try MemoService.save(memo: selected, content: savedContent, now: savedUpdatedAt, in: context)
            recorder.reset()
            session.refresh()
            try goalMemoRefreshValidateSession(
                session, depth: depth, recorder: recorder, fixture: fixture,
                selected: selected, selectedContent: savedContent, selectedUpdatedAt: savedUpdatedAt
            )

            var samples: [Double] = []
            var calls: [Int] = []
            var digests: [String] = []
            for _ in 0..<30 {
                // This models the read after autosave without sleeping or timing the save itself.
                editSequence += 1
                savedContent = fixture.seeds[30].content + "\n작성 차례 \(editSequence)"
                savedUpdatedAt = fixture.reference.addingTimeInterval(Double(editSequence))
                _ = try MemoService.save(memo: selected, content: savedContent, now: savedUpdatedAt, in: context)
                recorder.reset()
                let start = DispatchTime.now().uptimeNanoseconds
                session.refresh()
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                calls.append(recorder.calls)
                try goalMemoRefreshValidateSession(
                    session, depth: depth, recorder: recorder, fixture: fixture,
                    selected: selected, selectedContent: savedContent, selectedUpdatedAt: savedUpdatedAt
                )
                digests.append(try goalMemoRefreshDigest(
                    pages: recorder.traces.map(\.page), traces: recorder.traces
                ))
            }
            try goalMemoRefreshPrint(kind: "autosave-style-refresh", query: queryCase.name, depth: depth,
                                     samples: samples, calls: calls, digests: digests)
        }
    }
    #expect(!context.hasChanges)
    withExtendedLifetime(fixture.container) {}
}

@MainActor
private final class GoalMemoRefreshRecorder {
    struct Trace {
        let inputCursor: MemoQueryCursor?
        let page: MemoQueryPage
    }
    var calls = 0
    var traces: [Trace] = []

    init() { traces.reserveCapacity(10) }

    func reset() {
        calls = 0
        traces.removeAll(keepingCapacity: true)
    }

    func read(_ context: ModelContext, _ query: String, _ cursor: MemoQueryCursor?) throws -> MemoQueryPage {
        let page = try MemoService.page(in: context, query: query, cursor: cursor)
        calls += 1
        // Retain returned values only. IDs, summaries, cursors and digests are checked after timing.
        traces.append(Trace(inputCursor: cursor, page: page))
        return page
    }
}

private struct GoalMemoRefreshSeed {
    let id: UUID
    let instanceID: UUID
    let content: String
    let isPinned: Bool
    let createdAt: Date
    let updatedAt: Date
}

@MainActor
private struct GoalMemoRefreshFixture {
    let container: ModelContainer
    let reference: Date
    let seeds: [GoalMemoRefreshSeed]

    init(storeURL: URL) throws {
        let container = try PlanBaseContainerFactory.makePersistent(storeURL: storeURL, mode: .local)
        let context = container.mainContext
        context.autosaveEnabled = false
        let reference = Date(timeIntervalSince1970: 1_790_899_200)
        let body = String(repeating: "본문 · Cafe\u{301} · ＡＢＣ · 👨‍👩‍👧‍👦 · 감사\n", count: 12)
        var seeds: [GoalMemoRefreshSeed] = []
        seeds.reserveCapacity(2_000)
        for index in 0..<2_000 {
            let seed = GoalMemoRefreshSeed(
                id: goalMemoRefreshID(namespace: 1, index: index),
                instanceID: goalMemoRefreshID(namespace: 2, index: index),
                content: "합성 메모 \(index)\nCafé 계획\n" + body,
                isPinned: index % 10 == 0,
                createdAt: reference.addingTimeInterval(-Double(2_000 + index)),
                updatedAt: reference.addingTimeInterval(-Double(index))
            )
            seeds.append(seed)
            context.insert(Memo(id: seed.id, instanceID: seed.instanceID, content: seed.content,
                isPinned: seed.isPinned, createdAt: seed.createdAt, updatedAt: seed.updatedAt))
            context.insert(MemoChecklistItem(
                id: goalMemoRefreshID(namespace: 3, index: index),
                instanceID: goalMemoRefreshID(namespace: 4, index: index), memoId: seed.id,
                title: "확인 항목 \(index) · ＡＢＣ", isCompleted: index % 3 == 0, order: 100,
                createdAt: seed.updatedAt, updatedAt: seed.updatedAt
            ))
            if index % 250 == 249 { try context.save() }
        }
        try context.save()
        self.container = container
        self.reference = reference
        self.seeds = seeds
    }

    func expectedOrder(selected: Memo, selectedUpdatedAt: Date) -> [GoalMemoRefreshSeed] {
        let selectedInstanceID = selected.instanceID
        return seeds.sorted { left, right in
            if left.isPinned != right.isPinned { return left.isPinned }
            let leftUpdated = left.instanceID == selectedInstanceID ? selectedUpdatedAt : left.updatedAt
            let rightUpdated = right.instanceID == selectedInstanceID ? selectedUpdatedAt : right.updatedAt
            if leftUpdated != rightUpdated { return leftUpdated > rightUpdated }
            if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
            return left.instanceID.uuidString < right.instanceID.uuidString
        }
    }
}

@MainActor
private func goalMemoRefreshValidateSession(
    _ session: MemoQuerySession, depth: Int, recorder: GoalMemoRefreshRecorder,
    fixture: GoalMemoRefreshFixture, selected: Memo, selectedContent: String, selectedUpdatedAt: Date
) throws {
    #expect(recorder.calls == depth)
    #expect(recorder.traces.count == depth)
    #expect(session.memos.count == depth * MemoService.pageSize)
    #expect(session.hasMore)
    #expect(!session.isLoading)
    #expect(session.errorMessage == nil)
    #expect(Set(session.summaries.keys) == Set(session.memos.map(\.instanceID)))
    #expect(session.memos.first { $0.instanceID == selected.instanceID } === selected)
    #expect(session.memos.map(\.instanceID) == recorder.traces.flatMap { $0.page.memos.map(\.instanceID) })
    try goalMemoRefreshValidate(
        recorder.traces.map(\.page), traces: recorder.traces, fixture: fixture,
        selected: selected, selectedContent: selectedContent, selectedUpdatedAt: selectedUpdatedAt
    )
}

@MainActor
private func goalMemoRefreshValidate(
    _ pages: [MemoQueryPage], traces: [GoalMemoRefreshRecorder.Trace], fixture: GoalMemoRefreshFixture,
    selected: Memo, selectedContent: String, selectedUpdatedAt: Date
) throws {
    let expected = fixture.expectedOrder(selected: selected, selectedUpdatedAt: selectedUpdatedAt)
    #expect(pages.count == traces.count)
    let pinCount = fixture.seeds.filter(\.isPinned).count
    var previousCursor: MemoQueryCursor?
    for (pageIndex, page) in pages.enumerated() {
        let lower = pageIndex * MemoService.pageSize
        let upper = lower + MemoService.pageSize
        let expectedIDs = expected[lower..<upper].map(\.instanceID)
        #expect(page.memos.map(\.instanceID) == expectedIDs)
        #expect(Set(page.summaries.keys) == Set(expectedIDs))
        #expect(page.hasMore)
        let expectedCursor = MemoQueryCursor(
            scansPinned: upper <= pinCount, pinnedOffset: min(upper, pinCount),
            regularOffset: max(upper - pinCount, 0)
        )
        #expect(traces[pageIndex].inputCursor == previousCursor)
        #expect(page.nextCursor == expectedCursor)
        previousCursor = expectedCursor
        for (position, memo) in page.memos.enumerated() {
            let seed = expected[lower + position]
            let isSelected = memo.instanceID == selected.instanceID
            #expect(memo.content == (isSelected ? selectedContent : seed.content))
            #expect(memo.updatedAt == (isSelected ? selectedUpdatedAt : seed.updatedAt))
            #expect(memo.id == seed.id)
            #expect(memo.isPinned == seed.isPinned)
            if isSelected { #expect(memo === selected) }
            let summary = try #require(page.summaries[memo.instanceID])
            #expect(summary.isComposite)
            #expect(summary.drawingUpdatedAt == nil)
        }
    }
}

private struct GoalMemoRefreshSnapshot: Encodable {
    struct Row: Encodable {
        let id: UUID
        let instanceID: UUID
        let content: String
        let isPinned: Bool
        let preferredMode: String
        let createdAt: Date
        let updatedAt: Date
        let title: String
        let preview: String
        let mode: String
        let isComposite: Bool
        let drawingUpdatedAt: Date?
    }
    struct Cursor: Encodable {
        let scansPinned: Bool
        let pinnedOffset: Int
        let regularOffset: Int

        init(_ cursor: MemoQueryCursor) {
            scansPinned = cursor.scansPinned
            pinnedOffset = cursor.pinnedOffset
            regularOffset = cursor.regularOffset
        }
    }
    struct Page: Encodable {
        let inputCursor: Cursor?
        let outputCursor: Cursor?
        let hasMore: Bool
        let rows: [Row]
    }
    let pages: [Page]
}

@MainActor
private func goalMemoRefreshDigest(pages: [MemoQueryPage], traces: [GoalMemoRefreshRecorder.Trace]) throws -> String {
    let snapshots = try pages.enumerated().map { index, page in
        let rows = try page.memos.map { memo in
            let summary = try #require(page.summaries[memo.instanceID])
            return GoalMemoRefreshSnapshot.Row(
                id: memo.id, instanceID: memo.instanceID, content: memo.content, isPinned: memo.isPinned,
                preferredMode: memo.preferredModeRawValue, createdAt: memo.createdAt, updatedAt: memo.updatedAt,
                title: summary.title, preview: summary.preview, mode: summary.mode.rawValue,
                isComposite: summary.isComposite, drawingUpdatedAt: summary.drawingUpdatedAt
            )
        }
        return GoalMemoRefreshSnapshot.Page(
            inputCursor: traces[index].inputCursor.map(GoalMemoRefreshSnapshot.Cursor.init),
            outputCursor: page.nextCursor.map(GoalMemoRefreshSnapshot.Cursor.init),
            hasMore: page.hasMore, rows: rows
        )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .secondsSince1970
    return SHA256.hash(data: try encoder.encode(GoalMemoRefreshSnapshot(pages: snapshots)))
        .map { String(format: "%02x", $0) }.joined()
}

private func goalMemoRefreshPrint(kind: String, query: String, depth: Int,
                                  samples: [Double], calls: [Int], digests: [String]) throws {
    let ordered = samples.sorted()
    let midpoint = ordered.count / 2
    let p50 = (ordered[midpoint - 1] + ordered[midpoint]) / 2
    let p95 = ordered[Int(ceil(Double(ordered.count) * 0.95)) - 1]
    let record: [String: Any] = [
        "kind": kind, "query": query, "depth": depth, "loadedRows": depth * MemoService.pageSize,
        "fixtureMemos": 2_000, "fixtureChecklistItems": 2_000,
        "store": "isolated-local-file", "context": "warmed", "locale": Locale.current.identifier,
        "n": samples.count, "warmup": 1, "unit": "ms", "p50": p50, "p95": p95,
        "p95Estimator": "nearest-rank", "max": ordered.last ?? 0, "rawSamples": samples,
        "loaderCalls": calls, "sampleDigests": digests,
        "digest": SHA256.hash(data: Data(digests.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined(),
    ]
    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    print("GOAL_MEMO_REFRESH_BENCHMARK \(String(decoding: data, as: UTF8.self))")
}

private func goalMemoRefreshID(namespace: Int, index: Int) -> UUID {
    let suffix = String(index, radix: 16)
    let padded = String(repeating: "0", count: 12 - suffix.count) + suffix
    return UUID(uuidString: "0000000\(namespace)-0000-4000-8000-\(padded)")!
}
#endif
