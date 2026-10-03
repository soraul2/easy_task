#if DEBUG
import CryptoKit
import Darwin
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Measures one actual atomic PersistenceCommandService.perform, including its
/// pre-save, N applyStatus(.done) transitions, final save and synchronous change
/// notification. Each warmup/sample uses a new in-memory container with N saved
/// doing Tasks and N deterministic saved started events. Setup/save, assertions,
/// independent-context reads, hashes and repeat/rollback controls are untimed.
///
/// The production stop recorder creates random logical/physical UUIDs and uses
/// Date() for createdAt/updatedAt; completion physical UUIDs are also generated.
/// Canonical output substitutes ONLY those generated fields with task-bound role
/// tokens AFTER checking uniqueness, persisted values and command clock bounds.
/// Full raw digests retain every generated UUID/time and therefore are NOT
/// expected to match across samples. All Task fields, stop occurredAt, completion
/// logical ID/day/time/origin, pending state and physical counts remain actual
/// values in the canonical digest. This is an atomic-completion benchmark, not
/// record-only lookup time, application input-to-frame or CloudKit latency.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_CAPTURED_COMPLETION_PERFORMANCE"] == "1"))
@MainActor
func goalCapturedCompletionPerformance() throws {
    let completion = try #require(ISO8601DateFormatter().date(from: "2026-10-02T03:00:00Z"))
    let source = ProcessInfo.processInfo.environment["PLANBASE_GOAL_SOURCE_LABEL"] ?? "unspecified"
    try goalCapturedCompletionRepeatControl(completion: completion)
    try goalCapturedCompletionRollbackControl(completion: completion)

    for (count, sampleCount) in [(1, 30), (100, 30), (1_000, 5)] {
        let expected = goalCapturedCompletionExpectedPayload(count: count, completion: completion)
        let expectedDigest = goalCapturedCompletionSHA(expected)
        var samples: [GoalCapturedCompletionSample] = []
        var setupSamples: [Double] = []
        var rawDigests: [String] = []
        for sample in -1..<sampleCount {
            let measured = try autoreleasepool {
                try goalCapturedCompletionSample(count: count, completion: completion,
                                                 expectedPayload: expected)
            }
            #expect(measured.canonicalDigest == expectedDigest)
            setupSamples.append(measured.setupMs)
            if sample >= 0 {
                samples.append(measured)
                rawDigests.append(measured.rawDigest)
            }
        }
        goalCapturedCompletionReport(count: count, source: source, samples: samples,
                                     setupSamples: setupSamples, canonicalDigest: expectedDigest,
                                     rawDigests: rawDigests)
    }
}

private struct GoalCapturedCompletionFixture {
    let container: ModelContainer
    let context: ModelContext
    let tasks: [Task]
    let setupMs: Double
}

private struct GoalCapturedCompletionSample {
    let wallMs: Double
    let processCpuMs: Double
    let setupMs: Double
    let canonicalDigest: String
    let rawDigest: String
}

private struct GoalCapturedCompletionRead {
    let context: ModelContext
    let tasks: [Task]
    let progress: [TaskProgressEvent]
    let completions: [TaskCompletionActivity]
}

@MainActor
private func goalCapturedCompletionFixture(count: Int, completion: Date) throws -> GoalCapturedCompletionFixture {
    let start = DispatchTime.now().uptimeNanoseconds
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let plannedAt = DayKey.startOfDay(for: completion.addingTimeInterval(-86_400))
    var tasks: [Task] = []
    for index in 0..<count {
        let startedAt = goalCapturedCompletionStart(index: index, completion: completion)
        let task = Task(
            id: goalCapturedCompletionID(namespace: 1, index: index),
            instanceID: goalCapturedCompletionID(namespace: 2, index: index),
            title: "완료 성능 fixture \(index)", note: "시작과 완료를 함께 저장",
            status: .doing, plannedAt: plannedAt, order: Double((index + 1) * 100),
            eventId: goalCapturedCompletionID(namespace: 5, index: index),
            templatePlacementId: goalCapturedCompletionID(namespace: 6, index: index),
            priority: .high, tags: ["fixture", String(index % 3)],
            estimatedMinutes: 25 + index % 5,
            reminderAt: completion.addingTimeInterval(3_600 + Double(index)),
            createdAt: completion.addingTimeInterval(-86_400 + Double(index)), updatedAt: startedAt)
        context.insert(task)
        context.insert(TaskProgressEvent(
            id: goalCapturedCompletionID(namespace: 3, index: index),
            instanceID: goalCapturedCompletionID(namespace: 4, index: index),
            taskId: task.id, kind: .started, origin: .captured, occurredAt: startedAt,
            createdAt: startedAt.addingTimeInterval(1), updatedAt: startedAt.addingTimeInterval(2)))
        tasks.append(task)
    }
    try context.save()
    let setupMs = goalCapturedCompletionElapsed(start)
    #expect(!context.hasChanges)
    #expect(context.insertedModelsArray.isEmpty && context.changedModelsArray.isEmpty && context.deletedModelsArray.isEmpty)
    return GoalCapturedCompletionFixture(container: container, context: context, tasks: tasks, setupMs: setupMs)
}

@MainActor
private func goalCapturedCompletionSample(
    count: Int, completion: Date, expectedPayload: String
) throws -> GoalCapturedCompletionSample {
    let fixture = try goalCapturedCompletionFixture(count: count, completion: completion)
    let commandClockStart = Date()
    let cpuStart = try goalCapturedCompletionCPUms()
    let start = DispatchTime.now().uptimeNanoseconds
    let transitions = try PersistenceCommandService.perform(in: fixture.context) {
        try fixture.tasks.map { task in
            try TaskLifecycleService.applyStatus(.done, to: task, in: fixture.context, now: completion)
        }
    }
    let wallMs = goalCapturedCompletionElapsed(start)
    let processCpuMs = try goalCapturedCompletionCPUms() - cpuStart
    let commandClockEnd = Date()

    // No assertion, model read, normalization, fixture work or hash is timed.
    #expect(transitions.count == count)
    #expect(transitions.allSatisfy {
        $0 == TaskLifecycleTransitionResult(didChange: true, didComplete: true,
                                           activityInserted: true, progressEventKind: .stopped)
    })
    let read = try goalCapturedCompletionRead(in: fixture.container)
    #expect(read.context !== fixture.context)
    let canonical = try goalCapturedCompletionValidate(
        read, count: count, completion: completion, sourceContext: fixture.context,
        commandClockStart: commandClockStart, commandClockEnd: commandClockEnd)
    #expect(canonical == expectedPayload)
    let raw = goalCapturedCompletionRawPayload(read, sourceContext: fixture.context)
    withExtendedLifetime(fixture.container) {}
    return GoalCapturedCompletionSample(wallMs: wallMs, processCpuMs: processCpuMs,
                                       setupMs: fixture.setupMs,
                                       canonicalDigest: goalCapturedCompletionSHA(canonical),
                                       rawDigest: goalCapturedCompletionSHA(raw))
}

@MainActor
private func goalCapturedCompletionRead(in container: ModelContainer) throws -> GoalCapturedCompletionRead {
    let reader = ModelContext(container)
    reader.autosaveEnabled = false
    var tasks = FetchDescriptor<Task>()
    var progress = FetchDescriptor<TaskProgressEvent>()
    var completions = FetchDescriptor<TaskCompletionActivity>()
    tasks.includePendingChanges = false
    progress.includePendingChanges = false
    completions.includePendingChanges = false
    return try GoalCapturedCompletionRead(context: reader, tasks: reader.fetch(tasks),
                                         progress: reader.fetch(progress), completions: reader.fetch(completions))
}

@MainActor
private func goalCapturedCompletionValidate(
    _ read: GoalCapturedCompletionRead, count: Int, completion: Date, sourceContext: ModelContext,
    commandClockStart: Date, commandClockEnd: Date
) throws -> String {
    #expect(read.tasks.count == count && read.progress.count == count * 2 && read.completions.count == count)
    #expect(!read.context.hasChanges && !sourceContext.hasChanges)
    #expect(sourceContext.insertedModelsArray.isEmpty && sourceContext.changedModelsArray.isEmpty && sourceContext.deletedModelsArray.isEmpty)
    #expect(Set(read.tasks.map(\.instanceID)).count == count)
    #expect(Set(read.progress.map(\.id)).count == count * 2)
    #expect(Set(read.progress.map(\.instanceID)).count == count * 2)
    #expect(Set(read.completions.map(\.instanceID)).count == count)
    let allPhysical = read.tasks.map(\.instanceID) + read.progress.map(\.instanceID) + read.completions.map(\.instanceID)
    #expect(Set(allPhysical).count == count * 4)
    let tasksByID = Dictionary(grouping: read.tasks, by: \.id)
    let progressByTask = Dictionary(grouping: read.progress, by: \.taskId)
    let completionsByTask = Dictionary(grouping: read.completions, by: \.taskId)
    var rows: [String] = []
    for index in 0..<count {
        let taskID = goalCapturedCompletionID(namespace: 1, index: index)
        let task = try #require(tasksByID[taskID]?.first)
        let events = try #require(progressByTask[taskID])
        let started = try #require(events.first { $0.kindRawValue == TaskProgressEventKind.started.rawValue })
        let stopped = try #require(events.first { $0.kindRawValue == TaskProgressEventKind.stopped.rawValue })
        let activity = try #require(completionsByTask[taskID]?.first)
        #expect(tasksByID[taskID]?.count == 1 && events.count == 2 && completionsByTask[taskID]?.count == 1)
        #expect(goalCapturedCompletionTaskRow(task) == goalCapturedCompletionExpectedTaskRow(index: index, completion: completion))
        #expect(goalCapturedCompletionProgressRow(started) == goalCapturedCompletionExpectedStartRow(index: index, completion: completion))
        #expect(stopped.originRawValue == TaskProgressEventOrigin.captured.rawValue)
        #expect(stopped.occurredAt == completion && stopped.supersededAt == nil)
        #expect(stopped.createdAt == stopped.updatedAt)
        #expect(stopped.createdAt >= commandClockStart && stopped.createdAt <= commandClockEnd)
        #expect(stopped.id != started.id && stopped.instanceID != started.instanceID)
        #expect(activity.id == goalCapturedCompletionLogicalID(taskID: taskID, day: DayKey.key(for: completion)))
        #expect(activity.activityDayKey == DayKey.key(for: completion) && activity.occurredAt == completion)
        #expect(activity.originRawValue == TaskCompletionActivityOrigin.captured.rawValue)
        #expect(activity.createdAt == completion && activity.updatedAt == completion && activity.supersededAt == nil)
        let projection = TaskProgressEventRules.projection(for: events)
        let expectedStart = goalCapturedCompletionStart(index: index, completion: completion)
        #expect(projection.intervals == [TaskProgressInterval(startedAt: expectedStart, stoppedAt: completion)])
        #expect(projection.recordedDuration == completion.timeIntervalSince(expectedStart))
        #expect(projection.currentStartedAt == nil && !projection.hasUnknownDuration)
        rows.append(goalCapturedCompletionTaskRow(task))
        rows.append(goalCapturedCompletionProgressRow(started))
        rows.append(goalCapturedCompletionProgressRow(stopped, normalizeGenerated: true))
        rows.append(goalCapturedCompletionActivityRow(activity, normalizeGenerated: true))
    }
    rows.append(goalCapturedCompletionStateRow(read, sourceContext: sourceContext))
    return rows.sorted().joined(separator: "\n")
}

@MainActor
private func goalCapturedCompletionRepeatControl(completion: Date) throws {
    let fixture = try goalCapturedCompletionFixture(count: 2, completion: completion)
    _ = try PersistenceCommandService.perform(in: fixture.context) {
        try fixture.tasks.map { try TaskLifecycleService.applyStatus(.done, to: $0, in: fixture.context, now: completion) }
    }
    let before = try goalCapturedCompletionRead(in: fixture.container)
    #expect(before.tasks.count == 2 && before.progress.count == 4 && before.completions.count == 2)
    for activity in before.completions {
        #expect(activity.occurredAt == completion && activity.activityDayKey == DayKey.key(for: completion))
        #expect(activity.id == goalCapturedCompletionLogicalID(taskID: activity.taskId, day: DayKey.key(for: completion)))
        #expect(activity.originRawValue == TaskCompletionActivityOrigin.captured.rawValue)
        #expect(activity.createdAt == completion && activity.updatedAt == completion && activity.supersededAt == nil)
    }
    let original = goalCapturedCompletionRawPayload(before, sourceContext: fixture.context)
    let originalActivities = before.completions.map { goalCapturedCompletionActivityRow($0) }.sorted()
    let originalProgress = before.progress.map { goalCapturedCompletionProgressRow($0) }.sorted()
    let originalProgressPhysical = Set(before.progress.map(\.instanceID))
    let noops = try PersistenceCommandService.perform(in: fixture.context) {
        try fixture.tasks.map { try TaskLifecycleService.applyStatus(.done, to: $0, in: fixture.context, now: completion.addingTimeInterval(60)) }
    }
    #expect(noops == Array(repeating: TaskLifecycleTransitionResult.unchanged, count: 2))
    let afterNoop = try goalCapturedCompletionRead(in: fixture.container)
    #expect(goalCapturedCompletionRawPayload(afterNoop, sourceContext: fixture.context) == original)

    let restartedAt = completion.addingTimeInterval(120)
    let repeatedAt = completion.addingTimeInterval(180)
    #expect(DayKey.key(for: completion) == DayKey.key(for: repeatedAt))
    let repeatClockStart = Date()
    _ = try PersistenceCommandService.perform(in: fixture.context) {
        try fixture.tasks.map { try TaskLifecycleService.applyStatus(.doing, to: $0, in: fixture.context, now: restartedAt) }
    }
    let repeated = try PersistenceCommandService.perform(in: fixture.context) {
        try fixture.tasks.map { try TaskLifecycleService.applyStatus(.done, to: $0, in: fixture.context, now: repeatedAt) }
    }
    let repeatClockEnd = Date()
    #expect(repeated.count == 2)
    #expect(repeated.allSatisfy {
        $0 == TaskLifecycleTransitionResult(didChange: true, didComplete: true,
                                           activityInserted: false, progressEventKind: .stopped)
    })
    let afterRepeat = try goalCapturedCompletionRead(in: fixture.container)
    #expect(afterRepeat.completions.map { goalCapturedCompletionActivityRow($0) }.sorted() == originalActivities)
    #expect(afterRepeat.tasks.count == 2 && afterRepeat.completions.count == 2 && afterRepeat.progress.count == 8)
    #expect(Set(afterRepeat.progress.map(\.id)).count == 8 && Set(afterRepeat.progress.map(\.instanceID)).count == 8)
    let preservedProgress = afterRepeat.progress.filter { originalProgressPhysical.contains($0.instanceID) }
    #expect(preservedProgress.map { goalCapturedCompletionProgressRow($0) }.sorted() == originalProgress)
    let newlyRecorded = afterRepeat.progress.filter { !originalProgressPhysical.contains($0.instanceID) }
    #expect(newlyRecorded.count == 4 && newlyRecorded.allSatisfy {
        $0.createdAt == $0.updatedAt && $0.createdAt >= repeatClockStart && $0.createdAt <= repeatClockEnd
    })
    for index in 0..<2 {
        let id = goalCapturedCompletionID(namespace: 1, index: index)
        let task = try #require(afterRepeat.tasks.first { $0.id == id })
        #expect(goalCapturedCompletionTaskRow(task) == goalCapturedCompletionExpectedTaskRow(
            index: index, completion: completion, finishedAt: repeatedAt))
        let events = afterRepeat.progress.filter { $0.taskId == task.id }
        #expect(events.count == 4 && events.allSatisfy { $0.originRawValue == TaskProgressEventOrigin.captured.rawValue && $0.supersededAt == nil })
        let first = try #require(events.first { $0.kindRawValue == TaskProgressEventKind.started.rawValue && $0.occurredAt < completion })
        let expected = [TaskProgressInterval(startedAt: first.occurredAt, stoppedAt: completion),
                        TaskProgressInterval(startedAt: restartedAt, stoppedAt: repeatedAt)]
        #expect(TaskProgressEventRules.projection(for: events).intervals == expected)
    }
    #expect(!fixture.context.hasChanges)
    print("GOAL_CAPTURED_COMPLETION_CONTROL name=noop-and-same-day-repeat passedExpectationsRequired=true scope=untimed existingOccurrenceAndPhysicalValuesPreserved=true")
    withExtendedLifetime(fixture.container) {}
}

private enum GoalCapturedCompletionControlError: Error { case injected }

@MainActor
private func goalCapturedCompletionRollbackControl(completion: Date) throws {
    let fixture = try goalCapturedCompletionFixture(count: 2, completion: completion)
    let before = try goalCapturedCompletionRead(in: fixture.container)
    let expected = goalCapturedCompletionRawPayload(before, sourceContext: fixture.context)
    #expect(throws: GoalCapturedCompletionControlError.injected) {
        try PersistenceCommandService.perform(in: fixture.context) {
            for task in fixture.tasks {
                _ = try TaskLifecycleService.applyStatus(.done, to: task, in: fixture.context, now: completion)
            }
            throw GoalCapturedCompletionControlError.injected
        }
    }
    let after = try goalCapturedCompletionRead(in: fixture.container)
    #expect(goalCapturedCompletionRawPayload(after, sourceContext: fixture.context) == expected)
    #expect(after.tasks.count == 2 && after.tasks.allSatisfy { $0.status == TaskStatus.doing.rawValue && $0.completedAt == nil })
    #expect(after.progress.count == 2 && after.progress.allSatisfy { $0.kindRawValue == TaskProgressEventKind.started.rawValue })
    #expect(after.completions.isEmpty && !fixture.context.hasChanges)
    print("GOAL_CAPTURED_COMPLETION_CONTROL name=atomic-rollback passedExpectationsRequired=true scope=untimed savedTaskAndStartedValuesPreserved=true")
    withExtendedLifetime(fixture.container) {}
}

@MainActor
private func goalCapturedCompletionRawPayload(_ read: GoalCapturedCompletionRead, sourceContext: ModelContext) -> String {
    var rows = read.tasks.map(goalCapturedCompletionTaskRow)
    rows += read.progress.map { goalCapturedCompletionProgressRow($0) }
    rows += read.completions.map { goalCapturedCompletionActivityRow($0) }
    rows.append(goalCapturedCompletionStateRow(read, sourceContext: sourceContext))
    return rows.sorted().joined(separator: "\n")
}

@MainActor
private func goalCapturedCompletionStateRow(_ read: GoalCapturedCompletionRead, sourceContext: ModelContext) -> String {
    let physical = "physical-counts|tasks:\(read.tasks.count)|progress:\(read.progress.count)|completions:\(read.completions.count)"
    let pending = "pending|sourceHasChanges:\(sourceContext.hasChanges)|inserted:\(sourceContext.insertedModelsArray.count)|changed:\(sourceContext.changedModelsArray.count)|deleted:\(sourceContext.deletedModelsArray.count)|readerHasChanges:\(read.context.hasChanges)"
    return physical + "\n" + pending
}

private func goalCapturedCompletionExpectedPayload(count: Int, completion: Date) -> String {
    var rows: [String] = []
    for index in 0..<count {
        let taskID = goalCapturedCompletionID(namespace: 1, index: index)
        rows.append(goalCapturedCompletionExpectedTaskRow(index: index, completion: completion))
        rows.append(goalCapturedCompletionExpectedStartRow(index: index, completion: completion))
        rows.append(["progress", "generated-stop-logical:\(taskID)", "generated-stop-physical:\(taskID)",
                     taskID.uuidString, TaskProgressEventKind.stopped.rawValue, TaskProgressEventOrigin.captured.rawValue,
                     goalCapturedCompletionDate(completion), "command-recorded-at:\(taskID)",
                     "command-recorded-at:\(taskID)", "nil"].joined(separator: "|"))
        rows.append(["completion", goalCapturedCompletionLogicalID(taskID: taskID, day: DayKey.key(for: completion)).uuidString,
                     "generated-completion-physical:\(taskID)", taskID.uuidString, DayKey.key(for: completion),
                     goalCapturedCompletionDate(completion), TaskCompletionActivityOrigin.captured.rawValue,
                     goalCapturedCompletionDate(completion), goalCapturedCompletionDate(completion), "nil"].joined(separator: "|"))
    }
    rows.append("physical-counts|tasks:\(count)|progress:\(count * 2)|completions:\(count)\npending|sourceHasChanges:false|inserted:0|changed:0|deleted:0|readerHasChanges:false")
    return rows.sorted().joined(separator: "\n")
}

private func goalCapturedCompletionExpectedTaskRow(index: Int, completion: Date, finishedAt: Date? = nil) -> String {
    let plannedAt = DayKey.startOfDay(for: completion.addingTimeInterval(-86_400))
    let doneAt = finishedAt ?? completion
    let fields: [String] = [
        "task", goalCapturedCompletionID(namespace: 1, index: index).uuidString,
        goalCapturedCompletionID(namespace: 2, index: index).uuidString,
        "완료 성능 fixture \(index)", "시작과 완료를 함께 저장", TaskStatus.done.rawValue,
        goalCapturedCompletionDate(plannedAt), DayKey.key(for: plannedAt), String(Double((index + 1) * 100)),
        goalCapturedCompletionID(namespace: 5, index: index).uuidString,
        goalCapturedCompletionID(namespace: 6, index: index).uuidString, TaskPriority.high.rawValue,
        goalCapturedCompletionTags(["fixture", String(index % 3)]), String(25 + index % 5),
        goalCapturedCompletionDate(completion.addingTimeInterval(3_600 + Double(index))),
        goalCapturedCompletionDate(completion.addingTimeInterval(-86_400 + Double(index))),
        goalCapturedCompletionDate(doneAt), goalCapturedCompletionDate(doneAt),
        DayKey.key(for: doneAt), "nil", "nil", "nil"
    ]
    return fields.joined(separator: "|")
}

private func goalCapturedCompletionExpectedStartRow(index: Int, completion: Date) -> String {
    let startedAt = goalCapturedCompletionStart(index: index, completion: completion)
    return ["progress", goalCapturedCompletionID(namespace: 3, index: index).uuidString,
            goalCapturedCompletionID(namespace: 4, index: index).uuidString,
            goalCapturedCompletionID(namespace: 1, index: index).uuidString,
            TaskProgressEventKind.started.rawValue, TaskProgressEventOrigin.captured.rawValue,
            goalCapturedCompletionDate(startedAt), goalCapturedCompletionDate(startedAt.addingTimeInterval(1)),
            goalCapturedCompletionDate(startedAt.addingTimeInterval(2)), "nil"].joined(separator: "|")
}

private func goalCapturedCompletionTaskRow(_ task: Task) -> String {
    let fields: [String] = [
        "task", task.id.uuidString, task.instanceID.uuidString, task.title, task.note ?? "nil", task.status,
        goalCapturedCompletionDate(task.plannedAt), task.plannedDayKey, String(task.order),
        task.eventId?.uuidString ?? "nil", task.templatePlacementId?.uuidString ?? "nil", task.priority ?? "nil",
        goalCapturedCompletionTags(task.tags), task.estimatedMinutes.map(String.init) ?? "nil",
        goalCapturedCompletionDate(task.reminderAt), goalCapturedCompletionDate(task.createdAt),
        goalCapturedCompletionDate(task.updatedAt), goalCapturedCompletionDate(task.completedAt),
        task.completedDayKey ?? "nil", goalCapturedCompletionDate(task.archivedAt),
        task.archivedDayKey ?? "nil", goalCapturedCompletionDate(task.supersededAt)
    ]
    return fields.joined(separator: "|")
}

private func goalCapturedCompletionProgressRow(_ event: TaskProgressEvent, normalizeGenerated: Bool = false) -> String {
    let task = event.taskId.uuidString
    let fields: [String] = [
        "progress", normalizeGenerated ? "generated-stop-logical:\(task)" : event.id.uuidString,
        normalizeGenerated ? "generated-stop-physical:\(task)" : event.instanceID.uuidString,
        task, event.kindRawValue, event.originRawValue, goalCapturedCompletionDate(event.occurredAt),
        normalizeGenerated ? "command-recorded-at:\(task)" : goalCapturedCompletionDate(event.createdAt),
        normalizeGenerated ? "command-recorded-at:\(task)" : goalCapturedCompletionDate(event.updatedAt),
        goalCapturedCompletionDate(event.supersededAt)
    ]
    return fields.joined(separator: "|")
}

private func goalCapturedCompletionActivityRow(_ activity: TaskCompletionActivity, normalizeGenerated: Bool = false) -> String {
    ["completion", activity.id.uuidString,
     normalizeGenerated ? "generated-completion-physical:\(activity.taskId.uuidString)" : activity.instanceID.uuidString,
     activity.taskId.uuidString, activity.activityDayKey, goalCapturedCompletionDate(activity.occurredAt),
     activity.originRawValue, goalCapturedCompletionDate(activity.createdAt), goalCapturedCompletionDate(activity.updatedAt),
     goalCapturedCompletionDate(activity.supersededAt)].joined(separator: "|")
}

private func goalCapturedCompletionStart(index: Int, completion: Date) -> Date {
    completion.addingTimeInterval(-600 - Double(index % 60))
}

private func goalCapturedCompletionID(namespace: Int, index: Int) -> UUID {
    UUID(uuidString: String(format: "32000000-0000-4000-%04X-%012X", namespace, index + 1))!
}

/// Independent expected value for the deployed completion-ID algorithm.
private func goalCapturedCompletionLogicalID(taskID: UUID, day: String) -> UUID {
    let canonical = taskID.uuidString.lowercased() + "|" + day
    var bytes = Array(SHA256.hash(data: Data(canonical.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x80
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                       bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
}

private func goalCapturedCompletionDate(_ date: Date?) -> String {
    // The reference-date Double preserves Date's stored precision. Adding the
    // 1970 epoch offset can round away a low mantissa bit in generated clocks.
    date.map { String($0.timeIntervalSinceReferenceDate.bitPattern) } ?? "nil"
}

private func goalCapturedCompletionTags(_ tags: [String]) -> String {
    tags.map { "\($0.utf8.count):\($0)" }.joined(separator: ";")
}

private func goalCapturedCompletionSHA(_ payload: String) -> String {
    SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func goalCapturedCompletionElapsed(_ start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

private func goalCapturedCompletionCPUms() throws -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
        throw NSError(domain: "GoalCapturedCompletion.getrusage", code: Int(errno))
    }
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000
}

private func goalCapturedCompletionPercentile(_ samples: [Double], _ quantile: Double) -> Double {
    let ordered = samples.sorted()
    guard !ordered.isEmpty else { return 0 }
    if quantile == 0.5, ordered.count.isMultiple(of: 2) {
        return (ordered[ordered.count / 2 - 1] + ordered[ordered.count / 2]) / 2
    }
    return ordered[min(ordered.count - 1, max(0, Int(ceil(Double(ordered.count) * quantile)) - 1))]
}

private func goalCapturedCompletionReport(
    count: Int, source: String, samples: [GoalCapturedCompletionSample], setupSamples: [Double],
    canonicalDigest: String, rawDigests: [String]
) {
    let walls = samples.map(\.wallMs)
    let cpus = samples.map(\.processCpuMs)
    print("GOAL_CAPTURED_COMPLETION_BENCHMARK name=doing-to-done-atomic source=\(source) harness=v1 tasks=\(count) store=in-memory scope=one-actual-perform-and-save unit=ms n=\(samples.count) warmup=1 independentRepeat=1 independentFixturePerSample=true commandsPerSample=1 transitionsPerCommand=\(count) p50=\(goalCapturedCompletionPercentile(walls, 0.5)) p95=\(goalCapturedCompletionPercentile(walls, 0.95)) max=\(walls.max() ?? 0) processCpuP50=\(goalCapturedCompletionPercentile(cpus, 0.5)) processCpuP95=\(goalCapturedCompletionPercentile(cpus, 0.95)) processCpuMax=\(cpus.max() ?? 0) samples=\(walls) processCpuSamples=\(cpus)")
    print("GOAL_CAPTURED_COMPLETION_OUTPUT source=\(source) tasks=\(count) canonicalDigest=\(canonicalDigest) fullRawDigests=\(rawDigests) dateEncoding=referenceDateIntervalBitPattern generatedFieldsCanonicalized=stopLogicalUUID-stopPhysicalUUID-stopCreatedUpdatedClock-completionPhysicalUUID generationValidatedOutsideTiming=true allOtherFieldsActual=true expectedPendingAfterSave=0 expectedTaskPhysical=\(count) expectedProgressPhysical=\(count * 2) expectedCompletionPhysical=\(count)")
    print("GOAL_CAPTURED_COMPLETION_SETUP source=\(source) tasks=\(count) unit=ms includesWarmup=true timingOutsideCommand=true includesContainerInitTaskProgressSeedAndFixtureSave=true samples=\(setupSamples)")
    print("GOAL_CAPTURED_COMPLETION_LIMITS source=\(source) tasks=\(count) initialAndFinalCommandSaveTimed=true statusProgressActivityAndTransitionResultCaptureTimed=true synchronousChangeNotificationTimed=true validationAndSHAUntimed=true processCpuIncludesStoreThreadsAndOtherProcessWork=true clockOverheadNotSubtracted=true actualFetchCount=unmeasured sqlStatements=unmeasured appInputToFrame=unmeasured CloudKitLatency=unmeasured")
}
#endif
