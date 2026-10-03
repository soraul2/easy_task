#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Opt-in, warmed local-store measurements of the production page operation.
/// This does not measure debounce, rendered frames, or individual input latency.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_MEMO_PERFORMANCE"] == "1"))
@MainActor
func goalMemoSearchPerformance() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseGoalMemoSearch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    // A single test owns the loop: the three store sizes are not measured concurrently.
    for count in [200, 2_000, 10_000] {
        let fixture = try GoalMemoSearchFixture(
            count: count, storeURL: directory.appendingPathComponent("memo-\(count).store")
        )
        let context = ModelContext(fixture.container)
        context.autosaveEnabled = false
        let firstPageIDs = (
            Array(stride(from: 0, to: count, by: 10))
                + (0..<count).filter { $0 % 10 != 0 }
        ).prefix(MemoService.pageSize).map { goalMemoSearchID(namespace: 2, index: $0) }
        let cases: [GoalMemoSearchCase] = [
            .init(name: "absent", query: "ZzNoMatchToken_20261002", samples: 30,
                  expectedInstanceIDs: [], expectedHasMore: false),
            .init(name: "last-body-match", query: "needle-endbodye", samples: 5,
                  expectedInstanceIDs: [goalMemoSearchID(namespace: 2, index: count - 1)],
                  expectedHasMore: false),
            .init(name: "checklist-only", query: "checklistonlymarkere", samples: 5,
                  expectedInstanceIDs: [goalMemoSearchID(namespace: 2, index: count - 2)],
                  expectedHasMore: false),
            .init(name: "empty-query", query: "", samples: 5,
                  expectedInstanceIDs: firstPageIDs, expectedHasMore: true),
            .init(name: "first-page-match", query: "CAFE", samples: 5,
                  expectedInstanceIDs: firstPageIDs, expectedHasMore: true),
        ]

        // Confirm that the checklist marker is absent from the memo text/title.
        let checklistMemo = try #require(context.fetch(FetchDescriptor<Memo>()).first {
            $0.instanceID == goalMemoSearchID(namespace: 2, index: count - 2)
        })
        #expect(!MemoRules.matches(checklistMemo, query: "checklistonlymarkere"))

        for scenario in cases {
            let warmup = try MemoService.page(in: context, query: scenario.query)
            try scenario.validate(warmup)
            let expectedDigest = try goalMemoSearchDigest(warmup)
            var samples: [Double] = []
            samples.reserveCapacity(scenario.samples)
            for _ in 0..<scenario.samples {
                let started = DispatchTime.now().uptimeNanoseconds
                let page = try MemoService.page(in: context, query: scenario.query)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                samples.append(elapsed)
                // Validation and digest calculation are outside the timed page operation.
                try scenario.validate(page)
                #expect(try goalMemoSearchDigest(page) == expectedDigest)
            }
            let ordered = samples.sorted()
            let midpoint = ordered.count / 2
            let median = ordered.count.isMultiple(of: 2)
                ? (ordered[midpoint - 1] + ordered[midpoint]) / 2
                : ordered[midpoint]
            let p95Index = Int(ceil(Double(ordered.count) * 0.95)) - 1
            let record: [String: Any] = [
                "fixtureMemos": count,
                "fixtureChecklistItems": count,
                "bodyBytes": fixture.bodyBytes,
                "scenario": scenario.name,
                "store": "isolated-local-file",
                "context": "warmed",
                "locale": Locale.current.identifier,
                "unit": "ms",
                "n": samples.count,
                "warmup": 1,
                "p50": median,
                "p95": ordered[p95Index],
                "p95Estimator": "nearest-rank",
                "max": ordered.last ?? 0,
                "rawSamples": samples,
                "digest": expectedDigest,
                "resultCount": warmup.memos.count,
                "hasMore": warmup.hasMore,
                "auxiliarySmallSample": scenario.samples < 30,
            ]
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            print("GOAL_MEMO_SEARCH_BENCHMARK \(String(decoding: data, as: UTF8.self))")
        }
        #expect(!context.hasChanges)
        withExtendedLifetime(fixture.container) {}
    }
}

@MainActor
private struct GoalMemoSearchFixture {
    let container: ModelContainer
    let bodyBytes: Int

    init(count: Int, storeURL: URL) throws {
        let container = try PlanBaseContainerFactory.makePersistent(storeURL: storeURL, mode: .local)
        let context = container.mainContext
        context.autosaveEnabled = false
        let reference = Date(timeIntervalSince1970: 1_790_899_200)
        let body = String(repeating: "본문 순서 · Cafe\u{301} · ＡＢＣ · 👨‍👩‍👧‍👦 · 계획 점검\n", count: 12)
        var totalBodyBytes = 0
        for index in 0..<count {
            var content = "합성 메모 \(index)\n감사 · Café · ＡＢＣ\n" + body
            if index == count - 1 { content += "\nNeEdLe-EndBodyÉ" }
            totalBodyBytes += content.utf8.count
            let memoID = goalMemoSearchID(namespace: 1, index: index)
            let updatedAt = reference.addingTimeInterval(-Double(index))
            context.insert(Memo(
                id: memoID, instanceID: goalMemoSearchID(namespace: 2, index: index),
                content: content, isPinned: index % 10 == 0,
                createdAt: reference.addingTimeInterval(-Double(count + index)),
                updatedAt: updatedAt
            ))
            context.insert(MemoChecklistItem(
                id: goalMemoSearchID(namespace: 3, index: index),
                instanceID: goalMemoSearchID(namespace: 4, index: index), memoId: memoID,
                title: index == count - 2 ? "ChecklistOnlyMarkerÉ" : "확인 항목 \(index) · ＡＢＣ",
                isCompleted: index % 3 == 0, order: 100,
                createdAt: updatedAt, updatedAt: updatedAt
            ))
            if index % 250 == 249 { try context.save() }
        }
        try context.save()
        self.container = container
        self.bodyBytes = totalBodyBytes
    }
}

private struct GoalMemoSearchCase {
    let name: String
    let query: String
    let samples: Int
    let expectedInstanceIDs: [UUID]
    let expectedHasMore: Bool

    @MainActor
    func validate(_ page: MemoQueryPage) throws {
        #expect(page.memos.map(\.instanceID) == expectedInstanceIDs)
        #expect(page.hasMore == expectedHasMore)
        #expect(page.summaries.count == page.memos.count)
        #expect(Set(page.summaries.keys) == Set(expectedInstanceIDs))
        if !expectedHasMore { #expect(page.nextCursor == nil) }
    }
}

private struct GoalMemoSearchPageSnapshot: Encodable {
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
    }
    let rows: [Row]
    let cursor: Cursor?
    let hasMore: Bool
}

@MainActor
private func goalMemoSearchDigest(_ page: MemoQueryPage) throws -> String {
    let rows = try page.memos.map { memo in
        let summary = try #require(page.summaries[memo.instanceID])
        return GoalMemoSearchPageSnapshot.Row(
            id: memo.id, instanceID: memo.instanceID, content: memo.content,
            isPinned: memo.isPinned, preferredMode: memo.preferredModeRawValue,
            createdAt: memo.createdAt, updatedAt: memo.updatedAt,
            title: summary.title, preview: summary.preview, mode: summary.mode.rawValue,
            isComposite: summary.isComposite, drawingUpdatedAt: summary.drawingUpdatedAt
        )
    }
    let snapshot = GoalMemoSearchPageSnapshot(
        rows: rows,
        cursor: page.nextCursor.map {
            .init(scansPinned: $0.scansPinned, pinnedOffset: $0.pinnedOffset,
                  regularOffset: $0.regularOffset)
        },
        hasMore: page.hasMore
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .secondsSince1970
    return SHA256.hash(data: try encoder.encode(snapshot))
        .map { String(format: "%02x", $0) }.joined()
}

private func goalMemoSearchID(namespace: Int, index: Int) -> UUID {
    let suffix = String(index, radix: 16)
    let padded = String(repeating: "0", count: 12 - suffix.count) + suffix
    return UUID(uuidString: "0000000\(namespace)-0000-4000-8000-\(padded)")!
}
#endif
