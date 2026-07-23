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
                Text("날짜별 회고와 그날 한 일을 함께 봅니다.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

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
            Text(filter.hasActiveCriteria ? "기간, 키워드, 검색 대상을 조정해보세요." : "완료한 작업이나 회고를 작성하면 이곳에 표시됩니다.")
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
            oldFilter.customStartDate == newFilter.customStartDate &&
            oldFilter.customEndDate == newFilter.customEndDate
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
