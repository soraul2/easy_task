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
                if querySession?.isLoading == true && records.isEmpty {
                    ProgressView("기록 불러오는 중")
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
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
#endif
