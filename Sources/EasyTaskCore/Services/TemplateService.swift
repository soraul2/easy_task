import Foundation
import SwiftData

public struct TemplateTaskDraft: Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var note: String
    public var priority: String?
    public var tags: [String]
    public var estimatedMinutes: Int?
    public var order: Double

    public init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        priority: String? = nil,
        tags: [String] = [],
        estimatedMinutes: Int? = nil,
        order: Double
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.priority = priority
        self.tags = tags
        self.estimatedMinutes = estimatedMinutes
        self.order = order
    }

    public init(item: TaskTemplateItem) {
        self.init(
            id: item.id,
            title: item.title,
            note: item.note ?? "",
            priority: item.priority,
            tags: item.tags,
            estimatedMinutes: item.estimatedMinutes,
            order: item.order
        )
    }
}

public struct TemplateApplyResult {
    public var createdTaskCount: Int
    public var placements: [TemplatePlacement]

    public init(createdTaskCount: Int, placements: [TemplatePlacement]) {
        self.createdTaskCount = createdTaskCount
        self.placements = placements
    }
}

public struct TemplatePlacementDeleteSummary: Equatable {
    public var taskCount: Int
    public var deletableTaskCount: Int
    public var protectedTaskCount: Int

    public var canDeleteTasks: Bool {
        protectedTaskCount == 0
    }

    public init(
        taskCount: Int,
        deletableTaskCount: Int,
        protectedTaskCount: Int
    ) {
        self.taskCount = taskCount
        self.deletableTaskCount = deletableTaskCount
        self.protectedTaskCount = protectedTaskCount
    }
}

public enum TemplateService {
    @discardableResult
    public static func saveTemplate(
        named name: String,
        from tasks: [Task],
        in context: ModelContext
    ) -> TaskTemplate? {
        let sourceTasks = tasks
            .filter { $0.supersededAt == nil && $0.archivedAt == nil }
            .sorted { $0.order < $1.order }
        let drafts = sourceTasks.enumerated().map { index, task in
            TemplateTaskDraft(
                title: task.title,
                note: task.note ?? "",
                priority: task.priority,
                tags: task.tags,
                estimatedMinutes: task.estimatedMinutes,
                order: Double(index + 1) * 100
            )
        }
        return saveTemplate(named: name, from: drafts, in: context)
    }

    @discardableResult
    public static func saveTemplate(
        named name: String,
        from drafts: [TemplateTaskDraft],
        in context: ModelContext
    ) -> TaskTemplate? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceDrafts = drafts
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.order < $1.order }
        guard !trimmedName.isEmpty, !sourceDrafts.isEmpty else { return nil }

        let template = TaskTemplate(name: trimmedName)
        context.insert(template)

        for (index, draft) in sourceDrafts.enumerated() {
            let item = TaskTemplateItem(
                templateId: template.id,
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                note: normalizedOptionalText(draft.note),
                priority: draft.priority.flatMap { TaskPriority(rawValue: $0)?.rawValue },
                tags: draft.tags,
                estimatedMinutes: draft.estimatedMinutes,
                order: Double(index + 1) * 100
            )
            context.insert(item)
        }
        return template
    }

    @discardableResult
    public static func applyTemplate(
        _ template: TaskTemplate,
        items: [TaskTemplateItem],
        selectedDate: Date,
        existingTasks: [Task],
        in context: ModelContext
    ) -> Int {
        applyTemplate(
            template,
            items: items,
            selectedDates: [selectedDate],
            existingTasks: existingTasks,
            in: context,
            skipDuplicateTitles: false
        )
    }

    @discardableResult
    public static func applyTemplate(
        _ template: TaskTemplate,
        items: [TaskTemplateItem],
        selectedDates: [Date],
        existingTasks: [Task],
        in context: ModelContext,
        skipDuplicateTitles: Bool = true
    ) -> Int {
        applyTemplate(
            template,
            drafts: drafts(from: template, items: items),
            selectedDates: selectedDates,
            existingTasks: existingTasks,
            in: context,
            skipDuplicateTitles: skipDuplicateTitles
        )
    }

    public static func drafts(
        from template: TaskTemplate,
        items: [TaskTemplateItem]
    ) -> [TemplateTaskDraft] {
        items
            .filter { $0.supersededAt == nil && $0.templateId == template.id }
            .sorted { $0.order < $1.order }
            .map(TemplateTaskDraft.init(item:))
    }

    @discardableResult
    public static func applyTemplate(
        _ template: TaskTemplate,
        drafts: [TemplateTaskDraft],
        selectedDates: [Date],
        existingTasks: [Task],
        in context: ModelContext,
        skipDuplicateTitles: Bool = true
    ) -> Int {
        applyTemplateWithPlacements(
            template,
            drafts: drafts,
            selectedDates: selectedDates,
            existingTasks: existingTasks,
            in: context,
            skipDuplicateTitles: skipDuplicateTitles
        ).createdTaskCount
    }

    @discardableResult
    public static func applyTemplateWithPlacements(
        _ template: TaskTemplate,
        drafts: [TemplateTaskDraft],
        selectedDates: [Date],
        existingTasks: [Task],
        in context: ModelContext,
        skipDuplicateTitles: Bool = true,
        now: Date = Date()
    ) -> TemplateApplyResult {
        guard template.supersededAt == nil else {
            return TemplateApplyResult(createdTaskCount: 0, placements: [])
        }
        let orderedDrafts = drafts
            .sorted { $0.order < $1.order }
        guard !orderedDrafts.isEmpty else {
            return TemplateApplyResult(createdTaskCount: 0, placements: [])
        }

        let datesByKey = Dictionary(grouping: selectedDates.map(DayKey.startOfDay(for:)), by: DayKey.key(for:))
        let orderedDates = datesByKey
            .compactMap { _, dates in dates.first }
            .sorted { DayKey.key(for: $0) < DayKey.key(for: $1) }

        var createdCount = 0
        var placements: [TemplatePlacement] = []
        var nextOrderByDayKey: [String: Double] = [:]
        var knownTitlesByDayKey: [String: Set<String>] = [:]
        let templateName = normalizedOptionalText(template.name) ?? "템플릿"

        for date in orderedDates {
            let dayKey = DayKey.key(for: date)
            let dayTasks = existingTasks.filter {
                $0.supersededAt == nil && $0.archivedAt == nil && $0.plannedDayKey == dayKey
            }
            nextOrderByDayKey[dayKey] = ((dayTasks
                .filter { $0.status == TaskStatus.todo.rawValue }
                .map(\.order)
                .max()) ?? 0) + 100
            knownTitlesByDayKey[dayKey] = Set(dayTasks.map { normalizedTitle($0.title) })
            var placement: TemplatePlacement?

            for draft in orderedDrafts {
                let itemTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !itemTitle.isEmpty else { continue }

                let normalizedItemTitle = normalizedTitle(itemTitle)
                if skipDuplicateTitles, knownTitlesByDayKey[dayKey]?.contains(normalizedItemTitle) == true {
                    continue
                }

                if placement == nil {
                    let newPlacement = TemplatePlacement(
                        sourceTemplateId: template.id,
                        templateName: templateName,
                        dayKey: dayKey,
                        createdAt: now,
                        updatedAt: now
                    )
                    context.insert(newPlacement)
                    placement = newPlacement
                    placements.append(newPlacement)
                }

                guard let placement else { continue }
                let order = nextOrderByDayKey[dayKey] ?? 100
                let task = Task(
                    title: itemTitle,
                    note: normalizedOptionalText(draft.note),
                    status: .todo,
                    plannedAt: date,
                    order: order,
                    templatePlacementId: placement.id,
                    priority: draft.priority.flatMap(TaskPriority.init(rawValue:)),
                    tags: draft.tags,
                    estimatedMinutes: draft.estimatedMinutes,
                    createdAt: now,
                    updatedAt: now
                )
                context.insert(task)

                createdCount += 1
                nextOrderByDayKey[dayKey] = order + 100
                knownTitlesByDayKey[dayKey, default: []].insert(normalizedItemTitle)
            }
        }

        return TemplateApplyResult(createdTaskCount: createdCount, placements: placements)
    }

    @discardableResult
    public static func deleteTemplate(
        _ template: TaskTemplate,
        items: [TaskTemplateItem],
        in context: ModelContext
    ) -> Int {
        let templateItems = items.filter { $0.templateId == template.id }
        for item in templateItems {
            context.delete(item)
        }
        context.delete(template)
        return templateItems.count
    }

    public static func placements(on date: Date, in placements: [TemplatePlacement]) -> [TemplatePlacement] {
        Self.placements(onDayKey: DayKey.key(for: date), in: placements)
    }

    public static func placements(onDayKey dayKey: String, in placements: [TemplatePlacement]) -> [TemplatePlacement] {
        placements
            .filter { $0.supersededAt == nil && $0.dayKey == dayKey }
            .sorted(by: placementSort)
    }

    public static func placements(
        for template: TaskTemplate,
        in placements: [TemplatePlacement]
    ) -> [TemplatePlacement] {
        placements
            .filter { $0.supersededAt == nil && $0.sourceTemplateId == template.id }
            .sorted(by: placementSort)
    }

    public static func tasks(
        for placement: TemplatePlacement,
        in tasks: [Task]
    ) -> [Task] {
        return tasks
            .filter { $0.supersededAt == nil && $0.templatePlacementId == placement.id }
            .sorted(by: taskSort)
    }

    public static func deleteSummary(
        for placement: TemplatePlacement,
        in tasks: [Task]
    ) -> TemplatePlacementDeleteSummary {
        let placedTasks = Self.tasks(for: placement, in: tasks)
        let deletableTaskCount = placedTasks.filter(isDeletablePlacementTask).count
        return TemplatePlacementDeleteSummary(
            taskCount: placedTasks.count,
            deletableTaskCount: deletableTaskCount,
            protectedTaskCount: placedTasks.count - deletableTaskCount
        )
    }

    public static func canDeleteTasks(
        for placement: TemplatePlacement,
        in tasks: [Task]
    ) -> Bool {
        deleteSummary(for: placement, in: tasks).canDeleteTasks
    }

    @discardableResult
    public static func deletePlacement(
        _ placement: TemplatePlacement,
        tasks: [Task],
        in context: ModelContext,
        deleteTasks: Bool = true,
        now: Date = Date()
    ) -> Int {
        let placedTasks = Self.tasks(for: placement, in: tasks)
        if deleteTasks {
            guard Self.canDeleteTasks(for: placement, in: tasks) else { return 0 }
        }

        for task in placedTasks {
            if deleteTasks {
                context.delete(task)
            } else if task.templatePlacementId == placement.id {
                task.templatePlacementId = nil
                task.updatedAt = now
            }
        }
        context.delete(placement)
        return placedTasks.count
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedOptionalText(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func placementSort(_ lhs: TemplatePlacement, _ rhs: TemplatePlacement) -> Bool {
        if lhs.dayKey != rhs.dayKey {
            return lhs.dayKey < rhs.dayKey
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.templateName.localizedStandardCompare(rhs.templateName) == .orderedAscending
    }

    private static func taskSort(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.plannedDayKey != rhs.plannedDayKey {
            return lhs.plannedDayKey < rhs.plannedDayKey
        }
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func isDeletablePlacementTask(_ task: Task) -> Bool {
        task.status == TaskStatus.todo.rawValue && task.archivedAt == nil
    }
}
