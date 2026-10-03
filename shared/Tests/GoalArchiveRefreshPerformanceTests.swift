#if DEBUG
import CryptoKit
import Foundation
import Observation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Real page/session reads on one synthetic container; no loader-count proxy for CPU cost.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_ARCHIVE_REFRESH_PERFORMANCE"] == "1"))
@MainActor
func goalArchiveRefreshPerformance() async throws {
    for count in [1_000, 10_000] {
        let fixture = try GoalArchiveRefreshFixture(count: count)
        let context = fixture.container.mainContext
        let n = count == 1_000 ? 30 : 5
        var reviewSequence = 0
        var taskSequence = 0

        // Lower-cost control still fetches current reviews and calculates day records.
        // It preserves only the service's already prepared progress projection index.
        do {
            let service = DailyActivityQueryService(context: context)
            _ = try await service.page(filter: fixture.filter, referenceDate: fixture.reference)
            var samples: [Double] = []
            var digests: [String] = []
            for _ in 0..<n {
                reviewSequence += 1
                try fixture.editReview(sequence: reviewSequence)
                let start = DispatchTime.now().uptimeNanoseconds
                let page = try await service.page(filter: fixture.filter, referenceDate: fixture.reference)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                try fixture.validate(page.records, reviewSequence: reviewSequence, taskSequence: taskSequence)
                #expect(page.nextBeforeDayKey == nil)
                #expect(!page.hasMore)
                #expect(page.attachments.isEmpty && page.blocks.isEmpty)
                digests.append(try goalArchiveRefreshDigest(records: page.records, loadedDepth: 1, hasMore: page.hasMore))
            }
            try goalArchiveRefreshPrint(name: "service-cache-preserved-review-edit", count: count,
                samples: samples, digests: digests, readScheduled: nil, taskEdits: taskSequence,
                reviewEdits: reviewSequence)
        }

        for scenario in ["unchanged-reentry", "review-only", "tasks-change", "unknown-import-proxy"] {
            let service = DailyActivityQueryService(context: context)
            let session = ArchiveQuerySession(context: context, dailyService: service)
            session.apply(fixture.filter, debounceSearch: false)
            await goalArchiveWaitForCompletion(session)
            try fixture.validate(session.records, reviewSequence: reviewSequence, taskSequence: taskSequence)
            #expect(session.loadedPageCount == 1)
            #expect(session.errorMessage == nil)
            var samples: [Double] = []
            var digests: [String] = []
            var scheduled: [Bool] = []
            // Each session has one initial unmeasured real load. Mutation and notification
            // are also outside the measured refreshIfNeeded-to-completion interval.
            for _ in 0..<n {
                switch scenario {
                case "review-only":
                    reviewSequence += 1
                    try fixture.editReview(sequence: reviewSequence)
                case "tasks-change":
                    taskSequence += 1
                    try fixture.appendProgress(sequence: taskSequence)
                case "unknown-import-proxy":
                    // Conservative all-domain invalidation proxy; no CloudKit Event is fabricated.
                    NotificationCenter.default.post(name: PersistenceCommandService.dataChangedNotification,
                                                    object: context)
                default: break
                }
                let start = DispatchTime.now().uptimeNanoseconds
                session.refreshIfNeeded()
                let didSchedule = session.isLoading
                await goalArchiveWaitForCompletion(session)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                scheduled.append(didSchedule)
                #expect(didSchedule == (scenario != "unchanged-reentry"))
                #expect(!session.isLoading)
                #expect(session.errorMessage == nil)
                #expect(session.loadedPageCount == 1)
                #expect(!session.hasMore)
                #expect(session.attachments.isEmpty && session.blocks.isEmpty)
                try fixture.validate(session.records, reviewSequence: reviewSequence, taskSequence: taskSequence)
                digests.append(try goalArchiveRefreshDigest(
                    records: session.records, loadedDepth: session.loadedPageCount, hasMore: session.hasMore
                ))
            }
            try goalArchiveRefreshPrint(name: scenario, count: count, samples: samples, digests: digests,
                readScheduled: scheduled, taskEdits: taskSequence, reviewEdits: reviewSequence)
            session.cancel()
        }
        #expect(!context.hasChanges)
        withExtendedLifetime(fixture.container) {}
    }
}

@MainActor
private struct GoalArchiveRefreshFixture {
    let container: ModelContainer
    let count: Int
    let reference: Date
    let filter: ArchiveFilter
    let review: DailyReview
    let target: Task

    init(count: Int) throws {
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        context.autosaveEnabled = false
        let reference = try #require(DayKey.date(from: "2026-10-02"))
        var target: Task?
        for index in 0..<count {
            let day = DayKey.addingDays(-(index % 30), to: reference)
            let task = Task(id: goalArchiveRefreshID(namespace: 1, index: index),
                instanceID: goalArchiveRefreshID(namespace: 2, index: index),
                title: "합성 작업 \(index)", plannedAt: day, order: Double(index),
                createdAt: day, updatedAt: day)
            context.insert(task)
            if index == 0 { target = task }
            for interval in 0..<5 {
                let start = day.addingTimeInterval(Double(3_600 + interval * 600))
                let identity = index * 10 + interval * 2
                context.insert(TaskProgressEvent(
                    id: goalArchiveRefreshID(namespace: 3, index: identity),
                    instanceID: goalArchiveRefreshID(namespace: 4, index: identity),
                    taskId: task.id, kind: .started, occurredAt: start, createdAt: start, updatedAt: start
                ))
                context.insert(TaskProgressEvent(
                    id: goalArchiveRefreshID(namespace: 3, index: identity + 1),
                    instanceID: goalArchiveRefreshID(namespace: 4, index: identity + 1),
                    taskId: task.id, kind: .stopped, occurredAt: start.addingTimeInterval(300),
                    createdAt: start, updatedAt: start
                ))
            }
            if index % 250 == 249 { try context.save() }
        }
        let review = DailyReview(id: goalArchiveRefreshID(namespace: 5, index: 0),
            instanceID: goalArchiveRefreshID(namespace: 6, index: 0),
            dayKey: DayKey.key(for: reference), content: "회고 수정 0", createdAt: reference, updatedAt: reference)
        context.insert(review)
        try context.save()
        self.container = container
        self.count = count
        self.reference = reference
        self.review = review
        self.target = try #require(target)
        self.filter = ArchiveFilter(contentMode: .dailyActivity, period: .custom,
            customStartDate: DayKey.addingDays(-29, to: reference), customEndDate: reference)
    }

    func editReview(sequence: Int) throws {
        try PersistenceCommandService.perform(in: container.mainContext) {
            review.content = "회고 수정 \(sequence)"
            review.updatedAt = reference.addingTimeInterval(Double(sequence))
        }
    }

    func appendProgress(sequence: Int) throws {
        let start = reference.addingTimeInterval(Double(36_000 + sequence * 120))
        try PersistenceCommandService.perform(in: container.mainContext) {
            // Both transitions and final task state share one persistence command.
            _ = TaskProgressEventService.recordTransition(taskID: target.id, from: .todo, to: .doing,
                                                          occurredAt: start, in: container.mainContext)
            target.status = TaskStatus.doing.rawValue
            _ = TaskProgressEventService.recordTransition(taskID: target.id, from: .doing, to: .todo,
                                                          occurredAt: start.addingTimeInterval(60), in: container.mainContext)
            target.status = TaskStatus.todo.rawValue
            target.updatedAt = start.addingTimeInterval(60)
        }
    }

    func validate(_ records: [ArchiveDayRecord], reviewSequence: Int, taskSequence: Int) throws {
        let expectedDays = (0..<30).map { DayKey.key(for: DayKey.addingDays(-$0, to: reference)) }
        #expect(records.map(\.dayKey) == expectedDays)
        let entries = records.flatMap { $0.activityEntries ?? [] }
        #expect(entries.count == count)
        #expect(Set(entries.map(\.id)).count == count)
        #expect(Set(entries.map(\.id)) == Set((0..<count).map { goalArchiveRefreshID(namespace: 1, index: $0) }))
        #expect(records.flatMap(\.tasks).count == count)
        for entry in entries {
            #expect(entry.canOpenTask)
            #expect(entry.evidence.started)
            #expect(!entry.evidence.completed && !entry.evidence.legacyCompletion && !entry.evidence.unknownProgress)
            #expect(entry.evidence.focusSeconds == 0 && entry.evidence.focusSessionCount == 0)
            let expectedProgress = entry.id == target.id ? Double(1_500 + taskSequence * 60) : 1_500
            #expect(entry.evidence.progressSeconds == expectedProgress)
        }
        let latest = try #require(records.first?.review)
        #expect(latest === review)
        #expect(latest.content == "회고 수정 \(reviewSequence)")
        #expect(latest.updatedAt == reference.addingTimeInterval(Double(reviewSequence)))
    }
}

/// Observation resumes after isLoading changes; no polling sleep is included in latency.
@MainActor
private final class GoalArchiveCompletionWaiter {
    let session: ArchiveQuerySession
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ session: ArchiveQuerySession) { self.session = session }

    func wait() async {
        guard session.isLoading else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observe()
        }
    }

    private func observe() {
        guard session.isLoading else {
            let pending = continuation
            continuation = nil
            pending?.resume()
            return
        }
        withObservationTracking { _ = session.isLoading } onChange: { [weak self] in
            Swift.Task { @MainActor [weak self] in self?.observe() }
        }
    }
}

@MainActor
private func goalArchiveWaitForCompletion(_ session: ArchiveQuerySession) async {
    await GoalArchiveCompletionWaiter(session).wait()
}

private struct GoalArchiveRefreshSnapshot: Encodable {
    struct Entry: Encodable {
        let id: UUID
        let title: String
        let note: String?
        let completed: Bool
        let legacyCompletion: Bool
        let started: Bool
        let progressSeconds: Double
        let unknownProgress: Bool
        let focusSeconds: Int
        let focusSessionCount: Int
        let canOpenTask: Bool
        let matchingChecklistTitles: [String]
        let searchQuery: String
        let currentStatus: String?
    }
    struct Day: Encodable {
        let dayKey: String
        let taskInstanceIDs: [UUID]
        let reviewID: UUID?
        let reviewInstanceID: UUID?
        let reviewContent: String?
        let reviewUpdatedAt: Date?
        let entries: [Entry]
    }
    let days: [Day]
    let depth: Int
    let hasMore: Bool
}

@MainActor
private func goalArchiveRefreshDigest(records: [ArchiveDayRecord], loadedDepth: Int, hasMore: Bool) throws -> String {
    let days = records.map { record in
        GoalArchiveRefreshSnapshot.Day(
            dayKey: record.dayKey, taskInstanceIDs: record.tasks.map(\.instanceID),
            reviewID: record.review?.id, reviewInstanceID: record.review?.instanceID,
            reviewContent: record.review?.content, reviewUpdatedAt: record.review?.updatedAt,
            entries: (record.activityEntries ?? []).map { entry in
                GoalArchiveRefreshSnapshot.Entry(id: entry.id, title: entry.title, note: entry.note,
                    completed: entry.evidence.completed, legacyCompletion: entry.evidence.legacyCompletion,
                    started: entry.evidence.started, progressSeconds: entry.evidence.progressSeconds,
                    unknownProgress: entry.evidence.unknownProgress, focusSeconds: entry.evidence.focusSeconds,
                    focusSessionCount: entry.evidence.focusSessionCount, canOpenTask: entry.canOpenTask,
                    matchingChecklistTitles: entry.matchingChecklistTitles, searchQuery: entry.searchQuery,
                    currentStatus: entry.currentStatusRawValue)
            }
        )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .secondsSince1970
    return SHA256.hash(data: try encoder.encode(GoalArchiveRefreshSnapshot(days: days, depth: loadedDepth, hasMore: hasMore)))
        .map { String(format: "%02x", $0) }.joined()
}

private func goalArchiveRefreshPrint(name: String, count: Int, samples: [Double], digests: [String],
                                      readScheduled: [Bool]?, taskEdits: Int, reviewEdits: Int) throws {
    let ordered = samples.sorted()
    let midpoint = ordered.count / 2
    let p50 = ordered.count.isMultiple(of: 2) ? (ordered[midpoint - 1] + ordered[midpoint]) / 2 : ordered[midpoint]
    var record: [String: Any] = [
        "scenario": name, "tasks": count, "seedEvents": count * 10, "appendedEvents": taskEdits * 2,
        "reviewEdits": reviewEdits, "dayRange": "2026-09-03...2026-10-02", "depth": 1,
        "store": "synthetic-in-memory", "locale": Locale.current.identifier, "unit": "ms",
        "n": samples.count, "warmup": 1, "p50": p50,
        "p95": ordered[Int(ceil(Double(ordered.count) * 0.95)) - 1], "p95Estimator": "nearest-rank",
        "max": ordered.last ?? 0, "rawSamples": samples, "sampleDigests": digests,
        "smallSample": samples.count < 30,
        "digest": SHA256.hash(data: Data(digests.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined(),
    ]
    if let readScheduled { record["sessionReadScheduled"] = readScheduled }
    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    print("GOAL_ARCHIVE_REFRESH_BENCHMARK \(String(decoding: data, as: UTF8.self))")
}

private func goalArchiveRefreshID(namespace: Int, index: Int) -> UUID {
    let suffix = String(index, radix: 16)
    let padded = String(repeating: "0", count: 12 - suffix.count) + suffix
    return UUID(uuidString: "0000000\(namespace)-0000-4000-8000-\(padded)")!
}
#endif
