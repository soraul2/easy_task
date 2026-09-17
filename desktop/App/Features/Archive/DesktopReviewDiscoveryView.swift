import PlanBaseCore
import SwiftData
import SwiftUI

struct DesktopReviewDiscoveryView: View {
    @Bindable var state: ArchiveScreenState
    var onOpenBoardDate: (Date) -> Void
    @Environment(\.modelContext) private var context
    @State private var composeDay: ArchiveDaySelection?
    @State private var readDay: ArchiveDaySelection?
    @State private var showingFilter = false
    @FocusState private var searchFocused: Bool

    private var records: [ReviewDiscoveryRecord] { state.reviewSession?.records ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("기록").font(.system(size: 28, weight: .bold))
                        Text("남겨 둔 생각과 사진을 다시 만나요.")
                            .font(.callout).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Button { composeDay = ArchiveDaySelection(date: Date()) } label: {
                        Label("회고 작성", systemImage: "square.and.pencil")
                    }.buttonStyle(.bordered)
                }
                ArchivePanePicker(selection: $state.pane).frame(maxWidth: 320)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.secondaryText)
                    TextField("회고 제목, 본문, 날씨, 기분 검색", text: $state.reviewFilter.searchText)
                        .textFieldStyle(.plain).focused($searchFocused)
                        .accessibilityIdentifier("review-search")
                    Button { showingFilter.toggle() } label: {
                        Label(state.reviewFilter.period.title, systemImage: "line.3.horizontal.decrease")
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showingFilter) {
                        ReviewDiscoveryPeriodControls(filter: $state.reviewFilter).padding(20).frame(width: 300)
                    }
                    if state.reviewFilter.hasActiveCriteria {
                        Button("초기화") { state.reviewFilter.reset() }.buttonStyle(.bordered)
                    }
                }
                .padding(10)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 10))
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(spacing: 12) {
                    if records.isEmpty && state.reviewSession?.isLoading != true
                        && state.reviewSession?.errorMessage == nil {
                        ReviewDiscoveryEmptyState(filter: $state.reviewFilter) {
                            composeDay = ArchiveDaySelection(date: Date())
                        }
                    }
                    ForEach(records) { record in
                        ReviewDiscoveryCard(record: record, onOpen: {
                            if let date = DayKey.date(from: record.id) { readDay = ArchiveDaySelection(date: date) }
                        }) {
                            ArchiveReviewImagePreview(attachments: record.attachments, legacyFileNames: record.legacyFileNames)
                        }
                        .id(record.id)
                    }
                    ReviewDiscoveryFooter(session: state.reviewSession)
                }
                .scrollTargetLayout()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            .archiveRestoringScrollPosition(id: $state.reviewScrollDayKey)
        }
        .foregroundStyle(AppTheme.primaryText)
        .background(AppTheme.background)
        .reviewDiscoverySession(state)
        .sheet(item: $composeDay, onDismiss: { state.reviewSession?.refreshPreservingDepth() }) { day in
            DailyReviewSheet(selectedDate: day.date)
        }
        .sheet(item: $readDay) { day in
            DesktopReviewReader(day: day, state: state, onOpenBoardDate: onOpenBoardDate)
        }
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
    }
}

private struct DesktopReviewReader: View {
    var day: ArchiveDaySelection
    @Bindable var state: ArchiveScreenState
    var onOpenBoardDate: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var activitySession: ArchiveQuerySession?
    @State private var showingActivity = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("회고").font(.title2.bold())
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                if let record = state.reviewSession?.records.first(where: { $0.id == day.id }) {
                    ReviewDiscoveryCard(record: record, isDetail: true) {
                        ArchiveReviewImagePreview(attachments: record.attachments, legacyFileNames: record.legacyFileNames)
                    }
                } else {
                    ContentUnavailableView("회고 내용이 없어요", systemImage: "book.closed",
                        description: Text("이 날짜의 회고가 삭제되었거나 검색 조건에서 제외되었어요."))
                }
            }
            HStack(spacing: 12) {
                Button("회고 수정") { editing = true }.buttonStyle(.bordered)
                Button("이날 활동 보기") {
                    activitySession = ArchiveQuerySession(context: context)
                    showingActivity = true
                }.buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(minWidth: 520, idealWidth: 680, minHeight: 480, idealHeight: 720)
        .background(AppTheme.background)
        .sheet(isPresented: $editing, onDismiss: { state.reviewSession?.refreshPreservingDepth() }) {
            DailyReviewSheet(selectedDate: day.date)
        }
        .sheet(isPresented: $showingActivity) {
            if let activitySession {
                ArchiveSingleDaySheet(date: day.date, session: activitySession, onOpenBoardDate: onOpenBoardDate)
            }
        }
    }
}
