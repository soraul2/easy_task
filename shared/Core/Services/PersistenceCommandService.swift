import Foundation
import SwiftData

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

public enum PersistenceCommandService {
    public static let dataChangedNotification = Notification.Name(
        "PlanBasePersistenceDataChanged"
    )
    private static let changeDomainsKey = "PlanBasePersistenceChangeDomains"

    /// Legacy/import notifications without metadata conservatively invalidate all domains.
    public static func affects(_ domains: PersistenceChangeDomains, in notification: Notification) -> Bool {
        guard let rawValue = notification.userInfo?[changeDomainsKey] as? Int else { return true }
        return !domains.intersection(PersistenceChangeDomains(rawValue: rawValue)).isEmpty
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
        // Preserve unrelated pending edits before establishing this command's rollback point.
        let pendingDomains = changedDomains(in: context)
        try context.save()

        do {
            let result = try mutation()
            let mutationDomains = changedDomains(in: context)
            try context.save()
            postChanges(pendingDomains.union(mutationDomains).union(importedDomains), in: context)
            return result
        } catch {
            context.rollback()
            // These pending edits were committed before the command's rollback point.
            postChanges(pendingDomains, in: context)
            throw error
        }
    }

    @MainActor
    private static func postChanges(_ domains: PersistenceChangeDomains, in context: ModelContext) {
        guard !domains.isEmpty else { return }
        NotificationCenter.default.post(name: dataChangedNotification, object: context,
            userInfo: [changeDomainsKey: domains.rawValue])
    }

    @MainActor
    private static func changedDomains(in context: ModelContext) -> PersistenceChangeDomains {
        var domains: PersistenceChangeDomains = []
        for model in context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray {
            switch model {
            case is Task, is TaskChecklistItem, is TaskProgressEvent,
                 is TaskCompletionActivity, is FocusSession, is TemplatePlacement:
                domains.insert(.tasks)
            case is CalendarEvent:
                domains.insert(.calendar)
            case is TaskTemplate, is TaskTemplateItem:
                domains.insert(.templates)
            case is Memo, is MemoDrawing, is MemoChecklistItem:
                domains.insert(.memos)
            case is DailyReview, is DiaryBlock, is DiaryAttachment:
                domains.insert(.reviews)
            default:
                domains.formUnion(.all)
            }
        }
        return domains
    }
}
