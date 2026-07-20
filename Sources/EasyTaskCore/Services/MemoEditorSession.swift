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
    public private(set) var saveState: MemoSaveState

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var lastSavedContent: String
    @ObservationIgnored private var pendingSave: Swift.Task<Void, Never>?

    public init(memo: Memo?, context: ModelContext) {
        self.memo = memo
        self.context = context
        content = memo?.content ?? ""
        lastSavedContent = memo?.content ?? ""
        saveState = memo == nil ? .idle : .saved
    }

    deinit {
        pendingSave?.cancel()
    }

    public var isPinned: Bool {
        memo?.isPinned ?? false
    }

    public func updateContent(_ value: String) {
        guard content != value else { return }
        content = value
        scheduleSave()
    }

    public func scheduleSave() {
        pendingSave?.cancel()
        guard content != lastSavedContent else {
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
        guard content != lastSavedContent else { return }

        do {
            memo = try MemoService.save(
                memo: memo,
                content: content,
                in: context
            )
            lastSavedContent = content
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
        lastSavedContent = ""
        saveState = .idle
    }
}
