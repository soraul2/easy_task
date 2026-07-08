import Foundation
import SwiftData

public enum TemplateService {
    public static func saveTemplate(
        named name: String,
        from tasks: [Task],
        in context: ModelContext
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let template = TaskTemplate(name: trimmedName)
        context.insert(template)

        let sourceTasks = tasks
            .filter { $0.archivedAt == nil }
            .sorted { $0.order < $1.order }

        for (index, task) in sourceTasks.enumerated() {
            let item = TaskTemplateItem(
                templateId: template.id,
                title: task.title,
                note: task.note,
                priority: task.priority,
                tags: task.tags,
                estimatedMinutes: task.estimatedMinutes,
                order: Double(index + 1) * 100
            )
            context.insert(item)
        }
    }

    public static func applyTemplate(
        _ template: TaskTemplate,
        items: [TaskTemplateItem],
        selectedDate: Date,
        existingTasks: [Task],
        in context: ModelContext
    ) {
        let orderedItems = items
            .filter { $0.templateId == template.id }
            .sorted { $0.order < $1.order }

        let baseOrder = TaskRules.nextOrder(in: existingTasks, status: .todo)
        for (index, item) in orderedItems.enumerated() {
            let task = Task(
                title: item.title,
                note: item.note,
                status: .todo,
                plannedAt: selectedDate,
                order: baseOrder + Double(index) * 100,
                priority: item.priority.flatMap(TaskPriority.init(rawValue:)),
                tags: item.tags,
                estimatedMinutes: item.estimatedMinutes
            )
            context.insert(task)
        }
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
        let orderedItems = items
            .filter { $0.templateId == template.id }
            .sorted { $0.order < $1.order }
        guard !orderedItems.isEmpty else { return 0 }

        let datesByKey = Dictionary(grouping: selectedDates.map(DayKey.startOfDay(for:)), by: DayKey.key(for:))
        let orderedDates = datesByKey
            .compactMap { _, dates in dates.first }
            .sorted { DayKey.key(for: $0) < DayKey.key(for: $1) }

        var createdCount = 0
        var nextOrderByDayKey: [String: Double] = [:]
        var knownTitlesByDayKey: [String: Set<String>] = [:]

        for date in orderedDates {
            let dayKey = DayKey.key(for: date)
            let dayTasks = existingTasks.filter { $0.archivedAt == nil && $0.plannedDayKey == dayKey }
            nextOrderByDayKey[dayKey] = ((dayTasks
                .filter { $0.status == TaskStatus.todo.rawValue }
                .map(\.order)
                .max()) ?? 0) + 100
            knownTitlesByDayKey[dayKey] = Set(dayTasks.map { normalizedTitle($0.title) })

            for item in orderedItems {
                let itemTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !itemTitle.isEmpty else { continue }

                let normalizedItemTitle = normalizedTitle(itemTitle)
                if skipDuplicateTitles, knownTitlesByDayKey[dayKey]?.contains(normalizedItemTitle) == true {
                    continue
                }

                let order = nextOrderByDayKey[dayKey] ?? 100
                let task = Task(
                    title: itemTitle,
                    note: item.note,
                    status: .todo,
                    plannedAt: date,
                    order: order,
                    priority: item.priority.flatMap(TaskPriority.init(rawValue:)),
                    tags: item.tags,
                    estimatedMinutes: item.estimatedMinutes
                )
                context.insert(task)

                createdCount += 1
                nextOrderByDayKey[dayKey] = order + 100
                knownTitlesByDayKey[dayKey, default: []].insert(normalizedItemTitle)
            }
        }

        return createdCount
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
