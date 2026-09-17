import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@MainActor
private func inboxTask(id: UUID = UUID(), day: String = "2026-09-15", updated: Date = .distantPast) throws -> Task {
    Task(id: id, title: "이월 작업", status: .todo,
         plannedAt: try #require(DayKey.date(from: day)), order: 0, updatedAt: updated)
}

@Test @MainActor
func carryoverInboxBaselineAndRelaunchKeepTotalButAcknowledgeOnlyDisplayedEntries() throws {
    let suite = "CarryoverTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let existing = try inboxTask()
    let arriving = try inboxTask()
    var rows = [existing]
    let session = CarryoverInboxSession(defaults: defaults) { _ in rows }
    session.refresh(todayKey: "2026-09-17")
    #expect(session.count == 1)
    #expect(session.newCount == 0)
    rows.append(arriving)
    session.refresh(todayKey: "2026-09-17")
    #expect(session.newCount == 1)

    let relaunched = CarryoverInboxSession(defaults: defaults) { _ in rows }
    relaunched.refresh(todayKey: "2026-09-17")
    #expect(relaunched.newCount == 1)
    relaunched.didDisplayInbox()
    #expect(relaunched.count == 2)
    #expect(relaunched.newCount == 0)
    #expect(relaunched.displayedNewCount == 1)
    #expect(relaunched.displayedTasks.first?.id == arriving.id)
    relaunched.refresh(todayKey: "2026-09-17")
    #expect(relaunched.displayedNewCount == 1)
    relaunched.endPresentation()
    relaunched.didDisplayInbox()
    #expect(relaunched.displayedNewCount == 0)
}

@Test @MainActor
func carryoverInboxFailedLoadNeverEstablishesBaselineOrAcknowledgesNewEntries() throws {
    enum Failure: Error { case unavailable }
    let suite = "CarryoverTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var fails = true
    var rows = [try inboxTask()]
    let session = CarryoverInboxSession(defaults: defaults) { _ in
        if fails { throw Failure.unavailable }
        return rows
    }
    session.refresh(todayKey: "2026-09-17")
    session.didDisplayInbox()
    #expect(!session.hasLoaded)
    #expect(defaults.data(forKey: "PlanBaseCarryoverInboxReceipt.v1") == nil)
    fails = false
    session.refresh(todayKey: "2026-09-17")
    #expect(session.newCount == 0)
    rows.append(try inboxTask())
    session.refresh(todayKey: "2026-09-17")
    fails = true
    session.refresh(todayKey: "2026-09-17")
    session.didDisplayInbox()
    #expect(session.newCount == 1)
    #expect(session.count == 2)
    fails = false
    session.refresh(todayKey: "2026-09-17")
    session.didDisplayInbox()
    #expect(session.newCount == 0)
    #expect(session.displayedNewCount == 1)
}

@Test @MainActor
func carryoverInboxRolloverRenameAndRepresentativeReplacementHaveStableEntryIdentity() throws {
    let suite = "CarryoverTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let task = try inboxTask(day: "2026-09-17")
    var rows = [task]
    let session = CarryoverInboxSession(defaults: defaults) {
        CarryoverInboxRules.tasks(from: rows, todayKey: $0)
    }
    session.refresh(todayKey: "2026-09-17")
    #expect(session.count == 0)
    session.refresh(todayKey: "2026-09-18")
    #expect(session.newCount == 1)
    session.didDisplayInbox()
    session.endPresentation()
    let replacement = try inboxTask(id: task.id, day: task.plannedDayKey, updated: Date())
    replacement.title = "이름 수정"
    rows = [task, replacement]
    session.refresh(todayKey: "2026-09-18")
    #expect(session.count == 1)
    #expect(session.newCount == 0)
    replacement.plannedDayKey = "2026-09-18"
    session.refresh(todayKey: "2026-09-18")
    #expect(session.count == 0)
    session.refresh(todayKey: "2026-09-19")
    #expect(session.newCount == 1)
}

@Test @MainActor
func carryoverInboxBannerDismissalDoesNotMarkSeenOrRepeatAnnouncedEntriesTomorrow() throws {
    let suite = "CarryoverTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var rows: [Task] = []
    let session = CarryoverInboxSession(defaults: defaults) { _ in rows }
    session.refresh(todayKey: "2026-09-17")
    rows.append(try inboxTask())
    session.refresh(todayKey: "2026-09-17")
    #expect(session.bannerKeys.count == 1)
    session.didDisplayBanner()
    session.dismissBanner()
    #expect(session.newCount == 1)
    rows.append(try inboxTask())
    session.refresh(todayKey: "2026-09-17")
    #expect(session.bannerKeys.isEmpty)
    #expect(session.newCount == 2)
    session.refresh(todayKey: "2026-09-18")
    #expect(session.bannerKeys.count == 1)
    session.didDisplayBanner()
    session.refresh(todayKey: "2026-09-19")
    #expect(session.bannerKeys.isEmpty)
    #expect(session.newCount == 2)
}

@Test @MainActor
func carryoverInboxArrivalWhileOpenKeepsNewSectionUntilDismissal() throws {
    let suite = "CarryoverTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var rows: [Task] = []
    let session = CarryoverInboxSession(defaults: defaults) { _ in rows }
    session.refresh(todayKey: "2026-09-17")
    session.didDisplayInbox()
    rows.append(try inboxTask())
    session.refresh(todayKey: "2026-09-17")
    #expect(session.newCount == 1)
    #expect(session.bannerKeys.isEmpty)
    session.didDisplayInbox()
    #expect(session.newCount == 0)
    #expect(session.displayedNewCount == 1)
    rows.removeAll()
    session.refresh(todayKey: "2026-09-17")
    #expect(session.displayedNewCount == 0)
    #expect(session.count == 0)
}

@Test @MainActor
func carryoverInboxQueryChoosesRepresentativeBeforeEligibilityAndCountsLogicalIDs() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = ModelContext(container)
    let old = try inboxTask()
    let completed = try inboxTask(id: old.id, updated: Date())
    completed.status = TaskStatus.done.rawValue
    let movedOld = try inboxTask()
    let movedNew = try inboxTask(id: movedOld.id, day: "2026-09-18", updated: Date())
    let visibleOld = try inboxTask()
    let visibleNew = try inboxTask(id: visibleOld.id, updated: Date())
    let archived = try inboxTask()
    archived.archivedAt = Date()
    for row in [old, completed, movedOld, movedNew, visibleOld, visibleNew, archived] { context.insert(row) }
    try context.save()
    let result = try CarryoverInboxRules.fetch(in: context, todayKey: "2026-09-17")
    #expect(result.count == 1)
    #expect(result.first?.instanceID == visibleNew.instanceID)
}

@Test @MainActor
func carryoverInboxCorruptReceiptSafelyBaselinesWithoutTouchingTask() throws {
    let suite = "CarryoverTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Data("corrupt".utf8), forKey: "PlanBaseCarryoverInboxReceipt.v1")
    let task = try inboxTask()
    let updatedAt = task.updatedAt
    let session = CarryoverInboxSession(defaults: defaults) { _ in [task] }
    session.refresh(todayKey: "2026-09-17")
    session.didDisplayInbox()
    #expect(session.count == 1)
    #expect(session.newCount == 0)
    #expect(task.updatedAt == updatedAt)
    #expect(task.status == TaskStatus.todo.rawValue)
}

@Test(arguments: [0, 1, 99, 100, 140]) @MainActor
func carryoverInboxCountsAcrossBadgeAndFetchBatchBoundaries(count: Int) throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    for index in 0..<count {
        let task = try inboxTask()
        task.status = (index.isMultiple(of: 2) ? TaskStatus.todo : .doing).rawValue
        context.insert(task)
        let stale = try inboxTask(id: task.id, updated: .distantPast)
        stale.supersededAt = Date()
        context.insert(stale)
    }
    try context.save()
    let rows = try CarryoverInboxRules.fetch(in: context, todayKey: "2026-09-17")
    #expect(rows.count == count)
    #expect(Set(rows.map(\.id)).count == count)
}

@Test @MainActor
func carryoverInboxTimeZoneRoundTripAndFailedMoveDoNotCreateNewArrival() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let task = try inboxTask(day: "2026-09-17")
    context.insert(task)
    try context.save()
    let suite = "CarryoverTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let session = CarryoverInboxSession(defaults: defaults) {
        try CarryoverInboxRules.fetch(in: context, todayKey: $0)
    }
    var seoul = Calendar(identifier: .gregorian)
    seoul.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
    var la = seoul
    la.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-17T16:00:00Z"))
    let earlierDay = DayKey.key(for: instant, calendar: la)
    let laterDay = DayKey.key(for: instant, calendar: seoul)
    session.refresh(todayKey: earlierDay)
    #expect(session.count == 0)
    session.refresh(todayKey: laterDay)
    #expect(session.newCount == 1)
    session.didDisplayInbox()
    session.endPresentation()
    session.refresh(todayKey: earlierDay)
    session.refresh(todayKey: laterDay)
    #expect(session.count == 1 && session.newCount == 0)
    enum Failure: Error { case save }
    do {
        try PersistenceCommandService.perform(in: context) {
            task.plannedDayKey = laterDay
            throw Failure.save
        }
        Issue.record("이동 실패가 성공으로 반환됨")
    } catch Failure.save { }
    session.refresh(todayKey: laterDay)
    #expect(session.count == 1 && session.newCount == 0)
    #expect(session.tasks.first?.plannedDayKey == "2026-09-17")
}
