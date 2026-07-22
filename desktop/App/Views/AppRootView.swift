import Combine
import Foundation
import SwiftData
import SwiftUI
import EasyTaskCore

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

    @State private var selectedTab: AppTab = .board
    @State private var selectedBoardDate = DayKey.startOfDay(for: Date())
    @State private var themeRevision = 0
    @State private var activeDayKey = DayKey.today
    @State private var selectedBoardDayKey = DayKey.today
    @State private var isFollowingToday = true
    @State private var syncMonitor = CloudKitSyncMonitor()
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID

    private var cloudKitEnabled: Bool {
        EasyTaskContainerFactory.runtimeAppStoreMode.usesCloudKit
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: bottomContentInset)
                }
                .id("\(selectedThemeID)-\(colorScheme)-\(themeRevision)")

            HStack(spacing: 14) {
                FloatingTabBar(selectedTab: $selectedTab)
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
            refreshCurrentDay()
            if cloudKitEnabled {
                Swift.Task { await syncMonitor.refreshAccountStatus() }
            }
        }
        .onChange(of: selectedThemeID) {
            AppTheme.activate(selectedThemeID, colorScheme: colorScheme)
            themeRevision += 1
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
    }

    private var bottomContentInset: CGFloat {
        selectedTab == .calendar ? 0 : 92
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
                appSupportFolder: "TodoDesktopMVP"
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
            cloudKitEnabled: cloudKitEnabled
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

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .board:
            BoardView(selectedDate: $selectedBoardDate)
        case .calendar:
            CalendarView()
        case .archive:
            ArchiveView { date in
                selectedBoardDate = date
                selectedTab = .board
            }
        case .memo:
            MemoView()
        }
    }
}

struct CloudKitSyncStatusButton: View {
    let monitor: CloudKitSyncMonitor
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: monitor.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 54, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(monitor.lastErrorDescription == nil ? AppTheme.primaryText : Color.red)
        .padding(8)
        .background(AppTheme.floatingBar, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
        .help(monitor.title)
        .accessibilityLabel(monitor.title)
        .sheet(isPresented: $isPresented) {
            CloudKitSyncStatusSheet(monitor: monitor)
        }
    }
}

private struct CloudKitSyncStatusSheet: View {
    let monitor: CloudKitSyncMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("iCloud 동기화")
                    .font(.title2.weight(.bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("닫기")
            }

            Label(monitor.title, systemImage: monitor.systemImage)
                .font(.headline)

            LabeledContent("계정", value: monitor.accountAvailability.title)
            if let lastSuccessfulSyncAt = monitor.lastSuccessfulSyncAt {
                LabeledContent(
                    "마지막 성공",
                    value: lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened)
                )
            } else {
                LabeledContent("마지막 성공", value: "확인 전")
            }

            if let advisoryDescription = monitor.syncAdvisoryDescription {
                Text(advisoryDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
            }

            if let errorDescription = monitor.lastErrorDescription {
                Text(errorDescription)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button {
                    Swift.Task { await monitor.refreshAccountStatus() }
                } label: {
                    Label("계정 상태 다시 확인", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(AppTheme.panel)
        .foregroundStyle(AppTheme.primaryText)
    }
}

struct ThemeSelectorButton: View {
    @Binding var selectedThemeID: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 54, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.primaryText)
        .padding(8)
        .background(AppTheme.floatingBar, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
        .help("테마 선택")
        .accessibilityLabel("테마 선택")
        .sheet(isPresented: $isPresented) {
            ThemePickerSheet(selectedThemeID: $selectedThemeID)
        }
    }
}

struct ThemePickerSheet: View {
    @Binding var selectedThemeID: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 240), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("테마")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("화면 모드에 맞춘 기본 테마와 색감 중심의 소프트 대비 테마를 제공합니다.")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.secondaryText)
            }

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(AppThemePreset.all) { preset in
                        ThemePresetCard(
                            preset: preset,
                            isSelected: selectedThemeID == preset.id
                        ) {
                            AppTheme.activate(preset.id, colorScheme: colorScheme)
                            selectedThemeID = preset.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(22)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 480, idealHeight: 560)
        .background(AppTheme.panel)
    }
}

struct ThemePresetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    var preset: AppThemePreset
    var isSelected: Bool
    var onSelect: () -> Void

    private var colors: AppThemeColorSet {
        preset.colorSet(for: AppThemeAppearance(colorScheme: colorScheme))
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(preset.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(Array(preset.sourceColors.enumerated()), id: \.offset) { _, color in
                        color
                    }
                }
                .frame(height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.todo.color)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.doing.color)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.done.color)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.event.color)
                }
                .frame(height: 34)

                HStack(spacing: 6) {
                    Text("Aa")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(colors.primaryText.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(colors.panel.color, in: Capsule())
                    Text(preset.targetsWCAGTextContrast ? "WCAG 4.5:1" : "소프트 대비")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                }
            }
            .padding(12)
            .background(
                isSelected ? AppTheme.selectedTab.opacity(0.30) : AppTheme.input,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppTheme.primaryText.opacity(0.55) : AppTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 54, height: 44)
                        .background(tab == selectedTab ? AppTheme.selectedTab : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tab == selectedTab ? AppTheme.primaryText : AppTheme.secondaryText)
                .keyboardShortcut(shortcut(for: tab), modifiers: .command)
                .help(tab.title)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(8)
        .background(AppTheme.floatingBar, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
    }

    private func shortcut(for tab: AppTab) -> KeyEquivalent {
        switch tab {
        case .board: "1"
        case .calendar: "2"
        case .archive: "3"
        case .memo: "4"
        }
    }
}
