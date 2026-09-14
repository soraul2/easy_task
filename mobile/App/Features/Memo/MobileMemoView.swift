#if os(iOS)
import PencilKit
import PlanBaseCore
import SwiftData
import SwiftUI

private struct MobileMemoRoute: Hashable {
    var id = UUID()
    var memo: Memo?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MobileMemoView: View {
    var onShowTheme: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var querySession: MemoQuerySession?
    @State private var searchText = ""
    @State private var path: [MobileMemoRoute] = []
    @State private var memoPendingDeletion: Memo?
    @State private var actionFailure: String?

    var body: some View {
        NavigationStack(path: $path) {
            memoList
                .navigationTitle("메모")
                .searchable(text: $searchText, prompt: "메모 검색")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        MobileCloudKitSyncStatusButton(sheetTextSize: dynamicTypeSize)

                        MobileThemeButton(action: onShowTheme, minimumHitSize: 44)

                        Button {
                            path.append(MobileMemoRoute(memo: nil))
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
                        memo: route.memo,
                        onDeleted: {
                            if !path.isEmpty { path.removeLast() }
                        }
                    )
                    .id(route.id)
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
                    ? "오른쪽 위 작성 버튼으로 메모를 추가하세요."
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
        Button {
            path.append(MobileMemoRoute(memo: memo))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: MemoRules.systemImage(for: memo))
                    .foregroundStyle(memo.isPinned ? AppTheme.accent : AppTheme.secondaryText)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 5) {
                    Text(MemoRules.displayTitle(for: memo))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)

                    let preview = MemoRules.preview(for: memo.content)
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
        .listRowBackground(AppTheme.panel)
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
        .accessibilityLabel(MemoRules.displayTitle(for: memo))
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
            try MemoService.delete(memo, in: modelContext)
            actionFailure = nil
        } catch {
            actionFailure = "메모를 삭제하지 못했어요. 내용은 그대로 유지됩니다."
        }
    }
}

private struct MobileMemoEditorView: View {
    var memo: Memo?
    var onDeleted: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @State private var editorSession: MemoEditorSession?
    @State private var showingDeleteConfirmation = false
    @State private var showingClearDrawingConfirmation = false
    @State private var deletionFailure: String?
    @FocusState private var editorFocused: Bool

    var body: some View {
        Group {
            if let editorSession {
                VStack(spacing: 0) {
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
                    .planBaseAdaptiveSegmentedPicker()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .accessibilityLabel("메모 편집 방식")
                    .accessibilityIdentifier("memo-editor-mode")
                    .disabled(editorSession.loadErrorMessage != nil)

                    Divider()

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
                            dismiss()
                        } label: {
                            Label("메모", systemImage: "chevron.backward")
                        }
                        .accessibilityIdentifier("memo-editor-back")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
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
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.panel)
            }
        }
        .task {
            guard editorSession == nil else { return }
            let session = makeEditorSession()
            editorSession = session
            editorFocused = session.preferredMode == .text
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
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .focused($editorFocused)
            .accessibilityLabel("메모 내용")

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
                        Text("이 메모의 필기만 지워집니다. 텍스트와 체크리스트는 유지돼요.")
                    }
                }
            }
            .padding(12)

        case .checklist:
            MobileMemoChecklistEditor(session: session)
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

    private func makeEditorSession() -> MemoEditorSession {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"),
           (arguments.contains("--ui-testing-memo-save-failure-once") ||
            arguments.contains("--ui-testing-memo-save-failure-twice")) {
            return MemoEditorSession(
                memo: memo,
                context: modelContext,
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
            return MemoEditorSession(memo: memo, context: modelContext, loadContent: { id, context in
                let drawing = try MemoDrawingService.data(for: id, in: context)
                if MobileMemoEditorUITestFixture.consumeLoadFailure() {
                    throw NSError(domain: "PlanBase.UIFixture", code: 3)
                }
                return (drawing, try MemoChecklistService.drafts(for: id, in: context))
            })
        }
        #endif
        return MemoEditorSession(memo: memo, context: modelContext)
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
    @FocusState private var focusedItemID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
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

                        Button(role: .destructive) {
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { focusedItemID = nil }
                    .accessibilityIdentifier("memo-checklist-keyboard-dismiss")
            }
        }
    }

    private func appendAndFocusItem() {
        session.appendChecklistItem()
        focusedItemID = session.checklistDrafts.last?.id
    }
}
#endif
