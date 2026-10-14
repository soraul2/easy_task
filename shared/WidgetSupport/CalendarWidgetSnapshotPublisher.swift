import Combine
import PlanBaseCore
import SwiftData
import SwiftUI
import WidgetKit

actor CalendarWidgetSnapshotWriteCoordinator {
    static let shared = CalendarWidgetSnapshotWriteCoordinator()

    private var latestAcceptedSequenceByDestination: [String: UInt64] = [:]

    @discardableResult
    func write(
        _ snapshot: CalendarWidgetSnapshot,
        sequence: UInt64,
        directoryURL: URL? = nil,
        forceWrite: Bool = false
    ) throws -> Bool {
        let destinationKey = destinationKey(for: directoryURL)
        let latestAcceptedSequence = latestAcceptedSequenceByDestination[destinationKey] ?? 0
        guard sequence > latestAcceptedSequence else { return false }

        // Reserve the newest request before touching the file. If this write
        // fails, an older request must not replace the last known snapshot.
        latestAcceptedSequenceByDestination[destinationKey] = sequence
        return try CalendarWidgetSnapshotStore.writeIfChanged(
            snapshot,
            directoryURL: directoryURL,
            forceWrite: forceWrite
        )
    }

    private func destinationKey(for directoryURL: URL?) -> String {
        directoryURL?.standardizedFileURL.path
            ?? "app-group:\(CalendarWidgetConstants.appGroupIdentifier)"
    }
}

@MainActor
enum CalendarWidgetSnapshotPublicationService {
    private static var nextPublicationSequence: UInt64 = 0

    @discardableResult
    static func refresh(
        context: ModelContext,
        themeID: @MainActor () -> String,
        forceWrite: Bool,
        delay: Duration? = nil,
        directoryURL: URL? = nil,
        waitForDelay: (Duration) async throws -> Void = {
            try await Swift.Task.sleep(for: $0)
        },
        reloadTimelines: @MainActor () -> Void = reloadWidgetTimelines
    ) async throws -> Bool {
        if let delay {
            try await waitForDelay(delay)
        }
        // An import refresh may wait while the user selects a newer theme.
        // Read that preference when fetching the snapshot, after the delay.
        let selectedThemeID = themeID()
        return try await publish(
            context: context,
            themeID: selectedThemeID,
            forceWrite: forceWrite,
            forceTimelineReload: true,
            directoryURL: directoryURL,
            reloadTimelines: reloadTimelines
        )
    }

    @discardableResult
    static func publish(
        context: ModelContext,
        themeID: String,
        forceWrite: Bool = false,
        forceTimelineReload: Bool = false,
        referenceDate: Date = Date(),
        directoryURL: URL? = nil,
        reloadTimelines: @MainActor () -> Void = reloadWidgetTimelines
    ) async throws -> Bool {
#if DEBUG
        // In-memory UI fixtures must never overwrite the user's shared widget snapshot.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), directoryURL == nil {
            return false
        }
#endif
        nextPublicationSequence += 1
        let publicationSequence = nextPublicationSequence
        let snapshot: CalendarWidgetSnapshot
        let interval = PlanBasePerformanceTrace.begin("WidgetSnapshotRead")
        do {
            if context.hasChanges {
                // Preserve the previous publication semantics for pending edits:
                // another context can only read the saved store.
                snapshot = try CalendarWidgetSnapshotReader.makeSnapshot(
                    in: context,
                    referenceDate: referenceDate,
                    themeID: themeID
                )
            } else {
                let container = context.container
                let read = Swift.Task.detached(priority: .utility) {
                    let reader = CalendarWidgetSnapshotReader(modelContainer: container)
                    return try await reader.loadSnapshot(
                        referenceDate: referenceDate,
                        themeID: themeID
                    )
                }
                snapshot = try await withTaskCancellationHandler {
                    try await read.value
                } onCancel: {
                    read.cancel()
                }
            }
            try Swift.Task.checkCancellation()
            PlanBasePerformanceTrace.end("WidgetSnapshotRead", interval)
        } catch {
            PlanBasePerformanceTrace.end("WidgetSnapshotRead", interval)
            throw error
        }
        let didWrite = try await CalendarWidgetSnapshotWriteCoordinator.shared.write(
            snapshot,
            sequence: publicationSequence,
            directoryURL: directoryURL,
            forceWrite: forceWrite
        )

        if didWrite || forceTimelineReload {
            reloadTimelines()
        }
        return didWrite
    }

    private static func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.plannerKind)
#if os(iOS)
        WidgetCenter.shared.reloadTimelines(
            ofKind: CalendarWidgetConstants.lockScreenKind
        )
        WidgetCenter.shared.reloadTimelines(
            ofKind: CalendarWidgetConstants.calendarLockScreenKind
        )
#endif
    }

}

struct CalendarWidgetSnapshotPublisher: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID
    @State private var publicationTask: Swift.Task<Void, Never>?
    @State private var needsPublication = false
    @State private var hasCompletedInitialPublication = false

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
            .onReceive(NotificationCenter.default.publisher(
                for: PersistenceCommandService.dataChangedNotification
            )) { notification in
                guard let source = notification.object as? ModelContext, source === modelContext,
                      PersistenceCommandService.affects([.tasks, .calendar], in: notification) else { return }
                requestPublication()
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave, object: modelContext)) { notification in
                guard let source = notification.object as? ModelContext, source === modelContext,
                      !PersistenceCommandService.isPerformingCommand(in: modelContext),
                      PersistenceViewRevision.affects([.tasks, .calendar], inSaveNotification: notification) else { return }
                requestPublication()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: CloudKitSyncService.eventChangedNotification
            )) { notification in
                guard let event = CloudKitSyncService.summary(from: notification),
                      event.kind == .import, event.isCompleted, event.succeeded else { return }
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
            let isInitialPublication = !hasCompletedInitialPublication
            _ = try await CalendarWidgetSnapshotPublicationService.publish(
                context: modelContext,
                themeID: selectedThemeID,
                forceWrite: isInitialPublication,
                forceTimelineReload: isInitialPublication
            )
            hasCompletedInitialPublication = true
        } catch {
            print("캘린더 위젯 데이터를 갱신하지 못했습니다: \(error.localizedDescription)")
        }
    }
}
