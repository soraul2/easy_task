#if DEBUG
import CryptoKit
import Darwin
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Same memory fixture on original baseline and candidate. The baseline records sync only.
/// Candidate pairs actual sync/actual cooperative APIs; no copied or simulated scanner.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_MEMO_PAIRED_PERFORMANCE"] == "1"))
@MainActor
func goalMemoPairedPerformance() async throws {
    let fixture = try GoalMemoPairedFixture()
    let context = fixture.container.mainContext
    let query = "존재하지않는-목표검색어-9f43"
    let oracle = try MemoService.page(in: context, query: query)
    #expect(oracle.memos.isEmpty && oracle.summaries.isEmpty)
    #expect(oracle.nextCursor == nil && !oracle.hasMore)
    let expectedDigest = try goalMemoPairedDigest(oracle)
    _ = try goalMemoPairedSync(context, query)
#if PLANBASE_GOAL_CANDIDATE
    let validity = MemoReadValidity(context: context)
    _ = try await goalMemoPairedCooperative(context, query, validity)
#endif

    var syncReads: [GoalMemoPairedMeasurement] = []
    var cooperativeReads: [GoalMemoPairedMeasurement] = []
    var pairs: [[String: Any]] = []
    for index in 0..<30 {
        let sync: GoalMemoPairedMeasurement
#if PLANBASE_GOAL_CANDIDATE
        let cooperative: GoalMemoPairedMeasurement
        if index.isMultiple(of: 2) {
            sync = try goalMemoPairedSync(context, query)
            cooperative = try await goalMemoPairedCooperative(context, query, validity)
        } else {
            cooperative = try await goalMemoPairedCooperative(context, query, validity)
            sync = try goalMemoPairedSync(context, query)
        }
        // Full page comparison and checkpoint bookkeeping are outside both timed operations.
        let cooperativeDigest = try goalMemoPairedDigest(cooperative.page)
        #expect(cooperativeDigest == expectedDigest)
        #expect(cooperative.checkpoints > 0)
        #expect(cooperative.slices.count == cooperative.checkpoints + 1)
        #expect(cooperative.gaps.count == cooperative.checkpoints)
        #expect(cooperative.slices.allSatisfy { $0.isFinite && $0 >= 0 })
        #expect(cooperative.gaps.allSatisfy { $0.isFinite && $0 >= 0 })
        #expect(abs(cooperative.wall - cooperative.slices.reduce(0, +)
                    - cooperative.gaps.reduce(0, +)) < 0.001)
        cooperativeReads.append(cooperative)
#else
        sync = try goalMemoPairedSync(context, query)
#endif
        let syncDigest = try goalMemoPairedDigest(sync.page)
        #expect(syncDigest == expectedDigest)
        #expect(!context.hasChanges)
        syncReads.append(sync)
        var pair: [String: Any] = ["index": index, "sync": sync.record, "syncDigest": syncDigest]
#if PLANBASE_GOAL_CANDIDATE
        pair["order"] = index.isMultiple(of: 2) ? "sync-cooperative" : "cooperative-sync"
        pair["cooperative"] = cooperative.record
        pair["cooperativeDigest"] = cooperativeDigest
        pair["wallDeltaMs"] = cooperative.wall - sync.wall
        pair["cpuDeltaMs"] = cooperative.cpu - sync.cpu
#else
        pair["order"] = "sync-only-without-candidate-flag"
#endif
        pairs.append(pair)
    }

    // Auxiliary unpaired n=5 control: only two wall clocks, no CPU calls or slice instrumentation.
    // This checks clock-wrapper scale, rather than providing an independent repeat of 30 pairs.
    var wallOnlySync: [Double] = []
    for _ in 0..<5 {
        let start = DispatchTime.now().uptimeNanoseconds
        let page = try MemoService.page(in: context, query: query)
        let end = DispatchTime.now().uptimeNanoseconds
        wallOnlySync.append(Double(end - start) / 1_000_000)
        #expect(try goalMemoPairedDigest(page) == expectedDigest)
        #expect(!context.hasChanges)
    }
    var output: [String: Any] = [
        "scenario": "actual-sync-cooperative-same-memory-10k-absent",
        "store": "synthetic-in-memory", "context": "same-warmed-main-context",
        "memos": 10_000, "checklists": 10_000, "pinned": 200, "bodyRepeat": 80,
        "bodyBytes": fixture.bodyBytes, "bodyUTF8SHA256": fixture.bodyDigest,
        "query": query, "locale": Locale.current.identifier, "unit": "ms",
        "n": 30, "independentRepeat": 1, "warmupPerMethod": 1,
        "oracleReadsOutsideSamples": 1, "digest": expectedDigest,
        "sync": goalMemoPairedMetrics(syncReads), "pairs": pairs,
        "auxiliarySyncWallOnly": ["n": 5, "rawMs": wallOnlySync,
            "p50Ms": goalMemoPairedPercentile(wallOnlySync, 0.5),
            "meaning": "unpaired-post-loop-wall-only-control; auxiliary-small-sample"],
        "limits": "clean expensive fixture only; timing arrays/clocks add cooperative overhead; process CPU includes store threads; pooled slice percentiles are not per-read wall percentiles; yield gaps include scheduling; n5 control is unpaired; no UI/frame/input measurement; baseline vs candidate uses separate runs",
    ]
#if PLANBASE_GOAL_CANDIDATE
    output["mode"] = "candidate-actual-sync-cooperative-pairs"
    output["paired"] = true
    output["cooperative"] = goalMemoPairedMetrics(cooperativeReads)
    output["sliceInstrumentation"] = "two uptime clocks plus arrays per checkpoint; validity/cancellation checks and yield match actual checkpoint policy"
#else
    output["mode"] = "actual-sync-only-without-candidate-flag"
    output["paired"] = false
    output["cooperative"] = "unavailable-in-original-baseline-source"
#endif
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    print("GOAL_MEMO_PAIRED_BENCHMARK \(String(decoding: data, as: UTF8.self))")
    #expect(!context.hasChanges)
    withExtendedLifetime(fixture.container) {}
}

@MainActor
private struct GoalMemoPairedFixture {
    let container: ModelContainer
    let bodyBytes: Int
    let bodyDigest: String

    init() throws {
        // Same values/setup/save cadence as the frozen GoalMemoCooperativePerformanceTests fixture.
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        context.autosaveEnabled = false
        let reference = Date(timeIntervalSince1970: 1_790_899_200)
        let body = String(repeating: "본문 👨‍👩‍👧‍👦 감사 Ｃａｆｅ\u{301}\n", count: 80)
        var bodyBytes = 0
        for index in 0..<10_000 {
            let suffix = String(format: "%012x", index)
            let content = "제목 \(index)\n\(body)"
            let memo = Memo(id: UUID(uuidString: "00000001-0000-4000-8000-\(suffix)")!,
                instanceID: UUID(uuidString: "00000002-0000-4000-8000-\(suffix)")!,
                content: content, isPinned: index < 200,
                createdAt: reference.addingTimeInterval(-Double(index)),
                updatedAt: reference.addingTimeInterval(-Double(index)))
            context.insert(memo)
            context.insert(MemoChecklistItem(memoId: memo.id, title: "항목 \(index)", order: 100))
            bodyBytes += content.utf8.count
            if index % 250 == 249 { try context.save() }
        }
        try context.save()
        self.container = container
        self.bodyBytes = bodyBytes
        self.bodyDigest = goalMemoPairedHash(Data(body.utf8))
    }
}

@MainActor
private struct GoalMemoPairedMeasurement {
    let page: MemoQueryPage
    let wall: Double
    let cpu: Double
    let checkpoints: Int
    let slices: [Double]
    let gaps: [Double]

    var record: [String: Any] {
        ["wallMs": wall, "processCpuMs": cpu, "checkpoints": checkpoints,
         "sliceRawMs": slices, "yieldGapRawMs": gaps,
         "sliceP50Ms": goalMemoPairedPercentile(slices, 0.5), "sliceMaxMs": slices.max() ?? 0]
    }
}

@MainActor
private func goalMemoPairedSync(_ context: ModelContext, _ query: String) throws -> GoalMemoPairedMeasurement {
    let cpuStart = try goalMemoPairedCPUms()
    let start = DispatchTime.now().uptimeNanoseconds
    let page = try MemoService.page(in: context, query: query)
    let end = DispatchTime.now().uptimeNanoseconds
    let cpu = try goalMemoPairedCPUms() - cpuStart
    return GoalMemoPairedMeasurement(page: page, wall: Double(end - start) / 1_000_000,
        cpu: cpu, checkpoints: 0, slices: [], gaps: [])
}

#if PLANBASE_GOAL_CANDIDATE
@MainActor
private func goalMemoPairedCooperative(_ context: ModelContext, _ query: String,
                                      _ validity: MemoReadValidity) async throws -> GoalMemoPairedMeasurement {
    let version = validity.capture()
    var slices: [Double] = []
    var gaps: [Double] = []
    var checkpoints = 0
    slices.reserveCapacity(256)
    gaps.reserveCapacity(256)
    let cpuStart = try goalMemoPairedCPUms()
    let start = DispatchTime.now().uptimeNanoseconds
    var resumed = start
    let page = try await MemoService.cooperativePage(in: context, query: query, cursor: nil,
        checkpoint: MemoReadCheckpoint {
            checkpoints += 1
            try Swift.Task.checkCancellation()
            let before = DispatchTime.now().uptimeNanoseconds
            slices.append(Double(before - resumed) / 1_000_000)
            await Swift.Task.yield()
            let after = DispatchTime.now().uptimeNanoseconds
            gaps.append(Double(after - before) / 1_000_000)
            resumed = after
            try Swift.Task.checkCancellation()
            guard validity.capture() == version else { throw MemoReadInvalidated.changed }
        })
    let end = DispatchTime.now().uptimeNanoseconds
    let cpu = try goalMemoPairedCPUms() - cpuStart
    slices.append(Double(end - resumed) / 1_000_000)
    return GoalMemoPairedMeasurement(page: page, wall: Double(end - start) / 1_000_000,
        cpu: cpu, checkpoints: checkpoints, slices: slices, gaps: gaps)
}
#endif

@MainActor
private func goalMemoPairedMetrics(_ reads: [GoalMemoPairedMeasurement]) -> [String: Any] {
    let walls = reads.map(\.wall)
    let cpus = reads.map(\.cpu)
    let slices = reads.flatMap(\.slices)
    let gaps = reads.flatMap(\.gaps)
    return ["n": reads.count, "wallRawMs": walls, "cpuRawMs": cpus,
        "wallP50Ms": goalMemoPairedPercentile(walls, 0.5),
        "wallP95Ms": goalMemoPairedPercentile(walls, 0.95), "wallMaxMs": walls.max() ?? 0,
        "cpuP50Ms": goalMemoPairedPercentile(cpus, 0.5),
        "cpuP95Ms": goalMemoPairedPercentile(cpus, 0.95), "cpuMaxMs": cpus.max() ?? 0,
        "sliceP50Ms": goalMemoPairedPercentile(slices, 0.5),
        "sliceP95Ms": goalMemoPairedPercentile(slices, 0.95), "sliceMaxMs": slices.max() ?? 0,
        "yieldGapP50Ms": goalMemoPairedPercentile(gaps, 0.5), "yieldGapMaxMs": gaps.max() ?? 0,
        "checkpointCount": reads.map(\.checkpoints).reduce(0, +)]
}

private func goalMemoPairedCPUms() throws -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
        throw NSError(domain: "GoalMemoPaired.getrusage", code: Int(errno))
    }
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000
}

private func goalMemoPairedPercentile(_ samples: [Double], _ quantile: Double) -> Double {
    let sorted = samples.sorted()
    guard !sorted.isEmpty else { return 0 }
    if quantile == 0.5, sorted.count.isMultiple(of: 2) {
        return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }
    return sorted[max(0, Int(ceil(Double(sorted.count) * quantile)) - 1)]
}

private struct GoalMemoPairedPageSnapshot: Encodable {
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
    let summaryKeys: [UUID]
}

@MainActor
private func goalMemoPairedDigest(_ page: MemoQueryPage) throws -> String {
    #expect(page.summaries.count == page.memos.count)
    let rows = try page.memos.map { memo in
        let summary = try #require(page.summaries[memo.instanceID])
        return GoalMemoPairedPageSnapshot.Row(id: memo.id, instanceID: memo.instanceID,
            content: memo.content, isPinned: memo.isPinned, preferredMode: memo.preferredModeRawValue,
            createdAt: memo.createdAt, updatedAt: memo.updatedAt, title: summary.title,
            preview: summary.preview, mode: summary.mode.rawValue,
            isComposite: summary.isComposite, drawingUpdatedAt: summary.drawingUpdatedAt)
    }
    let snapshot = GoalMemoPairedPageSnapshot(rows: rows, cursor: page.nextCursor.map {
        .init(scansPinned: $0.scansPinned, pinnedOffset: $0.pinnedOffset, regularOffset: $0.regularOffset)
    }, hasMore: page.hasMore, summaryKeys: page.summaries.keys.sorted { $0.uuidString < $1.uuidString })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .secondsSince1970
    return goalMemoPairedHash(try encoder.encode(snapshot))
}

private func goalMemoPairedHash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
#endif
