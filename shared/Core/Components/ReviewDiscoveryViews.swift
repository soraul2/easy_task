#if !os(watchOS)
import Combine
import SwiftData
import SwiftUI

public struct ArchivePanePicker: View {
    @Binding var selection: ArchivePane
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    public init(selection: Binding<ArchivePane>) { _selection = selection }
    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize { picker.pickerStyle(.menu) }
            else { picker.pickerStyle(.segmented) }
        }
        .accessibilityIdentifier("archive-pane-picker")
    }
    private var picker: some View {
        Picker("기록 종류", selection: $selection) {
            ForEach(ArchivePane.allCases) { Text($0.title).tag($0) }
        }
    }
}

public struct ReviewDiscoveryPeriodControls: View {
    @Binding var filter: ReviewDiscoveryFilter
    public init(filter: Binding<ReviewDiscoveryFilter>) { _filter = filter }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("조회 기간", selection: $filter.period) {
                ForEach(ArchivePeriod.allCases) { Text($0.title).tag($0) }
            }
            if filter.period == .custom {
                DatePicker("시작", selection: $filter.customStartDate, displayedComponents: .date)
                DatePicker("종료", selection: $filter.customEndDate, displayedComponents: .date)
            }
            if filter.hasActiveCriteria {
                Button("검색 조건 초기화") { filter.reset() }
                    .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
            }
        }
        .foregroundStyle(AppTheme.primaryText)
        .accessibilityIdentifier("review-period-controls")
    }
}

public struct ReviewDiscoveryCard<Photos: View>: View {
    public var record: ReviewDiscoveryRecord
    public var isDetail: Bool
    public var onOpen: () -> Void
    private var photos: Photos
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(record: ReviewDiscoveryRecord, isDetail: Bool = false,
                onOpen: @escaping () -> Void = {}, @ViewBuilder photos: () -> Photos) {
        self.record = record; self.isDetail = isDetail; self.onOpen = onOpen; self.photos = photos()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isDetail { heading }
            else {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: 12) {
                        heading
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText).padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: PlanBaseControlMetrics.minimumTargetSize, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review-open-\(record.id)")
                .accessibilityLabel("\(DayKey.date(from: record.id).map(DayKey.display) ?? record.id), \(record.title)")
                .accessibilityHint("회고 전체 읽기")
            }
            if !record.bodyText.isEmpty {
                Text(record.bodyText)
                    .font(.body)
                    .lineSpacing(4)
                    .lineLimit(isDetail || dynamicTypeSize.isAccessibilitySize ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if record.photoCount > 0 {
                photos
                Label("사진 \(record.photoCount)장", systemImage: "photo")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            let metadata = [record.review.weather, record.review.mood].filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.joined(separator: " · ")
            if !metadata.isEmpty {
                Text(metadata).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .foregroundStyle(AppTheme.primaryText)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border, lineWidth: 1) }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DayKey.date(from: record.id).map(DayKey.display) ?? record.id)
                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            Text(record.title).font(isDetail ? .title2.bold() : .headline)
                .lineLimit(isDetail || dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
    }
}

public struct ReviewDiscoveryEmptyState: View {
    @Binding var filter: ReviewDiscoveryFilter
    var onCompose: () -> Void
    public init(filter: Binding<ReviewDiscoveryFilter>, onCompose: @escaping () -> Void) {
        _filter = filter; self.onCompose = onCompose
    }
    public var body: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                filter.hasActiveCriteria ? "조건에 맞는 회고가 없어요" : "아직 작성한 회고가 없어요",
                systemImage: filter.hasActiveCriteria ? "magnifyingglass" : "book.closed",
                description: Text(filter.hasActiveCriteria ? "검색어나 기간을 바꿔 보세요." : "하루의 생각과 사진을 남겨 보세요.")
            )
            if filter.hasActiveCriteria {
                Button("검색 조건 초기화") { filter.reset() }.buttonStyle(.bordered)
            } else {
                Button("회고 작성", action: onCompose).buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

public struct ReviewDiscoveryFooter: View {
    public var session: ReviewDiscoverySession?
    public init(session: ReviewDiscoverySession?) { self.session = session }
    public var body: some View {
        VStack(spacing: 12) {
            if session?.isLoading == true { ProgressView("회고 불러오는 중") }
            if let error = session?.errorMessage {
                Text(error).font(.callout).foregroundStyle(AppTheme.secondaryText)
                Button("다시 시도") { session?.refreshPreservingDepth() }.buttonStyle(.bordered)
            } else if session?.hasMore == true {
                Button("이전 회고 더 보기") { session?.loadNextPage() }
                    .buttonStyle(.bordered).disabled(session?.isLoading == true)
                    .accessibilityIdentifier("review-load-more")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ReviewDiscoveryConnection: ViewModifier {
    @Bindable var state: ArchiveScreenState
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .task {
                if state.reviewSession == nil {
                    state.reviewSession = ReviewDiscoverySession(context: context)
                    state.reviewSession?.apply(state.reviewFilter)
                } else { state.reviewSession?.refreshPreservingDepth() }
            }
            .onChange(of: state.reviewFilter) { old, new in
                state.reviewSession?.apply(new, debounceSearch: old.searchText != new.searchText)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { state.reviewSession?.refreshPreservingDepth() }
                else { state.reviewSession?.cancel() }
            }
            .onReceive(NotificationCenter.default.publisher(for: PersistenceCommandService.dataChangedNotification)) { note in
                guard PersistenceCommandService.affects(.reviews, in: note) else { return }
                if let source = note.object as? ModelContext, source !== context { return }
                state.reviewSession?.refreshPreservingDepth()
            }
            .onReceive(NotificationCenter.default.publisher(for: CloudKitSyncService.eventChangedNotification)) { _ in
                state.reviewSession?.refreshPreservingDepth()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                state.reviewSession?.refreshPreservingDepth()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                state.reviewSession?.refreshPreservingDepth()
            }
            .onDisappear { state.reviewSession?.cancel() }
    }
}

/// SwiftUI can report the top/nil position while a recreated scroll view lays out.
/// Keep the prior anchor until restoration finishes so that report cannot overwrite it.
private struct ArchiveScrollRestoration: ViewModifier {
    @Binding var savedID: String?
    @State private var currentID: String?
    @State private var initialID: String?
    @State private var isRestoring = true

    init(savedID: Binding<String?>) {
        _savedID = savedID
        _currentID = State(initialValue: savedID.wrappedValue)
        _initialID = State(initialValue: savedID.wrappedValue)
    }

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .scrollPosition(id: $currentID, anchor: .top)
#if os(macOS)
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.5) { visibleIDs in
                    if !isRestoring, let id = visibleIDs.first { savedID = id }
                }
#endif
                .onChange(of: currentID) { _, id in
                    if !isRestoring, let id { savedID = id }
                }
                .task {
                    if let initialID {
                        await Swift.Task.yield()
                        guard !Swift.Task.isCancelled else { return }
                        proxy.scrollTo(initialID, anchor: .top)
                        currentID = initialID
                        await Swift.Task.yield()
                    }
                    isRestoring = false
                }
        }
    }
}

public extension View {
    func archiveRestoringScrollPosition(id: Binding<String?>) -> some View {
        modifier(ArchiveScrollRestoration(savedID: id))
    }

    func reviewDiscoverySession(_ state: ArchiveScreenState) -> some View {
        modifier(ReviewDiscoveryConnection(state: state))
    }
}

#endif
