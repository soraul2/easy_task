import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_ARCHIVE_PERFORMANCE"] == "1"))
@MainActor
func dailyActivityLargeStoreBenchmark() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let today = DayKey.startOfDay(for: Date())
    for index in 0..<10_000 {
        let day = DayKey.addingDays(-(index % 365), to: today)
        let task = Task(title: "성능 검증 \(index)", plannedAt: day, order: Double(index))
        context.insert(task)
        for interval in 0..<5 {
            let start = day.addingTimeInterval(Double(3600 + interval * 600))
            context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: start))
            context.insert(TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: start.addingTimeInterval(300)))
        }
        if index % 500 == 499 { try context.save() }
    }
    try context.save()
    let service = DailyActivityQueryService(context: ModelContext(container))
    let clock = ContinuousClock()
    let firstStart = clock.now
    let first = try await service.page(filter: ArchiveFilter(contentMode: .dailyActivity))
    let firstDuration = firstStart.duration(to: clock.now)
    let nextStart = clock.now
    let next = try await service.page(filter: ArchiveFilter(contentMode: .dailyActivity), beforeDayKey: first.nextBeforeDayKey)
    let nextDuration = nextStart.duration(to: clock.now)
    print("ARCHIVE_BENCHMARK tasks=10000 events=100000 initial=\(firstDuration) next=\(nextDuration)")
    #expect(first.records.count == 30)
    #expect(next.records.count == 30)
    #expect(first.records.flatMap { $0.activityEntries ?? [] }.allSatisfy { $0.evidence.progressSeconds == 1500 })
    #expect(Set(first.records.map(\.dayKey)).isDisjoint(with: next.records.map(\.dayKey)))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_ARCHIVE_PERFORMANCE"] == "1"))
@MainActor
func dailyActivitySingleLongTaskBenchmark() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let today = DayKey.startOfDay(for: Date())
    let task = Task(title: "오래 진행한 작업", plannedAt: today, order: 100)
    context.insert(task)
    for interval in 0..<10_000 {
        let start = today.addingTimeInterval(-Double(interval * 600 + 300))
        context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: start))
        context.insert(TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: start.addingTimeInterval(120)))
        if interval % 500 == 499 { try context.save() }
    }
    try context.save()
    let service = DailyActivityQueryService(context: ModelContext(container))
    let clock = ContinuousClock()
    let started = clock.now
    let first = try await service.page(filter: ArchiveFilter(contentMode: .dailyActivity))
    print("ARCHIVE_SKEW_BENCHMARK tasks=1 events=20000 initial=\(started.duration(to: clock.now))")
    #expect(first.records.count == 30)
    #expect(first.records.allSatisfy { $0.activityEntries?.count == 1 })
    #expect(first.records.allSatisfy { $0.activityEntries?.first?.evidence.progressSeconds == 17280 })
}
