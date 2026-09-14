import Foundation
import Observation
import SwiftData

public enum MemoSaveState: Equatable, Sendable {
    case idle
    case saving
    case saved
    case failed(String)

    public var title: String {
        switch self {
        case .idle:
            ""
        case .saving:
            "저장 중"
        case .saved:
            "저장됨"
        case .failed:
            "저장 실패"
        }
    }
}

@MainActor
@Observable
public final class MemoEditorSession {
    public typealias ContentLoader = @MainActor (UUID, ModelContext) throws -> (drawing: Data, checklist: [MemoChecklistDraft])
    public typealias CompositeSaver = @MainActor (
        Memo?, String, MemoEditorMode, Data, [MemoChecklistDraft], ModelContext
    ) throws -> Memo?

    public private(set) var memo: Memo?
    public private(set) var content: String
    public private(set) var preferredMode: MemoEditorMode
    public private(set) var drawingData: Data
    public private(set) var checklistDrafts: [MemoChecklistDraft]
    public private(set) var saveState: MemoSaveState
    public private(set) var loadErrorMessage: String?
    private var pendingPin: Bool?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var lastSavedContent: String
    @ObservationIgnored private var lastSavedMode: MemoEditorMode
    @ObservationIgnored private var lastSavedDrawingData: Data
    @ObservationIgnored private var lastSavedChecklistDrafts: [MemoChecklistDraft]
    @ObservationIgnored private var pendingSave: Swift.Task<Void, Never>?
    @ObservationIgnored private let loadContent: ContentLoader
    @ObservationIgnored private let saveComposite: CompositeSaver

    public init(
        memo: Memo?,
        context: ModelContext,
        loadContent: @escaping ContentLoader = { id, context in
            (try MemoDrawingService.data(for: id, in: context),
             try MemoChecklistService.drafts(for: id, in: context))
        },
        saveComposite: @escaping CompositeSaver = { memo, content, mode, drawing, checklist, context in
            try MemoService.saveComposite(
                memo: memo,
                content: content,
                preferredMode: mode,
                drawingData: drawing,
                checklistDrafts: checklist,
                in: context
            )
        }
    ) {
        let initialContent = memo?.content ?? ""
        let initialMode = memo.map(MemoRules.mode(for:)) ?? .text

        self.memo = memo
        self.context = context
        self.saveComposite = saveComposite
        self.loadContent = loadContent
        content = initialContent
        preferredMode = initialMode
        drawingData = Data()
        checklistDrafts = []
        lastSavedContent = initialContent
        lastSavedMode = initialMode
        lastSavedDrawingData = Data()
        lastSavedChecklistDrafts = []
        saveState = memo == nil ? .idle : .saved
        reloadContent()
    }

    deinit {
        pendingSave?.cancel()
    }

    public var isPinned: Bool {
        memo?.isPinned ?? false
    }

    public var displayTitle: String {
        let title = MemoRules.displayTitle(for: content)
        guard title == MemoRules.emptyTitle else { return title }
        switch preferredMode {
        case .text:
            return title
        case .drawing:
            return "필기 메모"
        case .checklist:
            return "체크리스트"
        }
    }

    public var checklistProgress: ChecklistProgress {
        MemoChecklistService.progress(in: checklistDrafts)
    }

    public func updateContent(_ value: String) {
        guard loadErrorMessage == nil else { return }
        guard content != value else { return }
        content = value
        scheduleSave()
    }

    public func updatePreferredMode(_ value: MemoEditorMode) {
        guard loadErrorMessage == nil else { return }
        guard preferredMode != value else { return }
        preferredMode = value
        scheduleSave()
    }

    public func updateDrawingData(_ value: Data) {
        guard loadErrorMessage == nil else { return }
        guard drawingData != value else { return }
        drawingData = value
        scheduleSave()
    }

    public func appendChecklistItem() {
        guard loadErrorMessage == nil else { return }
        let nextOrder = (checklistDrafts.map(\.order).max() ?? 0) + 100
        checklistDrafts.append(MemoChecklistDraft(title: "", order: nextOrder))
        preferredMode = .checklist
        scheduleSave()
    }

    public func updateChecklistTitle(id: UUID, title: String) {
        guard loadErrorMessage == nil else { return }
        guard let index = checklistDrafts.firstIndex(where: { $0.id == id }),
              checklistDrafts[index].title != title else { return }
        checklistDrafts[index].title = title
        scheduleSave()
    }

    public func toggleChecklistItem(id: UUID) {
        guard loadErrorMessage == nil else { return }
        guard let index = checklistDrafts.firstIndex(where: { $0.id == id }) else { return }
        checklistDrafts[index].isCompleted.toggle()
        scheduleSave()
    }

    public func removeChecklistItem(id: UUID) {
        guard loadErrorMessage == nil else { return }
        guard let index = checklistDrafts.firstIndex(where: { $0.id == id }) else { return }
        checklistDrafts.remove(at: index)
        normalizeChecklistOrder()
        scheduleSave()
    }

    public func moveChecklistItems(fromOffsets: IndexSet, toOffset: Int) {
        guard loadErrorMessage == nil else { return }
        let validOffsets = fromOffsets
            .filter { checklistDrafts.indices.contains($0) }
            .sorted()
        guard !validOffsets.isEmpty else { return }

        let movingDrafts = validOffsets.map { checklistDrafts[$0] }
        for index in validOffsets.reversed() {
            checklistDrafts.remove(at: index)
        }
        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        let insertionIndex = min(
            checklistDrafts.count,
            max(0, toOffset - removedBeforeDestination)
        )
        checklistDrafts.insert(contentsOf: movingDrafts, at: insertionIndex)
        normalizeChecklistOrder()
        scheduleSave()
    }

    public func scheduleSave() {
        guard loadErrorMessage == nil else { return }
        pendingSave?.cancel()
        guard hasUnsavedChanges else {
            saveState = memo == nil ? .idle : .saved
            return
        }
        saveState = .saving
        pendingSave = Swift.Task { [weak self] in
            do {
                try await Swift.Task.sleep(for: .milliseconds(600))
                guard !Swift.Task.isCancelled else { return }
                self?.flush()
            } catch {
                // A newer edit superseded this save.
            }
        }
    }

    @discardableResult
    public func flush() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard loadErrorMessage == nil else { return false }
        guard hasUnsavedChanges else { return true }

        do {
            if hasContentChanges {
                memo = try saveComposite(
                    memo, content, preferredMode, drawingData, checklistDrafts, context
                )
                lastSavedContent = content
                lastSavedMode = preferredMode
                lastSavedDrawingData = drawingData
                lastSavedChecklistDrafts = checklistDrafts
            }
            if let pendingPin, let memo {
                try MemoService.setPinned(pendingPin, for: memo, in: context)
            }
            pendingPin = nil
            saveState = memo == nil ? .idle : .saved
            return true
        } catch {
            saveState = .failed(error.localizedDescription)
            return false
        }
    }

    public func setPinned(_ isPinned: Bool) {
        guard loadErrorMessage == nil else { return }
        pendingPin = isPinned
        flush()
    }

    public func delete() throws {
        pendingSave?.cancel()
        pendingSave = nil
        guard let memo else { return }
        try MemoService.delete(memo, in: context)
        self.memo = nil
        content = ""
        preferredMode = .text
        drawingData = Data()
        checklistDrafts = []
        lastSavedContent = ""
        lastSavedMode = .text
        lastSavedDrawingData = Data()
        lastSavedChecklistDrafts = []
        saveState = .idle
        loadErrorMessage = nil
        pendingPin = nil
    }

    /// A failed save must keep this draft alive when navigating between editors.
    public var hasUnsavedChanges: Bool {
        hasContentChanges || pendingPin != nil
    }

    private var hasContentChanges: Bool {
        content != lastSavedContent ||
            preferredMode != lastSavedMode ||
            drawingData != lastSavedDrawingData ||
            checklistDrafts != lastSavedChecklistDrafts
    }

    public func retryLoad() {
        guard loadErrorMessage != nil else { return }
        reloadContent()
    }

    private func reloadContent() {
        guard let memo else { return }
        do {
            // Commit the loaded snapshot only after both reads succeed. An unread
            // child collection must never be passed to the replacement saver as empty.
            let loaded = try loadContent(memo.id, context)
            content = memo.content
            preferredMode = MemoRules.mode(for: memo)
            lastSavedContent = content
            lastSavedMode = preferredMode
            drawingData = loaded.drawing
            checklistDrafts = loaded.checklist
            lastSavedDrawingData = loaded.drawing
            lastSavedChecklistDrafts = loaded.checklist
            loadErrorMessage = nil
            saveState = .saved
        } catch {
            saveState = .idle
            loadErrorMessage = "메모 내용을 불러오지 못했어요. 다시 시도해 주세요."
        }
    }

    private func normalizeChecklistOrder() {
        for index in checklistDrafts.indices {
            checklistDrafts[index].order = Double(index + 1) * 100
        }
    }
}
