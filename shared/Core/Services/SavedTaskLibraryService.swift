import Foundation
import SwiftData

@available(watchOS 11, *)
public struct SavedTaskEntry: Identifiable {
    public let id: UUID
    public var draft: TemplateTaskDraft
    public var isFavorite: Bool
    public var quickEntryAlias: String? = nil
}

/// Single-task templates share the existing sync/backup format. Applying one here
/// creates an independent task, without a placement or historical state.
@MainActor
@available(watchOS 11, *)
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
        let performanceInterval = PlanBasePerformanceTrace.begin("SavedTaskLibraryLoad")
        defer { PlanBasePerformanceTrace.end("SavedTaskLibraryLoad", performanceInterval) }
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
            return try insertTask(from: item, on: date, in: context)
        }
    }

    /// Validate the current shortcut before the command without rebuilding the
    /// entire display library. A selected suggestion still has to match the
    /// current query; an exact alias still has to identify one reusable record.
    @discardableResult
    public static func add(input: String, selectedID: UUID? = nil, on date: Date,
                           in context: ModelContext) throws -> Task {
        guard SavedTaskShortcutRules.query(in: input) != nil else {
            throw SavedTaskShortcutRules.Failure.selectionRequired
        }
        // Invalid shortcuts must not establish a save checkpoint for unrelated
        // dirty edits. Once preflight succeeds, pending edits retain the normal
        // command checkpoint and rollback behavior.
        let record = try submissionRecord(input: input, selectedID: selectedID, in: context)
        let hadPendingChanges = context.hasChanges
        return try PersistenceCommandService.perform(in: context) {
            // Pre-saving pending edits can deliver save observers. Resolve the
            // shortcut again in that case before using the current full draft.
            let current = hadPendingChanges
                ? try submissionRecord(input: input, selectedID: selectedID, in: context) : record
            let (_, item) = try resolve(current.id, in: context)
            guard item.instanceID == current.item.instanceID else { throw Failure.unavailable }
            return try insertTask(from: current.item, on: date, in: context)
        }
    }

    static func submissionTemplateID(input: String, selectedID: UUID?, in context: ModelContext) throws -> UUID {
        try submissionRecord(input: input, selectedID: selectedID, in: context).id
    }

    private static func submissionRecord(input: String, selectedID: UUID?, in context: ModelContext) throws
        -> (id: UUID, item: TaskTemplateItem) {
        let interval = PlanBasePerformanceTrace.begin("SavedTaskSubmissionResolve")
        defer { PlanBasePerformanceTrace.end("SavedTaskSubmissionResolve", interval) }
        guard let query = SavedTaskShortcutRules.query(in: input) else {
            throw SavedTaskShortcutRules.Failure.selectionRequired
        }
        if let selectedID {
            let templates = try context.fetch(
                FetchDescriptor<TaskTemplate>(predicate: #Predicate { $0.id == selectedID }))
            guard let template = representatives(templates).first,
                  let item = try shortcutItem(templateID: selectedID, in: context) else {
                throw Failure.unavailable
            }
            // Suggestion matching only uses title and alias. The full draft is
            // materialized once, after the current selection is validated.
            let entry = SavedTaskEntry(id: selectedID,
                draft: TemplateTaskDraft(title: item.title, order: item.order),
                isFavorite: template.isFavorite, quickEntryAlias: template.quickEntryAlias)
            guard !SavedTaskShortcutRules.suggestions([entry], input: input).isEmpty else {
                throw Failure.unavailable
            }
            return (selectedID, item)
        }
        guard !query.isEmpty else { throw SavedTaskShortcutRules.Failure.selectionRequired }
        // Select representatives before comparing aliases: an older physical
        // copy may still carry an alias the winning record no longer uses.
        let templates = representatives(try fetchPages(FetchDescriptor<TaskTemplate>(
            predicate: #Predicate { $0.supersededAt == nil },
            sortBy: [SortDescriptor(\TaskTemplate.instanceID)]), in: context))
        var match: (id: UUID, item: TaskTemplateItem)?
        for template in templates where SavedTaskShortcutRules.aliasKey(template.quickEntryAlias) == query {
            guard let item = try shortcutItem(templateID: template.id, in: context) else { continue }
            guard match == nil else { throw SavedTaskShortcutRules.Failure.ambiguousAlias }
            match = (template.id, item)
        }
        guard let match else { throw SavedTaskShortcutRules.Failure.unknownAlias }
        return match
    }

    /// Match the library's global child representative rule, including copies
    /// whose templateId was changed before convergence. Filtering by parent
    /// alone could resurrect an old physical copy under its previous parent.
    private static func shortcutItem(templateID: UUID, in context: ModelContext) throws -> TaskTemplateItem? {
        let seeds = try context.fetch(FetchDescriptor<TaskTemplateItem>(
            predicate: #Predicate { $0.supersededAt == nil && $0.templateId == templateID }))
        let ids = Array(Set(seeds.map(\.id)))
        var copies: [TaskTemplateItem] = []
        for start in stride(from: 0, to: ids.count, by: 200) {
            let batch = Array(ids[start..<min(start + 200, ids.count)])
            copies += try fetchPages(FetchDescriptor<TaskTemplateItem>(
                predicate: #Predicate { $0.supersededAt == nil && batch.contains($0.id) },
                sortBy: [SortDescriptor(\TaskTemplateItem.instanceID)]), in: context)
        }
        let children = representatives(copies).filter { $0.templateId == templateID }
        guard children.count == 1, let item = children.first,
              !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return item
    }

    private static func insertTask(from item: TaskTemplateItem, on date: Date,
                                   in context: ModelContext) throws -> Task {
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
            context.insert(TaskChecklistItem(taskId: task.id, title: title, order: Double(index + 1) * 100))
        }
        return task
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
