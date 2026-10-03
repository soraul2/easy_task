#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

// Test-only hypothesis: existing production Watch.make versus a private helper
// that preserves the accepted C3 input policy but creates only its first summary.
// The helper is NOT an adopted production API or a measured production change.
private let goalWatchProjectionEnabled =
    ProcessInfo.processInfo.environment["PLANBASE_GOAL_WATCH_PROJECTION_PERFORMANCE"] == "1"
private let goalWatchProjectionRepeat =
    ProcessInfo.processInfo.environment["PLANBASE_GOAL_WATCH_PROJECTION_REPEAT"] ?? "1"

private func goalWatchProjectionID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

@MainActor
private struct GoalWatchProjectionFixture {
    let container: ModelContainer
    let referenceDate: Date
    let tasks: [EasyTaskCore.Task]
    let allEvents: [CalendarEvent]
    let todayEvents: [CalendarEvent]

    init(todayTaskCount: Int, storedTaskCount: Int = 3_000) throws {
        container = try PlanBaseContainerFactory.makeInMemory()
        referenceDate = try #require(DayKey.date(from: "2026-08-06"))
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<storedTaskCount {
            let isToday = index < todayTaskCount
            let day = isToday ? referenceDate : DayKey.addingDays(-(1 + index % 120), to: referenceDate)
            let status: TaskStatus = isToday ? (index % 3 == 1 ? .doing : .todo) : .done
            let task = EasyTaskCore.Task(
                title: String(format: "성능 작업 %04d", index), status: status,
                plannedAt: day, order: Double(index), createdAt: timestamp, updatedAt: timestamp)
            task.id = goalWatchProjectionID(index + 1)
            task.instanceID = goalWatchProjectionID(index + 10_001)
            if !isToday {
                task.completedAt = day
                task.completedDayKey = DayKey.key(for: day)
                task.archivedAt = DayKey.addingDays(1, to: day)
                task.archivedDayKey = DayKey.key(for: DayKey.addingDays(1, to: day))
            }
            context.insert(task)
        }
        // Same 90-day distribution as ResponsivenessPreviewFixtures: two
        // physical events per day, including exactly two on the reference day.
        for index in 0..<180 {
            let day = DayKey.addingDays(index % 90 - 45, to: referenceDate)
            context.insert(CalendarEvent(
                id: goalWatchProjectionID(index + 20_001), instanceID: goalWatchProjectionID(index + 30_001),
                title: "성능 일정 \(index)", startAt: day, endAt: day.addingTimeInterval(3_600),
                createdAt: timestamp, updatedAt: timestamp))
        }
        try context.save()
        let key = DayKey.key(for: referenceDate)
        // Actual Watch publisher descriptor. Store seeding/query time is untimed.
        tasks = try context.fetch(BoundedQueryService.boardTasksDescriptor(selectedDayKey: key))
        allEvents = try context.fetch(FetchDescriptor<CalendarEvent>())
        todayEvents = try context.fetch(BoundedQueryService.eventsDescriptor(
            overlappingStartDayKey: key, endDayKey: key))
        #expect(tasks.count == todayTaskCount)
        #expect(allEvents.count == 180)
        #expect(todayEvents.count == 2)
    }
}

// Legacy baseline source SHA256:
// LockScreenWidgetRules.swift 3612b0c86df93d7a7d3eccb9fc35c4a668cc93fb41c541136fb082cbba96699e
// WatchWidgetSnapshot.swift 227dd7223ac8701699e47b8a68d20526434dd88656be4da5b901a17e5912d62c
// Pre-C3 test file SHA256:
// d274244a3afab9f4edd500f01e639f4ffcfdab51cc4fbccd6f310ba56f29e76c
// C3 adopted representative-before-visibility. Match that accepted policy here;
// do not turn a legacy old-row revival into an equality requirement. Eight-day
// coverage preparation remains intact; only summary generation is a one-day hypothesis.
@MainActor
private func goalWatchOneDayReference(
    tasks: [EasyTaskCore.Task], events: [CalendarEvent], referenceDate: Date,
    activeFocus: FocusActiveSessionSnapshot? = nil
) -> WatchWidgetSnapshot {
    let startDate = DayKey.startOfDay(for: referenceDate)
    let startKey = DayKey.key(for: startDate)
    let endKey = DayKey.key(for: DayKey.addingDays(7, to: startDate))
    let activeTasks = goalWatchRepresentativeTasks(tasks.filter {
        $0.supersededAt == nil && $0.archivedAt == nil && TaskStatus(rawValue: $0.status) != nil
    })
    let activeEvents = goalWatchRepresentativeEvents(events.filter { $0.supersededAt == nil })
        .filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && DayKey.date(from: $0.startDayKey) != nil
                && DayKey.date(from: $0.endDayKey) != nil
                && $0.startDayKey <= $0.endDayKey
                && $0.startDayKey <= endKey
                && $0.endDayKey >= startKey
        }
    let todo = activeTasks.filter { $0.status == TaskStatus.todo.rawValue && $0.plannedDayKey == startKey }
        .sorted(by: goalWatchTaskSort)
    let doing = activeTasks.filter { $0.status == TaskStatus.doing.rawValue && $0.plannedDayKey == startKey }
        .sorted(by: goalWatchTaskSort)
    let done = activeTasks.filter { $0.status == TaskStatus.done.rawValue && $0.plannedDayKey == startKey }
    let dayEvents = activeEvents.filter { $0.startDayKey <= startKey && startKey <= $0.endDayKey }
        .sorted(by: goalWatchEventSort)
    let focus = goalWatchFirstTitledTask(doing).map { ($0, LockScreenWidgetFocusKind.doingTask) }
        ?? goalWatchFirstTitledEvent(dayEvents).map { ($0, LockScreenWidgetFocusKind.event) }
        ?? goalWatchFirstTitledTask(todo).map { ($0, LockScreenWidgetFocusKind.todoTask) }
    let summary = LockScreenWidgetDaySummary(
        dayKey: startKey, todoCount: todo.count, doingCount: doing.count, doneCount: done.count,
        eventCount: dayEvents.count, focusTitle: focus?.0, focusKind: focus?.1)
    // Reuse the actual constructor for all Focus validation/metadata/fallback.
    return WatchWidgetSnapshot(
        generatedAt: referenceDate, dayKey: DayKey.key(for: referenceDate),
        todoCount: summary.todoCount, doingCount: summary.doingCount, doneCount: summary.doneCount,
        eventCount: summary.eventCount, focusTitle: summary.focusTitle, focusKind: summary.focusKind,
        activeFocus: activeFocus)
}

@MainActor
private func goalWatchRepresentativeTasks(_ tasks: [EasyTaskCore.Task]) -> [EasyTaskCore.Task] {
    Dictionary(grouping: tasks, by: \.id).values.compactMap { candidates in
        candidates.max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.instanceID.uuidString < rhs.instanceID.uuidString
        }
    }
}

@MainActor
private func goalWatchRepresentativeEvents(_ events: [CalendarEvent]) -> [CalendarEvent] {
    Dictionary(grouping: events, by: \.id).values.compactMap { candidates in
        candidates.max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.instanceID.uuidString < rhs.instanceID.uuidString
        }
    }
}

private func goalWatchNormalizedTitle(_ title: String) -> String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
}

@MainActor
private func goalWatchFirstTitledTask(_ tasks: [EasyTaskCore.Task]) -> String? {
    tasks.lazy.map { goalWatchNormalizedTitle($0.title) }.first { !$0.isEmpty }
}

@MainActor
private func goalWatchFirstTitledEvent(_ events: [CalendarEvent]) -> String? {
    events.lazy.map { goalWatchNormalizedTitle($0.title) }.first { !$0.isEmpty }
}

@MainActor
private func goalWatchTaskSort(_ lhs: EasyTaskCore.Task, _ rhs: EasyTaskCore.Task) -> Bool {
    if lhs.order != rhs.order { return lhs.order < rhs.order }
    let lhsTitle = goalWatchNormalizedTitle(lhs.title)
    let rhsTitle = goalWatchNormalizedTitle(rhs.title)
    if lhsTitle != rhsTitle { return lhsTitle < rhsTitle }
    return lhs.id.uuidString < rhs.id.uuidString
}

@MainActor
private func goalWatchEventSort(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
    if lhs.startDayKey != rhs.startDayKey { return lhs.startDayKey < rhs.startDayKey }
    if lhs.endDayKey != rhs.endDayKey { return lhs.endDayKey > rhs.endDayKey }
    let lhsTitle = goalWatchNormalizedTitle(lhs.title)
    let rhsTitle = goalWatchNormalizedTitle(rhs.title)
    if lhsTitle != rhsTitle { return lhsTitle < rhsTitle }
    if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
    return lhs.instanceID.uuidString < rhs.instanceID.uuidString
}

private func goalWatchSnapshotDigest(_ snapshot: WatchWidgetSnapshot) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .millisecondsSince1970
    return SHA256.hash(data: try encoder.encode(snapshot)).map { String(format: "%02x", $0) }.joined()
}

@MainActor
@inline(never)
private func goalWatchTimedProjection(
    _ operation: () -> WatchWidgetSnapshot
) -> (snapshot: WatchWidgetSnapshot, milliseconds: Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let snapshot = operation()
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    return (snapshot, Double(elapsed) / 1_000_000)
}

private func goalWatchProjectionReport(
    algorithm: String, details: String, samples: [Double], digest: String
) {
    let sorted = samples.sorted()
    let p95Index = Int(ceil(Double(samples.count) * 0.95)) - 1
    print("GOAL_WATCH_PROJECTION_BENCHMARK algorithm=\(algorithm) candidateKind=test-only-hypothesis unit=ms warmupPerAlgorithm=1 n=\(samples.count) pairs=30 independentInvocationCount=1 repeatLabel=\(goalWatchProjectionRepeat) order=alternating \(details) timezone=\(TimeZone.current.identifier) p50=\(sorted[samples.count / 2]) p95=\(sorted[p95Index]) max=\(sorted.last ?? 0) digest=\(digest) samples=\(samples)")
}

@Test(.enabled(if: goalWatchProjectionEnabled))
@MainActor
func goalWatchOneDayProjectionHypothesisPerformance() throws {
    for taskCount in [20, 240] {
        let fixture = try GoalWatchProjectionFixture(todayTaskCount: taskCount)
        for events in [fixture.todayEvents, fixture.allEvents] {
            let details = "storedTasks=3000 fetchedTasks=\(fixture.tasks.count) storedEvents=180 inputEvents=\(events.count) inputPolicy=\(events.count == 2 ? "watch-bounded-day" : "full-array-baseline") referenceDay=\(DayKey.key(for: fixture.referenceDate)) focus=nil"
            let original = {
                WatchWidgetSnapshot.make(tasks: fixture.tasks, events: events, referenceDate: fixture.referenceDate)
            }
            let candidate = {
                goalWatchOneDayReference(tasks: fixture.tasks, events: events, referenceDate: fixture.referenceDate)
            }
            let expected = original()
            #expect(candidate() == expected)
            let digest = try goalWatchSnapshotDigest(expected)
            var originalSamples: [Double] = []
            var candidateSamples: [Double] = []
            for index in 0..<30 {
                let baseline: (snapshot: WatchWidgetSnapshot, milliseconds: Double)
                let hypothesis: (snapshot: WatchWidgetSnapshot, milliseconds: Double)
                if index.isMultiple(of: 2) {
                    baseline = goalWatchTimedProjection(original)
                    hypothesis = goalWatchTimedProjection(candidate)
                } else {
                    hypothesis = goalWatchTimedProjection(candidate)
                    baseline = goalWatchTimedProjection(original)
                }
                originalSamples.append(baseline.milliseconds)
                candidateSamples.append(hypothesis.milliseconds)
                // Full Equatable value + full Codable digest, outside both timers.
                #expect(baseline.snapshot == expected)
                #expect(hypothesis.snapshot == expected)
                #expect(try goalWatchSnapshotDigest(baseline.snapshot) == digest)
                #expect(try goalWatchSnapshotDigest(hypothesis.snapshot) == digest)
            }
            goalWatchProjectionReport(algorithm: "actual-watch-eight-day", details: details, samples: originalSamples, digest: digest)
            goalWatchProjectionReport(algorithm: "one-day-private-reference", details: details, samples: candidateSamples, digest: digest)
        }
    }
}

@Test @MainActor
func goalWatchOneDayReferencePreservesFocusMetadataAndMidnightControls() throws {
    let fixture = try GoalWatchProjectionFixture(todayTaskCount: 20, storedTaskCount: 20)
    let midnight = DayKey.startOfDay(for: fixture.referenceDate)
    let nextMidnight = DayKey.addingDays(1, to: midnight)
    let references = [midnight.addingTimeInterval(-1), midnight, nextMidnight.addingTimeInterval(-1), nextMidnight]
    let active = FocusTimerRules.startFocus(
        taskID: goalWatchProjectionID(1), taskTitle: "  집중 작업  ", focusSeconds: 25 * 60, now: midnight)
    let paused = try FocusTimerRules.pause(active, now: midnight.addingTimeInterval(30))
    var blankActive = active
    blankActive.taskTitleSnapshot = " \n "
    var invalidActive = active
    invalidActive.revision = 0
    let focuses: [FocusActiveSessionSnapshot?] = [nil, active, paused, blankActive, invalidActive]
    for reference in references {
        for focus in focuses {
            let original = WatchWidgetSnapshot.make(
                tasks: fixture.tasks, events: fixture.todayEvents, referenceDate: reference, activeFocus: focus)
            let candidate = goalWatchOneDayReference(
                tasks: fixture.tasks, events: fixture.todayEvents, referenceDate: reference, activeFocus: focus)
            #expect(candidate == original)
            #expect(try goalWatchSnapshotDigest(candidate) == goalWatchSnapshotDigest(original))
            #expect(candidate.generatedAt == reference)
            #expect(candidate.dayKey == DayKey.key(for: reference))
        }
    }
    // Legacy tasks without progress events and the same task rows after adding
    // progress records give the same snapshot; this API consumes task status.
    let beforeProgress = WatchWidgetSnapshot.make(tasks: fixture.tasks, events: fixture.todayEvents, referenceDate: midnight)
    fixture.container.mainContext.insert(TaskProgressEvent(taskId: goalWatchProjectionID(1), kind: .started, occurredAt: midnight))
    fixture.container.mainContext.insert(TaskProgressEvent(taskId: goalWatchProjectionID(1), kind: .stopped, occurredAt: midnight.addingTimeInterval(30)))
    #expect(goalWatchOneDayReference(tasks: fixture.tasks, events: fixture.todayEvents, referenceDate: midnight) == beforeProgress)
    #expect(WatchWidgetSnapshot.make(tasks: fixture.tasks, events: fixture.todayEvents, referenceDate: midnight) == beforeProgress)
    fixture.container.mainContext.rollback()
}

@Test @MainActor
func goalWatchOneDayReferenceKeepsFutureRepresentativeAndBlankTaskFallback() throws {
    let fixture = try GoalWatchProjectionFixture(todayTaskCount: 20, storedTaskCount: 20)
    let context = fixture.container.mainContext
    let today = fixture.referenceDate
    let tomorrow = DayKey.addingDays(1, to: today)
    let old = CalendarEvent(id: goalWatchProjectionID(50_001), instanceID: goalWatchProjectionID(60_001),
        title: "이전 당일", startAt: today, endAt: today, updatedAt: Date(timeIntervalSince1970: 10))
    let latest = CalendarEvent(id: old.id, instanceID: goalWatchProjectionID(60_002),
        title: "최신 미래", startAt: tomorrow, endAt: tomorrow, updatedAt: Date(timeIntervalSince1970: 20))
    context.insert(old)
    context.insert(latest)
    let blank = EasyTaskCore.Task(title: " \n ", status: .doing, plannedAt: today, order: -100)
    let todo = EasyTaskCore.Task(title: "  할 일 fallback  ", status: .todo, plannedAt: today, order: -200)
    context.insert(blank)
    context.insert(todo)
    try context.save()
    let tasks = [blank, todo]
    let events = [old, latest]
    let original = WatchWidgetSnapshot.make(tasks: tasks, events: events, referenceDate: today)
    let candidate = goalWatchOneDayReference(tasks: tasks, events: events, referenceDate: today)
    #expect(candidate == original)
    #expect(candidate.eventCount == 0)
    #expect(candidate.doingCount == 1)
    #expect(candidate.todoCount == 1)
    #expect(candidate.focusTitle == "할 일 fallback")
    #expect(candidate.focusKind == .todoTask)
}

@Test @MainActor
func goalWatchOneDayReferenceUsesAcceptedRepresentativeBeforeVisibilityPolicy() throws {
    for scenario in ["outside", "blank", "invalid"] {
        let fixture = try GoalWatchProjectionFixture(todayTaskCount: 20, storedTaskCount: 20)
        let context = fixture.container.mainContext
        let today = fixture.referenceDate
        let latestDate = scenario == "outside" ? DayKey.addingDays(20, to: today) : today
        let old = CalendarEvent(id: goalWatchProjectionID(50_001), instanceID: goalWatchProjectionID(60_001),
            title: "구형 오늘", startAt: today, endAt: today, updatedAt: Date(timeIntervalSince1970: 10))
        let latest = CalendarEvent(id: old.id, instanceID: goalWatchProjectionID(60_002),
            title: "최신", startAt: latestDate, endAt: latestDate, updatedAt: Date(timeIntervalSince1970: 20))
        if scenario == "blank" { latest.title = " \n " }
        if scenario == "invalid" { latest.startDayKey = "2026-02-30" }
        context.insert(old)
        context.insert(latest)
        try context.save()
        let events = [old, latest]
        let original = WatchWidgetSnapshot.make(tasks: [], events: events, referenceDate: today)
        let candidate = goalWatchOneDayReference(tasks: [], events: events, referenceDate: today)
        #expect(candidate == original)
        #expect(try goalWatchSnapshotDigest(candidate) == goalWatchSnapshotDigest(original))
        #expect(candidate.eventCount == 0)
        #expect(candidate.focusTitle == nil)
    }
}
#endif
