#if os(iOS)
import Combine
import EasyTaskCore
import Foundation
import SwiftData
import SwiftUI

struct MobileArchiveView: View {
    var onOpenBoardDate: (Date) -> Void
    var onShowTheme: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var filter = ArchiveFilter()
    @State private var showingFilter = false
    @State private var querySession: ArchiveQuerySession?

    private var hasActiveFilterOptions: Bool {
        filter.period != .all || filter.scope != .all
    }

    var body: some View {
        let attachmentIndex = DiaryAttachmentIndex(
            attachments: querySession?.attachments ?? [],
            blocks: querySession?.blocks ?? []
        )
        let records = querySession?.records ?? []

        NavigationStack {
            List {
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
                    MobileThemeButton(action: onShowTheme)

                    Button { showingFilter = true } label: {
                        Image(systemName: hasActiveFilterOptions
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(hasActiveFilterOptions ? "적용된 기록 필터 변경" : "기록 필터")
                }
            }
            .sheet(isPresented: $showingFilter) {
                MobileArchiveFilterSheet(filter: $filter)
            }
        }
        .task {
            guard querySession == nil else { return }
            let session = ArchiveQuerySession(context: modelContext)
            querySession = session
            session.apply(filter, debounceSearch: false)
        }
        .onChange(of: filter) { oldFilter, newFilter in
            querySession?.apply(
                newFilter,
                debounceSearch: shouldDebounceSearch(
                    from: oldFilter,
                    to: newFilter
                )
            )
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { notification in
            guard let sourceContext = notification.object as? ModelContext,
                  sourceContext === modelContext else { return }
            querySession?.refreshPreservingDepth()
        }
    }

    private func shouldDebounceSearch(
        from oldFilter: ArchiveFilter,
        to newFilter: ArchiveFilter
    ) -> Bool {
        oldFilter.searchText != newFilter.searchText &&
            oldFilter.period == newFilter.period &&
            oldFilter.scope == newFilter.scope &&
            oldFilter.customStartDate == newFilter.customStartDate &&
            oldFilter.customEndDate == newFilter.customEndDate
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                filter.hasActiveCriteria ? "검색 결과 없음" : "보관된 기록 없음",
                systemImage: filter.hasActiveCriteria ? "magnifyingglass" : "book.pages",
                description: Text(filter.hasActiveCriteria
                    ? "기간, 키워드, 검색 대상을 조정해보세요."
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

                Button("모두 지우기") {
                    filter.period = .all
                    filter.scope = .all
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
