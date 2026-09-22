import Foundation

public enum TemplateListScope: String, CaseIterable, Identifiable {
    case all
    case favorites

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .favorites: "즐겨찾기"
        case .all: "전체보기"
        }
    }
}

public enum TemplateListRules {
    public static func filterAndSort(
        _ templates: [TaskTemplate],
        items: [TaskTemplateItem],
        query: String,
        scope: TemplateListScope = .all
    ) -> [TaskTemplate] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var matchingTemplateIDs: Set<UUID> = []
        if !trimmedQuery.isEmpty {
            for item in items where item.supersededAt == nil {
                if item.title.localizedCaseInsensitiveContains(trimmedQuery) {
                    matchingTemplateIDs.insert(item.templateId)
                }
            }
        }
        return templates
            .filter { template in
                guard template.supersededAt == nil else { return false }
                if trimmedQuery.isEmpty { return scope == .all || template.isFavorite }
                return template.name.localizedCaseInsensitiveContains(trimmedQuery)
                    || matchingTemplateIDs.contains(template.id)
            }
            .sorted(by: sort)
    }

    public static func preferredScope(for templates: [TaskTemplate]) -> TemplateListScope {
        .all
    }

    public static func itemsForTemplate(
        _ template: TaskTemplate,
        in items: [TaskTemplateItem]
    ) -> [TaskTemplateItem] {
        items
            .filter { $0.supersededAt == nil && $0.templateId == template.id }
            .sorted { $0.order < $1.order }
    }

    /// A render-scoped index: keep physical candidates and their input order so
    /// each row can apply the existing draft ordering without scanning all items.
    public static func itemsByTemplate(in items: [TaskTemplateItem]) -> [UUID: [TaskTemplateItem]] {
        var grouped: [UUID: [TaskTemplateItem]] = [:]
        for item in items where item.supersededAt == nil {
            grouped[item.templateId, default: []].append(item)
        }
        return grouped
    }

    private static func sort(_ lhs: TaskTemplate, _ rhs: TaskTemplate) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
