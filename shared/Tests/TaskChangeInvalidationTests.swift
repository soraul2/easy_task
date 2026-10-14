import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func taskChangeSummarySeparatesTaskRowsFromChildrenAndRetainsDeletedLogicalIDs() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let received = TaskChangeNotifications(context: context)
    let task = Task(title: "범위 확인", plannedAt: Date(), order: 100)
    let id = task.id
    try PersistenceCommandService.perform(in: context) { context.insert(task) }
    #expect(received.values.last?.taskIDs == Set([id]))
    #expect(received.values.last?.progressTaskIDs == [])
    let savedIdentifier = task.persistentModelID

    try PersistenceCommandService.perform(in: context) {
        context.insert(TaskChecklistItem(taskId: id, title: "항목", order: 100))
        context.insert(TaskProgressEvent(taskId: id, kind: .started, occurredAt: Date()))
    }
    #expect(received.values.last?.taskIDs == [])
    #expect(received.values.last?.taskIdentifiers == [])
    #expect(received.values.last?.checklistTaskIDs == Set([id]))
    #expect(received.values.last?.progressTaskIDs == Set([id]))

    try PersistenceCommandService.perform(in: context) { try TaskRules.delete(task, from: context) }
    #expect(received.values.last?.taskIDs == Set([id]))
    #expect(received.values.last?.taskIdentifiers == Set([savedIdentifier]))
    #expect(received.values.last?.checklistTaskIDs == Set([id]))
    #expect(received.values.last?.progressTaskIDs == Set([id]))
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
}

@Test @MainActor
func taskChangeSummaryNotifiesOnlyCommittedPendingIDsAfterRollback() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let pending = Task(title: "기존 작업", plannedAt: Date(), order: 100)
    context.insert(pending)
    try context.save()
    let received = TaskChangeNotifications(context: context)
    let revision = PersistenceViewRevision(context: context, domains: .tasks)
    pending.title = "대기 중인 편집"
    let rolledBack = Task(title: "실패할 작업", plannedAt: Date(), order: 200)
    do {
        try PersistenceCommandService.perform(in: context) {
            context.insert(rolledBack)
            throw CocoaError(.fileWriteUnknown)
        }
        Issue.record("명령 실패가 전달되어야 합니다")
    } catch {}
    #expect(received.values.count == 1)
    #expect(received.values.first?.taskIDs == Set([pending.id]))
    #expect(revision.value == 1)
    #expect(pending.title == "대기 중인 편집")
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
}

@Test @MainActor
func taskChangeSummaryCombinesNestedCommandsAndKeepsCommittedInnerPreSaveAfterFailure() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let received = TaskChangeNotifications(context: context)
    let revision = PersistenceViewRevision(context: context, domains: .tasks)
    let first = Task(title: "바깥", plannedAt: Date(), order: 100)
    let second = Task(title: "안쪽", plannedAt: Date(), order: 200)
    try PersistenceCommandService.perform(in: context) {
        context.insert(first)
        try PersistenceCommandService.perform(in: context) { context.insert(second) }
    }
    #expect(received.values.count == 1)
    #expect(received.values.first?.taskIDs == Set([first.id, second.id]))
    #expect(revision.value == 1)

    first.title = "명령 전에 대기한 편집"
    do {
        try PersistenceCommandService.perform(in: context) {
            second.title = "내부 명령이 선행 저장한 편집"
            try PersistenceCommandService.perform(in: context) {
                context.insert(Task(title: "롤백", plannedAt: Date(), order: 300))
                throw CocoaError(.fileWriteUnknown)
            }
        }
        Issue.record("중첩 명령 실패가 전달되어야 합니다")
    } catch {}
    #expect(received.values.count == 2)
    #expect(received.values.last?.taskIDs == Set([first.id, second.id]))
    #expect(revision.value == 2)
    #expect(second.title == "내부 명령이 선행 저장한 편집")
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 2)
    #expect(!PersistenceCommandService.isPerformingCommand(in: context))
}

@Test @MainActor
func taskChangeRevisionUsesOneCommandNotificationAndKeepsDirectSaveAndImportFallbacks() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let received = TaskChangeNotifications(context: context)
    let revision = PersistenceViewRevision(context: context, domains: .tasks)
    try PersistenceCommandService.perform(in: context) {
        context.insert(Task(title: "명령", plannedAt: Date(), order: 100))
    }
    #expect(revision.value == 1)
    context.insert(Task(title: "직접 저장", plannedAt: Date(), order: 200))
    try context.save()
    #expect(revision.value == 2)
    try PersistenceCommandService.perform(in: context, invalidating: .tasks) {}
    #expect(received.values.last?.taskIDs == nil)
    #expect(received.values.last?.taskIdentifiers == nil)
    #expect(revision.value == 3)
    try PersistenceCommandService.perform(in: context) {}
    #expect(revision.value == 3)
    #expect(PersistenceCommandService.changes(in: Notification(
        name: PersistenceCommandService.dataChangedNotification)).taskIDs == nil)
}

@Test @MainActor
func taskChangeSummaryRetainsDirectSaveInsideMutationWithConservativeScope() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let received = TaskChangeNotifications(context: context)
    let revision = PersistenceViewRevision(context: context, domains: .tasks)
    try PersistenceCommandService.perform(in: context) {
        context.insert(Task(title: "서비스 내부 저장", plannedAt: Date(), order: 100))
        try context.save()
    }
    #expect(received.values.count == 1)
    #expect(received.values.first?.domains == .tasks)
    #expect(received.values.first?.taskIDs == nil)
    #expect(revision.value == 1)
}

@Test @MainActor
func taskChangeSummaryConservativelyHandlesChangedChildParent() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let firstID = UUID()
    let secondID = UUID()
    let event = TaskProgressEvent(taskId: firstID, kind: .started, occurredAt: Date())
    context.insert(event)
    try context.save()
    let received = TaskChangeNotifications(context: context)
    try PersistenceCommandService.perform(in: context) { event.taskId = secondID }
    #expect(received.values.last?.taskIDs == [])
    #expect(received.values.last?.progressTaskIDs == nil)
}

private final class TaskChangeNotifications: @unchecked Sendable {
    private let lock = NSLock()
    private var summaries: [PersistenceChangeSummary] = []
    private var token: (any NSObjectProtocol)?
    var values: [PersistenceChangeSummary] { lock.withLock { summaries } }

    init(context: ModelContext) {
        token = NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification, object: context, queue: nil
        ) { [weak self] notification in
            let changes = PersistenceCommandService.changes(in: notification)
            self?.lock.withLock { self?.summaries.append(changes) }
        }
    }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
}
