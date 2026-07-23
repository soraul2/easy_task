#if os(iOS)
import PlanBaseCore
import SwiftData
import SwiftUI
import WidgetKit

struct CalendarWidgetSnapshotPublisher: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var observedEvents: [CalendarEvent]
    @Query private var observedPlannedTasks: [PlanBaseCore.Task]
    @Query private var observedCompletedTasks: [PlanBaseCore.Task]
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID
    @State private var publicationTask: Swift.Task<Void, Never>?
    @State private var needsPublication = false

    init(referenceDate: Date = Date()) {
        let coverage = CalendarWidgetSnapshot.coverageDayKeys(for: referenceDate)
        let lockScreenCoverage = LockScreenWidgetRules.coverageDayKeys(for: referenceDate)
        _observedEvents = Query(BoundedQueryService.eventsDescriptor(
            overlappingStartDayKey: coverage.startDayKey,
            endDayKey: coverage.endDayKey
        ))
        _observedPlannedTasks = Query(BoundedQueryService.widgetPlannedTasksDescriptor(
            from: lockScreenCoverage.startDayKey,
            through: lockScreenCoverage.endDayKey
        ))
        _observedCompletedTasks = Query(BoundedQueryService.widgetCompletedTasksDescriptor(
            from: lockScreenCoverage.startDayKey,
            through: lockScreenCoverage.endDayKey
        ))
    }

    private var eventFingerprint: String {
        observedEvents.map { event in
            [
                event.instanceID.uuidString,
                event.id.uuidString,
                event.title,
                event.startDayKey,
                event.endDayKey,
                event.color ?? "",
                String(event.updatedAt.timeIntervalSinceReferenceDate),
                String(event.supersededAt?.timeIntervalSinceReferenceDate ?? 0)
            ].joined(separator: "|")
        }
        .sorted()
        .joined(separator: ";")
    }

    private var taskFingerprint: String {
        (observedPlannedTasks + observedCompletedTasks).map { task in
            [
                task.instanceID.uuidString,
                task.id.uuidString,
                task.title,
                task.status,
                task.plannedDayKey,
                task.completedDayKey ?? "",
                String(task.order),
                String(task.updatedAt.timeIntervalSinceReferenceDate),
                String(task.archivedAt?.timeIntervalSinceReferenceDate ?? 0),
                String(task.supersededAt?.timeIntervalSinceReferenceDate ?? 0)
            ].joined(separator: "|")
        }
        .sorted()
        .joined(separator: ";")
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                requestPublication()
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                requestPublication()
            }
            .onChange(of: selectedThemeID) {
                requestPublication()
            }
            .onChange(of: eventFingerprint) {
                requestPublication()
            }
            .onChange(of: taskFingerprint) {
                requestPublication()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: PersistenceCommandService.dataChangedNotification
            )) { _ in
                requestPublication()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                requestPublication()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .NSSystemTimeZoneDidChange
            )) { _ in
                requestPublication()
            }
            .onDisappear {
                publicationTask?.cancel()
                publicationTask = nil
            }
    }

    @MainActor
    private func requestPublication() {
        needsPublication = true
        guard publicationTask == nil else { return }

        publicationTask = Swift.Task { @MainActor in
            try? await Swift.Task.sleep(for: .milliseconds(150))
            while !Swift.Task.isCancelled, needsPublication {
                needsPublication = false
                await publishSnapshot()
            }
            publicationTask = nil
        }
    }

    @MainActor
    private func publishSnapshot() async {
        do {
            let referenceDate = Date()
            let coverage = CalendarWidgetSnapshot.coverageDayKeys(for: referenceDate)
            let events = try modelContext.fetch(
                BoundedQueryService.eventsDescriptor(
                    overlappingStartDayKey: coverage.startDayKey,
                    endDayKey: coverage.endDayKey
                )
            )
            let lockScreenCoverage = LockScreenWidgetRules.coverageDayKeys(
                for: referenceDate
            )
            let plannedTasks = try modelContext.fetch(
                BoundedQueryService.widgetPlannedTasksDescriptor(
                    from: lockScreenCoverage.startDayKey,
                    through: lockScreenCoverage.endDayKey
                )
            )
            let completedTasks = try modelContext.fetch(
                BoundedQueryService.widgetCompletedTasksDescriptor(
                    from: lockScreenCoverage.startDayKey,
                    through: lockScreenCoverage.endDayKey
                )
            )
            let tasks = mergedTasks(plannedTasks, completedTasks)
            let snapshot = CalendarWidgetSnapshot.make(
                events: events,
                tasks: tasks,
                referenceDate: referenceDate,
                themeID: selectedThemeID
            )
            let didWrite = try await Swift.Task.detached(priority: .utility) {
                try CalendarWidgetSnapshotStore.writeIfChanged(snapshot)
            }.value
            if didWrite {
                WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
                WidgetCenter.shared.reloadTimelines(
                    ofKind: CalendarWidgetConstants.lockScreenKind
                )
            }
        } catch {
            print("캘린더 위젯 데이터를 갱신하지 못했습니다: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func mergedTasks(
        _ plannedTasks: [PlanBaseCore.Task],
        _ completedTasks: [PlanBaseCore.Task]
    ) -> [PlanBaseCore.Task] {
        var seenInstanceIDs: Set<UUID> = []
        return (plannedTasks + completedTasks).filter {
            seenInstanceIDs.insert($0.instanceID).inserted
        }
    }
}
#endif
