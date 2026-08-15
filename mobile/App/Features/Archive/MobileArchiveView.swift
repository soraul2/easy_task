#if os(iOS)
import Combine
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

struct MobileArchiveView: View {
    var onOpenBoardDate: (Date) -> Void
    var onShowTheme: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var filter = ArchiveFilter()
    @State private var showingFilter = false
    @State private var querySession: ArchiveQuerySession?
    @State private var statisticsSession: TaskHistoryStatisticsSession?
    @State private var activitySession: ActivityOverviewSession?
    @State private var selectedActivityDayKey: String?
    @AppStorage(ArchiveOverviewMode.storageKey) private var overviewModeRaw =
        ArchiveOverviewMode.activity.rawValue
    @StateObject private var backupCoordinator = MobileBackupCoordinator()

    private var hasActiveFilterOptions: Bool {
        filter.period != .all ||
            filter.scope != .all ||
            filter.dateBasis != .completed
    }

    var body: some View {
        let attachmentIndex = DiaryAttachmentIndex(
            attachments: querySession?.attachments ?? [],
            blocks: querySession?.blocks ?? []
        )
        let records = querySession?.records ?? []

        NavigationStack {
            List {
                Picker("기록 요약", selection: overviewModeBinding) {
                    ForEach(ArchiveOverviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                .accessibilityIdentifier("archive-overview-mode")

                if overviewMode == .activity, let activitySession {
                    MobileArchiveActivityOverview(
                        session: activitySession,
                        selectedDayKey: $selectedActivityDayKey
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } else if let statisticsSession {
                    MobileArchiveStatisticsOverview(
                        statistics: statisticsSession.statistics,
                        presentation: TaskHistoryStatisticsPresentation(filter: filter),
                        isLoading: statisticsSession.isLoading
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                }

                if hasActiveFilterOptions {
                    MobileArchiveActiveFilterBar(filter: $filter)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
                }

                if querySession?.isLoading == true && records.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        MobileArchiveSkeletonCard()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } else if records.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20))
                } else {
                    ForEach(records) { record in
                        MobileArchiveRecordCard(
                            record: record,
                            dateBasis: filter.dateBasis,
                            attachments: record.review.map {
                                attachmentIndex.activeAttachments(for: $0.id)
                            } ?? [],
                            legacyFileNames: record.review.map {
                                attachmentIndex.unresolvedLegacyImageFileNames(for: $0)
                            } ?? [],
                            onOpenBoardDate: onOpenBoardDate
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }

                    if querySession?.hasMore == true {
                        Button {
                            querySession?.loadNextPage()
                        } label: {
                            HStack {
                                Spacer()
                                if querySession?.isLoading == true {
                                    ProgressView()
                                } else {
                                    Label("이전 기록 더 보기", systemImage: "chevron.down")
                                }
                                Spacer()
                            }
                        }
                        .disabled(querySession?.isLoading == true)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }

                if let errorMessage = querySession?.errorMessage {
                    VStack(spacing: 10) {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("다시 시도") {
                            querySession?.retry()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: MobileLayout.bottomTabClearance)
            }
            .searchable(text: $filter.searchText, prompt: "작업 제목, 메모, 회고 검색")
            .navigationTitle("기록")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    MobileThemeButton(action: onShowTheme, minimumHitSize: 44)

                    Button { showingFilter = true } label: {
                        Image(systemName: hasActiveFilterOptions
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(hasActiveFilterOptions ? "적용된 기록 필터 변경" : "기록 필터")

                    Menu {
                        Button {
                            backupCoordinator.requestExport(context: modelContext)
                        } label: {
                            Label("백업 내보내기", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            backupCoordinator.requestImport()
                        } label: {
                            Label("백업 가져오기", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Group {
                            if backupCoordinator.isBusy {
                                ProgressView()
                            } else {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(AppTheme.primaryText)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .disabled(backupCoordinator.isBusy)
                    .accessibilityLabel(
                        backupCoordinator.isBusy ? "백업 처리 중" : "기록 및 백업 메뉴"
                    )
                }
            }
            .sheet(isPresented: $showingFilter) {
                MobileArchiveFilterSheet(filter: $filter)
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
                activity.apply(weekCount: activityWeekCount)
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
                activitySession?.apply(weekCount: activityWeekCount)
            } else {
                activitySession?.cancel()
                statisticsSession?.apply(filter)
            }
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            guard overviewMode == .activity else { return }
            selectedActivityDayKey = nil
            activitySession?.apply(weekCount: activityWeekCount)
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
        .sheet(item: $backupCoordinator.pickerRequest) { request in
            MobileBackupDocumentPicker(request: request) { result in
                backupCoordinator.handlePickerResult(
                    result,
                    for: request,
                    context: modelContext
                )
            }
        }
        .alert(item: $backupCoordinator.notice) { notice in
            Alert(
                title: Text(
                    notice.kind == .success ? "백업 완료" : "백업 실패"
                ),
                message: Text(notice.message),
                dismissButton: .default(Text("확인"))
            )
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

    private var activityWeekCount: Int {
        horizontalSizeClass == .regular
            ? TaskActivityRules.regularWeekCount
            : TaskActivityRules.compactWeekCount
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                filter.hasActiveCriteria ? "검색 결과 없음" : "보관된 기록 없음",
                systemImage: filter.hasActiveCriteria ? "magnifyingglass" : "book.pages",
                description: Text(filter.hasActiveCriteria
                    ? "\(filter.dateBasis.title), 기간, 키워드, 검색 대상을 조정해보세요."
                    : "완료한 작업이나 회고를 작성하면 이곳에 표시됩니다.")
            )

            if filter.hasActiveCriteria {
                Button("검색 조건 초기화") {
                    filter.reset()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

private struct MobileArchiveActivityOverview: View {
    @Bindable var session: ActivityOverviewSession
    @Binding var selectedDayKey: String?
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID
    @State private var themePreferences = ThemePreferenceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(AppTheme.doneForeground)
                    .padding(7)
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
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Text("최근 1년 최고 \(session.overview.bestStreakInLastYear)일")
                .font(.subheadline.weight(.semibold))
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .accessibilityIdentifier("activity-selected-day-summary")
                }
            } else if !session.isLoading {
                Text(session.errorMessage ?? "작업을 완료하면 활동 기록이 시작돼요")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            }

            if session.errorMessage != nil {
                Button("다시 시도") {
                    session.retry()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
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
                    size: 13
                )
            }
            Text("많음")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 8)
            if let weekCount = session.overview.range?.weekCount {
                Text("최근 \(weekCount)주")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
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

private struct MobileArchiveStatisticsOverview: View {
    var statistics: TaskHistoryStatistics
    var presentation: TaskHistoryStatisticsPresentation
    var isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("선택 기간 작업 요약")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("작업 통계 계산 중")
                    }
                }

                Text(presentation.populationTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Text(presentation.meaningDescription)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                statisticValue(title: "계획 작업", value: statistics.plannedTaskCount)
                statisticValue(title: "완료 작업", value: statistics.completedTaskCount)
                VStack(alignment: .leading, spacing: 2) {
                    Text("계획 대비 완료율")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    if let rate = statistics.plannedCompletionRate {
                        Text(rate, format: .percent.precision(.fractionLength(0)))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)
                            .contentTransition(.numericText())
                    } else {
                        Text("—")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(
                "계획일 내 \(statistics.completedOnOrBeforePlannedDayCount) · " +
                    "지연 완료 \(statistics.delayedCompletionCount) · " +
                    "미완료 \(statistics.incompleteCount)"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(16)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
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

    private func statisticValue(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value, format: .number)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MobileArchiveActiveFilterBar: View {
    @Binding var filter: ArchiveFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if filter.period != .all {
                    MobileArchiveFilterChip(title: filter.period.title) {
                        filter.period = .all
                    }
                }

                if filter.scope != .all {
                    MobileArchiveFilterChip(title: filter.scope.title) {
                        filter.scope = .all
                    }
                }

                if filter.dateBasis != .completed {
                    MobileArchiveFilterChip(title: filter.dateBasis.title) {
                        filter.dateBasis = .completed
                    }
                }

                Button("모두 지우기") {
                    filter.period = .all
                    filter.scope = .all
                    filter.dateBasis = .completed
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(minHeight: 44)
            }
        }
        .accessibilityLabel("적용된 기록 필터")
    }
}

private struct MobileArchiveFilterChip: View {
    var title: String
    var onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(AppTheme.selectedTab, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("\(title) 필터 제거")
    }
}

private struct MobileArchiveSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: 150, height: 15)
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: 90, height: 11)
                }
            }

            RoundedRectangle(cornerRadius: 4)
                .frame(height: 12)
            RoundedRectangle(cornerRadius: 4)
                .frame(width: 210, height: 12)
        }
        .foregroundStyle(AppTheme.input)
        .padding(14)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("기록 불러오는 중")
    }
}
#endif
