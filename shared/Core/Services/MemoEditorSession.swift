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
    public private(set) var isComposite = false
    private var hasWrittenContent = false
    private var isFlushing = false
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
        initialMode: MemoEditorMode = .text,
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
        let initialMode = memo.map(MemoRules.mode(for:)) ?? initialMode

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
        MemoTypeRules.title(content: content, checklist: checklistDrafts, mode: preferredMode)
    }

    public var canChooseType: Bool {
        memo == nil && !hasWrittenContent && !isComposite && loadErrorMessage == nil
    }

    private func canEdit(_ mode: MemoEditorMode) -> Bool {
        loadErrorMessage == nil && (isComposite || preferredMode == mode)
    }

    private func updateTypePolicy() {
        let modes = MemoTypeRules.contentModes(
            content: content, hasDrawing: !drawingData.isEmpty, checklist: checklistDrafts
        )
        if !modes.isEmpty { hasWrittenContent = true }
        if modes.count > 1 { isComposite = true }
        if !isComposite {
            preferredMode = MemoTypeRules.resolvedMode(preferred: preferredMode, contentModes: modes)
        }
    }

    public var checklistProgress: ChecklistProgress {
        MemoChecklistService.progress(in: checklistDrafts)
    }

    public func updateContent(_ value: String) {
        guard canEdit(.text) else { return }
        guard content != value else { return }
        content = value
        updateTypePolicy()
        scheduleSave()
    }

    public func updatePreferredMode(_ value: MemoEditorMode) {
        guard loadErrorMessage == nil, isComposite || canChooseType else { return }
        guard preferredMode != value else { return }
        preferredMode = value
        // Choosing an empty draft's type must not create a database record.
        if isComposite { scheduleSave() }
    }

    public func updateDrawingData(_ value: Data) {
        guard canEdit(.drawing) else { return }
        guard drawingData != value else { return }
        drawingData = value
        updateTypePolicy()
        scheduleSave()
    }

    public func appendChecklistItem() {
        guard canEdit(.checklist) else { return }
        let nextOrder = (checklistDrafts.map(\.order).max() ?? 0) + 100
        checklistDrafts.append(MemoChecklistDraft(title: "", order: nextOrder))
        preferredMode = .checklist
        scheduleSave()
    }

    public func updateChecklistTitle(id: UUID, title: String) {
        guard canEdit(.checklist) else { return }
        guard let index = checklistDrafts.firstIndex(where: { $0.id == id }),
              checklistDrafts[index].title != title else { return }
        checklistDrafts[index].title = title
        updateTypePolicy()
        scheduleSave()
    }

    public func toggleChecklistItem(id: UUID) {
        guard canEdit(.checklist) else { return }
        guard let index = checklistDrafts.firstIndex(where: { $0.id == id }) else { return }
        checklistDrafts[index].isCompleted.toggle()
        scheduleSave()
    }

    public func removeChecklistItem(id: UUID) {
        guard canEdit(.checklist) else { return }
        guard let index = checklistDrafts.firstIndex(where: { $0.id == id }) else { return }
        checklistDrafts.remove(at: index)
        normalizeChecklistOrder()
        scheduleSave()
    }

    public func moveChecklistItems(fromOffsets: IndexSet, toOffset: Int) {
        guard canEdit(.checklist) else { return }
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
        isFlushing = true
        defer { isFlushing = false }

        do {
            // Also resolve the current representative for a pin-only save.
            try mergeUneditedContentFromStore()
            if hasContentChanges {
                // The snapshot may predate a CloudKit import from an older app.
                // Refresh only untouched fields before the atomic replacement save.
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
        isComposite = false
        hasWrittenContent = false
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

    public func refreshFromStore() {
        guard !isFlushing else { return }
        reloadContent()
    }

    private func reloadContent() {
        guard memo != nil else { return }
        do {
            try mergeUneditedContentFromStore()
            loadErrorMessage = nil
            if !hasUnsavedChanges { saveState = .saved }
        } catch {
            loadErrorMessage = "메모 내용을 불러오지 못했어요. 다시 시도해 주세요."
        }
    }

    private func mergeUneditedContentFromStore() throws {
        guard let previous = memo else { return }
        let logicalID = previous.id
        let candidates = try context.fetch(FetchDescriptor<Memo>(predicate: #Predicate {
            $0.id == logicalID && $0.supersededAt == nil
        }))
        // CloudKit can replace the physical representative while this editor
        // remains open. Use the existing convergence order, including temporary
        // duplicates, without changing or deleting any superseded record.
        guard let memo = candidates.max(by: { DataIntegrityService.scalarPrecedes($0, $1) }) else {
            throw MemoEditorLoadError.unavailable
        }
        // Both reads must succeed before any baseline is advanced.
        let loaded = try loadContent(memo.id, context)
        self.memo = memo
        if content == lastSavedContent {
            content = memo.content
            lastSavedContent = content
        }
        if drawingData == lastSavedDrawingData {
            drawingData = loaded.drawing
            lastSavedDrawingData = loaded.drawing
        }
        if checklistDrafts == lastSavedChecklistDrafts {
            checklistDrafts = loaded.checklist
            lastSavedChecklistDrafts = loaded.checklist
        }
        // Keep the editor the user is using when new content arrives. A reopened
        // composite memo still starts in its persisted preferred editor.
        updateTypePolicy()
    }

    private func normalizeChecklistOrder() {
        for index in checklistDrafts.indices {
            checklistDrafts[index].order = Double(index + 1) * 100
        }
    }
}

private enum MemoEditorLoadError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "메모를 찾을 수 없어요. 목록을 새로 고친 뒤 다시 열어 주세요."
    }
}
