#if os(watchOS)
import Combine
import PlanBaseCore
import SwiftData
import SwiftUI
import WatchKit

struct WatchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeDayKey = DayKey.today
    @State private var startupIssue: String?
    @State private var focusPath: [WatchFocusDestination] = []
    @State private var isReconcilingFocus = false

    var body: some View {
        NavigationStack(path: $focusPath) {
            WatchTodayView(dayKey: activeDayKey, startupIssue: startupIssue)
                .id(activeDayKey)
                .navigationDestination(for: WatchFocusDestination.self) { destination in
                    WatchFocusView(initialTaskID: destination.taskID)
                }
        }
            .task {
                start()
                await WatchFocusNotificationScheduler.shared.reconcile()
                await handlePendingFocusNotificationRoutes()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshDay()
                reconcileFocusSession(playHaptic: true)
                publishWidget(forceWrite: true)
                Swift.Task { @MainActor in
                    await WatchFocusNotificationScheduler.shared.reconcile()
                    await handlePendingFocusNotificationRoutes()
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: CloudKitSyncService.eventChangedNotification
            )) { notification in
                handleCloudKitEvent(notification)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .NSCalendarDayChanged
            )) { _ in
                refreshDay()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .NSSystemTimeZoneDidChange
            )) { _ in
                refreshDay()
                reconcileFocusSession(playHaptic: false)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: PersistenceCommandService.dataChangedNotification
            )) { notification in
                guard let sourceContext = notification.object as? ModelContext,
                      sourceContext === modelContext else { return }
                Swift.Task { @MainActor in
                    reconcileFocusSession(playHaptic: false)
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: FocusActiveSessionStore.didChangeNotification
            )) { _ in
                publishWidget(forceWrite: true)
                Swift.Task { @MainActor in
                    await WatchFocusNotificationScheduler.shared.reconcile()
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: WatchFocusNotificationRouteStore.didReceiveRoute
            )) { _ in
                Swift.Task { @MainActor in
                    await handlePendingFocusNotificationRoutes()
                }
            }
            .onOpenURL(perform: handleDeepLink)
    }

    private func start() {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                _ = try DataIntegrityService.reconcile(
                    context: modelContext,
                    saveChanges: false
                )
                let candidates = try modelContext.fetch(
                    BoundedQueryService.tasksNeedingArchiveDescriptor(
                        before: activeDayKey
                    )
                )
                TaskRules.archiveIfNeeded(candidates, todayKey: activeDayKey)
            }
            startupIssue = nil
        } catch {
            startupIssue = "데이터 점검이 필요해요"
        }
        reconcileFocusSession(playHaptic: false)
        publishWidget(forceWrite: true)
    }

    private func refreshDay() {
        let currentDayKey = DayKey.today
        guard activeDayKey != currentDayKey else { return }
        activeDayKey = currentDayKey
    }

    private func handleCloudKitEvent(_ notification: Notification) {
        guard let summary = CloudKitSyncService.summary(from: notification) else { return }
        do {
            try CloudKitSyncService.reconcileIfNeeded(
                after: summary,
                context: modelContext
            )
            if CloudKitSyncService.shouldReconcile(after: summary) {
                startupIssue = nil
                reconcileFocusSession(playHaptic: false)
                publishWidget(forceWrite: true)
            }
        } catch {
            startupIssue = "iCloud 데이터 정리가 필요해요"
        }
    }

    private func publishWidget(forceWrite: Bool) {
        do {
            try WatchWidgetSnapshotPublicationService.publish(
                context: modelContext,
                forceWrite: forceWrite
            )
        } catch {
            print("PlanBase Watch 위젯 갱신 실패: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func reconcileFocusSession(playHaptic: Bool) {
        guard !isReconcilingFocus else { return }
        isReconcilingFocus = true
        defer { isReconcilingFocus = false }
        do {
            switch try FocusSessionService.reconcile(in: modelContext) {
            case .focusEnded, .breakEnded:
                if playHaptic {
                    WKInterfaceDevice.current().play(.notification)
                }
            case .unchanged, .noActiveSession:
                break
            }
        } catch {
            startupIssue = "집중 기록을 확인해 주세요"
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let route = PlanBaseDeepLink.focusRoute(from: url),
              let active = try? FocusSessionService.activeSnapshot() else { return }
        if let sessionID = route.sessionID, sessionID != active.sessionID { return }
        focusPath = [WatchFocusDestination(taskID: active.taskID)]
    }

    @MainActor
    private func handlePendingFocusNotificationRoutes() async {
        let routes = WatchFocusNotificationRouteStore.shared.consumeAll()
        guard !routes.isEmpty else { return }

        for route in routes {
            let taskID = (try? FocusNotificationActionTokenStore.read())?.taskID
            do {
                if route.action != .open {
                    _ = try FocusNotificationActionService.perform(
                        action: route.action,
                        tokenID: route.tokenID,
                        sessionID: route.sessionID,
                        revision: route.revision,
                        phase: route.phase,
                        deadline: route.deadline,
                        in: modelContext
                    )
                }
                WatchFocusNotificationScheduler.shared.removeDeliveredNotification(
                    identifier: route.requestIdentifier
                )
                await WatchFocusNotificationScheduler.shared.reconcile()
                publishWidget(forceWrite: true)
                if route.action != .dismiss, let taskID {
                    focusPath = [WatchFocusDestination(taskID: taskID)]
                }
            } catch FocusNotificationRulesError.staleAction {
                WatchFocusNotificationScheduler.shared.removeDeliveredNotification(
                    identifier: route.requestIdentifier
                )
                await WatchFocusNotificationScheduler.shared.reconcile()
            } catch {
                startupIssue = "집중 알림 동작을 실행하지 못했어요"
            }
        }
    }
}
#endif
