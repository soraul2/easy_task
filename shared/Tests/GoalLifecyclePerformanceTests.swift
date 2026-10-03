#if DEBUG
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Isolated CPU/query baselines. No application, App Group or system notification writes.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_LIFECYCLE_PERFORMANCE"] == "1"))
@MainActor
func goalLifecyclePerformance() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseGoalLifecycle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makePersistent(
        storeURL: directory.appendingPathComponent("fixture.store"), mode: .local)
    let context = container.mainContext
    try ResponsivenessPreviewFixtures.seed(in: context)
    let today = DayKey.today
    let tasks = try context.fetch(BoundedQueryService.boardTasksDescriptor(selectedDayKey: today))
    let events = try context.fetch(FetchDescriptor<CalendarEvent>())
    #expect(tasks.count == 240)
    // The fixture's 180 event colors need normalizing on first reconciliation.
    // Prepare that once outside the repeated steady-state interval.
    try PersistenceCommandService.perform(in: context) {
        _ = try DataIntegrityService.reconcile(context: context, saveChanges: false)
    }
    try goalLifecycleSamples("startup-integrity-3000", count: 5) {
        try PersistenceCommandService.perform(in: context) {
            let report = try DataIntegrityService.reconcile(context: context, saveChanges: false)
            #expect(!report.hasChanges)
        }
    }
    try goalLifecycleSamples("unchanged-tab-archive-3000", count: 30) {
        let count = try ArchiveMaintenanceService.archiveCompletedTasks(in: context, todayKey: today)
        #expect(count == 0)
    }
    try goalLifecycleSamples("focus-candidates-3000", count: 30) {
        let candidates = try FocusTaskQueryService.candidates(selectedTaskID: nil, in: context)
        #expect(candidates.count == 100)
    }
    try goalLifecycleSamples("focus-today-summary-3000", count: 30) {
        let summary = try FocusSessionQueryService.summary(in: context)
        #expect(summary.sessionCount == 0)
    }
    goalLifecycleSamples("calendar-widget-projection-240-180", count: 30) {
        let snapshot = CalendarWidgetSnapshot.make(events: events, tasks: tasks)
        #expect(!snapshot.events.isEmpty)
    }
    goalLifecycleSamples("watch-widget-projection-240-180", count: 30) {
        let snapshot = WatchWidgetSnapshot.make(tasks: tasks, events: events)
        #expect(snapshot.todoCount + snapshot.doingCount == 240)
    }
    // Read progress once, then repeat the same production session getter used by board cards.
    let session = TaskProgressEventQuerySession(context: context)
    session.apply(taskIDs: Set(tasks.map(\.id)))
    for _ in 0..<500 where session.isLoading { await Swift.Task.yield() }
    #expect(session.errorMessage == nil)
    #expect(!session.isLoading)
    goalLifecycleSamples("board-progress-projections-240", count: 30) {
        var intervalCount = 0
        for task in tasks { intervalCount += session.projection(for: task.id).intervals.count }
        #expect(intervalCount == 240)
    }
    goalLifecycleSamples("progress-start-formatting-240", count: 30) {
        var characters = 0
        for task in tasks { characters += TaskProgressEventRules.startTimeText(for: task.updatedAt).count }
        #expect(characters > 0)
    }
    session.cancel()
    #expect(!context.hasChanges)
    withExtendedLifetime(container) {}
}

@MainActor
private func goalLifecycleSamples(_ name: String, count: Int, operation: () throws -> Void) rethrows {
    try operation()
    var values: [Double] = []
    for _ in 0..<count {
        let start = DispatchTime.now().uptimeNanoseconds
        try operation()
        values.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
    let sorted = values.sorted()
    print("GOAL_BENCHMARK name=\(name) unit=ms n=\(count) p50=\(sorted[count / 2]) p95=\(sorted[Int(ceil(Double(count) * 0.95)) - 1]) max=\(sorted.last!) samples=\(values)")
}
#endif
