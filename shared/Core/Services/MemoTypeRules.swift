import Foundation

public extension MemoEditorMode {
    /// Creation labels are separate from the legacy composite editor's tabs.
    var creationTitle: String {
        switch self {
        case .text: "글 메모"
        case .checklist: "체크리스트"
        case .drawing: "필기·그림"
        }
    }

    static var creationOrder: [MemoEditorMode] { [.text, .checklist, .drawing] }
}

/// Content determines which editor is safe to show. A legacy preferred mode is
/// only a preference, and must never hide another nonempty content collection.
public enum MemoTypeRules {
    public static func contentModes(
        content: String, hasDrawing: Bool, checklist: [MemoChecklistDraft]
    ) -> [MemoEditorMode] {
        var modes: [MemoEditorMode] = []
        if !MemoRules.isBlank(content) { modes.append(.text) }
        if hasDrawing { modes.append(.drawing) }
        if !MemoChecklistService.normalizedDrafts(checklist).isEmpty { modes.append(.checklist) }
        return modes
    }

    public static func resolvedMode(
        preferred: MemoEditorMode, contentModes: [MemoEditorMode]
    ) -> MemoEditorMode {
        contentModes.count == 1 ? contentModes[0] : preferred
    }

    public static func title(
        content: String, checklist: [MemoChecklistDraft], mode: MemoEditorMode
    ) -> String {
        if !MemoRules.isBlank(content) { return MemoRules.displayTitle(for: content) }
        if let first = MemoChecklistService.normalizedDrafts(checklist).first { return first.title }
        return mode == .text ? MemoRules.emptyTitle : mode.creationTitle
    }
}

public struct MemoListSummary: Sendable {
    public let title: String
    public let preview: String
    public let mode: MemoEditorMode
    public let isComposite: Bool
    public let drawingUpdatedAt: Date?

    public init(content: String, preferred: MemoEditorMode,
                checklist: [MemoChecklistDraft], drawingUpdatedAt: Date?) {
        let modes = MemoTypeRules.contentModes(
            content: content, hasDrawing: drawingUpdatedAt != nil, checklist: checklist
        )
        mode = MemoTypeRules.resolvedMode(preferred: preferred, contentModes: modes)
        isComposite = modes.count > 1
        self.drawingUpdatedAt = drawingUpdatedAt
        title = MemoTypeRules.title(content: content, checklist: checklist, mode: mode)
        let progress = MemoChecklistService.progress(in: checklist)
        var parts: [String] = []
        if !MemoRules.isBlank(content) { parts.append(MemoRules.preview(for: content)) }
        if progress.totalCount > 0 {
            parts.append("\(progress.completedCount)/\(progress.totalCount) 완료")
            let titles = MemoChecklistService.normalizedDrafts(checklist).prefix(3).map(\.title)
            parts.append(String(titles.joined(separator: " · ").prefix(160)))
        }
        if drawingUpdatedAt != nil { parts.append(MemoEditorMode.drawing.creationTitle) }
        preview = parts.joined(separator: "\n")
    }

    public var systemImage: String { isComposite ? "square.stack" : mode.systemImage }
    public var typeTitle: String { isComposite ? "복합 메모" : mode.creationTitle }
}
