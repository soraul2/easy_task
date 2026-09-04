#if os(iOS)
import Combine
import Foundation
import PlanBaseCore
import SwiftData
import SwiftUI

private enum MobileTab: String, CaseIterable, Identifiable {
    case board
    case calendar
    case archive
    case memo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: "칸반"
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

struct MobileAppRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: MobileTab = .board
    @State private var archiveState = ArchiveScreenState()
    @State private var selectedBoardDate = DayKey.startOfDay(for: Date())
    @State private var boardActionRequest: MobileBoardActionRequest?
    @State private var calendarNavigationDate: Date?
    @State private var activeDayKey = DayKey.today
    @State private var selectedBoardDayKey = DayKey.today
    @State private var isFollowingToday = true
    @State private var isWidgetSnapshotPublisherReady = false
    @State private var showingSyncStatus = false
    @State private var showingThemePicker = false
    @State private var showingFocusMode = false
    @State private var initialFocusTaskID: UUID?
    @State private var syncMonitor = CloudKitSyncMonitor()
    @State private var activityImportCoordinator: TaskActivityImportCoordinator?
    @State private var themePreferences = ThemePreferenceStore.shared
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID
    @AppStorage(MobileCloudKitSyncUI.showsWarningBannerKey)
    private var showsSyncWarningBanner = true

    private var cloudKitEnabled: Bool {
        PlanBaseContainerFactory.runtimeAppStoreMode.usesCloudKit
    }

    private var preferredThemeColorScheme: ColorScheme {
        AppThemePreset.preset(for: selectedThemeID).preferredColorScheme
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MobileBoardView(
                selectedDate: $selectedBoardDate,
                actionRequest: $boardActionRequest,
                onStartFocus: presentFocusMode,
                onShowTheme: { showingThemePicker = true }
            )
                .tabItem {
                    Image(systemName: MobileTab.board.symbol)
                        .accessibilityLabel(MobileTab.board.title)
                }
                .tag(MobileTab.board)

            MobileCalendarView(
                navigationDate: $calendarNavigationDate,
                onOpenBoardDate: { date in
                    selectedBoardDate = date
                    selectedTab = .board
                },
                onShowTheme: { showingThemePicker = true }
            )
            .tabItem {
                Image(systemName: MobileTab.calendar.symbol)
                    .accessibilityLabel(MobileTab.calendar.title)
            }
            .tag(MobileTab.calendar)

            MobileArchiveView(
                state: archiveState,
                onOpenBoardDate: { date in
                    selectedBoardDate = date
                    selectedTab = .board
                },
                onShowTheme: { showingThemePicker = true }
            )
            .tabItem {
                Image(systemName: MobileTab.archive.symbol)
                    .accessibilityLabel(MobileTab.archive.title)
            }
            .tag(MobileTab.archive)

            MobileMemoView(onShowTheme: { showingThemePicker = true })
                .tabItem {
                    Image(systemName: MobileTab.memo.symbol)
                        .accessibilityLabel(MobileTab.memo.title)
                }
                .tag(MobileTab.memo)
        }
        .tint(AppTheme.accent)
        .background(AppTheme.background)
        .background {
            if isWidgetSnapshotPublisherReady {
                CalendarWidgetSnapshotPublisher()
            }
        }
        .toolbarBackground(AppTheme.floatingBar, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .overlay(alignment: .bottomTrailing) {
            FocusModeLauncher {
                initialFocusTaskID = nil
                showingFocusMode = true
            }
            .padding(.trailing, 16)
            .padding(.bottom, 72)
        }
        .preferredColorScheme(preferredThemeColorScheme)
        .environment(syncMonitor)
        .task {
            start()
            if cloudKitEnabled {
                await syncMonitor.refreshAccountStatus()
            }
            await TaskNotificationScheduler.shared.reconcile(context: modelContext)
            await FocusNotificationScheduler.shared.reconcile()
            await TaskLiveActivityCoordinator.shared.reconcile(context: modelContext)
            handlePendingNotificationRoute()
            await handlePendingFocusNotificationRoutes()
        }
        .onChange(of: selectedTab) {
            persistArchiveIfNeeded()
        }
        .onChange(of: selectedBoardDate) { _, newDate in
            selectedBoardDayKey = DayKey.key(for: newDate)
            isFollowingToday = selectedBoardDayKey == activeDayKey
        }
        .onChange(of: selectedThemeID) {
            AppTheme.activate(selectedThemeID, colorScheme: colorScheme)
            refreshWidgetSnapshot(forceWrite: true)
            Swift.Task {
                await TaskLiveActivityCoordinator.shared.reconcile(context: modelContext)
            }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            let syncedThemeID = themePreferences.refreshFromCloud()
            if syncedThemeID != selectedThemeID {
                selectedThemeID = syncedThemeID
            }
            refreshCurrentDay()
            refreshWidgetSnapshot(forceWrite: true)
            Swift.Task {
                if cloudKitEnabled {
                    await syncMonitor.refreshAccountStatus()
                }
                await TaskNotificationScheduler.shared.reconcile(context: modelContext)
                await FocusNotificationScheduler.shared.reconcile()
                await TaskLiveActivityCoordinator.shared.reconcile(context: modelContext)
                handlePendingNotificationRoute()
                await handlePendingFocusNotificationRoutes()
            }
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
            reconcileLiveActivity()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refreshCurrentDay()
            reconcileTaskNotifications()
            reconcileLiveActivity()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { _ in
            reconcileTaskNotifications()
            reconcileLiveActivity()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: FocusActiveSessionStore.didChangeNotification
        )) { _ in
            Swift.Task {
                if await TaskNotificationScheduler.shared.authorizationState() == .notDetermined {
                    _ = await TaskNotificationScheduler.shared.requestAuthorization()
                }
                await FocusNotificationScheduler.shared.reconcile()
            }
            reconcileLiveActivity()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: FocusNotificationRouteStore.didReceiveRoute
        )) { _ in
            Swift.Task {
                await handlePendingFocusNotificationRoutes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: TaskNotificationRouteStore.didReceiveRoute
        )) { _ in
            handlePendingNotificationRoute()
        }
        .onOpenURL(perform: handleDeepLink)
        .safeAreaInset(edge: .top, spacing: 0) {
            if cloudKitEnabled,
               showsSyncWarningBanner,
               let errorDescription = syncMonitor.lastErrorDescription {
                HStack(spacing: 4) {
                    Button {
                        showingSyncStatus = true
                    } label: {
                        Label(errorDescription, systemImage: "exclamationmark.icloud")
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .padding(.leading, 14)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("iCloud 상태 상세 보기")

                    Button {
                        showsSyncWarningBanner = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("iCloud 경고 배너 숨기기")
                }
                .foregroundStyle(AppTheme.primaryText)
                .background(AppTheme.input)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.border).frame(height: 1)
                }
            }
        }
        .sheet(isPresented: $showingSyncStatus) {
            MobileCloudKitSyncStatusSheet(monitor: syncMonitor)
        }
        .sheet(isPresented: $showingThemePicker) {
            MobileThemePickerSheet(selectedThemeID: $selectedThemeID)
        }
        .fullScreenCover(
            isPresented: $showingFocusMode,
            onDismiss: { initialFocusTaskID = nil }
        ) {
            FocusModeView(initialTaskID: initialFocusTaskID)
        }
    }

    private func presentFocusMode(taskID: UUID) {
        initialFocusTaskID = taskID
        showingFocusMode = true
    }

    private func start() {
        prepareActivityImportCoordinatorIfNeeded()
        defer {
            // Widget publication is best-effort and must not remain disabled when
            // an unrelated startup reconciliation or migration fails.
            isWidgetSnapshotPublisherReady = true
            refreshWidgetSnapshot(forceWrite: true)
        }
        let migratedThemeID = AppTheme.migrateStoredDefaultIfNeeded(selectedThemeID)
        if migratedThemeID != selectedThemeID {
            selectedThemeID = migratedThemeID
        }
        var syncedThemeID = themePreferences.start(
            syncsWithICloud: themePreferenceCloudSyncEnabled
        )
#if DEBUG
        if let themeFixtureID = PlanBaseLaunchEnvironment.themeFixtureID {
            syncedThemeID = themeFixtureID
            themePreferences.setSelectedThemeID(syncedThemeID)
        }
#endif
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
            let migration = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
                context: modelContext,
                appSupportFolder: MobileImageStorage.appSupportFolder
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
                try seedLiveActivityDurationFixtureIfNeeded()
                try seedDemoDataIfNeeded()
                try seedReminderCompletionFixturesIfNeeded()
                try seedEventHistoryFixturesIfNeeded()
                try archiveTasksIfNeeded()
            }
        } catch {
            syncMonitor.recordStartupFailure(error)
        }
    }

    private var themePreferenceCloudSyncEnabled: Bool {
#if DEBUG
        !PlanBaseLaunchEnvironment.isUITesting
#else
        true
#endif
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
                    "앱 활성화 위젯 데이터 갱신 실패: " +
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

    private func seedDemoDataIfNeeded() throws {
#if DEBUG
        if PlanBaseLaunchEnvironment.isUITesting,
           ProcessInfo.processInfo.arguments.contains("--ui-testing-daily-activity-fixtures") {
            try DailyActivityPreviewFixtures.seed(in: modelContext)
            return
        }
#endif
        guard !PlanBaseLaunchEnvironment.usesEmptyBoardFixture else { return }
        let policy = SeedPolicy.appStartup(
            cloudKitEnabled: cloudKitEnabled &&
                !PlanBaseLaunchEnvironment.isUITesting
        )
        guard case .demo = policy else { return }

        let tasks = try modelContext.fetch(FetchDescriptor<TodoTask>())
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

    private func seedLiveActivityDurationFixtureIfNeeded() throws {
#if DEBUG
        guard PlanBaseLaunchEnvironment.usesLiveActivityDurationFixture
                || PlanBaseLaunchEnvironment.usesLiveActivityTwoDoingFixture else { return }
        let fixtureTitle = "Live Activity 7시간 숫자 타이머 검증"
        let existing = try modelContext.fetch(FetchDescriptor<TodoTask>())
        guard !existing.contains(where: { $0.title == fixtureTitle }) else { return }

        let now = Date()
        let task = TodoTask(
            title: fixtureTitle,
            plannedAt: DayKey.startOfDay(for: now),
            order: 100
        )
        modelContext.insert(task)
        let nextTask = TodoTask(
            title: "다음 작업 전환 검증",
            plannedAt: DayKey.startOfDay(for: now),
            order: 200
        )
        modelContext.insert(nextTask)
        try TaskLifecycleService.applyStatus(
            .doing,
            to: task,
            in: modelContext,
            now: now.addingTimeInterval(-26_494)
        )
        if PlanBaseLaunchEnvironment.usesLiveActivityTwoDoingFixture {
            try TaskLifecycleService.applyStatus(
                .doing,
                to: nextTask,
                in: modelContext,
                now: now.addingTimeInterval(-1_234)
            )
        }
#endif
    }

    private func seedReminderCompletionFixturesIfNeeded() throws {
#if DEBUG
        guard PlanBaseLaunchEnvironment.usesReminderCompletionFixtures else { return }
        let fixturePrefix = "알림 완료 테스트:"
        let existing = try modelContext.fetch(FetchDescriptor<TodoTask>())
        guard !existing.contains(where: { $0.title.hasPrefix(fixturePrefix) }) else { return }

        let now = Date()
        let today = DayKey.startOfDay(for: now)
        let yesterday = DayKey.addingDays(-1, to: today)
        let pastReminder = TaskReminderRules.normalizedDate(
            now.addingTimeInterval(-3_600)
        )
        let futureReminder = TaskReminderRules.normalizedDate(
            now.addingTimeInterval(3_600)
        )

        modelContext.insert(TodoTask(
            title: "\(fixturePrefix) 알림 없음",
            status: .todo,
            plannedAt: today,
            order: 900
        ))
        modelContext.insert(TodoTask(
            title: "\(fixturePrefix) 지난 알림",
            status: .todo,
            plannedAt: today,
            order: 1_000,
            reminderAt: pastReminder
        ))
        modelContext.insert(TodoTask(
            title: "\(fixturePrefix) 미래 알림",
            status: .todo,
            plannedAt: today,
            order: 1_100,
            reminderAt: futureReminder
        ))
        modelContext.insert(TodoTask(
            title: "\(fixturePrefix) 이월 미래 알림",
            status: .doing,
            plannedAt: yesterday,
            order: 1_200,
            reminderAt: futureReminder
        ))
#endif
    }

    private func seedEventHistoryFixturesIfNeeded() throws {
#if DEBUG
        guard PlanBaseLaunchEnvironment.usesEventHistoryFixtures else { return }
        let fixturePrefix = "UI 검증:"
        let existingTasks = try modelContext.fetch(FetchDescriptor<TodoTask>())
        guard !existingTasks.contains(where: {
            $0.title.hasPrefix(fixturePrefix)
        }) else {
            return
        }

        let now = Date()
        let today = DayKey.startOfDay(for: now)
        let plannedDay = DayKey.addingDays(-2, to: today)
        let delayed = TodoTask(
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

        let sameDay = TodoTask(
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
        } catch {
            syncMonitor.recordReconciliationFailure(error)
        }
        if shouldRefreshWidget {
            // Imports can finish after startup published an empty local cache.
            // Republish even if reconciliation failed so imported events appear.
            refreshWidgetSnapshot(forceWrite: true, delay: .milliseconds(250))
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

    private func reconcileTaskNotifications() {
        Swift.Task {
            await TaskNotificationScheduler.shared.reconcile(context: modelContext)
        }
    }

    private func reconcileLiveActivity() {
        Swift.Task {
            await TaskLiveActivityCoordinator.shared.reconcile(context: modelContext)
        }
    }

    private func handlePendingNotificationRoute() {
        guard let route = TaskNotificationRouteStore.shared.consume() else { return }
        let currentTask = try? modelContext.fetch(
            BoundedQueryService.taskDescriptor(id: route.taskID)
        ).first
        let dayKey = currentTask?.plannedDayKey ?? route.fallbackDayKey
        guard let dayKey, let date = DayKey.date(from: dayKey) else { return }
        selectedBoardDate = date
        selectedTab = .board
    }

    @MainActor
    private func handlePendingFocusNotificationRoutes() async {
        let routes = FocusNotificationRouteStore.shared.consumeAll()
        guard !routes.isEmpty else { return }

        for route in routes {
            if route.action == .open {
                initialFocusTaskID = nil
                showingFocusMode = true
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
                FocusNotificationScheduler.shared.removeDeliveredNotification(
                    identifier: route.requestIdentifier
                )
                await FocusNotificationScheduler.shared.reconcile()
                await TaskLiveActivityCoordinator.shared.reconcile(context: modelContext)
                if route.action != .dismiss, scenePhase == .active {
                    initialFocusTaskID = nil
                    showingFocusMode = true
                }
            } catch {
                if route.action != .dismiss, scenePhase == .active {
                    initialFocusTaskID = nil
                    showingFocusMode = true
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        if let route = PlanBaseDeepLink.focusRoute(from: url) {
            if let sessionID = route.sessionID {
                guard let active = try? FocusSessionService.activeSnapshot(),
                      active.sessionID == sessionID else { return }
            }
            initialFocusTaskID = nil
            showingFocusMode = true
            return
        }
        if let route = PlanBaseDeepLink.calendarRoute(from: url),
           let date = DayKey.date(from: route.resolvedDayKey()) {
            calendarNavigationDate = date
            selectedTab = .calendar
            return
        }
        if let route = PlanBaseDeepLink.boardNavigationRoute(from: url),
           let date = DayKey.date(from: route.destination.resolvedDayKey()) {
            selectedBoardDate = date
            selectedTab = .board
            if let action = route.action {
                boardActionRequest = MobileBoardActionRequest(action: action)
            }
        }
    }
}
#endif
