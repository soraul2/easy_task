#if os(iOS)
import Combine
import EasyTaskCore
import Foundation
import SwiftData
import SwiftUI

@main
struct EasyTaskiOSApp: App {
    @State private var persistenceState: PersistenceState

    init() {
        _persistenceState = State(initialValue: Self.makePersistenceState())
    }

    var body: some Scene {
        WindowGroup {
            switch persistenceState {
            case .ready(let modelContainer):
                MobileAppRootView()
                    .modelContainer(modelContainer)
            case .failed(let details):
                PersistenceRecoveryView(details: details) {
                    persistenceState = Self.makePersistenceState()
                }
            }
        }
    }

    private static func makePersistenceState() -> PersistenceState {
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
            return .ready(try EasyTaskContainerFactory.makeAppPersistent())
        } catch {
            print("EasyTask 저장소를 열 수 없습니다: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }
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
    @State private var themeRevision = 0
    @State private var activeDayKey = DayKey.today
    @State private var selectedBoardDayKey = DayKey.today
    @State private var isFollowingToday = true
    @State private var showingSyncStatus = false
    @State private var syncMonitor = CloudKitSyncMonitor()
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID

    var body: some View {
        TabView(selection: $selectedTab) {
            MobileBoardView(selectedDate: $selectedBoardDate)
                .tabItem {
                    Image(systemName: MobileTab.board.symbol)
                        .accessibilityLabel(MobileTab.board.title)
                }
                .tag(MobileTab.board)

            MobileCalendarView { date in
                selectedBoardDate = date
                selectedTab = .board
            }
            .tabItem {
                Image(systemName: MobileTab.calendar.symbol)
                    .accessibilityLabel(MobileTab.calendar.title)
            }
            .tag(MobileTab.calendar)

            MobileArchiveView { date in
                selectedBoardDate = date
                selectedTab = .board
            }
            .tabItem {
                Image(systemName: MobileTab.archive.symbol)
                    .accessibilityLabel(MobileTab.archive.title)
            }
            .tag(MobileTab.archive)
        }
        .tint(AppTheme.event)
        .background(AppTheme.background)
        .environment(syncMonitor)
        .id("\(selectedThemeID)-\(colorScheme)-\(themeRevision)")
        .task {
            start()
#if DEBUG
            _ = await CloudKitConvergenceProbe.runIfRequested(
                context: modelContext
            )
#endif
            await syncMonitor.refreshAccountStatus()
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
            Swift.Task { await syncMonitor.refreshAccountStatus() }
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
        }
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
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID

    var body: some View {
        NavigationStack {
            List(AppThemePreset.all) { preset in
                Button {
                    AppTheme.activate(preset.id, colorScheme: colorScheme)
                    selectedThemeID = preset.id
                } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: 0) {
                            ForEach(Array(preset.sourceColors.prefix(4).enumerated()), id: \.offset) { _, color in
                                color.frame(width: 28, height: 28)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text(preset.name)
                            .foregroundStyle(AppTheme.primaryText)

                        Spacer()

                        if selectedThemeID == preset.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.event)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.name) 테마")
                .accessibilityValue(selectedThemeID == preset.id ? "선택됨" : "")
            }
            .scrollContentBackground(.hidden)
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
