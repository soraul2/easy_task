import Foundation
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func archiveSessionAppliesOnlyTheLatestDebouncedSearch() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let date = try #require(DayKey.date(from: DayKey.today))
    let previousDate = DayKey.addingDays(-1, to: date)

    let alpha = Task(title: "alpha", status: .done, plannedAt: previousDate, order: 100)
    alpha.completedAt = previousDate
    alpha.completedDayKey = DayKey.key(for: previousDate)
    let beta = Task(title: "beta", status: .done, plannedAt: date, order: 200)
    beta.completedAt = date
    beta.completedDayKey = DayKey.today
    context.insert(alpha)
    context.insert(beta)
    try context.save()

    let session = ArchiveQuerySession(context: context)
    var firstFilter = ArchiveFilter()
    firstFilter.searchText = "alpha"
    var finalFilter = ArchiveFilter()
    finalFilter.searchText = "beta"

    session.apply(firstFilter, debounceSearch: true)
    session.apply(finalFilter, debounceSearch: true)
    for _ in 0..<100 {
        if !session.records.isEmpty { break }
        try await Swift.Task.sleep(for: .milliseconds(50))
    }

    #expect(session.records.count == 1)
    #expect(session.records.first?.tasks.map(\.title) == ["beta"])
}

@Test
@MainActor
func archiveSessionRefreshPreservesLoadedPageDepth() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let referenceDate = try #require(DayKey.date(from: DayKey.today))

    for offset in 0..<35 {
        let date = DayKey.addingDays(-offset, to: referenceDate)
        let task = Task(
            title: "작업 \(offset)",
            status: .done,
            plannedAt: date,
            order: 100
        )
        task.completedAt = date
        task.completedDayKey = DayKey.key(for: date)
        context.insert(task)
    }
    try context.save()

    let session = ArchiveQuerySession(context: context)
    session.apply(ArchiveFilter(), debounceSearch: false)
    session.loadNextPage()

    #expect(session.loadedPageCount == 2)
    #expect(session.records.count == 35)

    session.refreshPreservingDepth()

    #expect(session.loadedPageCount == 2)
    #expect(session.records.count == 35)
    #expect(Set(session.records.map(\.dayKey)).count == 35)
}
