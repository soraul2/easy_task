import AppKit
import Combine
import SwiftData
import SwiftUI
import PlanBaseCore

struct ArchiveView: View {
    var onOpenBoardDate: (Date) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var filter = ArchiveFilter()
    @State private var message: String?
    @State private var querySession: ArchiveQuerySession?
    @State private var statisticsSession: TaskHistoryStatisticsSession?
    @State private var activitySession: ActivityOverviewSession?
    @State private var selectedActivityDayKey: String?
    @AppStorage(ArchiveOverviewMode.storageKey) private var overviewModeRaw =
        ArchiveOverviewMode.activity.rawValue
    @State private var showingFilter = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let attachmentIndex = DiaryAttachmentIndex(
            attachments: querySession?.attachments ?? [],
            blocks: querySession?.blocks ?? []
        )
        let archiveGroups = querySession?.records ?? []

        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 12)

            ArchiveSearchToolbar(
                text: $filter.searchText,
                period: $filter.period,
                scope: $filter.scope,
                dateBasis: $filter.dateBasis,
                startDate: $filter.customStartDate,
                endDate: $filter.customEndDate,
                showingFilter: $showingFilter,
                searchFocused: $searchFocused
            )
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if overviewMode == .activity, let activitySession {
                        ArchiveActivityOverview(
                            session: activitySession,
                            selectedDayKey: $selectedActivityDayKey
                        )
                    } else if let statisticsSession {
                        ArchiveStatisticsOverview(
                            statistics: statisticsSession.statistics,
                            presentation: TaskHistoryStatisticsPresentation(filter: filter),
                            isLoading: statisticsSession.isLoading
                        )
                    }

                    if let message {
                        ArchiveMessageView(message: message)
                    }

                    if querySession?.isLoading == true && archiveGroups.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            ArchiveSkeletonCard()
                        }
                    } else if archiveGroups.isEmpty {
                        emptyState
                    } else {
                        ForEach(archiveGroups) { group in
                            ArchiveDayGroupView(
                                group: group,
                                dateBasis: filter.dateBasis,
                                attachments: group.review.map {
                                    attachmentIndex.activeAttachments(for: $0.id)
                                } ?? [],
                                legacyFileNames: group.review.map {
                                    attachmentIndex.unresolvedLegacyImageFileNames(for: $0)
                                } ?? [],
                                onOpenBoardDate: onOpenBoardDate
                            )
                        }

                        if querySession?.hasMore == true {
                            Button {
                                querySession?.loadNextPage()
                            } label: {
                                if querySession?.isLoading == true {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("이전 기록 더 보기", systemImage: "chevron.down")
                                }
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(querySession?.isLoading == true)
                        }
                    }

                    if let errorMessage = querySession?.errorMessage {
                        VStack(spacing: 8) {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(AppTheme.secondaryText)
                            Button("다시 시도") {
                                querySession?.retry()
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .task {
            guard querySession == nil else { return }
            let session = ArchiveQuerySession(context: modelContext)
            let statistics = TaskHistoryStatisticsSession(context: modelContext)
            let activity = ActivityOverviewSession(context: modelContext)
            querySession = session
            statisticsSession = statistics
            activitySession = activity
            session.apply(filter, debounceSearch: false)
            if let launchMode = uiTestingOverviewMode {
                overviewModeRaw = launchMode.rawValue
            }
            if overviewMode == .activity {
                activity.apply(weekCount: TaskActivityRules.regularWeekCount)
            } else {
                statistics.apply(filter)
            }
        }
        .onChange(of: filter) { oldFilter, newFilter in
            querySession?.apply(
                newFilter,
                debounceSearch: shouldDebounceSearch(
                    from: oldFilter,
                    to: newFilter
                )
            )
            if overviewMode == .statistics,
               shouldRefreshStatistics(from: oldFilter, to: newFilter) {
                statisticsSession?.apply(newFilter)
            }
        }
        .onChange(of: overviewModeRaw) { _, _ in
            selectedActivityDayKey = nil
            if overviewMode == .activity {
                activitySession?.apply(weekCount: TaskActivityRules.regularWeekCount)
            } else {
                activitySession?.cancel()
                statisticsSession?.apply(filter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { notification in
            guard let sourceContext = notification.object as? ModelContext,
                  sourceContext === modelContext else { return }
            querySession?.refreshPreservingDepth()
            if overviewMode == .statistics {
                statisticsSession?.apply(filter)
            }
        }
        .onDisappear {
            activitySession?.cancel()
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
                Text("날짜별 회고와 \(filter.dateBasis.taskSectionTitle)을 함께 봅니다.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Picker("기록 요약", selection: overviewModeBinding) {
                ForEach(ArchiveOverviewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .accessibilityIdentifier("archive-overview-mode")

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
            .help("기록 및 백업 메뉴")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: filter.hasActiveCriteria ? "magnifyingglass" : "book.pages")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(filter.hasActiveCriteria ? "검색 결과 없음" : "보관된 기록 없음")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Text(filter.hasActiveCriteria
                ? "\(filter.dateBasis.title), 기간, 키워드, 검색 대상을 조정해보세요."
                : "완료한 작업이나 회고를 작성하면 이곳에 표시됩니다.")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private func shouldDebounceSearch(
        from oldFilter: ArchiveFilter,
        to newFilter: ArchiveFilter
    ) -> Bool {
        oldFilter.searchText != newFilter.searchText &&
            oldFilter.period == newFilter.period &&
            oldFilter.scope == newFilter.scope &&
            oldFilter.dateBasis == newFilter.dateBasis &&
            oldFilter.customStartDate == newFilter.customStartDate &&
            oldFilter.customEndDate == newFilter.customEndDate
    }

    private var overviewMode: ArchiveOverviewMode {
        ArchiveOverviewMode(rawValue: overviewModeRaw) ?? .activity
    }

    private var overviewModeBinding: Binding<ArchiveOverviewMode> {
        Binding(
            get: { overviewMode },
            set: { overviewModeRaw = $0.rawValue }
        )
    }

    private var uiTestingOverviewMode: ArchiveOverviewMode? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--ui-testing-archive-mode") else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return ArchiveOverviewMode(rawValue: arguments[valueIndex])
    }

    private func shouldRefreshStatistics(
        from oldFilter: ArchiveFilter,
        to newFilter: ArchiveFilter
    ) -> Bool {
        oldFilter.period != newFilter.period ||
            oldFilter.customStartDate != newFilter.customStartDate ||
            oldFilter.customEndDate != newFilter.customEndDate
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
                querySession?.refreshPreservingDepth()
            case .cancelled:
                message = nil
            }
        } catch {
            message = "가져오기 실패: \(error.localizedDescription)"
        }
    }
}

private struct ArchiveActivityOverview: View {
    @Bindable var session: ActivityOverviewSession
    @Binding var selectedDayKey: String?
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID
    @State private var themePreferences = ThemePreferenceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(AppTheme.doneForeground)
                    .padding(6)
                    .background(AppTheme.done, in: Circle())
                    .accessibilityHidden(true)
                Text("\(session.overview.currentStreak)일 연속")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)
                    .contentTransition(.numericText())
                Spacer()
                if session.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("활동 기록 계산 중")
                }
            }

            Text(session.overview.todayState.message)
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
            Text("최근 1년 최고 \(session.overview.bestStreakInLastYear)일")
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            if session.overview.range != nil {
                ActivityHeatmapView(
                    overview: session.overview,
                    palette: AppTheme.activityHeatmapPalette,
                    mark: themePreferences.activityMark(for: selectedThemeID),
                    selectedDayKey: selectedDayKey,
                    onSelectDay: { selectedDayKey = $0 }
                )
                .frame(maxWidth: .infinity)

                activityLegend

                if let selectedDayKey,
                   let day = session.overview.days.first(where: {
                       $0.dayKey == selectedDayKey
                   }) {
                    Text(selectionSummary(day))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .accessibilityIdentifier("activity-selected-day-summary")
                }
            } else if !session.isLoading {
                Text(session.errorMessage ?? "작업을 완료하면 활동 기록이 시작돼요")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            }

            if session.errorMessage != nil {
                Button("다시 시도") {
                    session.retry()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityIdentifier("activity-overview")
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

private struct ArchiveStatisticsOverview: View {
    var statistics: TaskHistoryStatistics
    var presentation: TaskHistoryStatisticsPresentation
    var isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("선택 기간 작업 요약")
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(presentation.populationTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("작업 통계 계산 중")
                }
            }

            Text(presentation.meaningDescription)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            Divider()

            HStack(spacing: 18) {
                statisticValue("계획 작업", statistics.plannedTaskCount)
                statisticValue("완료 작업", statistics.completedTaskCount)

                VStack(alignment: .leading, spacing: 2) {
                    Text("계획 대비 완료율")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    if let rate = statistics.plannedCompletionRate {
                        Text(rate, format: .percent.precision(.fractionLength(0)))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)
                    } else {
                        Text("—")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                Spacer()

                Text(
                    "계획일 내 \(statistics.completedOnOrBeforePlannedDayCount) · " +
                        "지연 완료 \(statistics.delayedCompletionCount) · " +
                        "미완료 \(statistics.incompleteCount)"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(14)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(presentation.populationTitle). \(presentation.meaningDescription) " +
                "계획 작업 \(statistics.plannedTaskCount)개, " +
                "완료 작업 \(statistics.completedTaskCount)개, " +
                "계획일 내 완료 \(statistics.completedOnOrBeforePlannedDayCount)개, " +
                "지연 완료 \(statistics.delayedCompletionCount)개, " +
                "미완료 \(statistics.incompleteCount)개."
        )
        .accessibilityIdentifier("archive-overview")
    }

    private func statisticValue(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value, format: .number)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
        }
    }
}
