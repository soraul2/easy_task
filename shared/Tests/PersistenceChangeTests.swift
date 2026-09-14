import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func persistenceChangesTrackInsertUpdateDeleteAndSkipNoOp() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let notifications = DomainNotifications(context: context)
    let memo = Memo(content: "원본")
    try PersistenceCommandService.perform(in: context) { context.insert(memo) }
    try PersistenceCommandService.perform(in: context) { memo.content = "편집" }
    try PersistenceCommandService.perform(in: context) { context.delete(memo) }
    try PersistenceCommandService.perform(in: context) {}
    #expect(notifications.values == [.memos, .memos, .memos])
    #expect(!context.hasChanges)
}

@Test @MainActor
func persistenceChangesCombinePendingEditsAndAtomicTaskLifecycle() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let task = Task(title: "진행 작업", status: .doing, plannedAt: Date(), order: 100)
    context.insert(task)
    try context.save()
    let notifications = DomainNotifications(context: context)
    context.insert(Memo(content: "먼저 저장할 초안"))
    try PersistenceCommandService.perform(in: context) {
        try TaskLifecycleService.applyStatus(.done, to: task, in: context)
    }
    #expect(notifications.values == [[.memos, .tasks]])
    #expect(try context.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 1)
}

@Test @MainActor
func persistenceFailureOnlyNotifiesEditsCommittedBeforeRollback() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let notifications = DomainNotifications(context: context)
    context.insert(Memo(content: "원래 대기 중인 메모"))
    do {
        try PersistenceCommandService.perform(in: context) {
            context.insert(Task(title: "실패할 작업", plannedAt: Date(), order: 100))
            throw CocoaError(.fileWriteUnknown)
        }
        Issue.record("저장 실패가 전달되어야 함")
    } catch {}
    #expect(notifications.values == [.memos])
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<Memo>()) == 1)
    do {
        try PersistenceCommandService.perform(in: context) {
            context.insert(Memo(content: "롤백할 메모"))
            throw CocoaError(.fileWriteUnknown)
        }
    } catch {}
    #expect(notifications.values == [.memos])
}

@Test
func persistenceLegacyImportNotificationsRefreshEveryDomain() {
    let notification = Notification(name: PersistenceCommandService.dataChangedNotification)
    for domain: PersistenceChangeDomains in [.tasks, .calendar, .memos, .templates, .reviews] {
        #expect(PersistenceCommandService.affects(domain, in: notification))
    }
}

@Test @MainActor
func persistenceCleanCloudImportStillRefreshesEveryDomain() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let notifications = DomainNotifications(context: context)
    try CloudKitSyncService.reconcileIfNeeded(
        after: CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: true),
        context: context)
    #expect(notifications.values == [.all])
    try CloudKitSyncService.reconcileIfNeeded(
        after: CloudKitSyncEventSummary(kind: .export, isCompleted: true, succeeded: true),
        context: context)
    #expect(notifications.values == [.all])
}

private final class DomainNotifications: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [PersistenceChangeDomains] = []
    private var token: (any NSObjectProtocol)?

    var values: [PersistenceChangeDomains] { lock.withLock { received } }

    init(context: ModelContext) {
        token = NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification, object: context, queue: nil
        ) { [weak self] notification in
            var affected: PersistenceChangeDomains = []
            for domain: PersistenceChangeDomains in [.tasks, .calendar, .memos, .templates, .reviews] {
                if PersistenceCommandService.affects(domain, in: notification) { affected.insert(domain) }
            }
            self?.lock.withLock { self?.received.append(affected) }
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}
