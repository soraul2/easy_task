#if os(watchOS)
import Combine
import PlanBaseCore
import SwiftData
import SwiftUI

struct WatchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeDayKey = DayKey.today
    @State private var startupIssue: String?

    var body: some View {
        WatchTodayView(dayKey: activeDayKey, startupIssue: startupIssue)
            .id(activeDayKey)
            .task {
                start()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshDay()
                publishWidget(forceWrite: true)
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
            }
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
}
#endif
