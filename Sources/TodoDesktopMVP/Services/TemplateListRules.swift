import Foundation

enum TemplateListScope: String, CaseIterable, Identifiable {
    case favorites
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: "즐겨찾기"
        case .all: "전체보기"
        }
    }
}

enum TemplateListRules {
    static func filterAndSort(
        _ templates: [TaskTemplate],
        items: [TaskTemplateItem],
        query: String,
        scope: TemplateListScope = .all
    ) -> [TaskTemplate] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return templates
            .filter { template in
                guard scope == .all || template.isFavorite else { return false }
                return matches(template, items: itemsForTemplate(template, in: items), query: trimmedQuery)
            }
            .sorted(by: sort)
    }

    static func preferredScope(for templates: [TaskTemplate]) -> TemplateListScope {
        templates.contains { $0.isFavorite } ? .favorites : .all
    }

    static func itemsForTemplate(
        _ template: TaskTemplate,
        in items: [TaskTemplateItem]
    ) -> [TaskTemplateItem] {
        items
            .filter { $0.templateId == template.id }
            .sorted { $0.order < $1.order }
    }

    private static func matches(
        _ template: TaskTemplate,
        items: [TaskTemplateItem],
        query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }
        if template.name.localizedCaseInsensitiveContains(query) {
            return true
        }
        return items.contains { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private static func sort(_ lhs: TaskTemplate, _ rhs: TaskTemplate) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
