#if os(iOS)
import Combine
import EasyTaskCore
import Foundation
import SwiftData
import SwiftUI

enum EasyTaskLaunchEnvironment {
    static var isUITesting: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
#else
        false
#endif
    }
}

@main
struct EasyTaskiOSApp: App {
    @UIApplicationDelegateAdaptor(EasyTaskAppDelegate.self) private var appDelegate
    @State private var persistenceState: PersistenceState

    init() {
        _persistenceState = State(initialValue: Self.makePersistenceState())
    }

    var body: some Scene {
        WindowGroup {
            switch persistenceState {
            case .ready(let modelContainer):
                Group {
#if DEBUG
                    if Self.isCloudKitProbeRequested {
                        Color.clear
                    } else {
                        MobileAppRootView()
                    }
#else
                    MobileAppRootView()
#endif
                }
                .modelContainer(modelContainer)
            case .failed(let details):
                PersistenceRecoveryView(details: details) {
                    persistenceState = Self.makePersistenceState()
                }
            }
        }
    }

    private static func makePersistenceState() -> PersistenceState {
#if DEBUG
        if EasyTaskLaunchEnvironment.isUITesting {
            do {
                return .ready(try EasyTaskContainerFactory.makeInMemory())
            } catch {
                return .failed(error.localizedDescription)
            }
        }
#endif

        if let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            try? FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
        }

        do {
#if DEBUG
            _ = try EasyTaskContainerFactory.initializeDevelopmentCloudKitSchemaIfRequested()
#endif
            let modelContainer = try EasyTaskContainerFactory.makeAppPersistent()
#if DEBUG
            startCloudKitProbeIfRequested(modelContainer: modelContainer)
#endif
            return .ready(modelContainer)
        } catch {
            print("EasyTask 저장소를 열 수 없습니다: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

#if DEBUG
    private static var isCloudKitProbeRequested: Bool {
        CloudKitConvergenceProbe.isProbeInvocation(
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    private static func startCloudKitProbeIfRequested(modelContainer: ModelContainer) {
        guard isCloudKitProbeRequested else { return }

        Swift.Task { @MainActor in
            _ = await CloudKitConvergenceProbe.runIfRequested(
                context: modelContainer.mainContext
            )
        }
    }
#endif
}

private enum PersistenceState {
    case ready(ModelContainer)
    case failed(String)
}

private struct PersistenceRecoveryView: View {
    let details: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("저장소를 열 수 없습니다")
                    .font(.title2.bold())

                Text("사용자 데이터를 삭제하거나 다른 저장소로 대체하지 않았습니다.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            Button(action: retry) {
                Label("다시 시도", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum MobileTab: String, CaseIterable, Identifiable {
    case board
    case calendar
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: "칸반"
        case .calendar: "캘린더"
        case .archive: "기록"
        }
    }

    var symbol: String {
        switch self {
        case .board: "rectangle.3.group"
        case .calendar: "calendar"
        case .archive: "book.pages"
        }
    }
}

private struct MobileAppRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: MobileTab = .board
    @State private var selectedBoardDate = DayKey.startOfDay(for: Date())
    @State private var calendarNavigationDate: Date?
    @State private var themeRevision = 0
    @State private var activeDayKey = DayKey.today
    @State private var selectedBoardDayKey = DayKey.today
    @State private var isFollowingToday = true
    @State private var showingSyncStatus = false
    @State private var showingThemePicker = false
    @State private var syncMonitor = CloudKitSyncMonitor()
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID

    var body: some View {
        TabView(selection: $selectedTab) {
            MobileBoardView(
                selectedDate: $selectedBoardDate,
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
        }
        .tint(AppTheme.event)
        .background(AppTheme.background)
        .background {
            CalendarWidgetSnapshotPublisher()
        }
        .toolbarBackground(AppTheme.floatingBar, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environment(syncMonitor)
        .id("\(selectedThemeID)-\(colorScheme)-\(themeRevision)")
        .task {
            start()
            await syncMonitor.refreshAccountStatus()
            await TaskNotificationScheduler.shared.reconcile(context: modelContext)
            handlePendingNotificationRoute()
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
            themeRevision += 1
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            refreshCurrentDay()
            Swift.Task {
                await syncMonitor.refreshAccountStatus()
                await TaskNotificationScheduler.shared.reconcile(context: modelContext)
                handlePendingNotificationRoute()
            }
        }
        .onChange(of: colorScheme) {
            AppTheme.activate(selectedThemeID, colorScheme: colorScheme)
            themeRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(
            for: CloudKitSyncService.eventChangedNotification
        )) { notification in
            handleCloudKitEvent(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshCurrentDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refreshCurrentDay()
            reconcileTaskNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { _ in
            reconcileTaskNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: TaskNotificationRouteStore.didReceiveRoute
        )) { _ in
            handlePendingNotificationRoute()
        }
        .onOpenURL(perform: handleDeepLink)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let errorDescription = syncMonitor.lastErrorDescription {
                Button {
                    showingSyncStatus = true
                } label: {
                    Label(errorDescription, systemImage: "exclamationmark.icloud")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.primaryText)
                .background(AppTheme.input)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.border).frame(height: 1)
                }
                .accessibilityHint("iCloud 상태 상세 보기")
            }
        }
        .sheet(isPresented: $showingSyncStatus) {
            MobileCloudKitSyncStatusSheet(monitor: syncMonitor)
        }
        .sheet(isPresented: $showingThemePicker) {
            MobileThemePickerSheet(selectedThemeID: $selectedThemeID)
        }
    }

    private func start() {
        let migratedThemeID = AppTheme.migrateStoredDefaultIfNeeded(selectedThemeID)
        if migratedThemeID != selectedThemeID {
            selectedThemeID = migratedThemeID
        }
        AppTheme.activate(migratedThemeID, colorScheme: colorScheme)
        themeRevision += 1
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
                try seedDemoDataIfNeeded()
                try archiveTasksIfNeeded()
            }
        } catch {
            syncMonitor.recordStartupFailure(error)
        }
    }

    private func seedDemoDataIfNeeded() throws {
        let policy = SeedPolicy.appStartup(
            cloudKitEnabled: EasyTaskContainerFactory.appStoreMode.usesCloudKit
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

    private func archiveTasksIfNeeded(todayKey: String = DayKey.today) throws {
        let candidates = try modelContext.fetch(
            BoundedQueryService.tasksNeedingArchiveDescriptor(before: todayKey)
        )
        TaskRules.archiveIfNeeded(candidates, todayKey: todayKey)
    }

    private func handleCloudKitEvent(_ notification: Notification) {
        guard let summary = CloudKitSyncService.summary(from: notification) else { return }
        syncMonitor.record(summary)

        do {
            try CloudKitSyncService.reconcileIfNeeded(
                after: summary,
                context: modelContext
            )
        } catch {
            syncMonitor.recordReconciliationFailure(error)
        }
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

    private func handleDeepLink(_ url: URL) {
        guard let dayKey = EasyTaskDeepLink.calendarDayKey(from: url),
              let date = DayKey.date(from: dayKey) else {
            return
        }
        calendarNavigationDate = date
        selectedTab = .calendar
    }
}

struct MobileCloudKitSyncStatusButton: View {
    @Environment(CloudKitSyncMonitor.self) private var monitor
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: monitor.systemImage)
        }
        .accessibilityLabel(monitor.title)
        .sheet(isPresented: $isPresented) {
            MobileCloudKitSyncStatusSheet(monitor: monitor)
        }
    }
}

private struct MobileCloudKitSyncStatusSheet: View {
    let monitor: CloudKitSyncMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("상태") {
                    Label(monitor.title, systemImage: monitor.systemImage)
                    if let lastSuccessfulSyncAt = monitor.lastSuccessfulSyncAt {
                        LabeledContent(
                            "마지막 성공",
                            value: lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    } else {
                        LabeledContent("마지막 성공", value: "확인 전")
                    }
                }

                if let errorDescription = monitor.lastErrorDescription {
                    Section("확인 필요") {
                        Text(errorDescription)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Swift.Task { await monitor.refreshAccountStatus() }
                    } label: {
                        Label("계정 상태 다시 확인", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("iCloud 동기화")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct MobileThemePickerSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedThemeID: String

    private let columns = [
        GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AppThemePreset.all) { preset in
                        MobileThemePresetCard(
                            preset: preset,
                            appearance: AppThemeAppearance(colorScheme: colorScheme),
                            isSelected: selectedThemeID == preset.id
                        ) {
                            AppTheme.activate(preset.id, colorScheme: colorScheme)
                            selectedThemeID = preset.id
                        }
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle("테마")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
    }
}

private struct MobileThemePresetCard: View {
    var preset: AppThemePreset
    var appearance: AppThemeAppearance
    var isSelected: Bool
    var action: () -> Void

    private var colors: AppThemeColorSet {
        preset.colorSet(for: appearance)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(preset.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(colors.primaryText.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? colors.event.color : colors.secondaryText.color)
                }

                HStack(spacing: 0) {
                    ForEach(Array(preset.sourceColors.prefix(4).enumerated()), id: \.offset) { _, color in
                        color.frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                HStack(spacing: 6) {
                    themeSample(color: colors.todo.color, symbol: "circle")
                    themeSample(color: colors.doing.color, symbol: "arrow.right")
                    themeSample(color: colors.done.color, symbol: "checkmark")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .background(colors.panel.color, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? colors.event.color : colors.border.color,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name) 테마")
        .accessibilityValue(isSelected ? "선택됨" : "")
    }

    private func themeSample(color: Color, symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(colors.cardText.color)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 6))
    }
}
#else
@main
struct EasyTaskiOSPlaceholder {
    static func main() {
        print("EasyTaskiOS builds only for iOS.")
    }
}
#endif
