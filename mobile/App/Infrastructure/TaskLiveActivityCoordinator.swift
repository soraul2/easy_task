#if os(iOS)
import ActivityKit
import Foundation
import PlanBaseCore
import SwiftData
import UIKit

@MainActor
final class TaskLiveActivityCoordinator {
    static let shared = TaskLiveActivityCoordinator()
#if DEBUG
    static let didReconcileNotification = Notification.Name("PlanBaseLiveActivityAuditUpdated")
#endif
    let selectionStore = TaskLiveActivitySelectionStore()
    private let lifetimeStore = TaskLiveActivityLifetimeStore()
    private var observers: [String: Swift.Task<Void, Never>] = [:]
    private var isReconciling = false
    private var pending: Request?

    private struct Request {
        var context: ModelContext
        var now: Date
        var allowStarting: Bool
        var fromIntent: Bool
        var explicitStart: Bool
    }

    func resumeAfterExplicitStart(taskID: UUID, context: ModelContext) async {
        do {
            let tasks = try TaskLiveActivitySelectionRules.fetchTodayTasks(in: context, dayKey: DayKey.today)
            try selectionStore.select(taskID: taskID, tasks: tasks, dayKey: DayKey.today)
            await reconcile(context: context, explicitStart: true)
        } catch {
            // The task may have moved out of today after the successful status command.
            await reconcile(context: context)
        }
    }

    func reconcile(
        context: ModelContext, now: Date = Date(), allowStarting: Bool = true,
        fromIntent: Bool = false, explicitStart: Bool = false
    ) async {
        pending = Request(context: context, now: now,
            allowStarting: allowStarting || pending?.allowStarting == true,
            fromIntent: fromIntent || pending?.fromIntent == true,
            explicitStart: explicitStart || pending?.explicitStart == true)
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }
        while let request = pending {
            pending = nil
            do { try await reconcileOnce(request) }
            catch { print("PlanBase Live Activity reconciliation failed: \(error)") }
#if DEBUG
            NotificationCenter.default.post(name: Self.didReconcileNotification, object: nil)
#endif
        }
    }

    private func reconcileOnce(_ request: Request) async throws {
        let context = request.context
        let now = request.now
        observeExisting(now: now)
        if try FocusSessionService.activeSnapshot() != nil,
           case .unchanged(let active) = try FocusSessionService.reconcile(now: now, in: context) {
            let state = PlanBaseTaskActivityAttributes.ContentState(
                taskSessionID: "focus:\(active.sessionID.uuidString.lowercased())",
                taskID: active.taskID, title: active.taskTitleSnapshot,
                completedCount: 0, totalCount: 0, hasNextTask: false,
                requiresCompletionConfirmation: false, elapsedTimerStartedAt: active.phaseStartedAt,
                themeID: themeID, focusSessionID: active.sessionID, focusRevision: active.revision,
                focusPhaseRawValue: active.phaseRawValue, focusRunStateRawValue: active.runStateRawValue,
                focusDeadline: active.deadline, focusRemainingSecondsAtPause: active.remainingSecondsAtPause)
            await synchronize(state: state, dayKey: DayKey.key(for: now), staleDate: active.deadline,
                              isFocus: true, request: request)
            return
        }

        let dayKey = DayKey.key(for: now)
        let tasks = try TaskLiveActivitySelectionRules.fetchTodayTasks(in: context, dayKey: dayKey)
        guard let selection = selectionStore.selection(tasks: tasks, dayKey: dayKey),
              let task = tasks.first(where: { $0.id == selection.taskID }) else {
            await endAllActivities()
            return
        }
        var timerStart = task.updatedAt
        if task.status == TaskStatus.doing.rawValue {
            let events = try TaskProgressEventService.events(forTaskIDs: [task.id], in: context)
            let projection = TaskProgressEventRules.projection(for: events)
            let currentStart = projection.currentStartedAt ?? task.updatedAt
            timerStart = now.addingTimeInterval(-(projection.recordedDuration + max(0, now.timeIntervalSince(currentStart))))
        }
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = PlanBaseTaskActivityAttributes.ContentState(
            taskSessionID: selection.token, taskID: task.id,
            title: title.isEmpty ? (task.status == TaskStatus.todo.rawValue ? "할 일" : "진행 중인 작업") : title,
            completedCount: tasks.filter { $0.status == TaskStatus.done.rawValue }.count,
            totalCount: tasks.count,
            hasNextTask: TaskLiveActivitySelectionRules.candidates(from: tasks, dayKey: dayKey).count > 1,
            requiresCompletionConfirmation: task.status == TaskStatus.doing.rawValue
                && TaskReminderRules.hasUpcomingReminder(task, now: now),
            elapsedTimerStartedAt: timerStart, themeID: themeID, taskStatusRawValue: task.status)
        await synchronize(state: state, dayKey: dayKey,
                          staleDate: DayKey.addingDays(1, to: DayKey.startOfDay(for: now)),
                          isFocus: false, request: request)
    }

    private func synchronize(
        state: PlanBaseTaskActivityAttributes.ContentState, dayKey: String, staleDate: Date?,
        isFocus: Bool, request: Request
    ) async {
        let canRequest = request.allowStarting && (request.fromIntent || UIApplication.shared.applicationState == .active)
        let content = ActivityContent(state: state, staleDate: staleDate, relevanceScore: isFocus ? 100 : 80)
        let activities = Activity<PlanBaseTaskActivityAttributes>.activities.sorted { $0.id < $1.id }
        var matching = activities.first { isUpdatable($0) && (isFocus || $0.attributes.dayKey == dayKey) }
        // Lifetime belongs to the Activity, regardless of how long a task has been running.
        if let current = matching, canRequest,
           let startedAt = current.attributes.createdAt ?? lifetimeStore.receipt?.startedAt,
           request.now.timeIntervalSince(startedAt) >= TaskLiveActivityLifetimeStore.maximumActivityAge {
            lifetimeStore.observeEnded(id: current.id, now: request.now)
            await end(current)
            matching = nil
        }
        for activity in activities where activity.id != matching?.id { await end(activity) }
        if let matching {
            if matching.content.state != state { await Self.updateActivity(id: matching.id, content: content) }
            return
        }
        guard canRequest, ActivityAuthorizationInfo().areActivitiesEnabled,
              lifetimeStore.permitsStarting(dayKey: dayKey, activityIsMissing: true, explicitStart: request.explicitStart) else { return }
        do {
            let activity = try Activity.request(
                attributes: PlanBaseTaskActivityAttributes(activityID: UUID(), dayKey: dayKey, createdAt: request.now),
                content: content, pushType: nil)
            lifetimeStore.recordStarted(id: activity.id, dayKey: dayKey, at: request.now)
            observe(activity)
        } catch {
            // Permissions and foreground eligibility can change. A failed request is retryable.
            print("PlanBase Live Activity request failed: \(error)")
        }
    }

    private var themeID: String {
        UserDefaults.standard.string(forKey: AppTheme.storageKey) ?? AppThemePreset.defaultID
    }

    private func isUpdatable(_ activity: Activity<PlanBaseTaskActivityAttributes>) -> Bool {
        activity.activityState == .active || activity.activityState == .stale
    }

    private func observeExisting(now: Date) {
        let activities = Activity<PlanBaseTaskActivityAttributes>.activities.sorted { $0.id < $1.id }
        if lifetimeStore.receipt?.activityID == nil, let activity = activities.first(where: isUpdatable) {
            lifetimeStore.recordStarted(id: activity.id, dayKey: activity.attributes.dayKey,
                                        at: activity.attributes.createdAt ?? now)
        }
        for activity in activities {
            record(activity.activityState, for: activity.id, now: now)
            observe(activity)
        }
    }

    private func observe(_ activity: Activity<PlanBaseTaskActivityAttributes>) {
        guard observers[activity.id] == nil else { return }
        observers[activity.id] = Swift.Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Swift.Task.isCancelled else { return }
                self?.record(state, for: activity.id, now: Date())
                if state == .dismissed { break }
            }
            self?.observers[activity.id] = nil
        }
    }

    private func record(_ state: ActivityState, for id: String, now: Date) {
        if state == .ended { lifetimeStore.observeEnded(id: id, now: now) }
        if state == .dismissed { lifetimeStore.observeDismissed(id: id, now: now) }
    }

    private func end(_ activity: Activity<PlanBaseTaskActivityAttributes>) async {
        lifetimeStore.recordAppEnding(id: activity.id)
        observers.removeValue(forKey: activity.id)?.cancel()
        await Self.endActivity(id: activity.id)
    }

    private nonisolated static func updateActivity(
        id: String, content: ActivityContent<PlanBaseTaskActivityAttributes.ContentState>
    ) async {
        guard let activity = Activity<PlanBaseTaskActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(content)
    }

    private nonisolated static func endActivity(id: String) async {
        guard let activity = Activity<PlanBaseTaskActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private func endAllActivities() async {
        for activity in Activity<PlanBaseTaskActivityAttributes>.activities { await end(activity) }
    }
}
#if DEBUG
import SwiftUI

struct TaskLiveActivityAuditView: View {
    @State private var summary = ""
    var body: some View {
        Text(summary)
            .font(.system(size: 8, design: .monospaced))
            .padding(3)
            .background(.thinMaterial)
            .accessibilityIdentifier("live-card-audit")
            .allowsHitTesting(false)
            .task { refresh() }
            .onReceive(NotificationCenter.default.publisher(for: TaskLiveActivityCoordinator.didReconcileNotification)) { _ in refresh() }
    }
    private func refresh() {
        let cards = Activity<PlanBaseTaskActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        summary = "cards=\(cards.count)|activity=\(cards.first?.id ?? "none")|status=\(cards.first?.content.state.taskStatusRawValue ?? "focus")"
    }
}
#endif
#endif
