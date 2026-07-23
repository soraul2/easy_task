#if os(iOS)
import PlanBaseCore
import SwiftData
import SwiftUI

private struct MobileMemoRoute: Hashable {
    var id = UUID()
    var memoInstanceID: UUID?
}

struct MobileMemoView: View {
    var onShowTheme: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var querySession: MemoQuerySession?
    @State private var searchText = ""
    @State private var path: [MobileMemoRoute] = []
    @State private var memoPendingDeletion: Memo?

    var body: some View {
        NavigationStack(path: $path) {
            memoList
                .navigationTitle("메모")
                .searchable(text: $searchText, prompt: "메모 검색")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        MobileThemeButton(action: onShowTheme, minimumHitSize: 44)

                        Button {
                            path.append(MobileMemoRoute(memoInstanceID: nil))
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("새 메모")
                    }
                }
                .navigationDestination(for: MobileMemoRoute.self) { route in
                    MobileMemoEditorView(
                        memo: memo(for: route.memoInstanceID),
                        onDeleted: {
                            if !path.isEmpty { path.removeLast() }
                        }
                    )
                    .id(route.id)
                }
        }
        .task {
            startQueryIfNeeded()
        }
        .onChange(of: searchText) { _, newValue in
            querySession?.apply(query: newValue, debounce: true)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { notification in
            guard let sourceContext = notification.object as? ModelContext,
                  sourceContext === modelContext else { return }
            querySession?.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: CloudKitSyncService.eventChangedNotification
        )) { notification in
            guard let summary = CloudKitSyncService.summary(from: notification),
                  summary.kind == .import,
                  summary.isCompleted,
                  summary.succeeded else { return }
            querySession?.refresh()
        }
        .alert(
            "메모 삭제",
            isPresented: Binding(
                get: { memoPendingDeletion != nil },
                set: { if !$0 { memoPendingDeletion = nil } }
            ),
            presenting: memoPendingDeletion
        ) { memo in
            Button("삭제", role: .destructive) {
                deleteMemo(memo)
            }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("삭제한 메모는 복구할 수 없습니다.")
        }
    }
}

private extension MobileMemoView {
    @ViewBuilder
    var memoList: some View {
        let memos = querySession?.memos ?? []
        if querySession?.isLoading == true, memos.isEmpty {
            ProgressView("메모 불러오는 중")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
        } else if memos.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "메모 없음" : "검색 결과 없음",
                systemImage: searchText.isEmpty ? "note.text" : "magnifyingglass",
                description: Text(searchText.isEmpty
                    ? "오른쪽 위 작성 버튼으로 메모를 추가하세요."
                    : "다른 검색어를 입력해 보세요.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
        } else {
            List {
                let pinned = memos.filter(\.isPinned)
                let regular = memos.filter { !$0.isPinned }

                if !pinned.isEmpty {
                    Section("고정됨") {
                        ForEach(pinned) { memo in
                            memoRow(memo)
                        }
                    }
                }

                if !regular.isEmpty {
                    Section(pinned.isEmpty ? "메모" : "전체 메모") {
                        ForEach(regular) { memo in
                            memoRow(memo)
                        }
                    }
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
                                Label("메모 더 보기", systemImage: "chevron.down")
                            }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(querySession?.isLoading == true)
                }

                if let errorMessage = querySession?.errorMessage {
                    VStack(spacing: 10) {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryText)
                        Button("다시 시도") {
                            querySession?.retry()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: MobileLayout.bottomTabClearance)
            }
        }
    }

    func memoRow(_ memo: Memo) -> some View {
        Button {
            path.append(MobileMemoRoute(memoInstanceID: memo.instanceID))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: memo.isPinned ? "pin.fill" : "note.text")
                    .foregroundStyle(memo.isPinned ? AppTheme.event : AppTheme.secondaryText)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 5) {
                    Text(MemoRules.displayTitle(for: memo.content))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)

                    let preview = MemoRules.preview(for: memo.content)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                    }

                    Text(memo.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(AppTheme.panel)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                setPinned(!memo.isPinned, memo: memo)
            } label: {
                Label(memo.isPinned ? "고정 해제" : "고정", systemImage: "pin")
            }
            .tint(AppTheme.event)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                memoPendingDeletion = memo
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .accessibilityLabel(MemoRules.displayTitle(for: memo.content))
        .accessibilityHint("두 번 탭하여 메모 편집")
    }

    func startQueryIfNeeded() {
        guard querySession == nil else { return }
        let session = MemoQuerySession(context: modelContext)
        querySession = session
        session.apply(query: searchText, debounce: false)
    }

    func memo(for instanceID: UUID?) -> Memo? {
        guard let instanceID else { return nil }
        return querySession?.memos.first { $0.instanceID == instanceID }
    }

    func setPinned(_ isPinned: Bool, memo: Memo) {
        try? MemoService.setPinned(isPinned, for: memo, in: modelContext)
    }

    func deleteMemo(_ memo: Memo) {
        defer { memoPendingDeletion = nil }
        try? MemoService.delete(memo, in: modelContext)
    }
}

private struct MobileMemoEditorView: View {
    var memo: Memo?
    var onDeleted: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var editorSession: MemoEditorSession?
    @State private var showingDeleteConfirmation = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        Group {
            if let editorSession {
                VStack(spacing: 0) {
                    TextEditor(text: Binding(
                        get: { editorSession.content },
                        set: { editorSession.updateContent($0) }
                    ))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .focused($editorFocused)
                    .accessibilityLabel("메모 내용")

                    HStack(spacing: 7) {
                        saveStateIcon(editorSession.saveState)
                        Text(editorSession.saveState.title)
                            .font(.caption)
                        Spacer()
                    }
                    .foregroundStyle(saveStateColor(editorSession.saveState))
                    .frame(height: 38)
                    .padding(.horizontal, 16)
                }
                .background(AppTheme.panel)
                .navigationTitle(MemoRules.displayTitle(for: editorSession.content))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            editorSession.setPinned(!editorSession.isPinned)
                        } label: {
                            Image(systemName: editorSession.isPinned ? "pin.fill" : "pin")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .disabled(editorSession.memo == nil)
                        .accessibilityLabel(editorSession.isPinned ? "고정 해제" : "상단에 고정")

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .disabled(editorSession.memo == nil)
                        .accessibilityLabel("메모 삭제")
                    }
                }
                .alert("메모 삭제", isPresented: $showingDeleteConfirmation) {
                    Button("삭제", role: .destructive) {
                        deleteMemo(editorSession)
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("삭제한 메모는 복구할 수 없습니다.")
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.panel)
            }
        }
        .task {
            guard editorSession == nil else { return }
            editorSession = MemoEditorSession(memo: memo, context: modelContext)
            editorFocused = true
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue != .active else { return }
            editorSession?.flush()
        }
        .onDisappear {
            editorSession?.flush()
        }
    }

    @ViewBuilder
    private func saveStateIcon(_ state: MemoSaveState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView()
                .controlSize(.small)
        case .saved:
            Image(systemName: "checkmark.circle")
        case .failed:
            Image(systemName: "exclamationmark.triangle")
        }
    }

    private func saveStateColor(_ state: MemoSaveState) -> Color {
        switch state {
        case .failed:
            .red
        default:
            AppTheme.secondaryText
        }
    }

    private func deleteMemo(_ session: MemoEditorSession) {
        do {
            try session.delete()
            onDeleted()
        } catch {
            // The editor stays open with its current content after rollback.
        }
    }
}
#endif
