#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Opt-in microbenchmarks, not rendered frames, SwiftUI body counts, or realized row counts.
/// All fixture creation, reference results, SHA computation, and correctness checks are untimed.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_BOARD_PROJECTION_PERFORMANCE"] == "1"))
@MainActor
func goalBoardProjectionPerformance() throws {
    let day = try #require(DayKey.date(from: "2026-10-02"))
    let dayKey = DayKey.key(for: day)
    for taskCount in [20, 240] {
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        context.autosaveEnabled = false
        let rows = goalBoardTaskFixture(count: taskCount, day: day)
        for task in rows { context.insert(task) }
        try context.save()
        // iOS retains this projection already. The Mac body also computes it;
        // that separate base projection is not inside the status-slice interval.
        let tasks = BoardQueryRules.tasksForBoard(rows, selectedDayKey: dayKey, todayKey: dayKey)
        #expect(tasks.count == taskCount)
        for readCount in [3, 4, 7] {
            let expected = goalBoardReferenceRender(tasks, readCount: readCount)
            let digest = goalBoardRenderDigest(expected)
            #expect(goalBoardRenderDigest(goalBoardSharedRender(tasks, readCount: readCount)) == digest)
            for algorithm in ["reference", "render-shared"] {
                goalBoardProjectionSamples(
                    name: "status-slices-\(algorithm)-reads\(readCount)",
                    details: "tasks=\(taskCount) referenceSliceCalls=\(readCount) measuredSliceCalls=\(algorithm == "reference" ? readCount : 3) scope=one-synthetic-render",
                    expectedDigest: digest,
                    operation: {
                        algorithm == "reference"
                            ? goalBoardReferenceRender(tasks, readCount: readCount)
                            : goalBoardSharedRender(tasks, readCount: readCount)
                    }, digest: goalBoardRenderDigest)
            }
        }
    }

    let now = Date(timeIntervalSince1970: 1_788_436_000)
    let locale = Locale(identifier: "en_US_POSIX")
    let timeZone = try #require(TimeZone(secondsFromGMT: 0))
    for eventCount in [0, 25, 250] {
        for tieAndBoundary in eventCount == 0 ? [false] : [false, true] {
            let fixture = goalBoardProgressFixture(count: eventCount, tieAndBoundary: tieAndBoundary)
            let expected = TaskProgressEventRules.projection(for: fixture.events)
            let closedCount = eventCount / 2 - (tieAndBoundary ? 1 : 0)
            #expect(expected.intervals.count == closedCount)
            #expect(expected.recordedDuration == Double(closedCount) * 60)
            #expect(expected.hasUnknownDuration == tieAndBoundary)
            #expect(expected.currentStartedAt == (eventCount % 2 == 1
                ? fixture.start.addingTimeInterval(Double(eventCount - 1) * 60) : nil))
            if tieAndBoundary {
                #expect(expected.unknownIntervalStarts == [fixture.start.addingTimeInterval(130)])
            }
            let history = tieAndBoundary ? "representative-tie-compatibility" : "captured"
            for syntheticCalls in [20, 240] {
                let projections = Array(repeating: expected, count: syntheticCalls)
                goalBoardProjectionSamples(
                    name: "progress-projection-\(history)",
                    details: "logicalEvents=\(eventCount) physicalEvents=\(fixture.events.count) syntheticCalls=\(syntheticCalls) actualRealizedRows=unmeasured cache=false",
                    expectedDigest: goalBoardProgressDigest(projections),
                    operation: {
                        // This is the rules path currently invoked by the session getter.
                        // Repeating one history models call cost; it does not create 240 UI rows.
                        (0..<syntheticCalls).map { _ in TaskProgressEventRules.projection(for: fixture.events) }
                    }, digest: goalBoardProgressDigest)

                let statuses: [TaskStatus] = [.todo, .doing, .done]
                let expectedText = (0..<syntheticCalls).map { index in
                    TaskProgressEventRules.detailText(
                        projection: expected, status: statuses[index % statuses.count], now: now,
                        completedAt: now, locale: locale, timeZone: timeZone)
                }
                goalBoardProjectionSamples(
                    name: "progress-detail-text-\(history)",
                    details: "logicalEvents=\(eventCount) syntheticCalls=\(syntheticCalls) actualRealizedRows=unmeasured projectionTimed=false locale=en_US_POSIX timeZone=UTC",
                    expectedDigest: goalBoardTextDigest(expectedText),
                    operation: {
                        // Only formatting/duration text: the projection was prepared above.
                        (0..<syntheticCalls).map { index in
                            TaskProgressEventRules.detailText(
                                projection: expected, status: statuses[index % statuses.count], now: now,
                                completedAt: now, locale: locale, timeZone: timeZone)
                        }
                    }, digest: goalBoardTextDigest)
            }
        }
    }
}

private struct GoalBoardRenderResult {
    var lists: [[Task]]
    var counts: [Int]
    var scrollIDs: [UUID]
}

private func goalBoardReferenceRender(_ tasks: [Task], readCount: Int) -> GoalBoardRenderResult {
    let statuses: [TaskStatus] = [.todo, .doing, .done]
    // Mac uses three list preparations. iPhone adds a scroll observation (four).
    // iPad three-column layout also separately prepares all three column counts (seven).
    var lists: [[Task]] = []
    var counts: [Int] = []
    for status in statuses {
        if readCount == 7 { counts.append(BoardQueryRules.tasks(tasks, matching: status).count) }
        lists.append(BoardQueryRules.tasks(tasks, matching: status))
    }
    if readCount != 7 { counts = lists.map(\.count) }
    let scrollIDs = readCount >= 4 ? BoardQueryRules.tasks(tasks, matching: .todo).map(\.id) : []
    return GoalBoardRenderResult(lists: lists, counts: counts, scrollIDs: scrollIDs)
}

private func goalBoardSharedRender(_ tasks: [Task], readCount: Int) -> GoalBoardRenderResult {
    // A test-only render-scoped reuse proposal. No persistent cache or production change.
    let lists = [TaskStatus.todo, .doing, .done].map { BoardQueryRules.tasks(tasks, matching: $0) }
    return GoalBoardRenderResult(
        lists: lists, counts: lists.map(\.count), scrollIDs: readCount >= 4 ? lists[0].map(\.id) : [])
}

@MainActor
private func goalBoardTaskFixture(count: Int, day: Date) -> [Task] {
    let statuses: [TaskStatus] = [.todo, .doing, .done]
    return (0..<count).map { index in
        let task = Task(
            id: goalBoardFixtureID(namespace: 1, index: index),
            instanceID: goalBoardFixtureID(namespace: 2, index: index),
            title: String(format: "보드 작업 %04d", count - index),
            status: statuses[index % statuses.count], plannedAt: day,
            order: Double(index % 8) * 100, createdAt: day, updatedAt: day)
        if task.status == TaskStatus.done.rawValue {
            task.completedAt = day.addingTimeInterval(Double(index % 5) * 60)
            task.completedDayKey = DayKey.key(for: day)
        }
        return task
    }
}

private struct GoalBoardProgressFixture {
    var start: Date
    var events: [TaskProgressEvent]
}

private func goalBoardProgressFixture(count: Int, tieAndBoundary: Bool) -> GoalBoardProgressFixture {
    let start = Date(timeIntervalSince1970: 1_788_400_000)
    let updatedAt = start.addingTimeInterval(20_000)
    let taskID = goalBoardFixtureID(namespace: 10, index: 0)
    var events = (0..<count).map { index in
        let occurredAt = start.addingTimeInterval(Double(index) * 60)
        return TaskProgressEvent(
            id: goalBoardFixtureID(namespace: 11, index: index),
            instanceID: goalBoardFixtureID(namespace: 12, index: index),
            taskId: taskID, kind: index % 2 == 0 ? .started : .stopped,
            occurredAt: occurredAt, createdAt: occurredAt, updatedAt: updatedAt)
    }
    if tieAndBoundary {
        events[3].originRawValue = TaskProgressEventOrigin.compatibilityBoundary.rawValue
        // Equal updatedAt physical representatives are resolved by instanceID.
        // The highest copy starts at +130s; lower copies must not affect duration.
        for (namespace, second) in [(9, 110.0), (13, 130.0)] {
            events.append(TaskProgressEvent(
                id: events[2].id, instanceID: goalBoardFixtureID(namespace: namespace, index: 2),
                taskId: taskID, kind: .started, occurredAt: start.addingTimeInterval(second),
                createdAt: events[2].createdAt, updatedAt: updatedAt))
        }
    }
    return GoalBoardProgressFixture(start: start, events: Array(events.reversed()))
}

@MainActor
private func goalBoardProjectionSamples<Output>(
    name: String, details: String, expectedDigest: String,
    operation: () -> Output, digest: (Output) -> String
) {
    #expect(digest(operation()) == expectedDigest) // One untimed warm-up.
    var samples: [Double] = []
    for _ in 0..<30 {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = operation()
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        #expect(digest(result) == expectedDigest)
    }
    let ordered = samples.sorted()
    let median = (ordered[14] + ordered[15]) / 2
    print("GOAL_BOARD_PROJECTION_BENCHMARK name=\(name) \(details) unit=ms n=30 warmup=1 p50=\(median) p95=\(ordered[28]) max=\(ordered[29]) outputDigest=\(expectedDigest) samples=\(samples)")
}

private func goalBoardRenderDigest(_ result: GoalBoardRenderResult) -> String {
    let lists = result.lists.map { $0.map { $0.id.uuidString }.joined(separator: ",") }.joined(separator: ";")
    let counts = result.counts.map(String.init).joined(separator: ",")
    let scroll = result.scrollIDs.map(\.uuidString).joined(separator: ",")
    return goalBoardDigest("\(lists)|\(counts)|\(scroll)")
}

private func goalBoardProgressDigest(_ values: [TaskProgressProjection]) -> String {
    let payload = values.map { value in
        let intervals = value.intervals.map { "\($0.startedAt.timeIntervalSince1970),\($0.stoppedAt.timeIntervalSince1970)" }.joined(separator: ";")
        let starts = value.recordedStarts.map { String($0.timeIntervalSince1970) }.joined(separator: ",")
        let unknown = value.unknownIntervalStarts.map { String($0.timeIntervalSince1970) }.joined(separator: ",")
        let active = value.currentStartedAt.map { String($0.timeIntervalSince1970) } ?? "-"
        return "\(intervals)|\(active)|\(value.hasUnknownDuration)|\(starts)|\(unknown)"
    }.joined(separator: "\n")
    return goalBoardDigest(payload)
}

private func goalBoardTextDigest(_ values: [String?]) -> String {
    goalBoardDigest(values.map { $0 ?? "<nil>" }.joined(separator: "\n"))
}

private func goalBoardDigest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func goalBoardFixtureID(namespace: Int, index: Int) -> UUID {
    UUID(uuidString: String(format: "20000000-0000-0000-%04X-%012X", namespace, index + 1))!
}
#endif
