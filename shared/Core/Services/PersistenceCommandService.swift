import Foundation
import SwiftData

@available(watchOS 11, *)
public struct PersistenceChangeDomains: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let tasks = Self(rawValue: 1 << 0)
    public static let calendar = Self(rawValue: 1 << 1)
    public static let templates = Self(rawValue: 1 << 2)
    public static let memos = Self(rawValue: 1 << 3)
    public static let reviews = Self(rawValue: 1 << 4)
    public static let all: Self = [.tasks, .calendar, .templates, .memos, .reviews]
}

/// Value-only invalidation metadata. A nil ID set means the change's scope is
/// unknown; an empty set means that no records of that kind were changed.
@available(watchOS 11, *)
public struct PersistenceChangeSummary: Sendable, Equatable {
    public var domains: PersistenceChangeDomains
    /// Logical IDs of Task rows, rather than IDs of their child records.
    public var taskIDs: Set<UUID>?
    /// SwiftData value identities captured before saving. A cached row can use
    /// these to invalidate its old logical ID when a command reassigns `id`.
    public var taskIdentifiers: Set<PersistentIdentifier>?
    public var checklistTaskIDs: Set<UUID>?
    public var progressTaskIDs: Set<UUID>?
    public var completionTaskIDs: Set<UUID>?
    public var focusTaskIDs: Set<UUID>?

    public init(
        domains: PersistenceChangeDomains = [],
        taskIDs: Set<UUID>? = [],
        taskIdentifiers: Set<PersistentIdentifier>? = [],
        checklistTaskIDs: Set<UUID>? = [],
        progressTaskIDs: Set<UUID>? = [],
        completionTaskIDs: Set<UUID>? = [],
        focusTaskIDs: Set<UUID>? = []
    ) {
        self.domains = domains
        self.taskIDs = taskIDs
        self.taskIdentifiers = taskIdentifiers
        self.checklistTaskIDs = checklistTaskIDs
        self.progressTaskIDs = progressTaskIDs
        self.completionTaskIDs = completionTaskIDs
        self.focusTaskIDs = focusTaskIDs
    }

    public static func unknown(in domains: PersistenceChangeDomains) -> Self {
        var result = Self(domains: domains)
        if domains.contains(.tasks) {
            result.taskIDs = nil
            result.taskIdentifiers = nil
            result.checklistTaskIDs = nil
            result.progressTaskIDs = nil
            result.completionTaskIDs = nil
            result.focusTaskIDs = nil
        }
        return result
    }

    public func union(_ other: Self) -> Self {
        func unionIDs(_ first: Set<UUID>?, _ second: Set<UUID>?) -> Set<UUID>? {
            guard let first, let second else { return nil }
            return first.union(second)
        }
        let identifiers: Set<PersistentIdentifier>?
        if let first = taskIdentifiers, let second = other.taskIdentifiers {
            identifiers = first.union(second)
        } else {
            identifiers = nil
        }
        return Self(
            domains: domains.union(other.domains),
            taskIDs: unionIDs(taskIDs, other.taskIDs),
            taskIdentifiers: identifiers,
            checklistTaskIDs: unionIDs(checklistTaskIDs, other.checklistTaskIDs),
            progressTaskIDs: unionIDs(progressTaskIDs, other.progressTaskIDs),
            completionTaskIDs: unionIDs(completionTaskIDs, other.completionTaskIDs),
            focusTaskIDs: unionIDs(focusTaskIDs, other.focusTaskIDs)
        )
    }
}

@available(watchOS 11, *)
public enum PersistenceCommandService {
    public static let dataChangedNotification = Notification.Name(
        "PlanBasePersistenceDataChanged"
    )
    private static let changeDomainsKey = "PlanBasePersistenceChangeDomains"
    private static let changeSummaryKey = "PlanBasePersistenceChangeSummary"

    private struct CommandState {
        var depth = 0
        var controlledSaveDepth = 0
        var committed = PersistenceChangeSummary()
        var saveObserver: CommandSaveObserver?
    }
    @MainActor private static var commands: [ObjectIdentifier: CommandState] = [:]

    /// Legacy/import notifications without metadata conservatively invalidate all domains.
    public static func affects(_ domains: PersistenceChangeDomains, in notification: Notification) -> Bool {
        guard let rawValue = notification.userInfo?[changeDomainsKey] as? Int else { return true }
        return !domains.intersection(PersistenceChangeDomains(rawValue: rawValue)).isEmpty
    }

    public static func changes(in notification: Notification) -> PersistenceChangeSummary {
        if let summary = notification.userInfo?[changeSummaryKey] as? PersistenceChangeSummary {
            return summary
        }
        let rawValue = notification.userInfo?[changeDomainsKey] as? Int
        return .unknown(in: rawValue.map { PersistenceChangeDomains(rawValue: $0) } ?? .all)
    }

    /// A command emits one explicit notification after all of its successful
    /// saves. didSave observers can avoid invalidating the same command twice.
    @MainActor
    public static func isPerformingCommand(in context: ModelContext) -> Bool {
        commands[ObjectIdentifier(context)] != nil
    }

    @MainActor
    @discardableResult
    public static func perform<Result>(
        in context: ModelContext,
        invalidating importedDomains: PersistenceChangeDomains = [],
        _ mutation: () throws -> Result
    ) throws -> Result {
        let performanceInterval = PlanBasePerformanceTrace.begin("PersistenceCommand")
        defer { PlanBasePerformanceTrace.end("PersistenceCommand", performanceInterval) }
        beginCommand(in: context)
        defer { finishCommand(in: context) }
        // Preserve unrelated pending edits before establishing this command's rollback point.
        let pendingChanges = changedRecords(in: context)
        try save(context)
        recordCommitted(pendingChanges, in: context)

        do {
            let result = try mutation()
            let mutationChanges = changedRecords(in: context)
            try save(context)
            recordCommitted(mutationChanges.union(.unknown(in: importedDomains)), in: context)
            return result
        } catch {
            context.rollback()
            // Only successful saves were added to the command's summary. This
            // includes a nested command's pre-save even if its mutation failed.
            throw error
        }
    }

    @MainActor
    private static func beginCommand(in context: ModelContext) {
        let key = ObjectIdentifier(context)
        var state = commands[key] ?? CommandState()
        if state.depth == 0 {
            state.saveObserver = CommandSaveObserver(NotificationCenter.default.addObserver(
                forName: ModelContext.didSave, object: context, queue: .main
            ) { notification in
                nonisolated(unsafe) let mainNotification = notification
                MainActor.assumeIsolated {
                    guard var state = commands[key], state.controlledSaveDepth == 0 else { return }
                    // A service may explicitly save inside the mutation. Its
                    // models are clean by the outer command's final save, so
                    // preserve that committed change with conservative scope.
                    state.committed = state.committed.union(.unknown(
                        in: PersistenceViewRevision.savedDomains(in: mainNotification)))
                    commands[key] = state
                }
            })
        }
        state.depth += 1
        commands[key] = state
    }

    @MainActor
    private static func save(_ context: ModelContext) throws {
        let key = ObjectIdentifier(context)
        commands[key]?.controlledSaveDepth += 1
        defer { commands[key]?.controlledSaveDepth -= 1 }
        try context.save()
    }

    @MainActor
    private static func recordCommitted(_ changes: PersistenceChangeSummary, in context: ModelContext) {
        let key = ObjectIdentifier(context)
        guard var state = commands[key] else { return }
        state.committed = state.committed.union(changes)
        commands[key] = state
    }

    @MainActor
    private static func finishCommand(in context: ModelContext) {
        let key = ObjectIdentifier(context)
        guard var state = commands[key] else { return }
        state.depth -= 1
        if state.depth > 0 {
            commands[key] = state
            return
        }
        commands.removeValue(forKey: key)
        state.saveObserver = nil
        postChanges(state.committed, in: context)
    }

    @MainActor
    private static func postChanges(_ changes: PersistenceChangeSummary, in context: ModelContext) {
        guard !changes.domains.isEmpty else { return }
        NotificationCenter.default.post(name: dataChangedNotification, object: context,
            userInfo: [changeDomainsKey: changes.domains.rawValue, changeSummaryKey: changes])
    }

    @MainActor
    private static func changedRecords(in context: ModelContext) -> PersistenceChangeSummary {
        var changes = PersistenceChangeSummary()
        let insertedOrDeleted = context.insertedModelsArray + context.deletedModelsArray
        let knownParents = Set(insertedOrDeleted.map { ObjectIdentifier($0) })
        for model in insertedOrDeleted + context.changedModelsArray {
            let mayHaveChangedParent = !knownParents.contains(ObjectIdentifier(model))
            switch model {
            case let task as Task:
                changes.domains.insert(.tasks)
                changes.taskIDs?.insert(task.id)
                changes.taskIdentifiers?.insert(task.persistentModelID)
            case let item as TaskChecklistItem:
                changes.domains.insert(.tasks)
                if mayHaveChangedParent { changes.checklistTaskIDs = nil }
                else { changes.checklistTaskIDs?.insert(item.taskId) }
            case let event as TaskProgressEvent:
                changes.domains.insert(.tasks)
                if mayHaveChangedParent { changes.progressTaskIDs = nil }
                else { changes.progressTaskIDs?.insert(event.taskId) }
            case let activity as TaskCompletionActivity:
                changes.domains.insert(.tasks)
                if mayHaveChangedParent { changes.completionTaskIDs = nil }
                else { changes.completionTaskIDs?.insert(activity.taskId) }
            case let session as FocusSession:
                changes.domains.insert(.tasks)
                if mayHaveChangedParent { changes.focusTaskIDs = nil }
                else { changes.focusTaskIDs?.insert(session.taskId) }
            case is TemplatePlacement:
                changes.domains.insert(.tasks)
            case is CalendarEvent:
                changes.domains.insert(.calendar)
            case is TaskTemplate, is TaskTemplateItem:
                changes.domains.insert(.templates)
            case is Memo, is MemoDrawing, is MemoChecklistItem:
                changes.domains.insert(.memos)
            case is DailyReview, is DiaryBlock, is DiaryAttachment:
                changes.domains.insert(.reviews)
            default:
                changes = changes.union(.unknown(in: .all))
            }
        }
        return changes
    }
}

private final class CommandSaveObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
