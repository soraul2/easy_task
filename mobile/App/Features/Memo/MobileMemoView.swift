#if os(iOS)
import PencilKit
import Observation
import PlanBaseCore
import SwiftData
import SwiftUI

@MainActor
@Observable
private final class MobileMemoRoute: Identifiable {
    let id = UUID()
    let session: MemoEditorSession
    var textSelection: TextSelection?
    var checklistItemID: UUID?
    var checklistSelections: [UUID: TextSelection] = [:]

    init(session: MemoEditorSession) {
        self.session = session
    }
}

struct MobileMemoView: View {
    @Environment(\.planBaseContentIsActive) private var contentIsActive
    @Environment(\.scenePhase) private var scenePhase
    var onShowTheme: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var querySession: MemoQuerySession?
    @State private var searchText = ""
    @State private var selection: MobileMemoRoute?
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var memoPendingDeletion: Memo?
    @State private var actionFailure: String?

    var body: some View {
        MobileAdaptiveSplitView(compactColumn: $compactColumn) {
            memoList
                .navigationTitle("메모")
                .searchable(text: $searchText, prompt: "글과 체크 항목 검색")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        MobileCloudKitSyncStatusButton(sheetTextSize: dynamicTypeSize)

                        MobileThemeButton(action: onShowTheme, minimumHitSize: 44)

                        Menu {
                            memoCreationActions
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("새 메모")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let actionFailure {
                        VStack(spacing: 8) {
                            MobileNoticeBanner(message: actionFailure, tone: .error)
                            Button("확인") { self.actionFailure = nil }
                                .buttonStyle(PlanBaseButtonStyle(.secondary))
                        }
                        .padding(16)
                        .background(AppTheme.background)
                    }
                }
        } detail: {
            NavigationStack {
                if let selection {
                    MobileMemoEditorView(
                        route: selection,
                        onClose: closeEditor,
                        onDeleted: {
                            self.selection = nil
                            compactColumn = .sidebar
                        }
                    )
                    .id(selection.id)
                } else {
                    ContentUnavailableView("메모 선택", systemImage: "note.text",
                        description: Text("목록에서 메모를 선택하거나 새 메모를 작성하세요."))
                }
            }
        }
        .refreshVisibleData(key: "memo", domains: .memos) {
            refreshQuery()
            selection?.session.refreshFromStore()
        }
        .onDisappear { querySession?.cancel() }
        .onChange(of: contentIsActive) { _, active in
            if active && scenePhase == .active { querySession?.refresh() } else { querySession?.cancel() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && contentIsActive { querySession?.refresh() } else { querySession?.cancel() }
        }
        .onChange(of: searchText) { _, newValue in
            querySession?.apply(query: newValue, debounce: true)
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
    var memoCreationActions: some View {
        ForEach(MemoEditorMode.creationOrder) { mode in
            Button {
                openMemo(nil, initialMode: mode)
            } label: {
                Label(mode.creationTitle, systemImage: mode.systemImage)
            }
            .accessibilityIdentifier("memo-create-\(mode.rawValue)")
        }
    }

    @ViewBuilder
    var memoList: some View {
        let memos = querySession?.memos ?? []
        if querySession?.isLoading == true, memos.isEmpty {
            ProgressView("메모 불러오는 중")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
        } else if memos.isEmpty, querySession?.errorMessage != nil {
            ContentUnavailableView {
                Label("메모를 불러오지 못했어요", systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
            } description: {
                Text("잠시 후 다시 시도해 주세요.")
            } actions: {
                Button("다시 시도") { querySession?.retry() }
                    .buttonStyle(PlanBaseButtonStyle(.primary))
                    .accessibilityIdentifier("memo-load-retry")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .accessibilityIdentifier("memo-load-error")
        } else if memos.isEmpty {
            ContentUnavailableView {
                Label {
                    Text(searchText.isEmpty ? "메모 없음" : "검색 결과 없음")
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: searchText.isEmpty ? "note.text" : "magnifyingglass")
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } description: {
                Text(searchText.isEmpty
                    ? "생각은 글로, 할 일은 체크리스트로 남겨보세요."
                    : "다른 검색어를 입력해 보세요.")
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } actions: {
                if searchText.isEmpty {
                    VStack(spacing: 12) {
                        Button {
                            openMemo(nil, initialMode: .text)
                        } label: {
                            Label("글 메모 만들기", systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PlanBaseButtonStyle(.primary))
                        .accessibilityIdentifier("memo-empty-create-text")

                        Button {
                            openMemo(nil, initialMode: .checklist)
                        } label: {
                            Label("체크리스트 만들기", systemImage: "checklist")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PlanBaseButtonStyle(.secondary))
                        .accessibilityIdentifier("memo-empty-create-checklist")
                    }
                    .frame(maxWidth: 280)
                } else {
                    Button("검색어 지우기") { searchText = "" }
                        .buttonStyle(PlanBaseButtonStyle(.secondary))
                        .accessibilityIdentifier("memo-clear-search")
                }
            }
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
        let summary = querySession?.summaries[memo.instanceID]
        let isSelected = selection?.session.memo?.id == memo.id
        let typeTitle = summary?.typeTitle ?? MemoRules.mode(for: memo).creationTitle
        return Button {
            openMemo(memo)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary?.systemImage ?? MemoRules.systemImage(for: memo))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected || memo.isPinned ? AppTheme.accent : AppTheme.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary?.title ?? MemoRules.displayTitle(for: memo))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)

                    let preview = summary?.preview ?? MemoRules.preview(for: memo.content)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    let metadataLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 8))
                    metadataLayout {
                        Text(typeTitle)
                            .font(.caption.weight(.medium))
                        Text(MemoRules.updatedAtText(memo.updatedAt))
                            .font(.caption2)
                    }
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize, let revision = summary?.drawingUpdatedAt {
                    MobileMemoThumbnail(memoID: memo.id, revision: revision)
                }
                if memo.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? AppTheme.selectedTab : AppTheme.panel)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                setPinned(!memo.isPinned, memo: memo)
            } label: {
                Label(memo.isPinned ? "고정 해제" : "고정", systemImage: "pin")
            }
            .tint(AppTheme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                memoPendingDeletion = memo
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .accessibilityLabel(summary?.title ?? MemoRules.displayTitle(for: memo))
        .accessibilityValue(memo.isPinned ? "\(typeTitle), 고정됨" : typeTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("두 번 탭하여 메모 열기")
    }

    func refreshQuery() {
        if querySession == nil {
            #if DEBUG
            if PlanBaseLaunchEnvironment.isUITesting,
               ProcessInfo.processInfo.arguments.contains("--ui-testing-memo-load-failure-once") {
                var shouldFail = true
                querySession = MemoQuerySession(context: modelContext) { context, query, cursor in
                    if shouldFail {
                        shouldFail = false
                        throw NSError(domain: "PlanBase.UIFixture", code: 1)
                    }
                    return try MemoService.page(in: context, query: query, cursor: cursor)
                }
            } else {
                querySession = MemoQuerySession(context: modelContext, cooperative: true)
            }
            #else
            querySession = MemoQuerySession(context: modelContext, cooperative: true)
            #endif
        }
        // Search changes are applied by onChange. Refresh preserves loaded pages
        // and also consumes a pending search when returning from another tab.
        querySession?.refresh()
    }

    func openMemo(_ memo: Memo?, initialMode: MemoEditorMode = .text) {
        if let current = selection {
            if let memo, current.session.memo?.id == memo.id {
                compactColumn = .detail
                return
            }
            guard !current.session.hasUnsavedChanges || current.session.flush() else { return }
        }
        selection = MobileMemoRoute(session: makeEditorSession(memo: memo, initialMode: initialMode))
        compactColumn = .detail
    }

    func closeEditor() {
        guard let current = selection,
              !current.session.hasUnsavedChanges || current.session.flush() else { return }
        compactColumn = .sidebar
        selection = nil
    }

    func makeEditorSession(memo: Memo?, initialMode: MemoEditorMode) -> MemoEditorSession {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"),
           (arguments.contains("--ui-testing-memo-save-failure-once") ||
            arguments.contains("--ui-testing-memo-save-failure-twice")) {
            return MemoEditorSession(
                memo: memo,
                context: modelContext,
                initialMode: initialMode,
                saveComposite: { memo, content, mode, _, checklist, context in
                    if MobileMemoEditorUITestFixture.consumeSaveFailure(
                        limit: arguments.contains("--ui-testing-memo-save-failure-twice") ? 2 : 1
                    ) {
                        throw NSError(domain: "PlanBase.UIFixture", code: 2)
                    }
                    return try MemoService.savePreservingDrawing(
                        memo: memo,
                        content: content,
                        preferredMode: mode,
                        checklistDrafts: checklist,
                        in: context
                    )
                }
            )
        }
        if arguments.contains("--ui-testing"),
           arguments.contains("--ui-testing-memo-content-load-failure-once") {
            return MemoEditorSession(memo: memo, context: modelContext, initialMode: initialMode, loadContent: { id, context in
                let drawing = try MemoDrawingService.data(for: id, in: context)
                if MobileMemoEditorUITestFixture.consumeLoadFailure() {
                    throw NSError(domain: "PlanBase.UIFixture", code: 3)
                }
                return (drawing, try MemoChecklistService.drafts(for: id, in: context))
            })
        }
        #endif
        return MemoEditorSession(memo: memo, context: modelContext, initialMode: initialMode)
    }

    func setPinned(_ isPinned: Bool, memo: Memo) {
        do {
            try MemoService.setPinned(isPinned, for: memo, in: modelContext)
            actionFailure = nil
        } catch {
            actionFailure = "메모 고정을 변경하지 못했어요. 다시 시도해 주세요."
        }
    }

    func deleteMemo(_ memo: Memo) {
        defer { memoPendingDeletion = nil }
        do {
            if selection?.session.memo?.id == memo.id,
               selection?.session.hasUnsavedChanges == true,
               selection?.session.flush() != true { return }
            try MemoService.delete(memo, in: modelContext)
            if selection?.session.memo?.id == memo.id {
                selection = nil
                compactColumn = .sidebar
            }
            actionFailure = nil
        } catch {
            actionFailure = "메모를 삭제하지 못했어요. 내용은 그대로 유지됩니다."
        }
    }
}

private struct MobileMemoEditorView: View {
    @Bindable var route: MobileMemoRoute
    var onClose: () -> Void
    var onDeleted: () -> Void

    private var editorSession: MemoEditorSession { route.session }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingDeleteConfirmation = false
    @State private var deletionFailure: String?
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if editorSession.availableModes.count > 1 {
                Picker("편집 방식", selection: Binding(
                    get: { editorSession.preferredMode },
                    set: { mode in
                        editorSession.updatePreferredMode(mode)
                        editorFocused = mode == .text
                        if mode != .checklist { route.checklistItemID = nil }
                    }
                )) {
                    ForEach(editorSession.availableModes) { mode in
                        Label(mode == .drawing ? "이전 필기" : mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .planBaseAdaptiveSegmentedPicker()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityLabel("메모 편집 방식")
                .accessibilityIdentifier("memo-editor-mode")
                .disabled(editorSession.loadErrorMessage != nil)

                Divider()

            }

            mobileEditorContent(editorSession)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 7) {
                saveStateIcon(editorSession.saveState)
                Text(saveStateText(editorSession.saveState))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("memo-save-state")
                Spacer()
            }
            .foregroundStyle(saveStateColor(editorSession.saveState))
            .frame(minHeight: 38)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            if let deletionFailure {
                MobileNoticeBanner(message: deletionFailure, tone: .error)
                    .padding(.horizontal, 16)
                Button("확인") { self.deletionFailure = nil }
                    .buttonStyle(PlanBaseButtonStyle(.secondary))
                    .padding(.bottom, 8)
            }
        }
        .background(AppTheme.panel)
        .navigationTitle(editorSession.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    guard !editorSession.hasUnsavedChanges || editorSession.flush() else { return }
                    onClose()
                } label: {
                    Label("메모", systemImage: "chevron.backward")
                }
                .accessibilityIdentifier("memo-editor-back")
            }
            if case .failed = editorSession.saveState {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        editorSession.flush()
                    } label: {
                        Label("다시 시도", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("다시 시도")
                    .accessibilityIdentifier("memo-save-retry")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if editorSession.canChooseType {
                    Menu {
                        ForEach(MemoEditorMode.creationOrder) { mode in
                            Button {
                                editorSession.updatePreferredMode(mode)
                                editorFocused = mode == .text
                                route.checklistItemID = nil
                            } label: {
                                Label(mode.creationTitle, systemImage: mode.systemImage)
                            }
                            .accessibilityIdentifier("memo-change-type-\(mode.rawValue)")
                        }
                    } label: {
                        Label("유형 변경", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityIdentifier("memo-change-type")
                }
                Button {
                    editorSession.setPinned(!editorSession.isPinned)
                } label: {
                    Image(systemName: editorSession.isPinned ? "pin.fill" : "pin")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(editorSession.memo == nil || editorSession.loadErrorMessage != nil)
                .accessibilityLabel(editorSession.isPinned ? "고정 해제" : "상단에 고정")

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(editorSession.memo == nil || editorSession.loadErrorMessage != nil)
                .accessibilityLabel("메모 삭제")
            }
            ToolbarItemGroup(placement: .keyboard) {
                if editorSession.preferredMode == .text {
                    Spacer()
                    Button("완료") { editorFocused = false }
                        .accessibilityLabel("키보드 닫기")
                        .accessibilityIdentifier("memo-text-keyboard-dismiss")
                }
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
        .onAppear {
            // NavigationSplitView can reattach the editor when its columns
            // collapse. Restore input using the route's retained selection.
            editorFocused = editorSession.preferredMode == .text
        }
        .task(id: horizontalSizeClass) {
            // The split view reparents its UIKit text view after the trait
            // update. Apply focus after SwiftUI has installed the new column.
            guard editorSession.preferredMode == .text else { return }
            editorFocused = false
            await _Concurrency.Task.yield()
            guard !_Concurrency.Task.isCancelled else { return }
            editorFocused = true
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue != .active else { return }
            editorSession.flush()
        }
        .onDisappear {
            editorSession.flush()
        }
    }

    @ViewBuilder
    private func mobileEditorContent(_ session: MemoEditorSession) -> some View {
        if let message = session.loadErrorMessage {
            ContentUnavailableView {
                Label("메모를 불러오지 못했어요", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("다시 시도") { session.retryLoad() }
                    .buttonStyle(PlanBaseButtonStyle(.primary))
                    .accessibilityIdentifier("memo-content-load-retry")
            }
        } else {
            loadedMobileEditorContent(session)
        }
    }

    @ViewBuilder
    private func loadedMobileEditorContent(_ session: MemoEditorSession) -> some View {
        switch session.preferredMode {
        case .text:
            TextEditor(text: Binding(
                get: { session.content },
                set: { session.updateContent($0) }
            ), selection: $route.textSelection)
            .font(.body)
            .scrollContentBackground(.hidden)
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .focused($editorFocused)
            .accessibilityLabel("메모 내용")
            .overlay(alignment: .topLeading) {
                if session.content.isEmpty {
                    Text("첫 줄은 제목이 됩니다.\n생각을 자유롭게 적어보세요.")
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 17).padding(.top, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

        case .drawing:
            MobileMemoLegacyDrawingPreview(data: session.drawingData)
                .padding(16)

        case .checklist:
            MobileMemoChecklistEditor(
                session: session,
                editingItemID: $route.checklistItemID,
                textSelections: $route.checklistSelections
            )
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
                .foregroundStyle(.red)
        }
    }

    private func saveStateColor(_ state: MemoSaveState) -> Color {
        switch state {
        case .failed:
            AppTheme.primaryText
        default:
            AppTheme.secondaryText
        }
    }

    private func saveStateText(_ state: MemoSaveState) -> String {
        if case .failed = state {
            return "저장 실패 · 내용은 화면에 남아 있어요."
        }
        if editorSession.isReadOnly { return "이전 필기 · 읽기 전용" }
        if case .idle = state { return "내용을 입력하면 자동으로 저장돼요." }
        if case .saved = state { return "자동 저장됨" }
        return state.title
    }

    private func deleteMemo(_ session: MemoEditorSession) {
        do {
            try session.delete()
            onDeleted()
        } catch {
            deletionFailure = "메모를 삭제하지 못했어요. 내용은 그대로 유지됩니다."
        }
    }
}

#if DEBUG
@MainActor
private enum MobileMemoEditorUITestFixture {
    private static var saveFailures = 0
    private static var didFailLoad = false

    static func consumeSaveFailure(limit: Int) -> Bool {
        guard saveFailures < limit else { return false }
        saveFailures += 1
        return true
    }

    static func consumeLoadFailure() -> Bool {
        guard !didFailLoad else { return false }
        didFailLoad = true
        return true
    }
}
#endif

/// Render only a visible row's canvas, at a bounded thumbnail size.
private struct MobileMemoThumbnail: View {
    let memoID: UUID
    let revision: Date
    @Environment(\.modelContext) private var modelContext
    @State private var preview: UIImage?

    var body: some View {
        Group {
            if let preview {
                Image(uiImage: preview).resizable().scaledToFit()
            } else {
                Image(systemName: "pencil.tip").foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(width: 76, height: 60)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: revision) {
            preview = nil
            guard let data = try? MemoDrawingService.data(for: memoID, in: modelContext),
                  let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return }
            let bounds = drawing.bounds.insetBy(dx: -8, dy: -8)
            guard let scale = MemoDrawingPreviewRules.scale(width: bounds.width, height: bounds.height) else { return }
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                preview = drawing.image(from: bounds, scale: min(scale, 240 / max(bounds.width, bounds.height)))
            }
        }
    }
}

/// Existing PencilKit content stays visible without a drawing editor or tool picker.
private struct MobileMemoLegacyDrawingPreview: View {
    let data: Data
    @State private var preview: UIImage?
    @State private var hasLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("이전 필기", systemImage: "doc.text.image")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Text("이전에 작성한 필기입니다. 보기만 할 수 있어요.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if let preview {
                    GeometryReader { geometry in
                        ScrollView {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(width: max(geometry.size.width - 32, 1))
                                .padding(16)
                                .accessibilityLabel("이전에 작성한 필기")
                                .accessibilityIdentifier("memo-legacy-drawing-image")
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                    .accessibilityLabel("이전에 작성한 필기 미리보기")
                } else if !hasLoaded {
                    ProgressView("필기 불러오는 중")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        data.isEmpty ? "저장된 필기가 없습니다" : "필기를 표시할 수 없어요",
                        systemImage: "doc.text.image",
                        description: Text(data.isEmpty
                            ? "글 메모나 체크리스트를 새로 만들어보세요."
                            : "기존 필기는 그대로 보관됩니다.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("memo-legacy-drawing-preview")
        .task(id: data) {
            preview = nil
            hasLoaded = false
            defer { hasLoaded = true }
            guard !data.isEmpty,
                  let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return }
            let bounds = drawing.bounds.insetBy(dx: -12, dy: -12)
            guard let scale = MemoDrawingPreviewRules.scale(width: bounds.width, height: bounds.height) else { return }
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                preview = drawing.image(from: bounds, scale: scale)
            }
        }
    }
}

private struct MobileMemoChecklistEditor: View {
    var session: MemoEditorSession
    @Binding var editingItemID: UUID?
    @Binding var textSelections: [UUID: TextSelection]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FocusState private var focusedItemID: UUID?
    @State private var pendingFocusItemID: UUID?
    @State private var isRestoringFocus = false

    var body: some View {
        ScrollView {
            // Every editable field stays installed while focus and keyboard geometry change.
            VStack(spacing: 10) {
                if session.checklistDrafts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("할 일을 하나씩 정리해보세요")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText)
                        Text("항목을 추가하고, 마친 일은 체크하세요.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } else {
                    checklistProgress
                }

                ForEach(session.checklistDrafts) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Button {
                            session.toggleChecklistItem(id: item.id)
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(item.isCompleted
                                    ? AppTheme.accent
                                    : AppTheme.secondaryText)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.title.isEmpty ? "빈 항목" : item.title) \(item.isCompleted ? "완료 해제" : "완료")")

                        TextField("체크 항목", text: Binding(
                            get: { item.title },
                            set: { session.updateChecklistTitle(id: item.id, title: $0) }
                        ), selection: Binding(
                            get: { textSelections[item.id] },
                            set: { textSelections[item.id] = $0 }
                        ), axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($focusedItemID, equals: item.id)
                        .accessibilityIdentifier("memo-checklist-title")
                        .fixedSize(horizontal: false, vertical: true)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted
                            ? AppTheme.secondaryText
                            : AppTheme.primaryText)
                        .submitLabel(.next)
                        .onSubmit {
                            appendAndFocusItem()
                        }

                        Menu {
                            Button("위로 이동", systemImage: "arrow.up") { moveItem(item.id, down: false) }
                                .disabled(session.checklistDrafts.first?.id == item.id)
                            Button("아래로 이동", systemImage: "arrow.down") { moveItem(item.id, down: true) }
                                .disabled(session.checklistDrafts.last?.id == item.id)
                            Divider()
                            Button("항목 삭제", systemImage: "trash", role: .destructive) {
                                removeItem(item.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("\(item.title.isEmpty ? "빈 항목" : item.title) 항목 관리")
                        .accessibilityIdentifier("memo-checklist-actions")
                    }
                    .padding(.horizontal, 10)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 10))
                    .id(item.id)
                    .task(id: pendingFocusItemID) {
                        // Apply focus after the new text field has joined the view hierarchy.
                        guard pendingFocusItemID == item.id else { return }
                        await _Concurrency.Task.yield()
                        guard !_Concurrency.Task.isCancelled,
                              pendingFocusItemID == item.id,
                              editingItemID == item.id else { return }
                        focusedItemID = item.id
                        pendingFocusItemID = nil
                    }
                }

                Button {
                    appendAndFocusItem()
                } label: {
                    Label("항목 추가", systemImage: "plus.circle.fill")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .accessibilityIdentifier("memo-checklist-add")
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityLabel("메모 체크리스트")
        .onScrollPhaseChange { oldPhase, newPhase in
            // Only a user scroll dismissal clears the route's editing target.
            // Keyboard geometry changes and split-view reparenting can temporarily resign focus.
            if (oldPhase == .interacting || oldPhase == .decelerating),
               newPhase == .idle, focusedItemID == nil,
               pendingFocusItemID == nil, !isRestoringFocus {
                editingItemID = nil
            }
        }
        .task(id: horizontalSizeClass) {
            // Restore the same field and selection after split-view reparenting.
            guard let itemID = editingItemID, pendingFocusItemID == nil else { return }
            isRestoringFocus = true
            defer { isRestoringFocus = false }
            focusedItemID = nil
            await _Concurrency.Task.yield()
            guard !_Concurrency.Task.isCancelled,
                  editingItemID == itemID, pendingFocusItemID == nil else { return }
            focusedItemID = itemID
        }
        .onChange(of: focusedItemID) { _, itemID in
            // A detached text field resigns focus before its replacement exists.
            // Only an explicit dismissal clears the route's editing target.
            if let itemID { editingItemID = itemID }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") {
                    pendingFocusItemID = nil
                    editingItemID = nil
                    focusedItemID = nil
                }
                    .accessibilityIdentifier("memo-checklist-keyboard-dismiss")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var checklistProgress: some View {
        let progress = session.checklistProgress
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(progress.completedCount)/\(progress.totalCount) 완료")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if progress.totalCount > 0, progress.completedCount == progress.totalCount {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("모두 완료")
                }
            }
            .foregroundStyle(AppTheme.primaryText)

            ProgressView(value: Double(progress.completedCount), total: Double(max(progress.totalCount, 1)))
                .tint(AppTheme.accent)
                .accessibilityLabel("체크리스트 진행률")
                .accessibilityValue("\(progress.totalCount)개 중 \(progress.completedCount)개 완료")
        }
        .padding(.bottom, 8)
    }

    private func removeItem(_ id: UUID) {
        if pendingFocusItemID == id { pendingFocusItemID = nil }
        if editingItemID == id {
            editingItemID = nil
            focusedItemID = nil
        }
        textSelections[id] = nil
        session.removeChecklistItem(id: id)
    }

    private func moveItem(_ id: UUID, down: Bool) {
        guard let index = session.checklistDrafts.firstIndex(where: { $0.id == id }) else { return }
        session.moveChecklistItems(fromOffsets: IndexSet(integer: index), toOffset: down ? index + 2 : index - 1)
    }

    private func appendAndFocusItem() {
        if let emptyItem = session.checklistDrafts.last, MemoRules.isBlank(emptyItem.title) {
            editingItemID = emptyItem.id
        } else {
            session.appendChecklistItem()
            editingItemID = session.checklistDrafts.last?.id
        }
        focusedItemID = nil
        pendingFocusItemID = editingItemID
    }
}
#endif
