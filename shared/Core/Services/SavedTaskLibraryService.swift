import Foundation
import SwiftData

public struct SavedTaskEntry: Identifiable {
    public let id: UUID
    public var draft: TemplateTaskDraft
    public var isFavorite: Bool
    public var quickEntryAlias: String? = nil
}

/// Single-task templates share the existing sync/backup format. Applying one here
/// creates an independent task, without a placement or historical state.
@MainActor
public enum SavedTaskLibraryService {
    public enum Failure: LocalizedError {
        case unavailable, emptyTitle, invalidEstimate

        public var errorDescription: String? {
            switch self {
            case .unavailable: "작업이 변경되었거나 삭제됐어요. 목록을 다시 확인해 주세요."
            case .emptyTitle: "작업 제목을 입력해 주세요."
            case .invalidEstimate: "예상 시간은 0 이상의 정수로 입력해 주세요."
            }
        }
    }

    public static func entries(
        templates: [TaskTemplate], items: [TaskTemplateItem], query: String = "",
        favoritesOnly: Bool = false
    ) -> [SavedTaskEntry] {
        let grouped = Dictionary(grouping: representatives(items), by: \.templateId)
        let values: [SavedTaskEntry] = representatives(templates).compactMap { template in
            guard let children = grouped[template.id], children.count == 1,
                let item = children.first, !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let draft = TemplateTaskDraft(item: item)
            return SavedTaskEntry(id: template.id, draft: draft, isFavorite: template.isFavorite,
                                  quickEntryAlias: template.quickEntryAlias)
        }
        return filter(values, query: query, favoritesOnly: favoritesOnly)
    }

    public static func filter(_ entries: [SavedTaskEntry], query: String = "", favoritesOnly: Bool = false)
        -> [SavedTaskEntry]
    {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            let draft = entry.draft
            let searchable = [draft.title, draft.note, entry.quickEntryAlias ?? ""] + draft.tags + draft.checklistTitles
            return (!favoritesOnly || entry.isFavorite)
                && (search.isEmpty || searchable.contains { $0.localizedStandardContains(search) })
        }.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            let comparison = $0.draft.title.localizedStandardCompare($1.draft.title)
            return comparison == .orderedSame
                ? $0.id.uuidString < $1.id.uuidString : comparison == .orderedAscending
        }
    }

    /// Read value snapshots while records are attached. Views never retain deleted model rows.
    public static func load(in context: ModelContext) throws -> [SavedTaskEntry] {
        let templates = try fetchPages(
            FetchDescriptor<TaskTemplate>(
                predicate: #Predicate { $0.supersededAt == nil },
                sortBy: [SortDescriptor(\TaskTemplate.instanceID)]), in: context)
        let items = try fetchPages(
            FetchDescriptor<TaskTemplateItem>(
                predicate: #Predicate { $0.supersededAt == nil },
                sortBy: [SortDescriptor(\TaskTemplateItem.instanceID)]), in: context)
        return entries(templates: templates, items: items)
    }

    private static func fetchPages<Model: PersistentModel>(
        _ descriptor: FetchDescriptor<Model>, in context: ModelContext
    ) throws -> [Model] {
        var request = descriptor
        request.fetchLimit = 256
        var result: [Model] = []
        while true {
            let page = try context.fetch(request)
            result.append(contentsOf: page)
            guard page.count == 256 else { return result }
            request.fetchOffset = result.count
        }
    }

    @discardableResult
    public static func save(taskID: UUID, in context: ModelContext) throws -> TaskTemplate {
        try PersistenceCommandService.perform(in: context) {
            let rows = try context.fetch(FetchDescriptor<Task>(predicate: #Predicate { $0.id == taskID }))
            guard let task = representatives(rows).first else { throw Failure.unavailable }
            let checklist = try TaskChecklistService.items(for: taskID, in: context)
            let draft = TemplateTaskDraft(
                title: task.title, note: task.note ?? "", priority: task.priority,
                tags: task.tags, estimatedMinutes: task.estimatedMinutes,
                checklistTitles: TaskChecklistService.titles(in: checklist), order: 100)
            guard
                let template = TemplateService.saveTemplate(
                    named: task.title, from: [try normalized(draft)], in: context)
            else {
                throw Failure.emptyTitle
            }
            return template
        }
    }

    @discardableResult
    public static func create(draft: TemplateTaskDraft, isFavorite: Bool, quickEntryAlias: String? = nil,
                              in context: ModelContext) throws
        -> TaskTemplate
    {
        try PersistenceCommandService.perform(in: context) {
            let draft = try normalized(draft)
            let alias = try validatedAlias(quickEntryAlias, excluding: nil, in: context)
            guard let template = TemplateService.saveTemplate(named: draft.title, from: [draft], in: context)
            else {
                throw Failure.emptyTitle
            }
            template.isFavorite = isFavorite
            template.quickEntryAlias = alias
            return template
        }
    }

    public static func update(id: UUID, draft: TemplateTaskDraft, isFavorite: Bool,
                              quickEntryAlias: String? = nil, in context: ModelContext)
        throws
    {
        try PersistenceCommandService.perform(in: context) {
            let (template, item) = try resolve(id, in: context)
            let draft = try normalized(draft)
            // Existing callers preserve the alias; the editor sends an empty string to clear it.
            if let quickEntryAlias {
                template.quickEntryAlias = try validatedAlias(quickEntryAlias, excluding: id, in: context)
            }
            template.name = draft.title
            template.isFavorite = isFavorite
            template.updatedAt = Date()
            item.title = draft.title
            item.note = draft.note.isEmpty ? nil : draft.note
            item.priority = draft.priority
            item.tags = draft.tags
            item.estimatedMinutes = draft.estimatedMinutes
            item.checklistTitles = draft.checklistTitles
            item.updatedAt = template.updatedAt
        }
    }

    public static func toggleFavorite(id: UUID, in context: ModelContext) throws {
        try PersistenceCommandService.perform(in: context) {
            let (template, _) = try resolve(id, in: context)
            template.isFavorite.toggle()
            template.updatedAt = Date()
        }
    }

    private static func validatedAlias(_ value: String?, excluding id: UUID?, in context: ModelContext) throws -> String? {
        guard let alias = try SavedTaskShortcutRules.normalizedAlias(value) else { return nil }
        let entries = try load(in: context)
        guard !entries.contains(where: {
            $0.id != id && SavedTaskShortcutRules.aliasKey($0.quickEntryAlias) == alias
        }) else { throw SavedTaskShortcutRules.Failure.duplicateAlias(alias) }
        return alias
    }

    @discardableResult
    public static func add(id: UUID, on date: Date, in context: ModelContext) throws -> Task {
        try PersistenceCommandService.perform(in: context) {
            let (_, item) = try resolve(id, in: context)
            let draft = try normalized(TemplateTaskDraft(item: item))
            let day = DayKey.startOfDay(for: date)
            let order = try BoundedQueryService.nextOrder(
                in: context, dayKey: DayKey.key(for: day), status: .todo)
            let task = Task(
                title: draft.title, note: draft.note.isEmpty ? nil : draft.note,
                status: .todo, plannedAt: day, order: order,
                priority: draft.priority.flatMap(TaskPriority.init(rawValue:)), tags: draft.tags,
                estimatedMinutes: draft.estimatedMinutes)
            context.insert(task)
            for (index, title) in draft.checklistTitles.enumerated() {
                context.insert(
                    TaskChecklistItem(taskId: task.id, title: title, order: Double(index + 1) * 100))
            }
            return task
        }
    }

    public static func delete(id: UUID, in context: ModelContext) throws {
        try PersistenceCommandService.perform(in: context) {
            _ = try resolve(id, in: context)
            // Delete all physical copies of the explicitly selected logical record.
            for item in try context.fetch(
                FetchDescriptor<TaskTemplateItem>(predicate: #Predicate { $0.templateId == id }))
            {
                context.delete(item)
            }
            for template in try context.fetch(
                FetchDescriptor<TaskTemplate>(predicate: #Predicate { $0.id == id }))
            {
                context.delete(template)
            }
        }
    }

    private static func resolve(_ id: UUID, in context: ModelContext) throws -> (
        TaskTemplate, TaskTemplateItem
    ) {
        let templates = try context.fetch(
            FetchDescriptor<TaskTemplate>(predicate: #Predicate { $0.id == id }))
        let items = try context.fetch(
            FetchDescriptor<TaskTemplateItem>(predicate: #Predicate { $0.templateId == id }))
        let activeItems = representatives(items)
        guard let template = representatives(templates).first,
            activeItems.count == 1, let item = activeItems.first
        else { throw Failure.unavailable }
        return (template, item)
    }

    private static func normalized(_ draft: TemplateTaskDraft) throws -> TemplateTaskDraft {
        var result = draft
        result.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.title.isEmpty else { throw Failure.emptyTitle }
        if let minutes = draft.estimatedMinutes, minutes < 0 { throw Failure.invalidEstimate }
        result.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        result.priority = draft.priority.flatMap { TaskPriority(rawValue: $0)?.rawValue }
        result.checklistTitles = draft.checklistTitles.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return result
    }

    private static func representatives<Record: IntegrityRecord>(_ records: [Record]) -> [Record] {
        var result: [UUID: Record] = [:]
        for record in records where record.supersededAt == nil {
            if let current = result[record.id], !DataIntegrityService.scalarPrecedes(current, record) {
                continue
            }
            result[record.id] = record
        }
        return Array(result.values)
    }
}
