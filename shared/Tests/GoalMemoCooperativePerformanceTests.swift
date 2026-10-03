#if DEBUG
import CryptoKit
import Darwin
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Candidate-only slice measurements: the actual production scanner, never a fake page loader.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_MEMO_COOPERATIVE_PERFORMANCE"] == "1"))
@MainActor
func goalMemoCooperativePerformance() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let reference = Date(timeIntervalSince1970: 1_790_899_200)
    let body = String(repeating: "본문 👨‍👩‍👧‍👦 감사 Ｃａｆｅ\u{301}\n", count: 80)
    for index in 0..<10_000 {
        let suffix = String(format: "%012x", index)
        let memo = Memo(id: UUID(uuidString: "00000001-0000-4000-8000-\(suffix)")!,
            instanceID: UUID(uuidString: "00000002-0000-4000-8000-\(suffix)")!,
            content: "제목 \(index)\n\(body)", isPinned: index < 200,
            createdAt: reference.addingTimeInterval(-Double(index)),
            updatedAt: reference.addingTimeInterval(-Double(index)))
        context.insert(memo)
        context.insert(MemoChecklistItem(memoId: memo.id, title: "항목 \(index)", order: 100))
        if index % 250 == 249 { try context.save() }
    }
    try context.save()
    let query = "존재하지않는-목표검색어-9f43"
    let expected = try MemoService.page(in: context, query: query)
    #expect(expected.memos.isEmpty && expected.nextCursor == nil && !expected.hasMore)
    let validity = MemoReadValidity(context: context)
    // Warmup and oracle/fixture are deliberately outside samples.
    _ = try await goalMemoCooperativeMeasuredPage(context, query, validity)
    var walls: [Double] = []
    var cpus: [Double] = []
    var allSlices: [Double] = []
    var allGaps: [Double] = []
    var perRead: [[String: Any]] = []
    var digests: [String] = []
    for _ in 0..<30 {
        let measurement = try await goalMemoCooperativeMeasuredPage(context, query, validity)
        #expect(measurement.page.memos.isEmpty && measurement.page.nextCursor == nil && !measurement.page.hasMore)
        #expect(measurement.page.summaries.isEmpty)
        walls.append(measurement.wall)
        cpus.append(measurement.cpu)
        allSlices += measurement.slices
        allGaps += measurement.gaps
        perRead.append(["wallMs": measurement.wall, "processCpuMs": measurement.cpu,
            "checkpoints": measurement.gaps.count, "sliceMs": measurement.slices,
            "yieldGapMs": measurement.gaps, "sliceP50Ms": goalMemoCooperativePercentile(measurement.slices, 0.5),
            "sliceMaxMs": measurement.slices.max() ?? 0])
        digests.append("empty:nil:false:0")
    }

    var cancellations: [Double] = []
    for _ in 0..<30 {
        let gate = GoalMemoCooperativePerformanceGate()
        let version = validity.capture()
        let read = Swift.Task { @MainActor in
            var count = 0
            _ = try await MemoService.cooperativePage(in: context, query: query, cursor: nil,
                checkpoint: MemoReadCheckpoint {
                    try Swift.Task.checkCancellation()
                    await Swift.Task.yield()
                    try Swift.Task.checkCancellation()
                    guard validity.capture() == version else { throw MemoReadInvalidated.changed }
                    count += 1
                    if count == 20 { await gate.pause(); try Swift.Task.checkCancellation() }
                })
        }
        await gate.waitReached()
        let start = DispatchTime.now().uptimeNanoseconds
        read.cancel()
        gate.release()
        do {
            _ = try await read.value
            Issue.record("Cancelled scanner completed a page")
        } catch is CancellationError {
            cancellations.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
    }
    #expect(cancellations.count == 30)

    let digest = SHA256.hash(data: Data(digests.joined(separator: "\n").utf8))
        .map { String(format: "%02x", $0) }.joined()
    let output: [String: Any] = [
        "scenario": "actual-cooperative-scanner-10k-absent", "store": "synthetic-in-memory",
        "tasks": 0, "memos": 10_000, "checklists": 10_000, "n": 30, "warmup": 1,
        "unit": "ms", "locale": Locale.current.identifier, "wallRaw": walls, "cpuRaw": cpus,
        "wallP50": goalMemoCooperativePercentile(walls, 0.5),
        "wallP95": goalMemoCooperativePercentile(walls, 0.95), "wallMax": walls.max() ?? 0,
        "cpuP50": goalMemoCooperativePercentile(cpus, 0.5), "cpuMax": cpus.max() ?? 0,
        "sliceP50": goalMemoCooperativePercentile(allSlices, 0.5),
        "sliceP95": goalMemoCooperativePercentile(allSlices, 0.95), "sliceMax": allSlices.max() ?? 0,
        "yieldGapP50": goalMemoCooperativePercentile(allGaps, 0.5), "yieldGapMax": allGaps.max() ?? 0,
        "checkpointCount": allGaps.count,
        "cancelRaw": cancellations, "cancelP50": goalMemoCooperativePercentile(cancellations, 0.5),
        "cancelP95": goalMemoCooperativePercentile(cancellations, 0.95),
        "cancelMax": cancellations.max() ?? 0, "cancelCheckpoint": 20,
        "cancelMeaning": "cancel-at-controlled-cooperative-boundary-to-read-task-finish",
        "reads": perRead, "digest": digest,
        "limits": "candidate-only; checkpoint clocks/arrays add overhead; yield gaps include scheduling; process CPU includes store threads; no UI/frame/input measurement",
    ]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    print("GOAL_MEMO_COOPERATIVE_BENCHMARK \(String(decoding: data, as: UTF8.self))")
    #expect(!context.hasChanges)
    withExtendedLifetime(container) {}
}

@MainActor
private func goalMemoCooperativeMeasuredPage(_ context: ModelContext, _ query: String,
                                             _ validity: MemoReadValidity) async throws
    -> (page: MemoQueryPage, wall: Double, cpu: Double, slices: [Double], gaps: [Double]) {
    let version = validity.capture()
    var slices: [Double] = []
    var gaps: [Double] = []
    slices.reserveCapacity(256)
    gaps.reserveCapacity(256)
    let cpuStart = try goalMemoCooperativeCPUms()
    let start = DispatchTime.now().uptimeNanoseconds
    var resumed = start
    let page = try await MemoService.cooperativePage(in: context, query: query, cursor: nil,
        checkpoint: MemoReadCheckpoint {
            try Swift.Task.checkCancellation()
            let beforeYield = DispatchTime.now().uptimeNanoseconds
            slices.append(Double(beforeYield - resumed) / 1_000_000)
            await Swift.Task.yield()
            let afterYield = DispatchTime.now().uptimeNanoseconds
            gaps.append(Double(afterYield - beforeYield) / 1_000_000)
            resumed = afterYield
            try Swift.Task.checkCancellation()
            guard validity.capture() == version else { throw MemoReadInvalidated.changed }
        })
    let end = DispatchTime.now().uptimeNanoseconds
    slices.append(Double(end - resumed) / 1_000_000)
    return (page, Double(end - start) / 1_000_000, try goalMemoCooperativeCPUms() - cpuStart, slices, gaps)
}

private func goalMemoCooperativeCPUms() throws -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
        throw NSError(domain: "GoalMemoCooperative.getrusage", code: Int(errno))
    }
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000
}

private func goalMemoCooperativePercentile(_ samples: [Double], _ quantile: Double) -> Double {
    let sorted = samples.sorted()
    guard !sorted.isEmpty else { return 0 }
    if quantile == 0.5, sorted.count.isMultiple(of: 2) {
        return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }
    return sorted[max(0, Int(ceil(Double(sorted.count) * quantile)) - 1)]
}

@MainActor
private final class GoalMemoCooperativePerformanceGate {
    private var reached = false
    private var blocked: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func pause() async {
        reached = true
        let waiting = waiter
        waiter = nil
        waiting?.resume()
        await withCheckedContinuation { blocked = $0 }
    }
    func waitReached() async {
        guard !reached else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        let waiting = blocked
        blocked = nil
        waiting?.resume()
    }
}
#endif
