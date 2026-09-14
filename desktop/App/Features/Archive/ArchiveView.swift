import AppKit
import Combine
import PlanBaseCore
import SwiftData
import SwiftUI

struct ArchiveView: View {
    @Bindable var state: ArchiveScreenState
    var onOpenBoardDate: (Date) -> Void

    @State private var selectedDay: ArchiveDaySelection?
    @State private var selectedTask: TaskRecordSelection?
    @State private var selectedReviewDay: ArchiveDaySelection?
    @State private var isVisible = false
    @AppStorage("planbase.archiveShowsOverview") private var showsOverview = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var message: String?
    @State private var showingFilter = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let attachmentIndex = DiaryAttachmentIndex(
            attachments: state.querySession?.attachments ?? [],
            blocks: state.querySession?.blocks ?? []
        )
        let archiveGroups = state.querySession?.records ?? []

        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 12)

            ArchiveSearchToolbar(
                text: $state.filter.searchText,
                period: $state.filter.period,
                scope: $state.filter.scope,
                contentMode: $state.filter.contentMode,
                dateBasis: $state.filter.dateBasis,
                startDate: $state.filter.customStartDate,
                endDate: $state.filter.customEndDate,
                showingFilter: $showingFilter,
                searchFocused: $searchFocused
            )
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 28)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let activitySession = state.activitySession {
                        ArchiveActivityOverview(
                            session: activitySession,
                            isExpanded: $showsOverview,
                            selectedDayKey: $state.selectedActivityDayKey,
                            onOpenDay: openDay
                        )
                    }

                    if let message {
                        ArchiveMessageView(message: message)
                    }

                    if state.querySession?.isLoading == true && archiveGroups.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            ArchiveSkeletonCard()
                        }
                    } else if archiveGroups.isEmpty && state.querySession?.errorMessage == nil {
                        emptyState
                    } else {
                        ForEach(archiveGroups) { group in
                            ArchiveDayGroupView(
                                group: group,
                                dateBasis: state.filter.dateBasis,
                                attachments: group.review.map {
                                    attachmentIndex.activeAttachments(for: $0.id)
                                } ?? [],
                                legacyFileNames: group.review.map {
                                    attachmentIndex.unresolvedLegacyImageFileNames(for: $0)
                                } ?? [],
                                onOpenDay: { openDay(group.dayKey) },
                                onOpenTask: { id in
                                    selectedTask = TaskRecordSelection(taskID: id, dayKey: group.dayKey)
                                },
                                onEditReview: {
                                    if let date = DayKey.date(from: group.dayKey) {
                                        selectedReviewDay = ArchiveDaySelection(date: date)
                                    }
                                },
                                isTaskListExpanded: expandedBinding(for: group.dayKey, reviews: false),
                                reviewExpanded: expandedBinding(for: group.dayKey, reviews: true)
                            )
                        }

                        if state.querySession?.hasMore == true {
                            Button {
                                state.querySession?.loadNextPage()
                            } label: {
                                if state.querySession?.isLoading == true {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("이전 기록 더 보기", systemImage: "chevron.down")
                                }
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(state.querySession?.isLoading == true)
                        }
                    }

                    if let errorMessage = state.querySession?.errorMessage {
                        VStack(spacing: 8) {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(AppTheme.secondaryText)
                            Button("다시 시도") {
                                state.querySession?.retry()
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .scrollTargetLayout()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            .scrollPosition(id: $state.scrollDayKey, anchor: .top)
        }
        .task {
            isVisible = true
            if state.querySession == nil {
                state.querySession = ArchiveQuerySession(context: modelContext)
                state.activitySession = ActivityOverviewSession(context: modelContext)
                state.querySession?.apply(state.filter, debounceSearch: false)
                if uiTestingShowsActivity {
                    showsOverview = true
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-archive-collapsed") {
                    showsOverview = false
                }
            } else {
                state.querySession?.refreshPreservingDepth()
            }
            refreshOverview()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, isVisible {
                state.querySession?.refreshPreservingDepth()
                refreshOverview()
            } else if phase != .active {
                state.querySession?.cancel()
                state.activitySession?.cancel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            guard isVisible else { return }
            state.querySession?.refreshPreservingDepth()
            refreshOverview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            guard isVisible else { return }
            state.querySession?.refreshPreservingDepth()
            refreshOverview()
        }
        .onChange(of: state.filter) { oldFilter, newFilter in
            state.querySession?.apply(
                newFilter,
                debounceSearch: shouldDebounceSearch(
                    from: oldFilter,
                    to: newFilter
                )
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: PersistenceCommandService.dataChangedNotification
            )
        ) { notification in
            guard PersistenceCommandService.affects([.tasks, .reviews], in: notification) else { return }
            guard isVisible, scenePhase == .active,
                let sourceContext = notification.object as? ModelContext,
                sourceContext === modelContext
            else { return }
            state.querySession?.refreshPreservingDepth()
        }
        .sheet(item: $selectedDay) { selection in
            ArchiveSingleDaySheet(
                date: selection.date,
                session: state.querySession?.makeDaySession() ?? ArchiveQuerySession(context: modelContext),
                onOpenBoardDate: onOpenBoardDate)
        }
        .sheet(item: $selectedTask) { selection in
            TaskRecordSheet(selection: selection)
        }
        .sheet(
            item: $selectedReviewDay,
            onDismiss: {
                state.querySession?.refreshPreservingDepth()
            }
        ) { selection in
            DailyReviewSheet(selectedDate: selection.date)
        }
        .onDisappear {
            isVisible = false
            state.activitySession?.cancel()
            state.querySession?.cancel()
        }
        .background {
            Button("") {
                searchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("기록")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("회고 없이도, 그날 한 일을 한눈에.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Button {
                openDay(DayKey.today)
            } label: {
                Label("날짜 찾기", systemImage: "calendar")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("날짜로 기록 찾기")

            Menu {
                Button {
                    exportBackup()
                } label: {
                    Label("백업 내보내기", systemImage: "square.and.arrow.up")
                }
                Button {
                    importBackup()
                } label: {
                    Label("백업 가져오기", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
                    .calendarToolbarButtonBackground()
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("기록 및 백업 메뉴")
            .help("기록 및 백업 메뉴")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: state.filter.hasActiveCriteria ? "magnifyingglass" : "book.pages")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(state.filter.hasActiveCriteria ? "검색 결과 없음" : "보관된 기록 없음")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Text(
                state.filter.hasActiveCriteria
                    ? "기간, 키워드, 검색 대상을 조정해보세요."
                    : "작업을 진행하거나 완료하면 날짜별로 모여요. 종료한 집중 기록과 회고도 함께 볼 수 있어요."
            )
            .font(.callout)
            .foregroundStyle(AppTheme.secondaryText)
            .multilineTextAlignment(.center)
            if state.filter.hasActiveCriteria {
                Button("검색 조건 초기화") { state.filter.reset() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private func refreshOverview() {
        guard isVisible, scenePhase == .active else { return }
        state.activitySession?.apply(weekCount: TaskActivityRules.regularWeekCount)
    }

    private func expandedBinding(for day: String, reviews: Bool) -> Binding<Bool> {
        Binding(
            get: {
                (reviews ? state.expandedReviewDays : state.expandedTaskDays).contains(day)
            },
            set: { expanded in
                if reviews {
                    if expanded {
                        state.expandedReviewDays.insert(day)
                    } else {
                        state.expandedReviewDays.remove(day)
                    }
                } else {
                    if expanded {
                        state.expandedTaskDays.insert(day)
                    } else {
                        state.expandedTaskDays.remove(day)
                    }
                }
            })
    }

    private func openDay(_ key: String) {
        if let date = DayKey.date(from: key) { selectedDay = ArchiveDaySelection(date: date) }
    }

    private func shouldDebounceSearch(
        from oldFilter: ArchiveFilter,
        to newFilter: ArchiveFilter
    ) -> Bool {
        oldFilter.searchText != newFilter.searchText && oldFilter.period == newFilter.period
            && oldFilter.scope == newFilter.scope && oldFilter.contentMode == newFilter.contentMode
            && oldFilter.dateBasis == newFilter.dateBasis
            && oldFilter.customStartDate == newFilter.customStartDate
            && oldFilter.customEndDate == newFilter.customEndDate
    }

    private var uiTestingShowsActivity: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--ui-testing-archive-mode") else {
            return false
        }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return false }
        return arguments[valueIndex] == "activity"
    }

    private func exportBackup() {
        do {
            switch try BackupService.exportPackage(context: modelContext) {
            case .completed(let completionMessage):
                message = completionMessage
            case .cancelled:
                message = nil
            }
        } catch {
            message = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    private func importBackup() {
        do {
            switch try BackupService.importBackup(context: modelContext) {
            case .completed(let completionMessage):
                message = completionMessage
                state.querySession?.refreshPreservingDepth()
            case .cancelled:
                message = nil
            }
        } catch {
            message = "가져오기 실패: \(error.localizedDescription)"
        }
    }
}

private struct ArchiveActivityOverview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var session: ActivityOverviewSession
    @Binding var isExpanded: Bool
    @Binding var selectedDayKey: String?
    var onOpenDay: (String) -> Void
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID
    @State private var themePreferences = ThemePreferenceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(AppTheme.doneForeground)
                        .accessibilityHidden(true)
                    Text(overviewTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if session.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("archive-overview-disclosure")
            .accessibilityLabel(overviewTitle)
            .accessibilityValue(isExpanded ? "펼침" : "접힘")
            .accessibilityHint(isExpanded ? "완료 활동 그래프를 접습니다" : "완료 활동 그래프를 펼칩니다")

            if isExpanded, session.overview.range != nil {
                graph
            }

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                Button("다시 시도") { session.retry() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity-overview")
    }

    private var overviewTitle: String {
        if session.overview.range != nil {
            return "완료 활동 · \(session.overview.currentStreak)일 연속"
        }
        return session.isLoading ? "완료 활동 · 불러오는 중" : "완료 활동"
    }

    private var graph: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.overview.todayState.message)
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
            Text("최근 1년 최고 \(session.overview.bestStreakInLastYear)일")
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            ActivityHeatmapView(
                overview: session.overview,
                palette: AppTheme.activityHeatmapPalette,
                mark: themePreferences.activityMark(for: selectedThemeID),
                selectedDayKey: selectedDayKey,
                onSelectDay: { key in
                    selectedDayKey = key
                    if let key { onOpenDay(key) }
                }
            )
            .frame(maxWidth: .infinity)

            activityLegend

            if let selectedDayKey,
                let day = session.overview.days.first(where: { $0.dayKey == selectedDayKey })
            {
                Text(selectionSummary(day))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .accessibilityIdentifier("activity-selected-day-summary")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity-graph")
    }

    private var activityLegend: some View {
        HStack(spacing: 5) {
            Text("적음")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
            ForEach(ActivityIntensityLevel.allCases, id: \.rawValue) { level in
                ActivityHeatmapMarkSample(
                    level: level,
                    palette: AppTheme.activityHeatmapPalette,
                    mark: themePreferences.activityMark(for: selectedThemeID),
                    size: 12
                )
            }
            Text("많음")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .accessibilityHidden(true)
    }

    private func selectionSummary(_ day: ActivityDaySummary) -> String {
        let dateText = DayKey.date(from: day.dayKey).map(DayKey.display) ?? day.dayKey
        return day.completedTaskCount == 0
            ? "\(dateText) · 완료 작업 없음"
            : "\(dateText) · 완료 작업 \(day.completedTaskCount)개"
    }
}

private struct ArchiveSingleDaySheet: View {
    var date: Date
    var session: ArchiveQuerySession
    var onOpenBoardDate: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTask: TaskRecordSelection?
    @State private var reviewDay: ArchiveDaySelection?

    var body: some View {
        NavigationStack {
            ArchiveDayDetailContent(
                date: date, session: session,
                onOpenTask: { selectedTask = $0 },
                onEditReview: { reviewDay = ArchiveDaySelection(date: $0) },
                onOpenBoard: { date in
                    dismiss()
                    onOpenBoardDate(date)
                }
            )
            .navigationTitle("하루 기록")

            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .frame(minWidth: 620, idealWidth: 740, minHeight: 620)
        .sheet(item: $selectedTask) { selection in
            TaskRecordSheet(selection: selection)
        }
        .sheet(item: $reviewDay, onDismiss: { session.refreshPreservingDepth() }) { selection in
            DailyReviewSheet(selectedDate: selection.date)
        }
    }
}
