#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Only the synchronous backfill call is timed. Store creation, inserts/save,
/// reports, complete record digests, and correctness controls are untimed.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_BACKFILL_PERFORMANCE"] == "1"))
@MainActor
func goalBackfillPerformance() throws {
    let completion = try #require(ISO8601DateFormatter().date(from: "2026-10-01T23:30:00Z"))
    let createdAt = completion.addingTimeInterval(86_400)
    for (count, samples) in [(100, 30), (1_000, 10), (2_760, 5)] {
        for alreadyCaptured in [true, false] {
            let name = alreadyCaptured ? "clean-already-captured" : "legacy-missing-new-context"
            var raw: [Double] = []
            var setup: [Double] = []
            var digest: String?
            // No-op repeats the same clean context. Missing activity repeats need
            // a fresh saved fixture: rollback/reset time never enters the interval.
            var reusable: GoalBackfillFixture?
            if alreadyCaptured {
                let start = DispatchTime.now().uptimeNanoseconds
                reusable = try goalBackfillFixture(count: count, completion: completion, captured: true)
                setup.append(goalBackfillElapsed(start))
            }
            for sample in -1..<samples { // One untimed warm-up with identical preconditions.
                try autoreleasepool {
                    let fixture: GoalBackfillFixture
                    if let reusable {
                        fixture = reusable
                    } else {
                        let start = DispatchTime.now().uptimeNanoseconds
                        fixture = try goalBackfillFixture(count: count, completion: completion, captured: false)
                        setup.append(goalBackfillElapsed(start))
                    }
                    #expect(!fixture.context.hasChanges)
                    let taskDigest = try goalBackfillTaskDigest(in: fixture.context)
                    let preserved = fixture.activities.map(goalBackfillPhysicalValue)
                    let expected = alreadyCaptured
                        ? fixture.activities.map(GoalBackfillActivityValue.init)
                        : fixture.tasks.map { goalBackfillExpectedLegacy($0, createdAt: createdAt) }
                    let expectedReport = TaskActivityBackfillReport(
                        scannedTasks: count, insertedActivities: alreadyCaptured ? 0 : count)
                    let expectedDigest = goalBackfillDigest(report: expectedReport, records: expected)
                    if let digest { #expect(digest == expectedDigest) } else { digest = expectedDigest }

                    let report: TaskActivityBackfillReport
                    if sample < 0 {
                        report = try TaskActivityBackfillService.backfillLegacyCompletions(in: fixture.context, createdAt: createdAt)
                    } else {
                        let start = DispatchTime.now().uptimeNanoseconds
                        report = try TaskActivityBackfillService.backfillLegacyCompletions(in: fixture.context, createdAt: createdAt)
                        raw.append(goalBackfillElapsed(start))
                    }

                    try goalBackfillValidate(
                        fixture, report: report, expectedReport: expectedReport, expected: expected,
                        taskDigest: taskDigest, preserved: preserved)
                    #expect(fixture.context.hasChanges == !alreadyCaptured)
                }
            }
            goalBackfillReport(name: name, count: count, samples: raw, digest: try #require(digest))
            print("GOAL_BACKFILL_SETUP name=\(name) eligible=\(count) unit=ms setupTimedInBackfill=false includesContainerInsertSave=true includesMissingWarmup=\(!alreadyCaptured) freshContexts=\(alreadyCaptured ? 1 : samples + 1) samples=\(setup)")
        }
    }
    try goalBackfillDirtyPendingControl(completion: completion, createdAt: createdAt)
    try goalBackfillPreflightCounterexamples(completion: completion, createdAt: createdAt)
    try goalBackfillCancellationControl(completion: completion, createdAt: createdAt)
    print("GOAL_BACKFILL_CONTROLS dirtyPending=completed preflightLimitWrongIDDayPhysicalTies=completed cancellationRollback=completed assertionOutcome=swift-testing timed=false")
}

private struct GoalBackfillFixture {
    var container: ModelContainer // Keep the isolated store alive through validation.
    var context: ModelContext
    var tasks: [Task]
    var activities: [TaskCompletionActivity]
}

@MainActor
private func goalBackfillFixture(count: Int, completion: Date, captured: Bool) throws -> GoalBackfillFixture {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let tasks = (0..<count).map { goalBackfillTask(index: $0, completion: completion) }
    var activities: [TaskCompletionActivity] = []
    for task in tasks {
        context.insert(task)
        if captured {
            let activity = goalBackfillCaptured(task, instanceID: goalBackfillID(namespace: 3, index: activities.count))
            context.insert(activity)
            activities.append(activity)
        }
    }
    try context.save()
    return GoalBackfillFixture(container: container, context: context, tasks: tasks, activities: activities)
}

private func goalBackfillTask(index: Int, completion: Date, logicalID: UUID? = nil) -> Task {
    let occurredAt = completion.addingTimeInterval(Double(index % 5) * 60)
    let task = Task(
        id: logicalID ?? goalBackfillID(namespace: 1, index: index),
        instanceID: goalBackfillID(namespace: 2, index: index), title: "Backfill \(index)",
        status: .done, plannedAt: completion.addingTimeInterval(-2 * 86_400), order: Double(index),
        createdAt: completion.addingTimeInterval(-30 * 86_400), updatedAt: occurredAt.addingTimeInterval(5))
    task.completedAt = occurredAt
    task.completedDayKey = "2026-09-29" // Backdated board meaning must not choose the activity day.
    return task
}

private func goalBackfillCaptured(_ task: Task, instanceID: UUID) -> TaskCompletionActivity {
    let occurredAt = task.completedAt!
    let day = TaskActivityRules.legacyDayKey(for: occurredAt)
    return TaskCompletionActivity(
        id: TaskActivityRules.logicalID(taskID: task.id, activityDayKey: day), instanceID: instanceID,
        taskId: task.id, activityDayKey: day, occurredAt: occurredAt, origin: .captured,
        createdAt: occurredAt.addingTimeInterval(1), updatedAt: occurredAt.addingTimeInterval(2))
}

private struct GoalBackfillActivityValue {
    var id: UUID
    var taskID: UUID
    var day: String
    var occurredAt: Date
    var origin: String
    var createdAt: Date
    var updatedAt: Date
    var supersededAt: Date?

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

    init(task: Task, createdAt: Date) {
        taskID = task.id
        occurredAt = task.completedAt!
        day = TaskActivityRules.legacyDayKey(for: occurredAt)
        id = TaskActivityRules.logicalID(taskID: taskID, activityDayKey: day)
        origin = TaskCompletionActivityOrigin.legacyBackfill.rawValue
        self.createdAt = createdAt
        updatedAt = createdAt
        supersededAt = nil
    }

    var payload: String {
        [id.uuidString, taskID.uuidString, day, goalBackfillDate(occurredAt), origin,
         goalBackfillDate(createdAt), goalBackfillDate(updatedAt), goalBackfillDate(supersededAt)].joined(separator: "|")
    }
}

private func goalBackfillExpectedLegacy(_ task: Task, createdAt: Date) -> GoalBackfillActivityValue {
    GoalBackfillActivityValue(task: task, createdAt: createdAt)
}

private func goalBackfillPhysicalValue(_ activity: TaskCompletionActivity) -> String {
    "\(activity.instanceID.uuidString)|\(GoalBackfillActivityValue(activity).payload)"
}

@MainActor
private func goalBackfillValidate(
    _ fixture: GoalBackfillFixture, report: TaskActivityBackfillReport,
    expectedReport: TaskActivityBackfillReport, expected: [GoalBackfillActivityValue],
    taskDigest: String, preserved: [String]
) throws {
    let rows = try fixture.context.fetch(FetchDescriptor<TaskCompletionActivity>())
    #expect(report == expectedReport)
    #expect(rows.count == expected.count)
    #expect(Set(rows.map(\.instanceID)).count == rows.count)
    #expect(goalBackfillDigest(report: report, records: rows.map(GoalBackfillActivityValue.init))
        == goalBackfillDigest(report: expectedReport, records: expected))
    #expect(Set(preserved).isSubset(of: Set(rows.map(goalBackfillPhysicalValue))))
    #expect(try goalBackfillTaskDigest(in: fixture.context) == taskDigest)
}

@MainActor
private func goalBackfillDirtyPendingControl(completion: Date, createdAt: Date) throws {
    var fixture = try goalBackfillFixture(count: 100, completion: completion, captured: true)
    let context = fixture.context
    context.delete(fixture.activities[0])
    fixture.tasks[1].completedAt = completion.addingTimeInterval(86_400)
    fixture.tasks[2].status = TaskStatus.todo.rawValue
    fixture.tasks[2].completedAt = nil
    context.delete(fixture.tasks[3])
    fixture.tasks[4].supersededAt = createdAt
    fixture.activities[5].supersededAt = createdAt
    fixture.activities[6].activityDayKey = TaskActivityRules.legacyDayKey(for: completion.addingTimeInterval(86_400))
    let missing = goalBackfillTask(index: 100, completion: completion)
    let covered = goalBackfillTask(index: 101, completion: completion)
    context.insert(missing)
    context.insert(covered)
    let pendingActivity = goalBackfillCaptured(covered, instanceID: goalBackfillID(namespace: 3, index: 101))
    context.insert(pendingActivity)
    fixture.tasks += [missing, covered]
    #expect(context.hasChanges)
    let before = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
    let expected = before.map(GoalBackfillActivityValue.init)
        + [fixture.tasks[0], fixture.tasks[1], fixture.tasks[5], fixture.tasks[6], missing]
            .map { goalBackfillExpectedLegacy($0, createdAt: createdAt) }
    let taskDigest = try goalBackfillTaskDigest(in: context)
    let report = try TaskActivityBackfillService.backfillLegacyCompletions(in: context, createdAt: createdAt)
    try goalBackfillValidate(
        fixture, report: report, expectedReport: .init(scannedTasks: 99, insertedActivities: 5),
        expected: expected, taskDigest: taskDigest, preserved: before.map(goalBackfillPhysicalValue))
}

@MainActor
private func goalBackfillPreflightCounterexamples(completion: Date, createdAt: Date) throws {
    var fixture = try goalBackfillFixture(count: 4, completion: completion, captured: true)
    let context = fixture.context
    // Activity presence is a natural-key test, not an ID/valid-origin test.
    fixture.activities[0].originRawValue = TaskCompletionActivityOrigin.legacyBackfill.rawValue
    fixture.activities[1].id = goalBackfillID(namespace: 9, index: 1)
    fixture.activities[1].originRawValue = "unknown-origin"
    fixture.activities[2].activityDayKey = TaskActivityRules.legacyDayKey(for: completion.addingTimeInterval(86_400))
    fixture.activities[3].supersededAt = createdAt
    for index in 0..<2 {
        let duplicate = goalBackfillCaptured(fixture.tasks[0], instanceID: goalBackfillID(namespace: 0, index: index))
        duplicate.originRawValue = TaskCompletionActivityOrigin.legacyBackfill.rawValue
        context.insert(duplicate) // Equal updatedAt, distinct physical records must remain.
    }
    let sameDayCopy = goalBackfillTask(index: 10, completion: completion, logicalID: fixture.tasks[0].id)
    let differentDayCopy = goalBackfillTask(index: 11, completion: completion.addingTimeInterval(86_400), logicalID: fixture.tasks[0].id)
    context.insert(sameDayCopy)
    context.insert(differentDayCopy)
    fixture.tasks += [sameDayCopy, differentDayCopy]
    try context.save()

    // A test-only positive preflight sketch. A cap/duplicate/wrong-ID miss is
    // not proof of absence: the unchanged service below is the ground truth.
    let canonicalIDs = fixture.tasks.map {
        TaskActivityRules.logicalID(taskID: $0.id, activityDayKey: TaskActivityRules.legacyDayKey(for: $0.completedAt!))
    }
    var descriptor = FetchDescriptor<TaskCompletionActivity>(predicate: #Predicate {
        $0.supersededAt == nil && canonicalIDs.contains($0.id)
    }, sortBy: [SortDescriptor(\TaskCompletionActivity.instanceID)])
    descriptor.fetchLimit = 2
    descriptor.includePendingChanges = false
    let prefix = try context.fetch(descriptor)
    #expect(prefix.count == 2)
    #expect(prefix.allSatisfy { $0.taskId == fixture.tasks[0].id })
    #expect(!prefix.contains { $0.taskId == fixture.tasks[1].id })
    #expect(!context.hasChanges)

    let before = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
    let expected = before.map(GoalBackfillActivityValue.init)
        + [fixture.tasks[2], fixture.tasks[3], differentDayCopy].map { goalBackfillExpectedLegacy($0, createdAt: createdAt) }
    let taskDigest = try goalBackfillTaskDigest(in: context)
    let report = try TaskActivityBackfillService.backfillLegacyCompletions(in: context, createdAt: createdAt)
    try goalBackfillValidate(
        fixture, report: report, expectedReport: .init(scannedTasks: 6, insertedActivities: 3),
        expected: expected, taskDigest: taskDigest, preserved: before.map(goalBackfillPhysicalValue))
}

@MainActor
private func goalBackfillCancellationControl(completion: Date, createdAt: Date) throws {
    let fixture = try goalBackfillFixture(count: 4, completion: completion, captured: false)
    let taskDigest = try goalBackfillTaskDigest(in: fixture.context)
    var checks = 0
    #expect(throws: CancellationError.self) {
        try PersistenceCommandService.perform(in: fixture.context) {
            try TaskActivityBackfillService.backfillLegacyCompletions(
                in: fixture.context, createdAt: createdAt,
                isCancelled: { checks += 1; return checks > 4 })
        }
    }
    #expect(checks == 5)
    #expect(try fixture.context.fetch(FetchDescriptor<TaskCompletionActivity>()).isEmpty)
    #expect(try goalBackfillTaskDigest(in: fixture.context) == taskDigest)
    #expect(!fixture.context.hasChanges)
}

@MainActor
private func goalBackfillTaskDigest(in context: ModelContext) throws -> String {
    let rows = try context.fetch(FetchDescriptor<Task>()).map { task in
        [task.id.uuidString, task.instanceID.uuidString, task.title, task.status, task.plannedDayKey,
         goalBackfillDate(task.plannedAt), String(task.order), task.completedDayKey ?? "nil",
         goalBackfillDate(task.completedAt), task.archivedDayKey ?? "nil", goalBackfillDate(task.archivedAt),
         goalBackfillDate(task.createdAt), goalBackfillDate(task.updatedAt), goalBackfillDate(task.supersededAt)].joined(separator: "|")
    }
    return goalBackfillSHA(rows.sorted().joined(separator: "\n"))
}

private func goalBackfillDigest(report: TaskActivityBackfillReport, records: [GoalBackfillActivityValue]) -> String {
    goalBackfillSHA("\(report.scannedTasks)|\(report.insertedActivities)\n" + records.map(\.payload).sorted().joined(separator: "\n"))
}

private func goalBackfillReport(name: String, count: Int, samples: [Double], digest: String) {
    let sorted = samples.sorted()
    let n = samples.count
    let median = n.isMultiple(of: 2) ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2 : sorted[n / 2]
    let p95 = sorted[min(n - 1, Int(ceil(Double(n) * 0.95)) - 1)]
    print("GOAL_BACKFILL_BENCHMARK name=\(name) eligible=\(count) store=in-memory scope=backfill-only saveTimed=false unit=ms n=\(n) warmup=1 p50=\(median) p95=\(p95) max=\(sorted[n - 1]) outputDigest=\(digest) samples=\(samples)")
}

private func goalBackfillElapsed(_ start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

private func goalBackfillDate(_ date: Date?) -> String {
    date.map { String($0.timeIntervalSince1970) } ?? "nil"
}

private func goalBackfillSHA(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func goalBackfillID(namespace: Int, index: Int) -> UUID {
    UUID(uuidString: String(format: "30000000-0000-0000-%04X-%012X", namespace, index + 1))!
}
#endif
