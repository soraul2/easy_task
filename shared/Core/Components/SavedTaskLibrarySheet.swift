#if os(iOS) || os(macOS)
import SwiftData
import SwiftUI

private struct SavedTaskEditRequest: Identifiable {
    let id = UUID()
    var entry: SavedTaskEntry?
}

public struct SavedTaskLibrarySheet: View {
    private let selectedDate: Date
    private let onAdded: (String) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var allEntries: [SavedTaskEntry] = []
    @FocusState private var isSearchFocused: Bool
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var editor: SavedTaskEditRequest?
    @State private var pendingDelete: SavedTaskEntry?
    @State private var addedIDs: Set<UUID> = []
    @State private var notice: String?
    @State private var failure: String?
    @State private var loadFailure: String?
    #if DEBUG
    @State private var didSimulateLoadFailure = false
    #endif

    public init(selectedDate: Date, onAdded: @escaping (String) -> Void) {
        self.selectedDate = selectedDate
        self.onAdded = onAdded
    }

    private var entries: [SavedTaskEntry] {
        SavedTaskLibraryService.filter(allEntries, query: query, favoritesOnly: favoritesOnly)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                if let loadFailure {
                    VStack(spacing: 16) {
                        Label {
                            Text("저장한 작업을 불러오지 못했어요")
                                .foregroundStyle(AppTheme.primaryText)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .accessibilityHidden(true)
                        }
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue("오류")
                        .accessibilityIdentifier("saved-task-load-error")

                        Text(loadFailure)
                            .font(.body)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)

                        Button("다시 시도") { reload() }
                            .buttonStyle(PlanBaseButtonStyle(.primary))
                            .accessibilityIdentifier("saved-task-load-retry")
                    }
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("\(DayKey.display(selectedDate))에 추가", systemImage: "calendar")
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("saved-task-target-date")
                            Text("자주 하는 일을 꺼내 새 할 일로 추가하세요.")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(AppTheme.secondaryText)
                            TextField(
                                "제목·입력어·메모 검색", text: $query,
                                prompt: Text("제목·입력어·메모 검색").foregroundStyle(AppTheme.secondaryText)
                            )
                            .textFieldStyle(.roundedBorder)
                            .focused($isSearchFocused)
                            .accessibilityIdentifier("saved-task-search")
                            Picker("저장한 작업 보기", selection: $favoritesOnly) {
                                Text("전체").tag(false)
                                Text("즐겨찾기").tag(true)
                            }
                            .planBaseAdaptiveSegmentedPicker()
                            if let notice {
                                Label(notice, systemImage: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.accent)
                                    .accessibilityIdentifier("saved-task-notice")
                            }
                        }
                        .padding(16)
                        Divider()
                        VStack(spacing: 0) {
                            LazyVStack(spacing: 12) {
                                if entries.isEmpty {
                                    ContentUnavailableView(
                                        allEntries.isEmpty ? "자주 쓰는 일을 저장해 보세요" : "해당하는 작업이 없어요",
                                        systemImage: "bookmark",
                                        description: Text(
                                            allEntries.isEmpty
                                                ? "작업 카드 메뉴에서 저장하거나, ‘새로 저장’으로 직접 만들 수 있어요."
                                                : "검색어를 바꾸거나 전체 목록을 확인해 주세요."))
                                }
                                ForEach(entries) { entry in
                                    row(entry)
                                }
                                Text("작업 한 개로 만든 템플릿도 여기에서 꺼내 쓸 수 있어요.")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .accessibilityIdentifier("saved-task-list")
            .background(AppTheme.background)
            .navigationTitle("저장한 작업")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .task { reload() }
            .onReceive(
                NotificationCenter.default.publisher(for: PersistenceCommandService.dataChangedNotification)
            ) { _ in reload() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = SavedTaskEditRequest()
                    } label: {
                        Label("새로 저장", systemImage: "plus")
                    }
                    .accessibilityIdentifier("saved-task-create")
                }
            }
            .sheet(item: $editor) { request in
                SavedTaskEditorSheet(entry: request.entry)
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
            }
            .alert(
                "저장한 작업을 삭제할까요?",
                isPresented: Binding(
                    get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
                ), presenting: pendingDelete
            ) { entry in
                Button("취소", role: .cancel) {}
                Button("삭제", role: .destructive) {
                    perform { try SavedTaskLibraryService.delete(id: entry.id, in: context) }
                    pendingDelete = nil
                }
            } message: { entry in
                Text("‘\(entry.draft.title)’을 저장 목록과 템플릿에서 삭제합니다. 보드에 이미 추가한 작업은 유지돼요.")
            }
            .alert(
                "처리하지 못했어요",
                isPresented: Binding(
                    get: { failure != nil }, set: { if !$0 { failure = nil } }
                )
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(failure ?? "다시 시도해 주세요.")
            }
        }
        .tint(AppTheme.accent)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 540, idealHeight: 680)
        #else
        .presentationDetents([.large])
        #endif
    }

    private func row(_ entry: SavedTaskEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    perform { try SavedTaskLibraryService.toggleFavorite(id: entry.id, in: context) }
                } label: {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(entry.isFavorite ? AppTheme.accent : AppTheme.secondaryText)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(entry.draft.title) 즐겨찾기 \(entry.isFavorite ? "해제" : "추가")")
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.draft.title).font(.headline).foregroundStyle(AppTheme.primaryText)
                    if let alias = entry.quickEntryAlias, !alias.isEmpty {
                        Text("/\(alias)").font(.subheadline.monospaced()).foregroundStyle(AppTheme.accent)
                    }
                    if !entry.draft.note.isEmpty {
                        Text(entry.draft.note).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("저장 내용 편집", systemImage: "pencil") { editor = SavedTaskEditRequest(entry: entry) }
                    if addedIDs.contains(entry.id) {
                        Button("한 번 더 추가", systemImage: "plus") { add(entry) }
                    }
                    Button("저장 목록에서 삭제", systemImage: "trash", role: .destructive) { pendingDelete = entry }
                } label: {
                    Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("\(entry.draft.title) 저장 메뉴")
            }
            if let minutes = entry.draft.estimatedMinutes {
                Label("예상 \(EstimatedTimeFormatter.short(minutes))", systemImage: "clock")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            }
            if !entry.draft.checklistTitles.isEmpty {
                Label("체크리스트 \(entry.draft.checklistTitles.count)개", systemImage: "checklist")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                Text(entry.draft.checklistTitles.prefix(3).joined(separator: " · "))
                    .font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(2)
            }
            Button {
                add(entry)
            } label: {
                Label(
                    addedIDs.contains(entry.id) ? "추가됨" : "이 날짜에 추가",
                    systemImage: addedIDs.contains(entry.id) ? "checkmark" : "plus"
                )
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(PlanBaseButtonStyle())
            .disabled(addedIDs.contains(entry.id))
            .accessibilityLabel("\(entry.draft.title) \(addedIDs.contains(entry.id) ? "추가됨" : "추가")")
        }
        .padding(14)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(AppTheme.border, lineWidth: 1) }
        .accessibilityIdentifier("saved-task-row-\(entry.id)")
    }

    private func reload() {
        do {
            #if DEBUG
            if !didSimulateLoadFailure,
                ProcessInfo.processInfo.arguments.contains("--ui-testing"),
                ProcessInfo.processInfo.arguments.contains("--ui-testing-saved-task-load-failure-once")
            {
                didSimulateLoadFailure = true
                throw CocoaError(.fileReadUnknown)
            }
            #endif
            allEntries = try SavedTaskLibraryService.load(in: context)
            loadFailure = nil
        } catch {
            loadFailure = "잠시 후 다시 시도해 주세요."
        }
    }

    private func add(_ entry: SavedTaskEntry) {
        perform {
            isSearchFocused = false
            let task = try SavedTaskLibraryService.add(id: entry.id, on: selectedDate, in: context)
            addedIDs.insert(entry.id)
            let message = "‘\(task.title)’ 추가했어요"
            notice = message
            onAdded(message)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { failure = error.localizedDescription }
    }
}
#endif
