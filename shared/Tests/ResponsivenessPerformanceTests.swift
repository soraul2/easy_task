#if DEBUG
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Opt-in, optimized local-store microbenchmarks. These do not measure rendered frames.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_RESPONSIVENESS_PERFORMANCE"] == "1"))
@MainActor
func responsivenessCoreBaseline() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseResponsiveness-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try PlanBaseContainerFactory.makePersistent(
        storeURL: directory.appendingPathComponent("fixture.store"), mode: .local)
    let context = container.mainContext
    try ResponsivenessPreviewFixtures.seed(in: context)
    let today = DayKey.today
    let rows = try context.fetch(BoundedQueryService.boardTasksDescriptor(selectedDayKey: today))
    #expect(rows.count == 240)

    // Retain the 9c5a7df tab-handler operation as an explicit reference, not a UI simulation.
    try reportResponsivenessSamples("reference-tab-archive-command", count: 50) {
        try PersistenceCommandService.perform(in: context) {
            let candidates = try context.fetch(
                BoundedQueryService.tasksNeedingArchiveDescriptor(before: today))
            TaskRules.archiveIfNeeded(candidates, todayKey: today)
        }
    }
    try reportResponsivenessSamples("conditional-tab-archive-command", count: 50) {
        _ = try ArchiveMaintenanceService.archiveCompletedTasks(in: context, todayKey: today)
    }
    reportResponsivenessSamples("board-projection-240", count: 50) {
        _ = BoardQueryRules.tasksForBoard(rows, selectedDayKey: today)
    }
    try reportResponsivenessSamples("saved-task-load-1000", count: 20) {
        let entries = try SavedTaskLibraryService.load(in: context)
        #expect(entries.count == 1_000)
    }
    try reportResponsivenessSamples("startup-integrity-3000", count: 3) {
        try PersistenceCommandService.perform(in: context) {
            _ = try DataIntegrityService.reconcile(context: context, saveChanges: false)
        }
    }
    let report = try DataIntegrityService.reconcile(context: context, saveChanges: false)
    print("RESPONSIVENESS_INTEGRITY reportHasChanges=\(report.hasChanges) contextHasChanges=\(context.hasChanges)")
    try context.save()
    var pageSamples: [Double] = []
    for _ in 0..<6 {
        let service = DailyActivityQueryService(context: context)
        let start = DispatchTime.now().uptimeNanoseconds
        let page = try await service.page(filter: ArchiveFilter(contentMode: .dailyActivity))
        pageSamples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        #expect(page.records.count == 30)
    }
    print("RESPONSIVENESS_BENCHMARK name=daily-page-3000 unit=ms warmup=\(pageSamples.removeFirst()) samples=\(pageSamples)")
}

@MainActor
private func reportResponsivenessSamples(
    _ name: String, count: Int, operation: () throws -> Void
) rethrows {
    // One unmeasured warm-up; raw samples let the report preserve outliers.
    try operation()
    var samples: [Double] = []
    for _ in 0..<count {
        let start = DispatchTime.now().uptimeNanoseconds
        try operation()
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
    let ordered = samples.sorted()
    let p95 = ordered[Int(ceil(Double(count) * 0.95)) - 1]
    print("RESPONSIVENESS_BENCHMARK name=\(name) unit=ms n=\(count) p50=\(ordered[count / 2]) p95=\(p95) samples=\(samples)")
}
#endif
