import Combine
import Foundation
import SwiftData
import SwiftUI
import PlanBaseCore

enum AppTab: String, CaseIterable, Identifiable {
    case board
    case calendar
    case archive
    case memo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: "칸반보드"
        case .calendar: "캘린더"
        case .archive: "기록"
        case .memo: "메모"
        }
    }

    var symbol: String {
        switch self {
        case .board: "rectangle.3.group"
        case .calendar: "calendar"
        case .archive: "book.pages"
        case .memo: "note.text"
        }
    }
}

struct AppRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    @State private var selectedTab: AppTab = .board
    @State private var archiveState = ArchiveScreenState()
    @State private var selectedBoardDate = DayKey.startOfDay(for: Date())
    @State private var calendarNavigationDate: Date?
    @State private var activeDayKey = DayKey.today
    @State private var selectedBoardDayKey = DayKey.today
    @State private var isFollowingToday = true
    @State private var isWidgetSnapshotPublisherReady = false
    @State private var syncMonitor = CloudKitSyncMonitor()
    @State private var activityImportCoordinator: TaskActivityImportCoordinator?
    @State private var themePreferences = ThemePreferenceStore.shared
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID

    private var cloudKitEnabled: Bool {
        PlanBaseContainerFactory.runtimeAppStoreMode.usesCloudKit
    }

    private var preferredThemeColorScheme: ColorScheme {
        AppThemePreset.preset(for: selectedThemeID).preferredColorScheme
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: bottomContentInset)
                }

            if isWidgetSnapshotPublisherReady {
                CalendarWidgetSnapshotPublisher()
            }

            HStack(spacing: 14) {
                FloatingTabBar(selectedTab: $selectedTab)
                FocusModeLauncher {
                    openWindow(id: "focus-mode")
                }
                if cloudKitEnabled {
                    CloudKitSyncStatusButton(monitor: syncMonitor)
                }
                ThemeSelectorButton(selectedThemeID: $selectedThemeID)
            }
            .padding(.bottom, 20)
        }
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
        .environment(syncMonitor)
        .task {
            start()
            await DesktopFocusNotificationScheduler.shared.reconcile()
            await handlePendingFocusNotificationRoutes()
            if cloudKitEnabled {
                await syncMonitor.refreshAccountStatus()
            }
        }
        .onChange(of: selectedTab) {
            persistArchiveIfNeeded()
        }
        .onChange(of: selectedBoardDate) { _, newDate in
            selectedBoardDayKey = DayKey.key(for: newDate)
            isFollowingToday = selectedBoardDayKey == activeDayKey
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            let syncedThemeID = themePreferences.refreshFromCloud()
            if syncedThemeID != selectedThemeID {
                selectedThemeID = syncedThemeID
            }
            refreshCurrentDay()
            reconcileFocusSession()
            refreshWidgetSnapshot(forceWrite: true)
            Swift.Task {
                await DesktopFocusNotificationScheduler.shared.reconcile()
            }
            if cloudKitEnabled {
                Swift.Task { await syncMonitor.refreshAccountStatus() }
            }
        }
        .onChange(of: selectedThemeID) {
            AppTheme.activate(selectedThemeID, colorScheme: colorScheme)
            refreshWidgetSnapshot(forceWrite: true)
        }
        .onChange(of: colorScheme) {
            AppTheme.activate(selectedThemeID, colorScheme: colorScheme)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: CloudKitSyncService.eventChangedNotification
        )) { notification in
            handleCloudKitEvent(notification)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { notification in
            guard let sourceContext = notification.object as? ModelContext,
                  sourceContext === modelContext else { return }
            reconcileFocusSession()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: FocusActiveSessionStore.didChangeNotification
        )) { _ in
            Swift.Task {
                await DesktopFocusNotificationScheduler.shared.reconcile(
                    requestAuthorizationIfNeeded: true
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: DesktopFocusNotificationRouteStore.didReceiveRoute
        )) { _ in
            Swift.Task {
                await handlePendingFocusNotificationRoutes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSUbiquitousKeyValueStore.didChangeExternallyNotification
        )) { notification in
            let keys = notification.userInfo?[
                NSUbiquitousKeyValueStoreChangedKeysKey
            ] as? [String]
            let syncedThemeID = themePreferences.applyCloudChanges(changedKeys: keys)
            if syncedThemeID != selectedThemeID {
                selectedThemeID = syncedThemeID
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshCurrentDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refreshCurrentDay()
        }
        .onOpenURL(perform: handleDeepLink)
        .preferredColorScheme(preferredThemeColorScheme)
    }

    private var bottomContentInset: CGFloat {
        selectedTab == .calendar ? 0 : 92
    }

    private func start() {
        prepareActivityImportCoordinatorIfNeeded()
        defer {
            // Widget publication is best-effort and must stay available even if
            // an unrelated startup reconciliation or migration fails.
            isWidgetSnapshotPublisherReady = true
            refreshWidgetSnapshot(forceWrite: true)
        }
        let migratedThemeID = AppTheme.migrateStoredDefaultIfNeeded(selectedThemeID)
        if migratedThemeID != selectedThemeID {
            selectedThemeID = migratedThemeID
        }
        let syncedThemeID = themePreferences.start(
            syncsWithICloud: themePreferenceCloudSyncEnabled
        )
        if syncedThemeID != selectedThemeID {
            selectedThemeID = syncedThemeID
        }
        AppTheme.activate(syncedThemeID, colorScheme: colorScheme)

        do {
            try PersistenceCommandService.perform(in: modelContext) {
                _ = try DataIntegrityService.reconcile(
                    context: modelContext,
                    saveChanges: false
                )
            }
            reconcileFocusSession()
            let migration = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
                context: modelContext,
                appSupportFolder: PlanBaseCompatibility.legacyDesktopImageFolderName
            )
            if !migration.missingFileNames.isEmpty ||
                !migration.rejectedFileNames.isEmpty ||
                !migration.deferredFileNames.isEmpty {
                syncMonitor.recordIssue(
                    "이전 회고 이미지 정리가 필요합니다. " +
                        "누락 \(migration.missingFileNames.count)개, " +
                        "거부 \(migration.rejectedFileNames.count)개, " +
                        "보류 \(migration.deferredFileNames.count)개"
                )
            }
            try PersistenceCommandService.perform(in: modelContext) {
                try seedDemoDataIfNeeded()
                try seedEventHistoryFixturesIfNeeded()
                try archiveTasksIfNeeded()
            }
        } catch {
            syncMonitor.recordStartupFailure(error)
        }
    }

    private var themePreferenceCloudSyncEnabled: Bool {
#if DEBUG
        !PlanBaseDesktopLaunchEnvironment.isUITesting
#else
        true
#endif
    }

    private func seedDemoDataIfNeeded() throws {
#if DEBUG
        if PlanBaseDesktopLaunchEnvironment.isUITesting,
           ProcessInfo.processInfo.arguments.contains("--ui-testing-daily-activity-fixtures") {
            try DailyActivityPreviewFixtures.seed(in: modelContext)
            return
        }
#endif
#if DEBUG
        let demoCloudKitEnabled =
            cloudKitEnabled && !PlanBaseDesktopLaunchEnvironment.isUITesting
#else
        let demoCloudKitEnabled = cloudKitEnabled
#endif
        let policy = SeedPolicy.appStartup(
            cloudKitEnabled: demoCloudKitEnabled
        )
        guard case .demo = policy else { return }

        let tasks = try modelContext.fetch(FetchDescriptor<Task>())
        let events = try modelContext.fetch(FetchDescriptor<CalendarEvent>())
        let templates = try modelContext.fetch(FetchDescriptor<TaskTemplate>())
        let reviews = try modelContext.fetch(FetchDescriptor<DailyReview>())
        SeedService.seedIfNeeded(
            context: modelContext,
            tasks: tasks,
            events: events,
            templates: templates,
            reviews: reviews,
            policy: policy
        )
    }

    private func seedEventHistoryFixturesIfNeeded() throws {
#if DEBUG
        guard PlanBaseDesktopLaunchEnvironment.usesEventHistoryFixtures else {
            return
        }
        let fixturePrefix = "UI 검증:"
        let existingTasks = try modelContext.fetch(FetchDescriptor<Task>())
        guard !existingTasks.contains(where: {
            $0.title.hasPrefix(fixturePrefix)
        }) else {
            return
        }

        let now = Date()
        let today = DayKey.startOfDay(for: now)
        let plannedDay = DayKey.addingDays(-2, to: today)
        let delayed = Task(
            title: "\(fixturePrefix) 지연 완료",
            plannedAt: plannedDay,
            order: 2_000
        )
        modelContext.insert(delayed)
        try TaskLifecycleService.applyStatus(
            .done,
            to: delayed,
            in: modelContext,
            now: now,
            completionDayKey: DayKey.key(for: today)
        )

        let sameDay = Task(
            title: "\(fixturePrefix) 같은 날 완료",
            plannedAt: today,
            order: 2_100
        )
        modelContext.insert(sameDay)
        try TaskLifecycleService.applyStatus(
            .done,
            to: sameDay,
            in: modelContext,
            now: now,
            completionDayKey: DayKey.key(for: today)
        )

        let baseUpdatedAt = now.addingTimeInterval(-600)
        let eventDrafts: [(String, Int, CalendarEventColor, String?)] = [
            ("공장", 3, .red, "설비 점검 메모"),
            ("공장 정기 점검", 2, .green, "정기 점검 메모"),
            ("공장", 1, .blue, nil),
            ("공장 야간", 4, .purple, "야간 작업 메모"),
            ("공장 출하", 5, .orange, "출하 메모")
        ]
        for (index, eventDraft) in eventDrafts.enumerated() {
            modelContext.insert(CalendarEvent(
                title: eventDraft.0,
                startAt: today,
                endAt: DayKey.addingDays(eventDraft.1 - 1, to: today),
                note: eventDraft.3,
                color: eventDraft.2.rawValue,
                createdAt: baseUpdatedAt,
                updatedAt: baseUpdatedAt.addingTimeInterval(Double(index))
            ))
        }

        let transientID = UUID()
        modelContext.insert(CalendarEvent(
            id: transientID,
            instanceID: UUID(
                uuidString: "00000000-0000-0000-0000-000000000001"
            )!,
            title: "공장 임시 중복",
            startAt: today,
            endAt: today,
            note: "이전 중복",
            color: CalendarEventColor.blue.rawValue,
            createdAt: baseUpdatedAt,
            updatedAt: baseUpdatedAt.addingTimeInterval(10)
        ))
        modelContext.insert(CalendarEvent(
            id: transientID,
            instanceID: UUID(
                uuidString: "00000000-0000-0000-0000-000000000002"
            )!,
            title: "공장 최신 중복",
            startAt: today,
            endAt: DayKey.addingDays(1, to: today),
            note: "최신 중복",
            color: CalendarEventColor.teal.rawValue,
            createdAt: baseUpdatedAt,
            updatedAt: baseUpdatedAt.addingTimeInterval(20)
        ))
#endif
    }

    private func archiveTasksIfNeeded(todayKey: String = DayKey.today) throws {
        let candidates = try modelContext.fetch(
            BoundedQueryService.tasksNeedingArchiveDescriptor(before: todayKey)
        )
        TaskRules.archiveIfNeeded(candidates, todayKey: todayKey)
    }

    private func refreshWidgetSnapshot(
        forceWrite: Bool,
        delay: Duration? = nil
    ) {
        let themeID = selectedThemeID
        Swift.Task { @MainActor in
            do {
                if let delay {
                    try await Swift.Task.sleep(for: delay)
                }
                _ = try await CalendarWidgetSnapshotPublicationService.publish(
                    context: modelContext,
                    themeID: themeID,
                    forceWrite: forceWrite,
                    forceTimelineReload: true
                )
            } catch {
                print(
                    "macOS 위젯 데이터 갱신 실패: " +
                        error.localizedDescription
                )
                if error as? CalendarWidgetSnapshotStore.StoreError
                    == .appGroupContainerUnavailable {
                    syncMonitor.recordIssue(
                        "위젯 일정 공유 권한을 사용할 수 없습니다. 앱 빌드 권한을 확인해 주세요."
                    )
                }
            }
        }
    }

    private func handleCloudKitEvent(_ notification: Notification) {
        guard let summary = CloudKitSyncService.summary(from: notification) else { return }
        syncMonitor.record(summary)
        activityImportCoordinator?.schedule(after: summary)

        let shouldRefreshWidget = CloudKitSyncService.shouldReconcile(after: summary)
        do {
            try CloudKitSyncService.reconcileIfNeeded(
                after: summary,
                context: modelContext
            )
            reconcileFocusSession()
        } catch {
            syncMonitor.recordReconciliationFailure(error)
        }
        if shouldRefreshWidget {
            // Imports can finish after startup published an empty local cache.
            refreshWidgetSnapshot(forceWrite: true, delay: .milliseconds(250))
        }
    }

    private func reconcileFocusSession() {
        do {
            _ = try FocusSessionService.reconcile(in: modelContext)
        } catch {
            syncMonitor.recordReconciliationFailure(error)
        }
    }

    private func prepareActivityImportCoordinatorIfNeeded() {
        guard activityImportCoordinator == nil else { return }
        activityImportCoordinator = TaskActivityImportCoordinator(
            context: modelContext,
            onFailure: { error in
                syncMonitor.recordReconciliationFailure(error)
            }
        )
    }

    private func persistArchiveIfNeeded() {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                try archiveTasksIfNeeded()
            }
        } catch {
            syncMonitor.recordStartupFailure(error)
        }
    }

    @MainActor
    private func handlePendingFocusNotificationRoutes() async {
        let routes = DesktopFocusNotificationRouteStore.shared.consumeAll()
        guard !routes.isEmpty else { return }

        for route in routes {
            if route.action == .open {
                openWindow(id: "focus-mode")
                continue
            }
            do {
                _ = try FocusNotificationActionService.perform(
                    action: route.action,
                    tokenID: route.tokenID,
                    sessionID: route.sessionID,
                    revision: route.revision,
                    phase: route.phase,
                    deadline: route.deadline,
                    in: modelContext
                )
                DesktopFocusNotificationScheduler.shared.removeDeliveredNotification(
                    identifier: route.requestIdentifier
                )
                await DesktopFocusNotificationScheduler.shared.reconcile()
                if route.action != .dismiss {
                    openWindow(id: "focus-mode")
                }
            } catch {
                if route.action != .dismiss {
                    openWindow(id: "focus-mode")
                }
            }
        }
    }

    private func refreshCurrentDay() {
        let nextDayKey = DayKey.today
        let targetDayKey = isFollowingToday ? nextDayKey : selectedBoardDayKey
        activeDayKey = nextDayKey
        selectedBoardDayKey = targetDayKey
        isFollowingToday = targetDayKey == nextDayKey
        if let reconstructedDate = DayKey.date(from: targetDayKey) {
            selectedBoardDate = reconstructedDate
        }
        persistArchiveIfNeeded()
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .board:
            BoardView(selectedDate: $selectedBoardDate)
        case .calendar:
            CalendarView(navigationDate: $calendarNavigationDate) { date in
                selectedBoardDate = date
                selectedTab = .board
            }
        case .archive:
            ArchiveView(state: archiveState) { date in
                selectedBoardDate = date
                selectedTab = .board
            }
        case .memo:
            MemoView()
        }
    }

    private func handleDeepLink(_ url: URL) {
        if let route = PlanBaseDeepLink.focusRoute(from: url) {
            if let sessionID = route.sessionID {
                guard let active = try? FocusSessionService.activeSnapshot(),
                      active.sessionID == sessionID else { return }
            }
            openWindow(id: "focus-mode")
            return
        }
        if let dayKey = PlanBaseDeepLink.calendarDayKey(from: url),
           let date = DayKey.date(from: dayKey) {
            calendarNavigationDate = date
            selectedTab = .calendar
            return
        }
        if let route = PlanBaseDeepLink.boardRoute(from: url),
           let date = DayKey.date(from: route.resolvedDayKey()) {
            selectedBoardDate = date
            selectedTab = .board
        }
    }
}
