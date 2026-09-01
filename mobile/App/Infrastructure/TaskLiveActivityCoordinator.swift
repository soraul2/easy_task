#if os(iOS)
import ActivityKit
import Foundation
import PlanBaseCore
import SwiftData

@MainActor
final class TaskLiveActivityCoordinator {
    static let shared = TaskLiveActivityCoordinator()

    private static let maximumSessionAge: TimeInterval = 8 * 60 * 60
    private static let receiptDefaultsKey = "planbase.live-activity.handled-sessions.v1"
    private static let maximumReceiptCount = 128

    private var isReconciling = false
    private var needsAnotherPass = false

    func reconcile(
        context: ModelContext,
        now: Date = Date(),
        allowStarting: Bool = true
    ) async {
        if isReconciling {
            needsAnotherPass = true
            return
        }

        isReconciling = true
        defer { isReconciling = false }
        repeat {
            needsAnotherPass = false
            do {
                try await reconcileOnce(
                    context: context,
                    now: now,
                    allowStarting: allowStarting
                )
            } catch {
                print("PlanBase Live Activity reconciliation failed: \(error)")
            }
        } while needsAnotherPass
    }

    func taskSessionID(
        for task: PlanBaseCore.Task,
        in context: ModelContext
    ) throws -> String {
        let events = try TaskProgressEventService.events(
            forTaskIDs: Set([task.id]),
            in: context
        )
        return Self.taskSession(
            task: task,
            projection: TaskProgressEventRules.projection(for: events)
        ).id
    }

    private func reconcileOnce(
        context: ModelContext,
        now: Date,
        allowStarting: Bool
    ) async throws {
        let dayKey = DayKey.key(for: now)
        let fetchedTasks = try context.fetch(
            BoundedQueryService.widgetPlannedTasksDescriptor(
                from: dayKey,
                through: dayKey
            )
        )
        let tasks = TodayTaskWidgetRules.eligibleRepresentatives(
            from: fetchedTasks,
            dayKey: dayKey
        )
        guard let currentTask = tasks.first(where: {
            $0.status == TaskStatus.doing.rawValue
        }) else {
            await Self.endAllActivities()
            return
        }

        let events = try TaskProgressEventService.events(
            forTaskIDs: Set([currentTask.id]),
            in: context
        )
        let projection = TaskProgressEventRules.projection(for: events)
        let session = Self.taskSession(task: currentTask, projection: projection)
        if now.timeIntervalSince(session.startedAt) >= Self.maximumSessionAge {
            markHandled(session.id)
            await Self.endAllActivities()
            return
        }

        let contentState = makeContentState(
            currentTask: currentTask,
            tasks: tasks,
            sessionID: session.id,
            elapsedTimerStartedAt: Self.elapsedTimerStartedAt(
                sessionStartedAt: session.startedAt,
                projection: projection,
                now: now
            ),
            now: now
        )
        let content = ActivityContent(
            state: contentState,
            staleDate: DayKey.addingDays(1, to: DayKey.startOfDay(for: now)),
            relevanceScore: 80
        )

        if await Self.updateExistingActivity(dayKey: dayKey, content: content) {
            markHandled(session.id)
            return
        }

        guard allowStarting, !handledSessionIDs.contains(session.id) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            markHandled(session.id)
            return
        }

        do {
            _ = try Activity.request(
                attributes: PlanBaseTaskActivityAttributes(
                    activityID: UUID(),
                    dayKey: dayKey
                ),
                content: content,
                pushType: nil
            )
            markHandled(session.id)
        } catch {
            markHandled(session.id)
            throw error
        }
    }

    private func makeContentState(
        currentTask: PlanBaseCore.Task,
        tasks: [PlanBaseCore.Task],
        sessionID: String,
        elapsedTimerStartedAt: Date,
        now: Date
    ) -> PlanBaseTaskActivityAttributes.ContentState {
        let completedCount = tasks.reduce(0) { result, task in
            result + (task.status == TaskStatus.done.rawValue ? 1 : 0)
        }
        let title = currentTask.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlanBaseTaskActivityAttributes.ContentState(
            taskSessionID: sessionID,
            taskID: currentTask.id,
            title: title.isEmpty ? "진행 중인 작업" : title,
            completedCount: completedCount,
            totalCount: tasks.count,
            hasNextTask: TodayTaskWidgetRules.nextTask(
                after: currentTask.id,
                from: tasks,
                dayKey: currentTask.plannedDayKey
            ) != nil,
            requiresCompletionConfirmation: TaskReminderRules.hasUpcomingReminder(
                currentTask,
                now: now
            ),
            elapsedTimerStartedAt: elapsedTimerStartedAt,
            themeID: UserDefaults.standard.string(forKey: AppTheme.storageKey)
                ?? AppThemePreset.defaultID
        )
    }

    private static func taskSession(
        task: PlanBaseCore.Task,
        projection: TaskProgressProjection
    ) -> (id: String, startedAt: Date) {
        if let startedAt = projection.currentStartedAt {
            return (
                "\(task.id.uuidString.lowercased()):\(startedAt.timeIntervalSinceReferenceDate.bitPattern)",
                startedAt
            )
        }
        return (
            "\(task.id.uuidString.lowercased()):legacy-doing",
            task.updatedAt
        )
    }

    private static func elapsedTimerStartedAt(
        sessionStartedAt: Date,
        projection: TaskProgressProjection,
        now: Date
    ) -> Date {
        let currentSessionDuration = max(0, now.timeIntervalSince(sessionStartedAt))
        let knownElapsedDuration = projection.recordedDuration + currentSessionDuration
        return now.addingTimeInterval(-knownElapsedDuration)
    }

    private nonisolated static func updateExistingActivity(
        dayKey: String,
        content: ActivityContent<PlanBaseTaskActivityAttributes.ContentState>
    ) async -> Bool {
        let activities = Activity<PlanBaseTaskActivityAttributes>.activities
            .sorted { $0.id < $1.id }
        let matching = activities.first { $0.attributes.dayKey == dayKey }
        for activity in activities where activity.id != matching?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let matching else { return false }
        await matching.update(content)
        return true
    }

    private nonisolated static func endAllActivities() async {
        let activities = Activity<PlanBaseTaskActivityAttributes>.activities
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private var handledSessionIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.receiptDefaultsKey) ?? [])
    }

    private func markHandled(_ sessionID: String) {
        var receipts = UserDefaults.standard.stringArray(forKey: Self.receiptDefaultsKey) ?? []
        receipts.removeAll { $0 == sessionID }
        receipts.append(sessionID)
        if receipts.count > Self.maximumReceiptCount {
            receipts.removeFirst(receipts.count - Self.maximumReceiptCount)
        }
        UserDefaults.standard.set(receipts, forKey: Self.receiptDefaultsKey)
    }
}
#endif
