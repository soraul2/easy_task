#if os(iOS)
import AppIntents
import Foundation
import PlanBaseCore
import SwiftData

@MainActor
enum PlanBaseTaskIntentRuntime {
    static func install(modelContainer: ModelContainer) {
        let executor = PlanBaseTaskIntentCommandExecutor(
            modelContainer: modelContainer
        )
        AppDependencyManager.shared.add(
            key: PlanBaseTaskIntentDependency.key,
            dependency: executor
        )
    }
}

@MainActor
private final class PlanBaseTaskIntentCommandExecutor:
    PlanBaseTaskIntentCommandHandling,
    @unchecked Sendable {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func perform(_ command: PlanBaseTaskIntentCommand) async throws {
        let context = modelContainer.mainContext
        let now = Date()
        let todayDayKey = DayKey.key(for: now)
        let fetchedTasks = try context.fetch(
            BoundedQueryService.widgetPlannedTasksDescriptor(
                from: todayDayKey,
                through: todayDayKey
            )
        )
        let tasks = TodayTaskWidgetRules.eligibleRepresentatives(
            from: fetchedTasks,
            dayKey: todayDayKey
        )

        switch command {
        case .start(let taskID):
            guard tasks.allSatisfy({ $0.status != TaskStatus.doing.rawValue }),
                  let task = tasks.first(where: { $0.id == taskID }),
                  task.status == TaskStatus.todo.rawValue else {
                throw PlanBaseTaskIntentRuntimeError.staleTask
            }
            try PersistenceCommandService.perform(in: context) {
                try TaskLifecycleService.applyStatus(
                    .doing,
                    to: task,
                    in: context,
                    now: now
                )
            }

        case .complete(let taskID, let taskSessionID):
            let task = try validatedCurrentTask(
                id: taskID,
                sessionID: taskSessionID,
                tasks: tasks,
                context: context
            )
            guard !TaskReminderRules.hasUpcomingReminder(task, now: now) else {
                throw PlanBaseTaskIntentRuntimeError.completionNeedsConfirmation
            }
            try PersistenceCommandService.perform(in: context) {
                try TaskLifecycleService.applyStatus(
                    .done,
                    to: task,
                    in: context,
                    now: now
                )
            }
            TaskNotificationScheduler.shared.cancelNotifications(for: [task.id])

        case .advance(let taskID, let taskSessionID):
            let task = try validatedCurrentTask(
                id: taskID,
                sessionID: taskSessionID,
                tasks: tasks,
                context: context
            )
            guard let nextTask = TodayTaskWidgetRules.nextTask(
                after: task.id,
                from: tasks,
                dayKey: todayDayKey
            ) else {
                throw PlanBaseTaskIntentRuntimeError.noNextTask
            }
            let nextStatus = TaskStatus(rawValue: nextTask.status) ?? .todo
            try PersistenceCommandService.perform(in: context) {
                try TaskLifecycleService.applyStatus(
                    .todo,
                    to: task,
                    in: context,
                    now: now
                )
                if nextStatus == .todo {
                    try TaskLifecycleService.applyStatus(
                        .doing,
                        to: nextTask,
                        in: context,
                        now: now
                    )
                }
            }
        }

        let themeID = UserDefaults.standard.string(forKey: AppTheme.storageKey)
            ?? AppThemePreset.defaultID
        _ = try await CalendarWidgetSnapshotPublicationService.publish(
            context: context,
            themeID: themeID,
            forceTimelineReload: true,
            referenceDate: now
        )
        await TaskLiveActivityCoordinator.shared.reconcile(
            context: context,
            now: now
        )
    }

    private func validatedCurrentTask(
        id: UUID,
        sessionID: String,
        tasks: [PlanBaseCore.Task],
        context: ModelContext
    ) throws -> PlanBaseCore.Task {
        guard let task = tasks.first(where: { $0.id == id }),
              task.status == TaskStatus.doing.rawValue,
              try TaskLiveActivityCoordinator.shared.taskSessionID(
                  for: task,
                  in: context
              ) == sessionID else {
            throw PlanBaseTaskIntentRuntimeError.staleTask
        }
        return task
    }
}

private enum PlanBaseTaskIntentRuntimeError: LocalizedError {
    case staleTask
    case noNextTask
    case completionNeedsConfirmation

    var errorDescription: String? {
        switch self {
        case .staleTask:
            "작업이 이미 변경되었습니다."
        case .noNextTask:
            "진행할 다음 작업이 없습니다."
        case .completionNeedsConfirmation:
            "예정된 알림을 확인한 뒤 앱에서 완료해 주세요."
        }
    }
}
#endif
