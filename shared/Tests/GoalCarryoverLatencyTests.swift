#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Synthetic local-store measurements of the public mutation and inbox session
/// callbacks used by CarryoverInboxConnection. This is not a SwiftUI rendering,
/// installed-app, CloudKit, or input-to-frame measurement. Compile the identical
/// file in the baseline without PLANBASE_LATENCY_CANDIDATE_COMPAT and in the
/// candidate with it: only the session refresh callback switches to the new API.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_CARRYOVER_LATENCY"] == "1"))
@MainActor
func goalCarryoverLatency() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseCarryoverLatency-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let reference = try #require(DayKey.date(from: "2026-10-12"))
    let todayKey = DayKey.key(for: reference)
    let sampleCount = 20

    for count in [100, 1_000, 3_000] {
        let container = try PlanBaseContainerFactory.makePersistent(
            storeURL: directory.appendingPathComponent("tasks-\(count).store"), mode: .local)
        let context = container.mainContext
        context.autosaveEnabled = false
        try goalCarryoverLatencySeed(count: count, reference: reference, context: context)
        _ = try DataIntegrityService.reconcile(context: context)
        let normalized = try DataIntegrityService.reconcile(context: context, saveChanges: false)
        #expect(!normalized.hasChanges && !context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Task>()) == count)
        let baselineIDs = Set(try context.fetch(FetchDescriptor<Task>()).map(\.id))
        let target = try #require(context.fetch(
            BoundedQueryService.taskCandidatesDescriptor(id: goalCarryoverLatencyID(namespace: 1, index: 0))).first)
        let historicalDate = target.plannedAt
        let historicalDayKey = target.plannedDayKey
        let suite = "PlanBaseCarryoverLatency.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = CarryoverInboxSession(context: context, defaults: defaults)
        let revision = PersistenceViewRevision(context: context, domains: .tasks)

        // Normalize and perform the first real session load before repeated CRUD.
        // Both builds call the same existing full-load API here.
        let initialStart = DispatchTime.now().uptimeNanoseconds
        session.refresh(todayKey: todayKey)
        let initialLoadMilliseconds = goalCarryoverLatencyMilliseconds(since: initialStart)
        let initialDigest = try goalCarryoverLatencyValidate(session: session, context: context,
            todayKey: todayKey, expectedInboxCount: count, expectedTaskCount: count)

        var values: [String: [GoalCarryoverLatencySample]] = [:]
        for index in 0..<sampleCount {
            var createdID: UUID?
            let add = try await goalCarryoverLatencyMeasure(index: index, session: session,
                context: context, revision: revision, todayKey: todayKey,
                expectedInboxCount: count, expectedTaskCount: count + 1) {
                try PersistenceCommandService.perform(in: context) {
                    let order = try BoundedQueryService.nextOrder(in: context, dayKey: todayKey, status: .todo)
                    let task = Task(id: goalCarryoverLatencyID(namespace: 5, index: index),
                        instanceID: goalCarryoverLatencyID(namespace: 6, index: index),
                        title: "합성 오늘 추가 \(index)", plannedAt: reference, order: order,
                        createdAt: reference, updatedAt: reference)
                    createdID = task.id
                    context.insert(task)
                }
            }
            values["today-add", default: []].append(add)
            let deletionID = try #require(createdID)
            let deletion = try await goalCarryoverLatencyMeasure(index: index, session: session,
                context: context, revision: revision, todayKey: todayKey,
                expectedInboxCount: count, expectedTaskCount: count) {
                try PersistenceCommandService.perform(in: context) {
                    let candidates = try context.fetch(BoundedQueryService.taskCandidatesDescriptor(id: deletionID))
                    let task = try #require(BoundedQueryService.representativeTask(from: candidates))
                    try TaskRules.delete(task, from: context)
                }
            }
            values["today-delete", default: []].append(deletion)
            #expect(deletion.canonicalSHA256 == initialDigest)
        }

        for index in 0..<sampleCount {
            let move = try await goalCarryoverLatencyMeasure(index: index, session: session,
                context: context, revision: revision, todayKey: todayKey,
                expectedInboxCount: count - 1, expectedTaskCount: count) {
                try PersistenceCommandService.perform(in: context) {
                    _ = try TaskLifecycleService.bringToToday(target, in: context, order: target.order, now: reference)
                }
            }
            values["historical-move-to-today", default: []].append(move)
            let restore = try await goalCarryoverLatencyMeasure(index: index, session: session,
                context: context, revision: revision, todayKey: todayKey,
                expectedInboxCount: count, expectedTaskCount: count) {
                try PersistenceCommandService.perform(in: context) {
                    TaskRules.move(target, to: historicalDate, now: reference)
                }
            }
            values["historical-restore-date", default: []].append(restore)
            #expect(restore.canonicalSHA256 == initialDigest)
        }

        for index in 0..<sampleCount {
            let now = reference.addingTimeInterval(Double(3_600 + index * 2))
            let completion = try await goalCarryoverLatencyMeasure(index: index, session: session,
                context: context, revision: revision, todayKey: todayKey,
                expectedInboxCount: count - 1, expectedTaskCount: count) {
                try PersistenceCommandService.perform(in: context) {
                    _ = try TaskLifecycleService.applyStatus(.done, to: target, in: context,
                        now: now, completionDayKey: historicalDayKey)
                }
            }
            values["historical-complete", default: []].append(completion)
            let undo = try await goalCarryoverLatencyMeasure(index: index, session: session,
                context: context, revision: revision, todayKey: todayKey,
                expectedInboxCount: count, expectedTaskCount: count) {
                try PersistenceCommandService.perform(in: context) {
                    _ = try TaskLifecycleService.applyStatus(.todo, to: target, in: context,
                        now: now.addingTimeInterval(1))
                }
            }
            values["historical-return-to-todo", default: []].append(undo)
            #expect(undo.canonicalSHA256 == initialDigest)
        }

        for scenario in values.keys.sorted() {
            let samples = try #require(values[scenario])
            #expect(samples.count == sampleCount)
            let ordered = samples.map(\.totalMilliseconds).sorted()
            let report = GoalCarryoverLatencyReport(
                scenario: scenario, taskRows: count, sampleCount: sampleCount,
                refreshCallback: goalCarryoverLatencyCallbackName,
                initialSessionLoadMilliseconds: initialLoadMilliseconds,
                medianMilliseconds: ordered[sampleCount / 2],
                p95Milliseconds: ordered[Int(ceil(Double(sampleCount) * 0.95)) - 1],
                maximumMilliseconds: try #require(ordered.last), samples: samples)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let json = try #require(String(data: encoder.encode(report), encoding: .utf8))
            print("GOAL_CARRYOVER_LATENCY_JSON \(json)")
        }
        #expect(Set(try context.fetch(FetchDescriptor<Task>()).map(\.id)) == baselineIDs)
        #expect(!context.hasChanges)
        withExtendedLifetime(container) {}
    }
}

private struct GoalCarryoverLatencySample: Codable {
    let index: Int
    let mutationMilliseconds: Double
    let refreshMilliseconds: Double
    let totalMilliseconds: Double
    let viewRevisionDelta: Int
    let inboxCount: Int
    let canonicalSHA256: String
}

private struct GoalCarryoverLatencyReport: Codable {
    let scenario: String
    let taskRows: Int
    let sampleCount: Int
    let refreshCallback: String
    let initialSessionLoadMilliseconds: Double
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double
    let samples: [GoalCarryoverLatencySample]
}

private struct GoalCarryoverLatencyRow: Codable, Equatable {
    let id: UUID
    let instanceID: UUID
    let title: String
    let status: String
    let plannedDayKey: String
    let order: Double

    @MainActor init(_ task: Task) {
        id = task.id; instanceID = task.instanceID; title = task.title
        status = task.status; plannedDayKey = task.plannedDayKey; order = task.order
    }
}

@MainActor
private func goalCarryoverLatencyMeasure(
    index: Int, session: CarryoverInboxSession, context: ModelContext,
    revision: PersistenceViewRevision, todayKey: String,
    expectedInboxCount: Int, expectedTaskCount: Int,
    mutate: () throws -> Void
) async throws -> GoalCarryoverLatencySample {
    let previousRevision = revision.value
    let mutationStart = DispatchTime.now().uptimeNanoseconds
    try mutate()
    let mutationMilliseconds = goalCarryoverLatencyMilliseconds(since: mutationStart)
    let refreshStart = DispatchTime.now().uptimeNanoseconds
    // VisibleDataRefresh schedules its refresh callback after a main-actor yield.
    // Exercise that session callback once for the latest revision; do not put a
    // full inbox query into a made-up synchronous notification subscriber.
    await Swift.Task.yield()
#if PLANBASE_LATENCY_CANDIDATE_COMPAT
    session.refreshPendingChanges(todayKey: todayKey)
#else
    session.refresh(todayKey: todayKey)
#endif
    let refreshMilliseconds = goalCarryoverLatencyMilliseconds(since: refreshStart)
    let totalMilliseconds = goalCarryoverLatencyMilliseconds(since: mutationStart)
    let delta = revision.value - previousRevision
    #expect(delta > 0)
    // Query/count/equality checks are outside all measured intervals. They warm
    // subsequent local reads equally in both builds and are not rendered-frame evidence.
    let digest = try goalCarryoverLatencyValidate(session: session, context: context,
        todayKey: todayKey, expectedInboxCount: expectedInboxCount, expectedTaskCount: expectedTaskCount)
    return GoalCarryoverLatencySample(index: index, mutationMilliseconds: mutationMilliseconds,
        refreshMilliseconds: refreshMilliseconds, totalMilliseconds: totalMilliseconds,
        viewRevisionDelta: delta, inboxCount: session.count, canonicalSHA256: digest)
}

@MainActor
private func goalCarryoverLatencyValidate(
    session: CarryoverInboxSession, context: ModelContext, todayKey: String,
    expectedInboxCount: Int, expectedTaskCount: Int
) throws -> String {
    #expect(session.hasLoaded && session.errorMessage == nil)
    #expect(session.count == expectedInboxCount)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == expectedTaskCount)
    let actual = session.tasks.map(GoalCarryoverLatencyRow.init)
    let canonical = try CarryoverInboxRules.fetch(in: context, todayKey: todayKey)
        .map(GoalCarryoverLatencyRow.init)
    #expect(actual == canonical)
    #expect(Set(actual.map(\.id)).count == actual.count)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return SHA256.hash(data: try encoder.encode(actual)).map { String(format: "%02x", $0) }.joined()
}

@MainActor
private func goalCarryoverLatencySeed(count: Int, reference: Date, context: ModelContext) throws {
    for index in 0..<count {
        let day = DayKey.addingDays(-(1 + index % 30), to: reference)
        let start = day.addingTimeInterval(9 * 3_600)
        let task = Task(id: goalCarryoverLatencyID(namespace: 1, index: index),
            instanceID: goalCarryoverLatencyID(namespace: 2, index: index),
            title: "합성 이월 작업 \(index)", plannedAt: day, order: Double(index) * 100,
            createdAt: start, updatedAt: start.addingTimeInterval(1_800))
        context.insert(task)
        context.insert(TaskChecklistItem(taskId: task.id, title: "합성 항목", order: 100))
        for offset in 0...1 {
            let occurredAt = start.addingTimeInterval(Double(offset) * 1_800)
            context.insert(TaskProgressEvent(
                id: goalCarryoverLatencyID(namespace: 3, index: index * 2 + offset),
                instanceID: goalCarryoverLatencyID(namespace: 4, index: index * 2 + offset),
                taskId: task.id, kind: offset == 0 ? .started : .stopped,
                occurredAt: occurredAt, createdAt: occurredAt, updatedAt: occurredAt))
        }
        if index % 250 == 249 { try context.save() }
    }
    try context.save()
}

private func goalCarryoverLatencyMilliseconds(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

private func goalCarryoverLatencyID(namespace: UInt8, index: Int) -> UUID {
    let value = UInt64(index)
    return UUID(uuid: (0x61, 0x73, 0, namespace, 0, 0, 0x40, 0, 0x80, 0,
        UInt8((value >> 40) & 255), UInt8((value >> 32) & 255), UInt8((value >> 24) & 255),
        UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)))
}

private var goalCarryoverLatencyCallbackName: String {
#if PLANBASE_LATENCY_CANDIDATE_COMPAT
    "candidate: CarryoverInboxSession.refreshPendingChanges"
#else
    "baseline: CarryoverInboxSession.refresh"
#endif
}
#endif
