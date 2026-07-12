import Foundation

public struct TaskReminderSnapshot: Equatable, Hashable, Sendable {
    public var taskID: UUID
    public var title: String
    public var plannedDayKey: String
    public var reminderAt: Date

    public init(
        taskID: UUID,
        title: String,
        plannedDayKey: String,
        reminderAt: Date
    ) {
        self.taskID = taskID
        self.title = title
        self.plannedDayKey = plannedDayKey
        self.reminderAt = reminderAt
    }

    public var identifier: String {
        TaskReminderRules.identifier(for: taskID)
    }
}

public struct PendingTaskReminder: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var reminderAt: Date?

    public init(identifier: String, title: String, reminderAt: Date?) {
        self.identifier = identifier
        self.title = title
        self.reminderAt = reminderAt
    }
}

public struct TaskReminderReconciliationPlan: Equatable, Sendable {
    public var remindersToSchedule: [TaskReminderSnapshot]
    public var identifiersToCancel: [String]

    public init(
        remindersToSchedule: [TaskReminderSnapshot] = [],
        identifiersToCancel: [String] = []
    ) {
        self.remindersToSchedule = remindersToSchedule
        self.identifiersToCancel = identifiersToCancel
    }

    public var isEmpty: Bool {
        remindersToSchedule.isEmpty && identifiersToCancel.isEmpty
    }
}

public enum TaskReminderRules {
    public static let identifierPrefix = "easytask.task-reminder."

    public static func normalizedDate(_ date: Date?) -> Date? {
        guard let date,
              date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let minute = floor(date.timeIntervalSinceReferenceDate / 60) * 60
        return Date(timeIntervalSinceReferenceDate: minute)
    }

    public static func identifier(for taskID: UUID) -> String {
        identifierPrefix + taskID.uuidString.lowercased()
    }

    public static func taskID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(identifierPrefix.count)))
    }

    public static func snapshot(
        for task: Task,
        now: Date = Date()
    ) -> TaskReminderSnapshot? {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard task.supersededAt == nil,
              let status = TaskStatus(rawValue: task.status),
              status == .todo || status == .doing,
              !title.isEmpty,
              let reminderAt = normalizedDate(task.reminderAt),
              reminderAt > now else { return nil }
        return TaskReminderSnapshot(
            taskID: task.id,
            title: title,
            plannedDayKey: task.plannedDayKey,
            reminderAt: reminderAt
        )
    }

    public static func desiredSnapshots(
        from tasks: [Task],
        now: Date = Date()
    ) -> [TaskReminderSnapshot] {
        let candidates = tasks.compactMap { snapshot(for: $0, now: now) }
        let grouped = Dictionary(grouping: candidates, by: \.taskID)
        return grouped.values.compactMap { records in
            records.sorted {
                if $0.reminderAt != $1.reminderAt {
                    return $0.reminderAt > $1.reminderAt
                }
                return $0.title > $1.title
            }.first
        }.sorted { $0.identifier < $1.identifier }
    }

    public static func reconciliationPlan(
        desired: [TaskReminderSnapshot],
        pending: [PendingTaskReminder]
    ) -> TaskReminderReconciliationPlan {
        let desiredByIdentifier = desired.reduce(
            into: [String: TaskReminderSnapshot]()
        ) { result, snapshot in
            result[snapshot.identifier] = snapshot
        }
        let ownedPending = pending.filter {
            $0.identifier.hasPrefix(identifierPrefix)
        }
        let pendingByIdentifier = Dictionary(
            grouping: ownedPending,
            by: \.identifier
        )

        var schedule: [TaskReminderSnapshot] = []
        var cancel: Set<String> = []

        for (identifier, requests) in pendingByIdentifier {
            guard let target = desiredByIdentifier[identifier] else {
                cancel.insert(identifier)
                continue
            }
            let exactMatches = requests.filter {
                $0.title == target.title &&
                    normalizedDate($0.reminderAt) == target.reminderAt
            }
            if exactMatches.count != 1 || requests.count != 1 {
                cancel.insert(identifier)
                schedule.append(target)
            }
        }

        for target in desired where pendingByIdentifier[target.identifier] == nil {
            schedule.append(target)
        }

        return TaskReminderReconciliationPlan(
            remindersToSchedule: schedule.sorted { $0.identifier < $1.identifier },
            identifiersToCancel: cancel.sorted()
        )
    }
}
