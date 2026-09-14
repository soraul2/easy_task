import PencilKit
import PlanBaseCore
import SwiftData
import SwiftUI

struct MemoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var querySession: MemoQuerySession?
    @Binding var editorSession: MemoEditorSession?
    @State private var searchText = ""
    @State private var memoPendingDeletion: Memo?
    @State private var actionFailure: String?
    @State private var showingClearDrawingConfirmation = false
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
        .persistenceFailureAlert(message: $actionFailure)
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
            // Release saved snapshots so returning to this tab reads current data.
            // Only a failed draft stays owned by the root until it can be saved.
            if let editorSession,
               !editorSession.hasUnsavedChanges || editorSession.flush() {
                self.editorSession = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { notification in
            guard PersistenceCommandService.affects(.memos, in: notification) else { return }
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
            } else if querySession.memos.isEmpty, let errorMessage = querySession.errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Label("메모를 불러오지 못했어요", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(errorMessage).font(.callout).foregroundStyle(AppTheme.secondaryText)
                    Button("다시 시도") { querySession.retry() }
                        .buttonStyle(PlanBaseButtonStyle(.primary))
                }
                .multilineTextAlignment(.center)
                .padding(16)
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

            if !querySession.memos.isEmpty, let errorMessage = querySession.errorMessage {
                HStack {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.primaryText)
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
                Image(systemName: MemoRules.systemImage(for: memo))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(memo.isPinned ? AppTheme.accent : AppTheme.secondaryText)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 5) {
                    Text(MemoRules.displayTitle(for: memo))
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

                    Text(MemoRules.updatedAtText(memo.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 0)
                if memo.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)
                }
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
        .accessibilityLabel(MemoRules.displayTitle(for: memo))
    }

    @ViewBuilder
    var editor: some View {
        if let editorSession {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(editorSession.displayTitle)
                            .font(.title3.bold())
                            .lineLimit(1)
                        Text(editorSession.memo.map { MemoRules.updatedAtText($0.updatedAt) } ?? "새 메모")
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
                    .disabled(editorSession.memo == nil || editorSession.loadErrorMessage != nil)
                    .help(editorSession.isPinned ? "고정 해제" : "상단에 고정")

                    Button {
                        memoPendingDeletion = editorSession.memo
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 34, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(editorSession.memo == nil || editorSession.loadErrorMessage != nil)
                    .help("메모 삭제")
                }
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)

                Picker("편집 방식", selection: Binding(
                    get: { editorSession.preferredMode },
                    set: { mode in
                        editorSession.updatePreferredMode(mode)
                        editorFocused = mode == .text
                    }
                )) {
                    ForEach(MemoEditorMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 440)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityLabel("메모 편집 방식")
                .disabled(editorSession.loadErrorMessage != nil)

                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)

                desktopEditorContent(editorSession)

                HStack(spacing: 7) {
                    saveStateIcon(editorSession.saveState)
                    Text(editorSession.hasUnsavedChanges && editorSession.saveState != .saving
                         ? "저장 실패 · 내용은 화면에 남아 있어요." : editorSession.saveState.title)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if case .failed = editorSession.saveState {
                        Button("다시 시도") { editorSession.flush() }
                            .accessibilityIdentifier("memo-save-retry")
                    }
                }
                .foregroundStyle(saveStateColor(editorSession.saveState))
                .frame(minHeight: 34)
                .padding(.vertical, 6)
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
    func desktopEditorContent(_ session: MemoEditorSession) -> some View {
        if let message = session.loadErrorMessage {
            ContentUnavailableView {
                Label("메모를 불러오지 못했어요", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("다시 시도") { session.retryLoad() }
                    .accessibilityIdentifier("memo-content-load-retry")
            }
        } else {
            loadedDesktopEditorContent(session)
        }
    }

    @ViewBuilder
    func loadedDesktopEditorContent(_ session: MemoEditorSession) -> some View {
        switch session.preferredMode {
        case .text:
            TextEditor(text: Binding(
                get: { session.content },
                set: { session.updateContent($0) }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .foregroundStyle(AppTheme.primaryText)
            .padding(16)
            .focused($editorFocused)
            .accessibilityLabel("메모 내용")

        case .drawing:
            VStack(spacing: 14) {
                DesktopMemoDrawingPreview(data: session.drawingData)

                HStack {
                    Label("필기는 iPhone 또는 iPad에서 편집할 수 있습니다.", systemImage: "ipad.and.iphone")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Button("필기 지우기", role: .destructive) {
                        showingClearDrawingConfirmation = true
                    }
                    .disabled(session.drawingData.isEmpty)
                    .alert("필기를 모두 지울까요?", isPresented: $showingClearDrawingConfirmation) {
                        Button("필기 모두 지우기", role: .destructive) {
                            session.updateDrawingData(Data())
                        }
                        Button("취소", role: .cancel) {}
                    } message: {
                        Text("이 메모의 필기만 지워집니다. 텍스트와 체크리스트는 유지돼요.")
                    }
                }
            }
            .padding(18)

        case .checklist:
            ScrollView {
                LazyVStack(spacing: 9) {
                    if !session.checklistDrafts.isEmpty {
                        let progress = session.checklistProgress
                        HStack {
                            Text("\(progress.completedCount)/\(progress.totalCount) 완료")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                            Spacer()
                        }
                    }

                    ForEach(session.checklistDrafts) { item in
                        HStack(spacing: 10) {
                            Button {
                                session.toggleChecklistItem(id: item.id)
                            } label: {
                                Image(systemName: item.isCompleted
                                    ? "checkmark.circle.fill"
                                    : "circle")
                                    .font(.title3)
                                    .foregroundStyle(item.isCompleted
                                        ? AppTheme.accent
                                        : AppTheme.secondaryText)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.title.isEmpty ? "빈 항목" : item.title) \(item.isCompleted ? "완료 해제" : "완료")")

                            TextField("체크 항목", text: Binding(
                                get: { item.title },
                                set: { session.updateChecklistTitle(id: item.id, title: $0) }
                            ))
                            .textFieldStyle(.plain)
                            .strikethrough(item.isCompleted)
                            .foregroundStyle(item.isCompleted
                                ? AppTheme.secondaryText
                                : AppTheme.primaryText)
                            .onSubmit {
                                session.appendChecklistItem()
                            }

                            Button(role: .destructive) {
                                session.removeChecklistItem(id: item.id)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.title.isEmpty ? "빈 항목" : item.title) 항목 삭제")
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        session.appendChecklistItem()
                    } label: {
                        Label("항목 추가", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                }
                .padding(18)
            }
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
                .foregroundStyle(.red)
        }
    }

    func saveStateColor(_ state: MemoSaveState) -> Color {
        switch state {
        case .failed:
            AppTheme.primaryText
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
        if let editorSession, editorSession.hasUnsavedChanges, !editorSession.flush() { return }
        editorSession = makeEditorSession(memo: nil)
        Swift.Task { @MainActor in
            editorFocused = true
        }
    }

    func openMemo(_ memo: Memo) {
        guard editorSession?.memo?.instanceID != memo.instanceID else { return }
        if let editorSession, editorSession.hasUnsavedChanges, !editorSession.flush() { return }
        editorSession = makeEditorSession(memo: memo)
        editorFocused = true
    }

    func makeEditorSession(memo: Memo?) -> MemoEditorSession {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"),
           arguments.contains("--ui-testing-memo-save-failure-twice") {
            var remainingFailures = 2
            return MemoEditorSession(memo: memo, context: modelContext, saveComposite: {
                memo, content, mode, drawing, checklist, context in
                if remainingFailures > 0 {
                    remainingFailures -= 1
                    throw CocoaError(.fileWriteUnknown)
                }
                return try MemoService.saveComposite(memo: memo, content: content,
                    preferredMode: mode, drawingData: drawing, checklistDrafts: checklist, in: context)
            })
        }
#endif
        return MemoEditorSession(memo: memo, context: modelContext)
    }

    func setPinned(_ isPinned: Bool, memo: Memo) {
        do {
            try MemoService.setPinned(isPinned, for: memo, in: modelContext)
        } catch {
            actionFailure = "메모 고정을 변경하지 못했어요. 다시 시도해 주세요."
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
            actionFailure = "메모를 삭제하지 못했어요. 내용은 그대로 유지됩니다."
        }
    }
}

/// Keep rasterization outside body; unrelated save/pin/sidebar updates reuse the image.
private struct DesktopMemoDrawingPreview: View {
    let data: Data
    @State private var preview: NSImage?
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if let preview {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 900, maxHeight: 900)
                        .padding(24)
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1)
                }
            } else if !data.isEmpty, !hasLoaded {
                ProgressView("필기 미리보기 준비 중")
            } else {
                ContentUnavailableView(
                    data.isEmpty ? "아직 필기 내용이 없습니다" : "필기 미리보기를 표시하지 못했어요",
                    systemImage: "pencil.tip",
                    description: Text(data.isEmpty
                        ? "iPhone 또는 iPad에서 필기를 시작하세요."
                        : "원본 필기는 유지됩니다. iPhone 또는 iPad에서 확인해 주세요.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: data) {
            hasLoaded = false
            preview = nil
            defer { hasLoaded = true }
            guard !data.isEmpty, let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return }
            let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
            guard let scale = MemoDrawingPreviewRules.scale(width: bounds.width, height: bounds.height) else { return }
            preview = drawing.image(from: bounds, scale: scale)
        }
    }
}
