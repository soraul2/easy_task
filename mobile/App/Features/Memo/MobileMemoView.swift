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
                .searchable(text: $searchText, prompt: "메모 검색")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        MobileCloudKitSyncStatusButton(sheetTextSize: dynamicTypeSize)

                        MobileThemeButton(action: onShowTheme, minimumHitSize: 44)

                        Menu {
                            ForEach(MemoEditorMode.creationOrder) { mode in
                                Button {
                                    openMemo(nil, initialMode: mode)
                                } label: {
                                    Label(mode.creationTitle, systemImage: mode.systemImage)
                                }
                                .accessibilityIdentifier("memo-create-\(mode.rawValue)")
                            }
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
        .task {
            refreshQuery()
        }
        .onChange(of: searchText) { _, newValue in
            querySession?.apply(query: newValue, debounce: true)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { notification in
            guard PersistenceCommandService.affects(.memos, in: notification) else { return }
            guard let sourceContext = notification.object as? ModelContext,
                  sourceContext === modelContext else { return }
            querySession?.refresh()
            selection?.session.refreshFromStore()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: CloudKitSyncService.eventChangedNotification
        )) { notification in
            guard let summary = CloudKitSyncService.summary(from: notification),
                  summary.kind == .import,
                  summary.isCompleted,
                  summary.succeeded else { return }
            querySession?.refresh()
            selection?.session.refreshFromStore()
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
                    ? "새 메모 버튼으로 메모를 추가하세요."
                    : "다른 검색어를 입력해 보세요.")
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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
        return Button {
            openMemo(memo)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary?.systemImage ?? MemoRules.systemImage(for: memo))
                    .foregroundStyle(memo.isPinned ? AppTheme.accent : AppTheme.secondaryText)
                    .frame(width: 22, height: 22)

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

                    Text(MemoRules.updatedAtText(memo.updatedAt))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 0)
                if let revision = summary?.drawingUpdatedAt {
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
        .listRowBackground(selection?.session.memo?.id == memo.id ? AppTheme.selectedTab : AppTheme.panel)
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
        .accessibilityValue(summary?.typeTitle ?? MemoRules.mode(for: memo).creationTitle)
        .accessibilityHint("두 번 탭하여 메모 편집")
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
                querySession = MemoQuerySession(context: modelContext)
            }
            #else
            querySession = MemoQuerySession(context: modelContext)
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
                saveComposite: { memo, content, mode, drawing, checklist, context in
                    if MobileMemoEditorUITestFixture.consumeSaveFailure(
                        limit: arguments.contains("--ui-testing-memo-save-failure-twice") ? 2 : 1
                    ) {
                        throw NSError(domain: "PlanBase.UIFixture", code: 2)
                    }
                    return try MemoService.saveComposite(
                        memo: memo,
                        content: content,
                        preferredMode: mode,
                        drawingData: drawing,
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
    @State private var showingClearDrawingConfirmation = false
    @State private var deletionFailure: String?
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if editorSession.isComposite {
                Picker("편집 방식", selection: Binding(
                    get: { editorSession.preferredMode },
                    set: { mode in
                        editorSession.updatePreferredMode(mode)
                        editorFocused = mode == .text
                        if mode != .checklist { route.checklistItemID = nil }
                    }
                )) {
                    ForEach(MemoEditorMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
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

            HStack(spacing: 7) {
                saveStateIcon(editorSession.saveState)
                Text(saveStateText(editorSession.saveState))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("memo-save-state")
                Spacer()
                if case .failed = editorSession.saveState {
                    Button("다시 시도") {
                        editorSession.flush()
                    }
                    .buttonStyle(PlanBaseButtonStyle(.secondary))
                    .accessibilityIdentifier("memo-save-retry")
                }
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
                    Text("생각을 자유롭게 적어보세요.")
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 17).padding(.top, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

        case .drawing:
            VStack(spacing: 8) {
                MobileMemoDrawingCanvas(
                    drawingData: session.drawingData,
                    onDrawingChanged: session.updateDrawingData
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.border, lineWidth: 1)
                }

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Label("Apple Pencil 또는 손가락으로 작성", systemImage: "pencil.tip")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Button("모두 지우기", role: .destructive) {
                        showingClearDrawingConfirmation = true
                    }
                    .font(.caption)
                    .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
                    .disabled(session.drawingData.isEmpty)
                    .accessibilityIdentifier("memo-clear-drawing")
                    .alert("필기를 모두 지울까요?", isPresented: $showingClearDrawingConfirmation) {
                        Button("필기 모두 지우기", role: .destructive) {
                            session.updateDrawingData(Data())
                        }
                        Button("취소", role: .cancel) {}
                    } message: {
                        Text(session.isComposite
                            ? "이 메모의 필기만 지워집니다. 텍스트와 체크리스트는 유지돼요."
                            : "이 메모의 필기와 그림이 모두 지워집니다.")
                    }
                }
            }
            .padding(12)

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
            preview = drawing.image(from: bounds, scale: min(scale, 240 / max(bounds.width, bounds.height)))
        }
    }
}

private struct MobileMemoDrawingCanvas: UIViewRepresentable {
    var drawingData: Data
    var onDrawingChanged: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .secondarySystemBackground
        canvas.isOpaque = true
        canvas.alwaysBounceVertical = true
        canvas.contentSize = CGSize(width: 1_600, height: 2_000)
        canvas.accessibilityIdentifier = "memo-drawing-canvas"
        if let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }

        context.coordinator.toolPicker.addObserver(canvas)
        DispatchQueue.main.async {
            context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.onDrawingChanged = onDrawingChanged
        let currentData = canvas.drawing.strokes.isEmpty
            ? Data()
            : canvas.drawing.dataRepresentation()
        guard currentData != drawingData else { return }
        if drawingData.isEmpty {
            canvas.drawing = PKDrawing()
        } else if let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        var onDrawingChanged: (Data) -> Void

        init(onDrawingChanged: @escaping (Data) -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged(
                canvasView.drawing.strokes.isEmpty
                    ? Data()
                    : canvasView.drawing.dataRepresentation()
            )
        }
    }
}

private struct MobileMemoChecklistEditor: View {
    var session: MemoEditorSession
    @Binding var editingItemID: UUID?
    @Binding var textSelections: [UUID: TextSelection]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FocusState private var focusedItemID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if session.checklistDrafts.isEmpty {
                    Text("항목을 추가해 목록을 만들어보세요.")
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("\(item.title.isEmpty ? "빈 항목" : item.title) 항목 이동")

                        Button(role: .destructive) {
                            if editingItemID == item.id {
                                editingItemID = nil
                                focusedItemID = nil
                            }
                            textSelections[item.id] = nil
                            session.removeChecklistItem(id: item.id)
                        } label: {
                            Image(systemName: "trash")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.title.isEmpty ? "빈 항목" : item.title) 항목 삭제")
                    }
                    .padding(.horizontal, 10)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    appendAndFocusItem()
                } label: {
                    Label("항목 추가", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityLabel("메모 체크리스트")
        .onScrollPhaseChange { oldPhase, newPhase in
            if oldPhase != .idle, newPhase == .idle, focusedItemID == nil {
                editingItemID = nil
            }
        }
        .task(id: horizontalSizeClass) {
            // Restore the same field and selection after split-view reparenting.
            guard let itemID = editingItemID else { return }
            focusedItemID = nil
            await _Concurrency.Task.yield()
            guard !_Concurrency.Task.isCancelled else { return }
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
                    editingItemID = nil
                    focusedItemID = nil
                }
                    .accessibilityIdentifier("memo-checklist-keyboard-dismiss")
            }
        }
    }

    private func moveItem(_ id: UUID, down: Bool) {
        guard let index = session.checklistDrafts.firstIndex(where: { $0.id == id }) else { return }
        session.moveChecklistItems(fromOffsets: IndexSet(integer: index), toOffset: down ? index + 2 : index - 1)
    }

    private func appendAndFocusItem() {
        session.appendChecklistItem()
        editingItemID = session.checklistDrafts.last?.id
        focusedItemID = editingItemID
    }
}
#endif
