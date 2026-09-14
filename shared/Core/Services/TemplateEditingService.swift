import Foundation
import SwiftData

public struct TemplateContentSnapshot: Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var drafts: [TemplateTaskDraft]
    public var isFavorite: Bool
    public var updatedAt: Date
    public var itemUpdates: [UUID: Date]
}

/// Editing a saved routine never changes tasks or placement history already on a board.
@MainActor
public enum TemplateEditingService {
    public enum Failure: LocalizedError {
        case unavailable, changed, emptyName, emptyTasks, invalidTask

        public var errorDescription: String? {
            switch self {
            case .unavailable: "이 루틴이 삭제되었어요. 목록에서 다시 확인해 주세요."
            case .changed: "다른 곳에서 루틴이 변경됐어요. 작성 내용은 유지됩니다. 새 루틴으로 저장하거나 최신 내용을 다시 열어 주세요."
            case .emptyName: "루틴 이름을 입력해 주세요."
            case .emptyTasks: "작업을 하나 이상 추가해 주세요."
            case .invalidTask: "모든 작업의 제목과 예상 시간을 확인해 주세요."
            }
        }
    }

    public static func snapshot(id: UUID, in context: ModelContext) throws -> TemplateContentSnapshot {
        let (template, items) = try resolve(id: id, in: context)
        return snapshot(template: template, items: items)
    }

    @discardableResult
    public static func save(
        original: TemplateContentSnapshot?, name: String, drafts: [TemplateTaskDraft],
        isFavorite: Bool, in context: ModelContext
    ) throws -> TaskTemplate {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.emptyName }
        guard !drafts.isEmpty else { throw Failure.emptyTasks }
        guard Set(drafts.map(\.id)).count == drafts.count,
              drafts.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  ($0.estimatedMinutes ?? 0) >= 0 }) else { throw Failure.invalidTask }
        let drafts = drafts.enumerated().map { index, value in
            var value = value
            value.order = Double(index + 1) * 100
            return value
        }

        return try PersistenceCommandService.perform(in: context) {
            guard let original else {
                guard let template = TemplateService.saveTemplate(named: name, from: drafts, in: context)
                else { throw Failure.emptyTasks }
                template.isFavorite = isFavorite
                return template
            }
            let (template, items) = try resolve(id: original.id, in: context)
            guard snapshot(template: template, items: items) == original else { throw Failure.changed }
            let now = Date()
            let retainedIDs = Set(drafts.map(\.id))
            let templateID = template.id
            // An explicit removal deletes all physical copies of the selected logical item.
            for item in try context.fetch(FetchDescriptor<TaskTemplateItem>(
                predicate: #Predicate { $0.templateId == templateID }
            )) where !retainedIDs.contains(item.id) {
                context.delete(item)
            }
            let existingByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            for draft in drafts {
                let item: TaskTemplateItem
                if let existing = existingByID[draft.id] {
                    item = existing
                } else {
                    item = TaskTemplateItem(templateId: template.id, title: draft.title, order: draft.order)
                    context.insert(item)
                }
                item.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
                item.note = note.isEmpty ? nil : note
                item.priority = draft.priority.flatMap { TaskPriority(rawValue: $0)?.rawValue }
                item.tags = draft.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                item.estimatedMinutes = draft.estimatedMinutes
                item.checklistTitles = draft.checklistTitles.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                item.order = draft.order
                item.updatedAt = now
            }
            template.name = name
            template.isFavorite = isFavorite
            template.updatedAt = now
            return template
        }
    }

    public static func delete(id: UUID, in context: ModelContext) throws {
        try PersistenceCommandService.perform(in: context) {
            _ = try resolve(id: id, in: context)
            for item in try context.fetch(FetchDescriptor<TaskTemplateItem>(
                predicate: #Predicate { $0.templateId == id }
            )) { context.delete(item) }
            for template in try context.fetch(FetchDescriptor<TaskTemplate>(
                predicate: #Predicate { $0.id == id }
            )) { context.delete(template) }
        }
    }

    private static func resolve(id: UUID, in context: ModelContext) throws -> (TaskTemplate, [TaskTemplateItem]) {
        let templates = try context.fetch(FetchDescriptor<TaskTemplate>(predicate: #Predicate { $0.id == id }))
        let items = try context.fetch(FetchDescriptor<TaskTemplateItem>(predicate: #Predicate { $0.templateId == id }))
        guard let template = representatives(templates).first else { throw Failure.unavailable }
        return (template, representatives(items).sorted {
            $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
        })
    }

    private static func snapshot(template: TaskTemplate, items: [TaskTemplateItem]) -> TemplateContentSnapshot {
        TemplateContentSnapshot(id: template.id, name: template.name,
            drafts: items.map(TemplateTaskDraft.init(item:)), isFavorite: template.isFavorite,
            updatedAt: template.updatedAt, itemUpdates: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.updatedAt) }))
    }

    private static func representatives<Record: IntegrityRecord>(_ records: [Record]) -> [Record] {
        var result: [UUID: Record] = [:]
        for record in records where record.supersededAt == nil {
            if let current = result[record.id], !DataIntegrityService.scalarPrecedes(current, record) { continue }
            result[record.id] = record
        }
        return Array(result.values)
    }
}
