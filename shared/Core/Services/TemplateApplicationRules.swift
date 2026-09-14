import Foundation

public struct TemplateApplicationSummary: Equatable {
    public var totalCount: Int
    public var newCount: Int
    public var duplicateCount: Int { totalCount - newCount }

    public init(totalCount: Int, newCount: Int) {
        self.totalCount = totalCount
        self.newCount = newCount
    }
}

public enum TemplateApplicationRules {
    public static func summary(drafts: [TemplateTaskDraft], dates: [Date], tasks: [Task]) -> TemplateApplicationSummary {
        let titles = drafts.map { normalize($0.title) }.filter { !$0.isEmpty }
        let dayKeys = Set(dates.map(DayKey.key(for:)))
        guard !titles.isEmpty, !dayKeys.isEmpty else { return .init(totalCount: 0, newCount: 0) }
        var knownByDay: [String: Set<String>] = [:]
        for task in tasks where task.supersededAt == nil && task.archivedAt == nil {
            let key = task.plannedDayKey
            guard dayKeys.contains(key) else { continue }
            knownByDay[key, default: []].insert(normalize(task.title))
        }
        let uniqueTitles = Set(titles)
        var newCount = 0
        for key in dayKeys {
            let known = knownByDay[key] ?? []
            for title in uniqueTitles where !known.contains(title) { newCount += 1 }
        }
        return TemplateApplicationSummary(totalCount: titles.count * dayKeys.count, newCount: newCount)
    }

    private static func normalize(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
