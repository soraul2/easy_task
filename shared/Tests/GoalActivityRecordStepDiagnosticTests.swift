#if DEBUG
import CryptoKit
import Darwin
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Fixed-pending component controls, not additive production instrumentation or
/// end-to-end backfill timing. Only the actual-record interval calls the public
/// product API; all other intervals are explicitly equivalent operation controls.
/// Saved-only controls return identifiers, never hydrate models or save contexts.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_ACTIVITY_RECORD_STEP_DIAGNOSTIC"] == "1"))
@MainActor
func goalActivityRecordStepDiagnostic() throws {
    let label = ProcessInfo.processInfo.environment["PLANBASE_GOAL_SOURCE_LABEL"] ?? "unspecified"
    for count in [100, 1_000, 2_760] {
        let fixture = try GoalActivityStepFixture(count: count)
        defer { withExtendedLifetime(fixture.container) {} }
        let before = goalActivityStepState(fixture.caller)
        let beforeDigest = goalActivityStepDigest(before.values)
        #expect(before.values.count == count && before.inserted.count == count)
        #expect(Set(before.values.map(\.task)).count == count)
        #expect(before.changed.isEmpty && before.deleted.isEmpty && fixture.caller.hasChanges)
        #expect(!fixture.reusedReader.hasChanges)
        let firstPending = goalActivityStepPending(fixture.caller).pending
        let target = try #require(firstPending.last)
        let key = GoalActivityStepKey(taskID: target.taskId, day: target.activityDayKey,
                                     occurredAt: target.occurredAt, createdAt: target.createdAt)
        let targetPhysical = target.persistentModelID
        let descriptor = goalActivityStepDescriptor(key)
        var samples: [String: [GoalActivityStepTime]] = [:]
        var observedPositions: [Int] = []
        var outputDigests: Set<String> = []
        for sample in -1..<30 {
            var timings: [String: GoalActivityStepTime] = [:]
            let arrays = try goalActivityStepMeasure { goalActivityStepPending(fixture.caller) }
            timings["pending-arrays"] = arrays.time
            let pending = arrays.value
            let sets = try goalActivityStepMeasure {
                let deletedIDs = Set(pending.deleted.map(\.persistentModelID))
                let excludedIDs = Set(pending.pending.map(\.persistentModelID)).union(deletedIDs)
                return GoalActivityStepIDs(deleted: deletedIDs, excluded: excludedIDs)
            }
            timings["pending-pid-sets"] = sets.time
            #expect(sets.value.deleted.isEmpty && sets.value.excluded == before.inserted)
            #expect(pending.pending.count == count && pending.deleted.isEmpty)
            let position = try #require(pending.pending.firstIndex { $0.persistentModelID == targetPhysical })
            if sample >= 0 { observedPositions.append(position) }

            // Reverse caller/reused order every sample to avoid a fixed query-order bias.
            var callerIDs: [PersistentIdentifier] = []
            var reusedIDs: [PersistentIdentifier] = []
            for callerFirst in (sample % 2 == 0 ? [true, false] : [false, true]) {
                let context = callerFirst ? fixture.caller : fixture.reusedReader
                let read = try goalActivityStepMeasure { try context.fetchIdentifiers(descriptor) }
                if callerFirst {
                    callerIDs = read.value
                    timings["saved-identifiers-caller-dirty"] = read.time
                } else {
                    reusedIDs = read.value
                    timings["saved-identifiers-reused-clean"] = read.time
                }
            }
            // Creation is separately timed; lifetime/deinitialization is outside it.
            let fresh = try goalActivityStepMeasure {
                let context = ModelContext(fixture.container)
                context.autosaveEnabled = false
                return context
            }
            timings["fresh-context-create"] = fresh.time
            let freshIDs = try goalActivityStepMeasure { try fresh.value.fetchIdentifiers(descriptor) }
            timings["saved-identifiers-fresh-clean"] = freshIDs.time
            // Also measure one uninterrupted creation+query control. Return its context
            // so deinitialization does not silently enter that interval.
            let combined = try goalActivityStepMeasure {
                let context = ModelContext(fixture.container)
                context.autosaveEnabled = false
                return GoalActivityStepFreshRead(context: context,
                                                identifiers: try context.fetchIdentifiers(descriptor))
            }
            timings["fresh-context-create-and-saved-identifiers"] = combined.time
            #expect(callerIDs.isEmpty && reusedIDs.isEmpty && freshIDs.value.isEmpty
                    && combined.value.identifiers.isEmpty)
            #expect(!fresh.value.hasChanges && !combined.value.context.hasChanges && !fixture.reusedReader.hasChanges)

            var originalMatch = false, taskFirstMatch = false
            for originalFirst in (sample % 2 == 0 ? [true, false] : [false, true]) {
                if originalFirst {
                    let original = try goalActivityStepMeasure {
                        pending.pending.contains { activity in
                            !sets.value.deleted.contains(activity.persistentModelID) &&
                                activity.supersededAt == nil && activity.taskId == key.taskID &&
                                activity.activityDayKey == key.day
                            // Requested legacy backfill accepts any active origin.
                        }
                    }
                    timings["pending-match-original"] = original.time
                    originalMatch = original.value
                } else {
                    let taskFirst = try goalActivityStepMeasure {
                        pending.pending.contains { activity in
                            activity.taskId == key.taskID && activity.activityDayKey == key.day &&
                                activity.supersededAt == nil && !sets.value.deleted.contains(activity.persistentModelID)
                        }
                    }
                    timings["pending-match-task-day-first"] = taskFirst.time
                    taskFirstMatch = taskFirst.value
                }
            }
            #expect(originalMatch && taskFirstMatch)
            let actual = try goalActivityStepMeasure {
                try TaskActivityService.record(taskID: key.taskID, activityDayKey: key.day,
                    occurredAt: key.occurredAt, origin: .legacyBackfill, createdAt: key.createdAt,
                    in: fixture.caller)
            }
            timings["actual-record-existing-pending"] = actual.time
            #expect(actual.value == nil) // No insertion/reset/save occurs in a timed interval.

            // All checks and digests are outside component timers. Stored IDs remain
            // empty; this deliberately does not use model fetch/count/hydration.
            let after = goalActivityStepState(fixture.caller)
            #expect(after == before && goalActivityStepDigest(after.values) == beforeDigest)
            #expect(fixture.caller.hasChanges)
            let allStored = try fixture.reusedReader.fetchIdentifiers(FetchDescriptor<TaskCompletionActivity>())
            #expect(allStored.isEmpty && !fixture.reusedReader.hasChanges)
            let outcome = "pending=\(pending.pending.count)|deleted=\(pending.deleted.count)|excluded=\(sets.value.excluded.count)|caller=\(callerIDs.count)|reused=\(reusedIDs.count)|fresh=\(freshIDs.value.count)|combined=\(combined.value.identifiers.count)|original=\(originalMatch)|taskFirst=\(taskFirstMatch)|record=nil|fields=\(beforeDigest)"
            outputDigests.insert(goalActivityStepHash(outcome))
            if sample >= 0 {
                for (name, timing) in timings { samples[name, default: []].append(timing) }
            }
            withExtendedLifetime(fresh.value) {}
            withExtendedLifetime(combined.value.context) {}
        }
        #expect(outputDigests.count == 1)
        for name in samples.keys.sorted() {
            goalActivityStepReport(name: name, count: count, source: label,
                times: samples[name] ?? [], digest: outputDigests.first ?? "missing",
                fieldsDigest: beforeDigest)
        }
        print("GOAL_ACTIVITY_STEP_POSITIONS source=\(label) pending=\(count) requested=last-initial-captured-pending-array targetIndexRaw=\(observedPositions) originalContainsUsesCapturedArray=true actualRecordPrivateArrayOrder=unobserved")
        print("GOAL_ACTIVITY_STEP_LIMITS source=\(label) pending=\(count) fixedContext=true savedRows=0 pendingRowsAllInserted=true origin=legacyBackfill actualRecordReturnsNil=true insertTimed=false saveTimed=false modelHydrationRequestedByControls=false actualRecordFetchImplementation=product descriptorConstructionTimed=false fixtureSetupTimed=false validationTimed=false additiveAttribution=false productionInstrumentation=false savedQueryFreshnessOrErrors=unmeasured sqlStatements=unmeasured peakMemory=unmeasured inputToFrame=unmeasured processCpuIncludesStoreThreads=true clockOverheadNotSubtracted=true freshCreationQueryExcludesContextDestruction=true warmStore=true independentRuns=1")
    }
}

private struct GoalActivityStepKey {
    let taskID: UUID
    let day: String
    let occurredAt: Date
    let createdAt: Date
}

@MainActor
private struct GoalActivityStepFixture {
    let container: ModelContainer
    let caller: ModelContext
    let reusedReader: ModelContext
    init(count: Int) throws {
        container = try PlanBaseContainerFactory.makeInMemory()
        caller = container.mainContext
        caller.autosaveEnabled = false
        try caller.save() // Prepare a real, empty saved store outside all intervals.
        reusedReader = ModelContext(container)
        reusedReader.autosaveEnabled = false
        let date = Date(timeIntervalSince1970: 1_790_899_200)
        let day = "2026-10-02"
        for index in 0..<count {
            let suffix = String(format: "%012x", index)
            let taskID = UUID(uuidString: "d1090001-0000-4000-8000-\(suffix)")!
            caller.insert(TaskCompletionActivity(id: TaskActivityRules.logicalID(taskID: taskID, activityDayKey: day),
                instanceID: UUID(uuidString: "d1090002-0000-4000-8000-\(suffix)")!,
                taskId: taskID, activityDayKey: day, occurredAt: date.addingTimeInterval(Double(index)),
                origin: .legacyBackfill, createdAt: date, updatedAt: date))
        }
    }
}

@MainActor
private struct GoalActivityStepPending {
    let pending: [TaskCompletionActivity]
    let deleted: [TaskCompletionActivity]
}

@MainActor
private func goalActivityStepPending(_ context: ModelContext) -> GoalActivityStepPending {
    GoalActivityStepPending(pending: (context.insertedModelsArray + context.changedModelsArray)
        .compactMap { $0 as? TaskCompletionActivity },
        deleted: context.deletedModelsArray.compactMap { $0 as? TaskCompletionActivity })
}

private struct GoalActivityStepIDs {
    let deleted: Set<PersistentIdentifier>
    let excluded: Set<PersistentIdentifier>
}

@MainActor
private struct GoalActivityStepFreshRead {
    let context: ModelContext
    let identifiers: [PersistentIdentifier]
}

private struct GoalActivityStepTime { let wallMs: Double; let cpuMs: Double }
private struct GoalActivityStepMeasurement<Value> { let value: Value; let time: GoalActivityStepTime }

@MainActor
private func goalActivityStepMeasure<Value>(_ body: () throws -> Value) throws -> GoalActivityStepMeasurement<Value> {
    let cpuStart = try goalActivityStepCPU()
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try body()
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    let cpu = try goalActivityStepCPU() - cpuStart
    return GoalActivityStepMeasurement(value: value, time: GoalActivityStepTime(wallMs: elapsed, cpuMs: cpu))
}

@MainActor
private func goalActivityStepDescriptor(_ key: GoalActivityStepKey) -> FetchDescriptor<TaskCompletionActivity> {
    var descriptor = TaskActivityService.activeDescriptor(taskID: key.taskID, activityDayKey: key.day)
    descriptor.includePendingChanges = false
    descriptor.sortBy = []
    return descriptor
}

private struct GoalActivityStepValue: Equatable {
    let logical: UUID
    let physical: UUID
    let task: UUID
    let day: String
    let occurred: Date
    let origin: String
    let created: Date
    let updated: Date
    let superseded: Date?
    @MainActor init(_ activity: TaskCompletionActivity) {
        logical = activity.id; physical = activity.instanceID; task = activity.taskId
        day = activity.activityDayKey; occurred = activity.occurredAt; origin = activity.originRawValue
        created = activity.createdAt; updated = activity.updatedAt; superseded = activity.supersededAt
    }
    var payload: String {
        [logical.uuidString, physical.uuidString, task.uuidString, day,
         String(occurred.timeIntervalSince1970.bitPattern), origin,
         String(created.timeIntervalSince1970.bitPattern), String(updated.timeIntervalSince1970.bitPattern),
         superseded.map { String($0.timeIntervalSince1970.bitPattern) } ?? "nil"].joined(separator: "|")
    }
}

private struct GoalActivityStepState: Equatable {
    let values: [GoalActivityStepValue]
    let inserted: Set<PersistentIdentifier>
    let changed: Set<PersistentIdentifier>
    let deleted: Set<PersistentIdentifier>
}

@MainActor
private func goalActivityStepState(_ context: ModelContext) -> GoalActivityStepState {
    let inserted = context.insertedModelsArray.compactMap { $0 as? TaskCompletionActivity }
    let changed = context.changedModelsArray.compactMap { $0 as? TaskCompletionActivity }
    let deleted = context.deletedModelsArray.compactMap { $0 as? TaskCompletionActivity }
    var byPhysical: [UUID: GoalActivityStepValue] = [:]
    for row in inserted + changed + deleted { byPhysical[row.instanceID] = GoalActivityStepValue(row) }
    return GoalActivityStepState(values: byPhysical.values.sorted { $0.physical.uuidString < $1.physical.uuidString },
        inserted: Set(inserted.map(\.persistentModelID)), changed: Set(changed.map(\.persistentModelID)),
        deleted: Set(deleted.map(\.persistentModelID)))
}

private func goalActivityStepCPU() throws -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
        throw NSError(domain: "GoalActivityRecordStep.getrusage", code: Int(errno))
    }
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000
}

private func goalActivityStepDigest(_ values: [GoalActivityStepValue]) -> String {
    goalActivityStepHash("\(values.count)\n" + values.map(\.payload).sorted().joined(separator: "\n"))
}

private func goalActivityStepHash(_ payload: String) -> String {
    SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func goalActivityStepPercentile(_ values: [Double], _ q: Double) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    if q == 0.5 && sorted.count.isMultiple(of: 2) {
        return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }
    return sorted[min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * q)) - 1))]
}

private func goalActivityStepReport(name: String, count: Int, source: String,
                                  times: [GoalActivityStepTime], digest: String, fieldsDigest: String) {
    let wall = times.map(\.wallMs), cpu = times.map(\.cpuMs)
    print("GOAL_ACTIVITY_STEP component=\(name) source=\(source) harness=v1 pending=\(count) n=\(times.count) warmup=1 unit=ms scope=one-fixed-pending-component-call p50=\(goalActivityStepPercentile(wall, 0.5)) p95=\(goalActivityStepPercentile(wall, 0.95)) max=\(wall.max() ?? 0) processCpuP50=\(goalActivityStepPercentile(cpu, 0.5)) processCpuP95=\(goalActivityStepPercentile(cpu, 0.95)) processCpuMax=\(cpu.max() ?? 0) outputDigest=\(digest) fieldsDigest=\(fieldsDigest) wallRawMs=\(wall) processCpuRawMs=\(cpu)")
}
#endif
