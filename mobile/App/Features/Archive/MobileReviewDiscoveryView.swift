#if os(iOS)
import PlanBaseCore
import SwiftData
import SwiftUI

struct MobileReviewDiscoveryView: View {
    @Bindable var state: ArchiveScreenState
    var onOpenBoardDate: (Date) -> Void
    var onShowTheme: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var showingFilter = false
    @State private var composeDay: ArchiveDaySelection?
    @State private var activitySelection: ReviewActivitySelection?
    @State private var activityEditDay: ArchiveDaySelection?
    @State private var selectedTask: TaskRecordSelection?
    @State private var pendingNotice: String?
    @State private var notice: String?

    private var records: [ReviewDiscoveryRecord] { state.reviewSession?.records ?? [] }
    private var selectedRecord: ReviewDiscoveryRecord? {
        records.first { $0.id == state.selectedReviewDayKey }
    }

    var body: some View {
        MobileAdaptiveSplitView(compactColumn: $compactColumn, sidebarIdealWidth: 400) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if state.reviewFilter.hasActiveCriteria {
                        HStack {
                            Text(state.reviewFilter.period.title).font(.caption)
                            Spacer()
                            Button("초기화") { state.reviewFilter.reset() }
                                .font(.callout)
                                .frame(minHeight: 44)
                        }
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                    if records.isEmpty && state.reviewSession?.isLoading != true
                        && state.reviewSession?.errorMessage == nil {
                        ReviewDiscoveryEmptyState(filter: $state.reviewFilter) { composeToday() }
                    }
                    ForEach(records) { record in
                        ReviewDiscoveryCard(record: record, onOpen: {
                            state.selectedReviewDayKey = record.id
                            compactColumn = .detail
                        }) {
                            MobileArchiveImageCarousel(attachments: record.attachments, legacyFileNames: record.legacyFileNames)
                        }
                        .id(record.id)
                    }
                    ReviewDiscoveryFooter(session: state.reviewSession)
                }
                .scrollTargetLayout()
                .padding(16)
                .padding(.bottom, MobileLayout.bottomTabClearance)
            }
            .archiveRestoringScrollPosition(id: $state.reviewScrollDayKey)
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                ArchivePanePicker(selection: $state.pane)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(AppTheme.background)
            }
            .searchable(text: $state.reviewFilter.searchText,
                        placement: .navigationBarDrawer(displayMode: .always), prompt: "회고 제목, 본문, 날씨, 기분 검색")
            .navigationTitle("기록")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    MobileThemeButton(action: onShowTheme, minimumHitSize: 44)
                    Button { showingFilter = true } label: {
                        Image(systemName: state.reviewFilter.period == .all
                              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("회고 기간 필터")
                    Button { composeToday() } label: {
                        Image(systemName: "square.and.pencil").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("회고 작성")
                }
            }
        } detail: {
            if let record = selectedRecord {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ReviewDiscoveryCard(record: record, isDetail: true) {
                            MobileArchiveImageCarousel(attachments: record.attachments, legacyFileNames: record.legacyFileNames)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { detailActions(record) }
                            VStack(alignment: .leading, spacing: 12) { detailActions(record) }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, MobileLayout.bottomTabClearance)
                }
                .background(AppTheme.background)
                .navigationTitle("회고")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("회고 선택", systemImage: "book.closed",
                                       description: Text("목록에서 회고를 선택해 전체 내용을 읽어 보세요."))
            }
        }
        .reviewDiscoverySession(state)
        .onAppear { compactColumn = state.reviewShowsDetail ? .detail : .sidebar }
        .onChange(of: compactColumn) { _, column in state.reviewShowsDetail = column == .detail }
        .sheet(isPresented: $showingFilter) {
            NavigationStack {
                Form { Section("기간") { ReviewDiscoveryPeriodControls(filter: $state.reviewFilter) } }
                    .navigationTitle("회고 필터")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { showingFilter = false } } }
            }
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $composeDay, onDismiss: {
            state.reviewSession?.refreshPreservingDepth()
            notice = pendingNotice
            pendingNotice = nil
        }) { day in
            MobileReviewComposerSheet(selectedDate: day.date, onSaved: { pendingNotice = $0 })
                .environment(\.dynamicTypeSize, dynamicTypeSize)
        }
        .sheet(item: $activitySelection) { selection in
            let activitySession = selection.session
            Group {
                MobileArchiveDayDetail(
                        date: selection.date, session: activitySession, onOpenBoardDate: onOpenBoardDate,
                        onOpenTask: { selectedTask = $0 },
                        onEditReview: { activityEditDay = ArchiveDaySelection(date: $0) },
                        onClose: { activitySelection = nil }
                )
                .sheet(item: $selectedTask) { TaskRecordSheet(selection: $0) }
                .sheet(item: $activityEditDay, onDismiss: {
                    activitySession.refreshPreservingDepth()
                    state.reviewSession?.refreshPreservingDepth()
                }) { editDay in
                    MobileReviewComposerSheet(selectedDate: editDay.date)
                }
            }
        }
        .mobileSavedNotice($notice)
    }

    @ViewBuilder private func detailActions(_ record: ReviewDiscoveryRecord) -> some View {
        if let date = DayKey.date(from: record.id) {
            Button("회고 수정") { composeDay = ArchiveDaySelection(date: date) }
                .buttonStyle(PlanBaseButtonStyle(.secondary))
            Button("이날 활동 보기") {
                activitySelection = ReviewActivitySelection(date: date, session: ArchiveQuerySession(context: context))
            }
            .buttonStyle(PlanBaseButtonStyle(.secondary))
            .accessibilityIdentifier("review-open-activity")
        }
    }

    private func composeToday() { composeDay = ArchiveDaySelection(date: Date()) }

    private struct ReviewActivitySelection: Identifiable {
        let id = UUID()
        let date: Date
        let session: ArchiveQuerySession
    }
}
#endif
