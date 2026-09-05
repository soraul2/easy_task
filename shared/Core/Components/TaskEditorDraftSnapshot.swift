import Foundation

/// UI-only comparison state; never written to the persistent store.
public struct TaskEditorDraftSnapshot: Equatable {
    public var title: String
    public var note: String
    public var status: TaskStatus
    public var plannedDate: Date
    public var priority: TaskPriority?
    public var estimatedMinutesText: String
    public var tagsText: String
    public var reminderAt: Date?
    public var checklist: [ChecklistItemDraft] = []
    public var pendingChecklistTitle = ""

    public init(task: Task) {
        title = task.title
        note = task.note ?? ""
        status = TaskStatus(rawValue: task.status) ?? .todo
        plannedDate = task.plannedAt
        priority = task.priority.flatMap(TaskPriority.init(rawValue:))
        estimatedMinutesText = task.estimatedMinutes.map(String.init) ?? ""
        tagsText = task.tags.joined(separator: ", ")
        reminderAt = TaskReminderRules.normalizedDate(task.reminderAt)
    }
}
