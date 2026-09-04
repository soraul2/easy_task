#if os(iOS) || os(macOS)
import SwiftData
import SwiftUI

public struct ArchiveDayDetailContent: View {
    @State private var date: Date
    @State private var session: ArchiveQuerySession
    @State private var didRequest = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let onOpenTask: (TaskRecordSelection) -> Void
    private let onEditReview: (Date) -> Void
    private let onOpenBoard: (Date) -> Void

    public init(
        date: Date, session: ArchiveQuerySession,
        onOpenTask: @escaping (TaskRecordSelection) -> Void,
        onEditReview: @escaping (Date) -> Void,
        onOpenBoard: @escaping (Date) -> Void
    ) {
        _date = State(initialValue: date)
        _session = State(initialValue: session)
        self.onOpenTask = onOpenTask
        self.onEditReview = onEditReview
        self.onOpenBoard = onOpenBoard
    }

    public var body: some View {
        VStack(spacing: 0) {
            dateNavigation
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = session.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle")
                        Button("다시 시도") { session.retry() }.buttonStyle(.bordered)
                    }
                    if !didRequest || (session.isLoading && session.records.isEmpty) {
                        ProgressView("하루 기록을 불러오는 중")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if let record = session.records.first {
                        let entries = record.activityEntries ?? []
                        Text(ArchiveDayPresentation(record: record).summaryText)
                            .font(.headline)
                        DailyActivityTaskList(
                            entries: entries, dayKey: record.dayKey,
                            matchedTaskIDs: [], expanded: .constant(true),
                            onOpenTask: {
                                onOpenTask(TaskRecordSelection(taskID: $0, dayKey: record.dayKey))
                            },
                            showsExpansionControl: false)
                        if entries.contains(where: { $0.evidence.legacyCompletion && !$0.evidence.completed })
                        {
                            Text("이전 완료 기록은 저장된 날짜를 사용해요. 실제로 활동한 날짜와 다를 수 있어요.")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        if let review = record.review {
                            Divider()
                            Label(
                                review.title.isEmpty ? "이날의 회고" : review.title,
                                systemImage: "text.book.closed"
                            )
                            .font(.headline)
                            if !review.content.isEmpty {
                                Text(review.content).lineLimit(6)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        reviewButton(hasReview: record.review != nil)
                    } else if session.errorMessage == nil {
                        ContentUnavailableView(
                            "저장된 활동 기록이 없어요", systemImage: "calendar",
                            description: Text("다른 날짜를 확인하거나 이날의 회고를 남겨보세요."))
                        reviewButton(hasReview: false)
                    }
                    Button {
                        onOpenBoard(date)
                    } label: {
                        Label("이 날짜의 보드 열기", systemImage: "rectangle.3.group")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("archive-day-detail")
        .task(id: DayKey.key(for: date)) {
            didRequest = true
            session.apply(
                ArchiveFilter(
                    contentMode: .dailyActivity, period: .custom,
                    customStartDate: date, customEndDate: date), debounceSearch: false)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: PersistenceCommandService.dataChangedNotification)
        ) { notification in
            guard let source = notification.object as? ModelContext, source === modelContext else { return }
            session.refreshPreservingDepth()
        }
        .onDisappear { session.cancel() }
    }

    @ViewBuilder
    private var dateNavigation: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                datePicker
                HStack {
                    previousDayButton
                    Spacer(minLength: 0)
                    nextDayButton
                }
            }
            .padding(.vertical, 8)
        } else {
            HStack(spacing: 12) {
                previousDayButton
                Spacer(minLength: 0)
                datePicker
                Spacer(minLength: 0)
                nextDayButton
            }
        }
    }

    private var datePicker: some View {
        DatePicker("기록 날짜", selection: $date, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .environment(\.locale, Locale(identifier: "ko_KR"))
    }

    private var previousDayButton: some View {
        Button {
            date = DayKey.addingDays(-1, to: date)
        } label: {
            Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("이전 날짜")
    }

    private var nextDayButton: some View {
        Button {
            date = DayKey.addingDays(1, to: date)
        } label: {
            Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("다음 날짜")
    }

    private func reviewButton(hasReview: Bool) -> some View {
        Button {
            onEditReview(date)
        } label: {
            Label(hasReview ? "회고와 사진 보기" : "회고 남기기", systemImage: "square.and.pencil")
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.secondaryText)
    }
}

#endif
