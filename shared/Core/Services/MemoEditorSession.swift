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
    public private(set) var memo: Memo?
    public private(set) var content: String
    public private(set) var preferredMode: MemoEditorMode
    public private(set) var drawingData: Data
    public private(set) var checklistDrafts: [MemoChecklistDraft]
    public private(set) var saveState: MemoSaveState

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var lastSavedContent: String
    @ObservationIgnored private var lastSavedMode: MemoEditorMode
    @ObservationIgnored private var lastSavedDrawingData: Data
    @ObservationIgnored private var lastSavedChecklistDrafts: [MemoChecklistDraft]
    @ObservationIgnored private var pendingSave: Swift.Task<Void, Never>?

    public init(memo: Memo?, context: ModelContext) {
        let initialContent = memo?.content ?? ""
        let initialMode = memo.map(MemoRules.mode(for:)) ?? .text
        let initialDrawingData: Data
        let initialChecklistDrafts: [MemoChecklistDraft]
        if let memo {
            initialDrawingData = (try? MemoDrawingService.data(for: memo.id, in: context)) ?? Data()
            initialChecklistDrafts = (try? MemoChecklistService.drafts(
                for: memo.id,
                in: context
            )) ?? []
        } else {
            initialDrawingData = Data()
            initialChecklistDrafts = []
        }

        self.memo = memo
        self.context = context
        content = initialContent
        preferredMode = initialMode
        drawingData = initialDrawingData
        checklistDrafts = initialChecklistDrafts
        lastSavedContent = initialContent
        lastSavedMode = initialMode
        lastSavedDrawingData = initialDrawingData
        lastSavedChecklistDrafts = initialChecklistDrafts
        saveState = memo == nil ? .idle : .saved
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
        guard content != value else { return }
        content = value
        scheduleSave()
    }

    public func updatePreferredMode(_ value: MemoEditorMode) {
        guard preferredMode != value else { return }
        preferredMode = value
        scheduleSave()
    }

    public func updateDrawingData(_ value: Data) {
        guard drawingData != value else { return }
        drawingData = value
        scheduleSave()
    }

    public func appendChecklistItem() {
        let nextOrder = (checklistDrafts.map(\.order).max() ?? 0) + 100
        checklistDrafts.append(MemoChecklistDraft(title: "", order: nextOrder))
        preferredMode = .checklist
        scheduleSave()
    }

    public func updateChecklistTitle(id: UUID, title: String) {
        guard let index = checklistDrafts.firstIndex(where: { $0.id == id }),
              checklistDrafts[index].title != title else { return }
        checklistDrafts[index].title = title
        scheduleSave()
    }

    public func toggleChecklistItem(id: UUID) {
        guard let index = checklistDrafts.firstIndex(where: { $0.id == id }) else { return }
        checklistDrafts[index].isCompleted.toggle()
        scheduleSave()
    }

    public func removeChecklistItem(id: UUID) {
        guard let index = checklistDrafts.firstIndex(where: { $0.id == id }) else { return }
        checklistDrafts.remove(at: index)
        normalizeChecklistOrder()
        scheduleSave()
    }

    public func moveChecklistItems(fromOffsets: IndexSet, toOffset: Int) {
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
        pendingSave?.cancel()
        guard hasChanges else {
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

    public func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasChanges else { return }

        do {
            memo = try MemoService.saveComposite(
                memo: memo,
                content: content,
                preferredMode: preferredMode,
                drawingData: drawingData,
                checklistDrafts: checklistDrafts,
                in: context
            )
            lastSavedContent = content
            lastSavedMode = preferredMode
            lastSavedDrawingData = drawingData
            lastSavedChecklistDrafts = checklistDrafts
            saveState = memo == nil ? .idle : .saved
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    public func setPinned(_ isPinned: Bool) {
        flush()
        guard let memo else { return }
        do {
            try MemoService.setPinned(isPinned, for: memo, in: context)
            saveState = .saved
        } catch {
            saveState = .failed(error.localizedDescription)
        }
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
    }

    private var hasChanges: Bool {
        content != lastSavedContent ||
            preferredMode != lastSavedMode ||
            drawingData != lastSavedDrawingData ||
            checklistDrafts != lastSavedChecklistDrafts
    }

    private func normalizeChecklistOrder() {
        for index in checklistDrafts.indices {
            checklistDrafts[index].order = Double(index + 1) * 100
        }
    }
}
