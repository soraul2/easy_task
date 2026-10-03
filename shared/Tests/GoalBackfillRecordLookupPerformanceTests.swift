#if DEBUG
import CryptoKit
import Darwin
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Public-API record diagnostics, compatible with the frozen baseline. Every
/// interval contains exactly one actual record(.legacyBackfill) call. Per-sample
/// wall/CPU values are sums of those intervals, NOT end-to-end backfill latency.
/// Fixture/context construction, seed/save, output checks and SHA are untimed.
/// No Tasks are needed: record's authority reads TaskCompletionActivity only.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_BACKFILL_RECORD_PERFORMANCE"] == "1"))
@MainActor
func goalBackfillRecordLookupPerformance() throws {
    let completion = try #require(ISO8601DateFormatter().date(from: "2026-10-01T23:30:00Z"))
    let createdAt = completion.addingTimeInterval(86_400)
    let source = ProcessInfo.processInfo.environment["PLANBASE_GOAL_SOURCE_LABEL"] ?? "unspecified"
    for (count, sampleCount) in [(100, 30), (1_000, 5), (2_760, 5)] {
        let keys = (0..<count).map { GoalBackfillRecordKey(index: $0, completion: completion) }
        #expect(Set(keys.map(\.taskID)).count == count)
        for mode in GoalBackfillRecordMode.allCases {
            let expected = keys.map { GoalBackfillRecordValue(key: $0, captured: mode == .alreadyCaptured,
                                                            createdAt: createdAt) }
            let expectedDigest = goalBackfillRecordDigest(expected)
            var samples: [GoalBackfillRecordSample] = []
            var setup: [Double] = []
            for sample in -1..<sampleCount {
                let measurement = try autoreleasepool {
                    try goalBackfillRecordSample(mode: mode, keys: keys, expected: expected,
                                                 expectedDigest: expectedDigest, createdAt: createdAt)
                }
                setup.append(measurement.setupMs)
                if sample >= 0 { samples.append(measurement) }
            }
            goalBackfillRecordReport(mode: mode, source: source, keys: count, samples: samples,
                                     setup: setup, digest: expectedDigest)
        }
    }
}

private enum GoalBackfillRecordMode: String, CaseIterable {
    case growingPending = "record-growing-pending"
    case freshContext = "record-fresh-context-empty-pending"
    case alreadyCaptured = "record-saved-captured-control"
}

private struct GoalBackfillRecordKey {
    let taskID: UUID
    let day: String
    let occurredAt: Date

    init(index: Int, completion: Date) {
        taskID = goalBackfillRecordID(namespace: 1, index: index)
        occurredAt = completion.addingTimeInterval(Double(index % 5) * 60)
        day = TaskActivityRules.legacyDayKey(for: occurredAt)
    }
}

private struct GoalBackfillRecordValue: Equatable {
    let id: UUID
    let taskID: UUID
    let day: String
    let occurredAt: Date
    let origin: String
    let createdAt: Date
    let updatedAt: Date
    let supersededAt: Date?

    init(_ activity: TaskCompletionActivity) {
        id = activity.id
        taskID = activity.taskId
        day = activity.activityDayKey
        occurredAt = activity.occurredAt
        origin = activity.originRawValue
        createdAt = activity.createdAt
        updatedAt = activity.updatedAt
        supersededAt = activity.supersededAt
    }

    init(key: GoalBackfillRecordKey, captured: Bool, createdAt: Date) {
        id = TaskActivityRules.logicalID(taskID: key.taskID, activityDayKey: key.day)
        taskID = key.taskID
        day = key.day
        occurredAt = key.occurredAt
        origin = (captured ? TaskCompletionActivityOrigin.captured : .legacyBackfill).rawValue
        self.createdAt = captured ? key.occurredAt.addingTimeInterval(1) : createdAt
        updatedAt = captured ? key.occurredAt.addingTimeInterval(2) : createdAt
        supersededAt = nil
    }

    var payload: String {
        [id.uuidString, taskID.uuidString, day, String(occurredAt.timeIntervalSince1970), origin,
         String(createdAt.timeIntervalSince1970), String(updatedAt.timeIntervalSince1970),
         supersededAt.map { String($0.timeIntervalSince1970) } ?? "nil"].joined(separator: "|")
    }
}

private struct GoalBackfillRecordSample {
    let wallMs: Double
    let processCpuMs: Double
    let setupMs: Double
    let blockWallMs: [Double]
    let blockCpuMs: [Double]
}

@MainActor
private func goalBackfillRecordSample(
    mode: GoalBackfillRecordMode, keys: [GoalBackfillRecordKey], expected: [GoalBackfillRecordValue],
    expectedDigest: String, createdAt: Date
) throws -> GoalBackfillRecordSample {
    let setupStart = DispatchTime.now().uptimeNanoseconds
    let container = try PlanBaseContainerFactory.makeInMemory()
    let writer = container.mainContext
    writer.autosaveEnabled = false
    var savedPhysical: [String] = []
    if mode == .alreadyCaptured {
        for (index, key) in keys.enumerated() {
            let activity = TaskCompletionActivity(
                id: TaskActivityRules.logicalID(taskID: key.taskID, activityDayKey: key.day),
                instanceID: goalBackfillRecordID(namespace: 2, index: index),
                taskId: key.taskID, activityDayKey: key.day, occurredAt: key.occurredAt,
                origin: .captured, createdAt: key.occurredAt.addingTimeInterval(1),
                updatedAt: key.occurredAt.addingTimeInterval(2))
            writer.insert(activity)
            savedPhysical.append("\(activity.instanceID.uuidString)|\(GoalBackfillRecordValue(activity).payload)")
        }
    }
    try writer.save() // Empty saved store for A/B; captured seed for the positive control.
    let shared = ModelContext(container)
    shared.autosaveEnabled = false
    var setupMs = goalBackfillRecordElapsed(setupStart)
    #expect(!shared.hasChanges && !writer.hasChanges)
    var actual: [GoalBackfillRecordValue] = []
    var insertedPhysical: Set<UUID> = []
    var inserted = 0
    var wallMs = 0.0
    var cpuMs = 0.0
    let blockSize = 100
    var blockWalls = Array(repeating: 0.0, count: (keys.count + blockSize - 1) / blockSize)
    var blockCpus = blockWalls

    for (index, key) in keys.enumerated() {
        // B creates a new context on the SAME empty saved container for each
        // call. Its newly inserted row is inspected, then that unsaved context
        // is released; it cannot add pending rows to the next call. No save or
        // rollback is used to reset the measured call.
        try autoreleasepool {
            let context: ModelContext
            if mode == .freshContext {
                let contextStart = DispatchTime.now().uptimeNanoseconds
                let fresh = ModelContext(container)
                fresh.autosaveEnabled = false
                context = fresh
                setupMs += goalBackfillRecordElapsed(contextStart)
                #expect(!context.hasChanges && context.insertedModelsArray.isEmpty)
            } else {
                context = shared
            }

            let cpuStart = try goalBackfillRecordCPUms()
            let start = DispatchTime.now().uptimeNanoseconds
            let activity = try TaskActivityService.record(
                taskID: key.taskID, activityDayKey: key.day, occurredAt: key.occurredAt,
                origin: .legacyBackfill, createdAt: createdAt, in: context)
            let elapsed = goalBackfillRecordElapsed(start)
            let cpu = try goalBackfillRecordCPUms() - cpuStart
            wallMs += elapsed
            cpuMs += cpu
            blockWalls[index / blockSize] += elapsed
            blockCpus[index / blockSize] += cpu

            // Everything below is outside both record intervals.
            if mode == .alreadyCaptured {
                #expect(activity == nil && !context.hasChanges)
            } else {
                let activity = try #require(activity)
                inserted += 1
                #expect(insertedPhysical.insert(activity.instanceID).inserted)
                let value = GoalBackfillRecordValue(activity)
                #expect(value == expected[index])
                actual.append(value)
                #expect(context.hasChanges)
                if mode == .freshContext {
                    #expect(context.insertedModelsArray.compactMap { $0 as? TaskCompletionActivity }.count == 1)
                }
            }
        }
    }

    if mode == .freshContext {
        // These are N canonical unsaved outcomes across N isolated contexts,
        // NOT a single backfill that published N rows to the common store.
        #expect(inserted == keys.count && actual.count == keys.count)
        #expect(goalBackfillRecordDigest(actual) == expectedDigest)
        #expect(!shared.hasChanges && !writer.hasChanges)
        let verifier = ModelContext(container)
        verifier.autosaveEnabled = false
        #expect(try verifier.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 0)
    } else {
        let rows = try shared.fetch(FetchDescriptor<TaskCompletionActivity>())
        #expect(rows.count == keys.count && Set(rows.map(\.instanceID)).count == keys.count)
        #expect(goalBackfillRecordDigest(rows.map(GoalBackfillRecordValue.init)) == expectedDigest)
        if mode == .alreadyCaptured {
            #expect(inserted == 0 && !shared.hasChanges)
            let preserved = rows.map { "\($0.instanceID.uuidString)|\(GoalBackfillRecordValue($0).payload)" }
            #expect(Set(preserved) == Set(savedPhysical))
        } else {
            #expect(inserted == keys.count && shared.hasChanges)
            #expect(shared.insertedModelsArray.compactMap { $0 as? TaskCompletionActivity }.count == keys.count)
            let verifier = ModelContext(container)
            verifier.autosaveEnabled = false
            #expect(try verifier.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 0)
        }
    }
    withExtendedLifetime(container) {}
    return GoalBackfillRecordSample(wallMs: wallMs, processCpuMs: cpuMs, setupMs: setupMs,
                                   blockWallMs: blockWalls, blockCpuMs: blockCpus)
}

private func goalBackfillRecordReport(
    mode: GoalBackfillRecordMode, source: String, keys: Int, samples: [GoalBackfillRecordSample],
    setup: [Double], digest: String
) {
    let walls = samples.map(\.wallMs)
    let cpus = samples.map(\.processCpuMs)
    let inserted = mode == .alreadyCaptured ? 0 : keys
    let finalPending = mode == .growingPending ? keys : mode == .freshContext ? 1 : 0
    print("GOAL_BACKFILL_RECORD_BENCHMARK name=\(mode.rawValue) source=\(source) harness=v1 keys=\(keys) operationsPerSample=\(keys) store=in-memory scope=sum-of-actual-record-intervals unit=ms n=\(samples.count) warmup=1 saveTimed=false contextSetupTimed=false recordInsertTimed=true insertedOutcomesExpected=\(inserted) finalPendingPerContextExpected=\(finalPending) p50=\(goalBackfillRecordPercentile(walls, 0.5)) p95=\(goalBackfillRecordPercentile(walls, 0.95)) max=\(walls.max() ?? 0) processCpuP50=\(goalBackfillRecordPercentile(cpus, 0.5)) processCpuP95=\(goalBackfillRecordPercentile(cpus, 0.95)) processCpuMax=\(cpus.max() ?? 0) outputDigest=\(digest) samples=\(walls) processCpuSamples=\(cpus)")
    print("GOAL_BACKFILL_RECORD_BLOCKS name=\(mode.rawValue) source=\(source) keys=\(keys) blockSize=100 lastBlockOperations=\(keys % 100 == 0 ? 100 : keys % 100) scope=sum-of-record-intervals wallRawMs=\(samples.map(\.blockWallMs)) processCpuRawMs=\(samples.map(\.blockCpuMs))")
    print("GOAL_BACKFILL_RECORD_SETUP name=\(mode.rawValue) source=\(source) keys=\(keys) unit=ms timingOutsideRecord=true includesWarmup=true includesContainerContextSeedSave=true recordContextsPerSample=\(mode == .freshContext ? keys : 1) samples=\(setup)")
    print("GOAL_BACKFILL_RECORD_LIMITS name=\(mode.rawValue) source=\(source) actualFetchCount=unmeasured sqlStatements=unmeasured inputToFrame=unmeasured processCpuIncludesStoreThreads=true clockOverheadNotSubtracted=true freshContextOutcomeIsAggregateUnsavedValues=\(mode == .freshContext) totalBackfillOrSaveLatency=false")
}

private func goalBackfillRecordPercentile(_ samples: [Double], _ quantile: Double) -> Double {
    let ordered = samples.sorted()
    guard !ordered.isEmpty else { return 0 }
    if quantile == 0.5, ordered.count.isMultiple(of: 2) {
        return (ordered[ordered.count / 2 - 1] + ordered[ordered.count / 2]) / 2
    }
    return ordered[min(ordered.count - 1, max(0, Int(ceil(Double(ordered.count) * quantile)) - 1))]
}

private func goalBackfillRecordCPUms() throws -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
        throw NSError(domain: "GoalBackfillRecord.getrusage", code: Int(errno))
    }
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000
}

private func goalBackfillRecordElapsed(_ start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

private func goalBackfillRecordDigest(_ values: [GoalBackfillRecordValue]) -> String {
    let payload = "\(values.count)\n" + values.map(\.payload).sorted().joined(separator: "\n")
    return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func goalBackfillRecordID(namespace: Int, index: Int) -> UUID {
    UUID(uuidString: String(format: "31000000-0000-0000-%04X-%012X", namespace, index + 1))!
}
#endif
