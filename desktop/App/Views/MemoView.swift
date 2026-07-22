import EasyTaskCore
import SwiftData
import SwiftUI

struct MemoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var querySession: MemoQuerySession?
    @State private var editorSession: MemoEditorSession?
    @State private var searchText = ""
    @State private var memoPendingDeletion: Memo?
    @FocusState private var editorFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 260, idealWidth: 310, maxWidth: 360)

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1)

            editor
        }
        .background(AppTheme.background)
        .task {
            startQueryIfNeeded()
        }
        .onChange(of: searchText) { _, newValue in
            querySession?.apply(query: newValue, debounce: true)
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue != .active else { return }
            editorSession?.flush()
        }
        .onDisappear {
            editorSession?.flush()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { _ in
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

private extension MemoView {
    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("메모")
                    .font(.title2.bold())
                Spacer()
                Button(action: createMemo) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.primaryText)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 7))
                .help("새 메모")
                .accessibilityLabel("새 메모")
            }
            .padding(16)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.secondaryText)
                TextField("메모 검색", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)

            memoList
        }
        .background(AppTheme.panel)
    }

    @ViewBuilder
    var memoList: some View {
        if let querySession {
            if querySession.memos.isEmpty, querySession.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if querySession.memos.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: searchText.isEmpty ? "note.text" : "magnifyingglass")
                        .font(.system(size: 28))
                    Text(searchText.isEmpty ? "새 메모를 작성해 보세요" : "검색 결과가 없습니다")
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(AppTheme.secondaryText)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        let pinned = querySession.memos.filter(\.isPinned)
                        let regular = querySession.memos.filter { !$0.isPinned }

                        if !pinned.isEmpty {
                            sectionLabel("고정됨")
                            ForEach(pinned) { memo in
                                memoRow(memo)
                            }
                        }
                        if !regular.isEmpty {
                            sectionLabel(pinned.isEmpty ? "메모" : "전체 메모")
                            ForEach(regular) { memo in
                                memoRow(memo)
                            }
                        }

                        if querySession.hasMore {
                            ProgressView()
                                .padding(12)
                                .onAppear {
                                    querySession.loadNextPage()
                                }
                        }
                    }
                    .padding(10)
                }
            }

            if let errorMessage = querySession.errorMessage {
                HStack {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                    Spacer()
                    Button("다시 시도") {
                        querySession.retry()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
            }
        }
    }

    func sectionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
    }

    func memoRow(_ memo: Memo) -> some View {
        let isSelected = editorSession?.memo?.instanceID == memo.instanceID
        return Button {
            openMemo(memo)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: memo.isPinned ? "pin.fill" : "note.text")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(memo.isPinned ? AppTheme.event : AppTheme.secondaryText)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 5) {
                    Text(MemoRules.displayTitle(for: memo.content))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)

                    let preview = MemoRules.preview(for: memo.content)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                    }

                    Text(memo.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                isSelected ? AppTheme.selectedTab.opacity(0.72) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                setPinned(!memo.isPinned, memo: memo)
            } label: {
                Label(memo.isPinned ? "고정 해제" : "상단에 고정", systemImage: "pin")
            }
            Divider()
            Button(role: .destructive) {
                memoPendingDeletion = memo
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .accessibilityLabel(MemoRules.displayTitle(for: memo.content))
    }

    @ViewBuilder
    var editor: some View {
        if let editorSession {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MemoRules.displayTitle(for: editorSession.content))
                            .font(.title3.bold())
                            .lineLimit(1)
                        Text(editorSession.memo?.updatedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        ) ?? "새 메모")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Spacer()

                    Button {
                        editorSession.setPinned(!editorSession.isPinned)
                    } label: {
                        Image(systemName: editorSession.isPinned ? "pin.fill" : "pin")
                            .frame(width: 34, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(editorSession.memo == nil)
                    .help(editorSession.isPinned ? "고정 해제" : "상단에 고정")

                    Button {
                        memoPendingDeletion = editorSession.memo
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 34, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(editorSession.memo == nil)
                    .help("메모 삭제")
                }
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)

                TextEditor(text: Binding(
                    get: { editorSession.content },
                    set: { editorSession.updateContent($0) }
                ))
                .font(.body)
                .scrollContentBackground(.hidden)
                .foregroundStyle(AppTheme.primaryText)
                .padding(16)
                .focused($editorFocused)
                .accessibilityLabel("메모 내용")

                HStack(spacing: 7) {
                    saveStateIcon(editorSession.saveState)
                    Text(editorSession.saveState.title)
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(saveStateColor(editorSession.saveState))
                .frame(height: 34)
                .padding(.horizontal, 20)
            }
            .background(AppTheme.panel)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "note.text")
                    .font(.system(size: 36))
                Text("메모를 선택하거나 새로 작성하세요")
                    .font(.headline)
            }
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.panel)
        }
    }

    @ViewBuilder
    func saveStateIcon(_ state: MemoSaveState) -> some View {
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

    func saveStateColor(_ state: MemoSaveState) -> Color {
        switch state {
        case .failed:
            .red
        default:
            AppTheme.secondaryText
        }
    }

    func startQueryIfNeeded() {
        guard querySession == nil else { return }
        let session = MemoQuerySession(context: modelContext)
        querySession = session
        session.apply(query: searchText, debounce: false)
    }

    func createMemo() {
        editorSession?.flush()
        editorSession = MemoEditorSession(memo: nil, context: modelContext)
        Swift.Task { @MainActor in
            editorFocused = true
        }
    }

    func openMemo(_ memo: Memo) {
        guard editorSession?.memo?.instanceID != memo.instanceID else { return }
        editorSession?.flush()
        editorSession = MemoEditorSession(memo: memo, context: modelContext)
        editorFocused = true
    }

    func setPinned(_ isPinned: Bool, memo: Memo) {
        do {
            try MemoService.setPinned(isPinned, for: memo, in: modelContext)
        } catch {
            // The query session displays the persisted state and will remain unchanged.
        }
    }

    func deleteMemo(_ memo: Memo) {
        defer { memoPendingDeletion = nil }
        do {
            if editorSession?.memo?.instanceID == memo.instanceID {
                try editorSession?.delete()
                editorSession = nil
            } else {
                try MemoService.delete(memo, in: modelContext)
            }
        } catch {
            // The memo remains visible when the command rolls back.
        }
    }
}
