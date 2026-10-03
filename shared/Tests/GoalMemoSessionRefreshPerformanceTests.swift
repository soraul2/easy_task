#if DEBUG
import CryptoKit
import Darwin
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Same fixture, edits, page depth and canonical page digest as the frozen sync refresh harness.
/// Candidate measures the UI session's actual cooperative reader through a trace-only wrapper.
/// Baseline uses its actual synchronous PageLoader. All saves and validation are untimed.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_MEMO_SESSION_REFRESH_PERFORMANCE"] == "1"))
@MainActor
func goalMemoSessionRefreshPerformance() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseGoalMemoSessionRefresh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = try GoalMemoSessionRefreshFixture(storeURL: directory.appendingPathComponent("memos.store"))
    defer { withExtendedLifetime(fixture.container) {} }
    let context = ModelContext(fixture.container)
    context.autosaveEnabled = false
    let selectedID = fixture.seeds[30].id // The same selected first-page pin as the frozen harness.
    var selectedDescriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == selectedID })
    selectedDescriptor.fetchLimit = 1
    let selected = try #require(try context.fetch(selectedDescriptor).first)
    var savedContent = fixture.seeds[30].content
    var savedUpdatedAt = fixture.seeds[30].updatedAt
    var editSequence = 0
    #expect(MemoService.pageSize == 40)

    for queryCase in [(name: "empty", query: ""), (name: "dense", query: "CAFE")] {
        for depth in [1, 5, 10] {
            let recorder = GoalMemoSessionRefreshRecorder()
#if PLANBASE_GOAL_CANDIDATE
            let session = MemoQuerySession(context: context, cooperativeLoader: { context, query, cursor, checkpoint in
                try await recorder.readCooperative(context, query, cursor, checkpoint)
            })
#else
            let session = MemoQuerySession(context: context) { context, query, cursor in
                try recorder.read(context, query, cursor)
            }
#endif
            // apply/append must settle before another page is requested. Otherwise
            // the actual cooperative session correctly ignores append while loading.
            session.apply(query: queryCase.query, debounce: false)
            var setupWaitYields = try await goalMemoSessionRefreshWaitReady(session, recorder: recorder)
            for _ in 1..<depth {
                session.loadNextPage()
                setupWaitYields += try await goalMemoSessionRefreshWaitReady(session, recorder: recorder)
            }
            try goalMemoSessionRefreshValidateSession(session, depth: depth, recorder: recorder, fixture: fixture,
                selected: selected, selectedContent: savedContent, selectedUpdatedAt: savedUpdatedAt)
            _ = try goalMemoSessionRefreshPublishedDigest(session, depth: depth, recorder: recorder)

            // Exactly one ordinary saved edit + refresh warmup per query/depth.
            editSequence += 1
            savedContent = fixture.seeds[30].content + "\n작성 차례 \(editSequence)"
            savedUpdatedAt = fixture.reference.addingTimeInterval(Double(editSequence))
            _ = try MemoService.save(memo: selected, content: savedContent, now: savedUpdatedAt, in: context)
            recorder.reset()
            let warmup = try await goalMemoSessionRefreshMeasure(session, recorder: recorder)
            try goalMemoSessionRefreshValidateSession(session, depth: depth, recorder: recorder, fixture: fixture,
                selected: selected, selectedContent: savedContent, selectedUpdatedAt: savedUpdatedAt)
            _ = try goalMemoSessionRefreshPublishedDigest(session, depth: depth, recorder: recorder)

            var measurements: [GoalMemoSessionRefreshMeasurement] = []
            var calls: [Int] = []
            var startedCalls: [Int] = []
            var pageDigests: [String] = []
            var publishedDigests: [String] = []
            var callResultTraces: [[[String: Any]]] = []
            measurements.reserveCapacity(30)
            for _ in 0..<30 {
                // Same edit sequence as frozen GoalMemoRefreshPerformanceTests.
                // Its separate first-page controls never edit, so omitting that
                // already measured control preserves all 186 edited values here.
                editSequence += 1
                savedContent = fixture.seeds[30].content + "\n작성 차례 \(editSequence)"
                savedUpdatedAt = fixture.reference.addingTimeInterval(Double(editSequence))
                _ = try MemoService.save(memo: selected, content: savedContent, now: savedUpdatedAt, in: context)
                #expect(!context.hasChanges)
                recorder.reset()
                let measurement = try await goalMemoSessionRefreshMeasure(session, recorder: recorder)
                // Capturing results, every row/summary/cursor check, sorting and
                // encoding digests happen after the ready wall/CPU clocks stop.
                #expect(measurement.readyWallMs.isFinite && measurement.readyWallMs >= 0)
                #expect(measurement.processCpuMs.isFinite && measurement.processCpuMs >= 0)
                #expect(abs(measurement.readyWallMs - measurement.refreshReturnMs - measurement.waitAfterReturnMs) < 0.001)
                measurements.append(measurement)
                calls.append(recorder.calls)
                startedCalls.append(recorder.startedCalls)
                try goalMemoSessionRefreshValidateSession(session, depth: depth, recorder: recorder, fixture: fixture,
                    selected: selected, selectedContent: savedContent, selectedUpdatedAt: savedUpdatedAt)
                pageDigests.append(try goalMemoSessionRefreshDigest(
                    pages: recorder.traces.map(\.page), traces: recorder.traces))
                publishedDigests.append(try goalMemoSessionRefreshPublishedDigest(session, depth: depth, recorder: recorder))
                callResultTraces.append(recorder.traces.enumerated().map { index, trace in
                    ["call": index + 1, "query": trace.inputQuery,
                     "inputCursor": goalMemoSessionRefreshCursorRecord(trace.inputCursor),
                     "outputCursor": goalMemoSessionRefreshCursorRecord(trace.page.nextCursor),
                     "returnedRows": trace.page.memos.count, "hasMore": trace.page.hasMore]
                })
                #expect(!context.hasChanges && recorder.inFlight == 0)
            }
            try goalMemoSessionRefreshPrint(query: queryCase.name, depth: depth, measurements: measurements,
                warmup: warmup, setupWaitYields: setupWaitYields, calls: calls, startedCalls: startedCalls,
                pageDigests: pageDigests, publishedDigests: publishedDigests, traces: callResultTraces)
#if PLANBASE_GOAL_CANDIDATE
            session.cancel()
#endif
        }
    }
    #expect(editSequence == 186 && !context.hasChanges)
}

@MainActor
private final class GoalMemoSessionRefreshRecorder {
    struct Trace {
        let inputQuery: String
        let inputCursor: MemoQueryCursor?
        let page: MemoQueryPage
    }
    var calls = 0
    var startedCalls = 0
    var inFlight = 0
    var traces: [Trace] = []

    init() { traces.reserveCapacity(10) }

    func reset() {
        #expect(inFlight == 0)
        calls = 0
        startedCalls = 0
        traces.removeAll(keepingCapacity: true)
    }

    func read(_ context: ModelContext, _ query: String, _ cursor: MemoQueryCursor?) throws -> MemoQueryPage {
        startedCalls += 1
        inFlight += 1
        defer { inFlight -= 1 }
        let page = try MemoService.page(in: context, query: query, cursor: cursor)
        calls += 1
        traces.append(Trace(inputQuery: query, inputCursor: cursor, page: page))
        return page
    }

#if PLANBASE_GOAL_CANDIDATE
    func readCooperative(_ context: ModelContext, _ query: String, _ cursor: MemoQueryCursor?,
                         _ checkpoint: MemoReadCheckpoint) async throws -> MemoQueryPage {
        startedCalls += 1
        inFlight += 1
        defer { inFlight -= 1 }
        // Use the real session checkpoint unchanged: production owns cancellation,
        // yield/revision policy and retry. Do not simulate a cooperative scan here.
        let page = try await MemoService.cooperativePage(in: context, query: query, cursor: cursor,
                                                       checkpoint: checkpoint)
        calls += 1
        traces.append(Trace(inputQuery: query, inputCursor: cursor, page: page))
        return page
    }
#endif
}

private struct GoalMemoSessionRefreshSeed {
    let id: UUID
    let instanceID: UUID
    let content: String
    let isPinned: Bool
    let createdAt: Date
    let updatedAt: Date
}

@MainActor
private struct GoalMemoSessionRefreshFixture {
    let container: ModelContainer
    let reference: Date
    let seeds: [GoalMemoSessionRefreshSeed]

    init(storeURL: URL) throws {
        let container = try PlanBaseContainerFactory.makePersistent(storeURL: storeURL, mode: .local)
        let context = container.mainContext
        context.autosaveEnabled = false
        let reference = Date(timeIntervalSince1970: 1_790_899_200)
        let body = String(repeating: "본문 · Cafe\u{301} · ＡＢＣ · 👨‍👩‍👧‍👦 · 감사\n", count: 12)
        var seeds: [GoalMemoSessionRefreshSeed] = []
        seeds.reserveCapacity(2_000)
        for index in 0..<2_000 {
            let seed = GoalMemoSessionRefreshSeed(
                id: goalMemoSessionRefreshID(namespace: 1, index: index),
                instanceID: goalMemoSessionRefreshID(namespace: 2, index: index),
                content: "합성 메모 \(index)\nCafé 계획\n" + body,
                isPinned: index % 10 == 0,
                createdAt: reference.addingTimeInterval(-Double(2_000 + index)),
                updatedAt: reference.addingTimeInterval(-Double(index))
            )
            seeds.append(seed)
            context.insert(Memo(id: seed.id, instanceID: seed.instanceID, content: seed.content,
                isPinned: seed.isPinned, createdAt: seed.createdAt, updatedAt: seed.updatedAt))
            context.insert(MemoChecklistItem(
                id: goalMemoSessionRefreshID(namespace: 3, index: index),
                instanceID: goalMemoSessionRefreshID(namespace: 4, index: index), memoId: seed.id,
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

    func expectedOrder(selected: Memo, selectedUpdatedAt: Date) -> [GoalMemoSessionRefreshSeed] {
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
private func goalMemoSessionRefreshValidateSession(
    _ session: MemoQuerySession, depth: Int, recorder: GoalMemoSessionRefreshRecorder,
    fixture: GoalMemoSessionRefreshFixture, selected: Memo, selectedContent: String, selectedUpdatedAt: Date
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
    try goalMemoSessionRefreshValidate(
        recorder.traces.map(\.page), traces: recorder.traces, fixture: fixture,
        selected: selected, selectedContent: selectedContent, selectedUpdatedAt: selectedUpdatedAt
    )
}

@MainActor
private func goalMemoSessionRefreshValidate(
    _ pages: [MemoQueryPage], traces: [GoalMemoSessionRefreshRecorder.Trace], fixture: GoalMemoSessionRefreshFixture,
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

private struct GoalMemoSessionRefreshSnapshot: Encodable {
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
private func goalMemoSessionRefreshDigest(pages: [MemoQueryPage], traces: [GoalMemoSessionRefreshRecorder.Trace]) throws -> String {
    let snapshots = try pages.enumerated().map { index, page in
        let rows = try page.memos.map { memo in
            let summary = try #require(page.summaries[memo.instanceID])
            return GoalMemoSessionRefreshSnapshot.Row(
                id: memo.id, instanceID: memo.instanceID, content: memo.content, isPinned: memo.isPinned,
                preferredMode: memo.preferredModeRawValue, createdAt: memo.createdAt, updatedAt: memo.updatedAt,
                title: summary.title, preview: summary.preview, mode: summary.mode.rawValue,
                isComposite: summary.isComposite, drawingUpdatedAt: summary.drawingUpdatedAt
            )
        }
        return GoalMemoSessionRefreshSnapshot.Page(
            inputCursor: traces[index].inputCursor.map(GoalMemoSessionRefreshSnapshot.Cursor.init),
            outputCursor: page.nextCursor.map(GoalMemoSessionRefreshSnapshot.Cursor.init),
            hasMore: page.hasMore, rows: rows
        )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .secondsSince1970
    return SHA256.hash(data: try encoder.encode(GoalMemoSessionRefreshSnapshot(pages: snapshots)))
        .map { String(format: "%02x", $0) }.joined()
}

private struct GoalMemoSessionRefreshMeasurement {
    let readyWallMs: Double
    let processCpuMs: Double
    let refreshReturnMs: Double
    let waitAfterReturnMs: Double
    let waitYields: Int
}

@MainActor
private func goalMemoSessionRefreshMeasure(_ session: MemoQuerySession,
    recorder: GoalMemoSessionRefreshRecorder) async throws -> GoalMemoSessionRefreshMeasurement {
    let cpuStart = try goalMemoSessionRefreshCPUms()
    let start = DispatchTime.now().uptimeNanoseconds
    session.refresh()
    let returned = DispatchTime.now().uptimeNanoseconds
    let yields = try await goalMemoSessionRefreshWaitReady(session, recorder: recorder)
    let ready = DispatchTime.now().uptimeNanoseconds
    let cpu = try goalMemoSessionRefreshCPUms() - cpuStart
    return GoalMemoSessionRefreshMeasurement(readyWallMs: Double(ready - start) / 1_000_000,
        processCpuMs: cpu, refreshReturnMs: Double(returned - start) / 1_000_000,
        waitAfterReturnMs: Double(ready - returned) / 1_000_000, waitYields: yields)
}

@MainActor
private func goalMemoSessionRefreshWaitReady(_ session: MemoQuerySession,
    recorder: GoalMemoSessionRefreshRecorder) async throws -> Int {
    let start = DispatchTime.now().uptimeNanoseconds
    let timeout: UInt64 = 30_000_000_000
    var yields = 0
    while session.isLoading {
        try Swift.Task.checkCancellation()
        if let error = session.errorMessage {
            throw NSError(domain: "GoalMemoSessionRefresh.load", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: error])
        }
        if DispatchTime.now().uptimeNanoseconds - start >= timeout {
#if PLANBASE_GOAL_CANDIDATE
            session.cancel()
            // The actual cooperative loader checks cancellation at its checkpoints.
            // A bounded harness-only drain lets the active wrapper unwind first.
            let drainStart = DispatchTime.now().uptimeNanoseconds
            while recorder.inFlight > 0 && DispatchTime.now().uptimeNanoseconds - drainStart < 2_000_000_000 {
                await Swift.Task.yield()
            }
#endif
            throw NSError(domain: "GoalMemoSessionRefresh.timeout", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Session did not publish a ready result within the 30-second async wait limit."])
        }
        yields += 1
        await Swift.Task.yield()
    }
    try Swift.Task.checkCancellation()
    if let error = session.errorMessage {
        throw NSError(domain: "GoalMemoSessionRefresh.load", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: error])
    }
    return yields
}

private struct GoalMemoSessionRefreshPublication: Encodable {
    let loadedDepth: Int
    let hasMore: Bool
    let isLoading: Bool
    let errorMessage: String?
    let rows: [GoalMemoSessionRefreshSnapshot.Row]
}

@MainActor
private func goalMemoSessionRefreshPublishedDigest(_ session: MemoQuerySession, depth: Int,
    recorder: GoalMemoSessionRefreshRecorder) throws -> String {
    #expect(recorder.startedCalls == depth && recorder.inFlight == 0)
    func publication(_ memos: [Memo], _ summaries: [UUID: MemoListSummary],
        loadedDepth: Int, hasMore: Bool, isLoading: Bool, errorMessage: String?) throws -> String {
        let rows = try memos.map { memo in
            let summary = try #require(summaries[memo.instanceID])
            return GoalMemoSessionRefreshSnapshot.Row(id: memo.id, instanceID: memo.instanceID,
                content: memo.content, isPinned: memo.isPinned, preferredMode: memo.preferredModeRawValue,
                createdAt: memo.createdAt, updatedAt: memo.updatedAt,
                title: summary.title, preview: summary.preview, mode: summary.mode.rawValue,
                isComposite: summary.isComposite, drawingUpdatedAt: summary.drawingUpdatedAt)
        }
        let snapshot = GoalMemoSessionRefreshPublication(loadedDepth: loadedDepth, hasMore: hasMore,
            isLoading: isLoading, errorMessage: errorMessage, rows: rows)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return goalMemoSessionRefreshHash(try encoder.encode(snapshot))
    }
    let pages = recorder.traces.map(\.page)
    var expectedSummaries: [UUID: MemoListSummary] = [:]
    for page in pages { expectedSummaries.merge(page.summaries) { _, new in new } }
    let expected = try publication(pages.flatMap(\.memos), expectedSummaries,
        loadedDepth: depth, hasMore: pages.last?.hasMore ?? false, isLoading: false, errorMessage: nil)
    let actual = try publication(session.memos, session.summaries,
        loadedDepth: session.memos.count / MemoService.pageSize, hasMore: session.hasMore,
        isLoading: session.isLoading, errorMessage: session.errorMessage)
    #expect(session.memos.count % MemoService.pageSize == 0)
    #expect(actual == expected)
#if PLANBASE_GOAL_CANDIDATE
    #expect(session.readPosition.depth == depth)
    #expect(session.readPosition.cursor == pages.last?.nextCursor)
#endif
    return actual
}

private func goalMemoSessionRefreshPrint(query: String, depth: Int,
    measurements: [GoalMemoSessionRefreshMeasurement], warmup: GoalMemoSessionRefreshMeasurement,
    setupWaitYields: Int, calls: [Int], startedCalls: [Int], pageDigests: [String],
    publishedDigests: [String], traces: [[[String: Any]]]) throws {
    let walls = measurements.map(\.readyWallMs)
    let cpus = measurements.map(\.processCpuMs)
    let returns = measurements.map(\.refreshReturnMs)
    let waits = measurements.map(\.waitAfterReturnMs)
    let yields = measurements.map(\.waitYields)
    let mode: String
#if PLANBASE_GOAL_CANDIDATE
    mode = "candidate-actual-cooperative-session"
#else
    mode = "actual-synchronous-session-without-candidate-flag"
#endif
    let record: [String: Any] = [
        "kind": "autosave-style-session-refresh-to-ready", "mode": mode,
        "sourceTag": ProcessInfo.processInfo.environment["PLANBASE_GOAL_SOURCE_LABEL"] ?? "unspecified",
        "query": query, "depth": depth, "loadedRows": depth * MemoService.pageSize,
        "fixtureMemos": 2_000, "fixtureChecklistItems": 2_000, "fixturePageSize": 40,
        "fixtureBodyRepeat": 12, "selectedSeedIndex": 30, "store": "isolated-local-file",
        "context": "same-warmed-context", "locale": Locale.current.identifier,
        "n": measurements.count, "warmup": 1, "unit": "ms", "p95Estimator": "nearest-rank",
        "readyWallRawMs": walls, "readyWallP50Ms": goalMemoSessionRefreshPercentile(walls, 0.5),
        "readyWallP95Ms": goalMemoSessionRefreshPercentile(walls, 0.95), "readyWallMaxMs": walls.max() ?? 0,
        "processCpuRawMs": cpus, "processCpuP50Ms": goalMemoSessionRefreshPercentile(cpus, 0.5),
        "processCpuP95Ms": goalMemoSessionRefreshPercentile(cpus, 0.95), "processCpuMaxMs": cpus.max() ?? 0,
        "refreshReturnRawMs": returns, "refreshReturnP50Ms": goalMemoSessionRefreshPercentile(returns, 0.5),
        "refreshReturnP95Ms": goalMemoSessionRefreshPercentile(returns, 0.95), "refreshReturnMaxMs": returns.max() ?? 0,
        "waitAfterReturnRawMs": waits, "waitAfterReturnP50Ms": goalMemoSessionRefreshPercentile(waits, 0.5),
        "waitAfterReturnP95Ms": goalMemoSessionRefreshPercentile(waits, 0.95), "waitAfterReturnMaxMs": waits.max() ?? 0,
        "waitYieldCounts": yields, "setupWaitYields": setupWaitYields,
        "warmupReadyWallMs": warmup.readyWallMs, "warmupProcessCpuMs": warmup.processCpuMs,
        "warmupWaitYields": warmup.waitYields, "loaderCallsStarted": startedCalls, "loaderCallsCompleted": calls,
        "sampleCallResultTraces": traces, "sampleDigests": pageDigests,
        "digest": goalMemoSessionRefreshHash(Data(pageDigests.joined(separator: "\n").utf8)),
        "publishedSampleDigests": publishedDigests,
        "publishedDigest": goalMemoSessionRefreshHash(Data(publishedDigests.joined(separator: "\n").utf8)),
        "timeoutSeconds": 30,
        "limits": "ready wall and process CPU include harness isLoading/error polling, timeout clocks and Task.yield scheduling; observer sample sees public loading false after publication; refreshReturn is dispatch-to-return, not cooperative completion; process CPU includes all process/store threads and getrusage wrapper; trace retention adds identical per-page bookkeeping but async/sync scheduling differs; fixture/setup/apply/append/saves/validation/encoding are outside refresh intervals; async-wait timeout cannot preempt a blocking synchronous refresh; original UI checkpoints are passed unchanged; no SwiftUI body/frame/realized-row/input measurement; baseline and candidate are separate runs",
    ]
    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    print("GOAL_MEMO_SESSION_REFRESH_BENCHMARK \(String(decoding: data, as: UTF8.self))")
}

private func goalMemoSessionRefreshCursorRecord(_ cursor: MemoQueryCursor?) -> Any {
    guard let cursor else { return NSNull() }
    let record: [String: Any] = ["scansPinned": cursor.scansPinned,
        "pinnedOffset": cursor.pinnedOffset, "regularOffset": cursor.regularOffset]
    return record
}

private func goalMemoSessionRefreshCPUms() throws -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
        throw NSError(domain: "GoalMemoSessionRefresh.getrusage", code: Int(errno))
    }
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000
}

private func goalMemoSessionRefreshPercentile(_ samples: [Double], _ quantile: Double) -> Double {
    let ordered = samples.sorted()
    guard !ordered.isEmpty else { return 0 }
    if quantile == 0.5 && ordered.count.isMultiple(of: 2) {
        return (ordered[ordered.count / 2 - 1] + ordered[ordered.count / 2]) / 2
    }
    return ordered[max(0, Int(ceil(Double(ordered.count) * quantile)) - 1)]
}

private func goalMemoSessionRefreshHash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func goalMemoSessionRefreshID(namespace: Int, index: Int) -> UUID {
    let suffix = String(index, radix: 16)
    let padded = String(repeating: "0", count: 12 - suffix.count) + suffix
    return UUID(uuidString: "0000000\(namespace)-0000-4000-8000-\(padded)")!
}
#endif
