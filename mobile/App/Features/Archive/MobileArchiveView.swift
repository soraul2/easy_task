#if os(iOS)
import Combine
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

struct MobileArchiveView: View {
    @Bindable var state: ArchiveScreenState
    var onOpenBoardDate: (Date) -> Void
    var onShowTheme: () -> Void

    @State private var selectedDay: ArchiveDaySelection?
    @State private var daySession: ArchiveQuerySession?
    @State private var daySelectionID = UUID()
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var selectedTask: TaskRecordSelection?
    @State private var selectedReviewDay: ArchiveDaySelection?
    @State private var pendingReviewNotice: String?
    @State private var reviewNotice: String?
    @State private var isVisible = false
    @AppStorage("planbase.archiveShowsOverview") private var showsOverview = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingFilter = false
    @StateObject private var backupCoordinator = MobileBackupCoordinator()

    private var hasActiveFilterOptions: Bool {
        state.filter.period != .all || state.filter.scope != .all
            || state.filter.contentMode != .dailyActivity
    }

    var body: some View {
        if state.pane == .reviews {
            MobileReviewDiscoveryView(state: state, onOpenBoardDate: onOpenBoardDate, onShowTheme: onShowTheme)
        } else {
            activityContent
        }
    }

    @ViewBuilder private var activityContent: some View {
        let attachmentIndex = DiaryAttachmentIndex(
            attachments: state.querySession?.attachments ?? [],
            blocks: state.querySession?.blocks ?? []
        )
        let records = state.querySession?.records ?? []

        MobileAdaptiveSplitView(compactColumn: $compactColumn, sidebarIdealWidth: 400) {
            List {
                if verticalSizeClass == .compact {
                    ArchivePanePicker(selection: $state.pane)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if let activitySession = state.activitySession {
                    MobileArchiveActivityOverview(
                        session: activitySession,
                        isExpanded: $showsOverview,
                        selectedDayKey: $state.selectedActivityDayKey,
                        onOpenDay: openDay
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                if hasActiveFilterOptions {
                    MobileArchiveActiveFilterBar(filter: $state.filter)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
                }

                if state.querySession?.isLoading == true && records.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        MobileArchiveSkeletonCard()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } else if records.isEmpty && state.querySession?.errorMessage == nil {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20))
                } else {
                    ForEach(records) { record in
                        MobileArchiveRecordCard(
                            record: record,
                            dateBasis: state.filter.dateBasis,
                            attachments: record.review.map {
                                attachmentIndex.activeAttachments(for: $0.id)
                            } ?? [],
                            legacyFileNames: record.review.map {
                                attachmentIndex.unresolvedLegacyImageFileNames(for: $0)
                            } ?? [],
                            onOpenDay: { openDay(record.dayKey) },
                            onOpenTask: { id in
                                selectedTask = TaskRecordSelection(taskID: id, dayKey: record.dayKey)
                            },
                            onEditReview: {
                                if let date = DayKey.date(from: record.dayKey) {
                                    selectedReviewDay = ArchiveDaySelection(date: date)
                                }
                            },
                            tasksExpanded: expandedBinding(for: record.dayKey, reviews: false),
                            reviewExpanded: expandedBinding(for: record.dayKey, reviews: true)
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }

                    if state.querySession?.hasMore == true {
                        Button {
                            state.querySession?.loadNextPage()
                        } label: {
                            HStack {
                                Spacer()
                                if state.querySession?.isLoading == true {
                                    ProgressView()
                                } else {
                                    Label("이전 기록 더 보기", systemImage: "chevron.down")
                                }
                                Spacer()
                            }
                        }
                        .disabled(state.querySession?.isLoading == true)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }

                if let errorMessage = state.querySession?.errorMessage {
                    VStack(spacing: 10) {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("다시 시도") {
                            state.querySession?.retry()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .archiveRestoringScrollPosition(id: $state.scrollDayKey)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                if verticalSizeClass != .compact {
                    ArchivePanePicker(selection: $state.pane)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(AppTheme.background)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: MobileLayout.bottomTabClearance)
            }
            .searchable(
                text: $state.filter.searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "기록 검색"
            )
            .navigationTitle("기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        openDay(DayKey.today)
                    } label: {
                        Image(systemName: "calendar")
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("날짜로 기록 찾기")

                    MobileThemeButton(action: onShowTheme, minimumHitSize: 44)

                    Button {
                        showingFilter = true
                    } label: {
                        Image(
                            systemName: hasActiveFilterOptions
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
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
                            backupCoordinator.requestImport(context: modelContext)
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
                MobileArchiveFilterSheet(filter: $state.filter)
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
            }
        } detail: {
            if let selectedDay, let daySession {
                MobileArchiveDayDetail(
                    date: selectedDay.date,
                    session: daySession,
                    onOpenBoardDate: onOpenBoardDate,
                    onOpenTask: { selectedTask = $0 },
                    onEditReview: { selectedReviewDay = ArchiveDaySelection(date: $0) },
                    onClose: { compactColumn = .sidebar }
                )
                .id(daySelectionID)
            } else {
                ContentUnavailableView("하루 기록 선택", systemImage: "book.closed",
                    description: Text("목록에서 날짜를 선택해 하루의 작업과 회고를 확인하세요."))
            }
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
        .onChange(of: horizontalSizeClass) { _, _ in
            refreshOverview()
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
        .sheet(item: $selectedTask) { selection in
            TaskRecordSheet(selection: selection)
                .dynamicTypeSize(dynamicTypeSize)
        }
        .sheet(
            item: $selectedReviewDay,
            onDismiss: {
                state.querySession?.refreshPreservingDepth()
                daySession?.refreshPreservingDepth()
                reviewNotice = pendingReviewNotice
                pendingReviewNotice = nil
            }
        ) { selection in
            MobileReviewComposerSheet(selectedDate: selection.date, onSaved: { pendingReviewNotice = $0 })
                .environment(\.dynamicTypeSize, dynamicTypeSize)
        }
        .mobileSavedNotice($reviewNotice)
        .onDisappear {
            isVisible = false
            state.activitySession?.cancel()
            state.querySession?.cancel()
        }
        .sheet(item: Binding(
            get: { backupCoordinator.pickerRequest },
            set: { request in
                if request == nil, let pending = backupCoordinator.pickerRequest {
                    backupCoordinator.handlePickerResult(.cancelled, for: pending, context: modelContext)
                } else {
                    backupCoordinator.pickerRequest = request
                }
            }
        )) { request in
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
        .confirmationDialog(
            "진행 중인 타이머를 종료할까요?",
            isPresented: $backupCoordinator.isConfirmingFocusTerminationForImport,
            titleVisibility: .visible
        ) {
            Button("종료하고 백업 가져오기", role: .destructive) {
                backupCoordinator.terminateFocusAndRequestImport(context: modelContext)
            }
            Button("취소", role: .cancel) {
                backupCoordinator.cancelFocusTerminationForImport()
            }
        } message: {
            Text("백업을 병합하기 전에 현재 집중 기록을 안전하게 저장합니다.")
        }
    }

    private func refreshOverview() {
        guard isVisible, scenePhase == .active else { return }
        state.activitySession?.apply(weekCount: activityWeekCount)
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
        guard let date = DayKey.date(from: key) else { return }
        // A user choosing a day starts a new detail query. Resizing does not.
        daySession = state.querySession?.makeDaySession()
            ?? ArchiveQuerySession(context: modelContext)
        daySelectionID = UUID()
        selectedDay = ArchiveDaySelection(date: date)
        compactColumn = .detail
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

    private var activityWeekCount: Int {
        horizontalSizeClass == .regular
            ? TaskActivityRules.regularWeekCount
            : TaskActivityRules.compactWeekCount
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                state.filter.hasActiveCriteria ? "검색 결과 없음" : "보관된 기록 없음",
                systemImage: state.filter.hasActiveCriteria ? "magnifyingglass" : "book.pages",
                description: Text(
                    state.filter.hasActiveCriteria
                        ? "기간, 키워드, 검색 대상을 조정해보세요."
                        : "작업을 진행하거나 완료하면 날짜별로 모여요. 종료한 집중 기록과 회고도 함께 볼 수 있어요.")
            )

            if state.filter.hasActiveCriteria {
                Button("검색 조건 초기화") {
                    state.filter.reset()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

private struct MobileArchiveActivityOverview: View {
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
                    .font(.subheadline)
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
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Text("최근 1년 최고 \(session.overview.bestStreakInLastYear)일")
                .font(.subheadline.weight(.semibold))
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
                    .font(.subheadline.weight(.semibold))
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

                if filter.contentMode != .dailyActivity {
                    MobileArchiveFilterChip(title: filter.dateBasis.title) {
                        filter.dateBasis = .completed
                        filter.contentMode = .dailyActivity
                    }
                }

                Button("모두 지우기") {
                    filter.period = .all
                    filter.scope = .all
                    filter.dateBasis = .completed
                    filter.contentMode = .dailyActivity
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

struct MobileArchiveDayDetail: View {
    var date: Date
    var session: ArchiveQuerySession
    var onOpenBoardDate: (Date) -> Void
    var onOpenTask: (TaskRecordSelection) -> Void
    var onEditReview: (Date) -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ArchiveDayDetailContent(
                date: date, session: session,
                onOpenTask: onOpenTask,
                onEditReview: onEditReview,
                onOpenBoard: onOpenBoardDate
            )
            .navigationTitle("하루 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기", action: onClose)
                }
            }
        }
    }
}
#endif
