import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

// Frozen reference behavior from the working tree at the start of the 2026-09-14 audit.
private func originalTemplateList(_ templates: [TaskTemplate], items: [TaskTemplateItem],
                                  query: String, scope: TemplateListScope) -> [TaskTemplate] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return templates.filter { template in
        guard template.supersededAt == nil else { return false }
        guard !query.isEmpty || scope == .all || template.isFavorite else { return false }
        let children = items.filter { $0.supersededAt == nil && $0.templateId == template.id }
            .sorted { $0.order < $1.order }
        return query.isEmpty || template.name.localizedCaseInsensitiveContains(query)
            || children.contains { $0.title.localizedCaseInsensitiveContains(query) }
    }.sorted {
        if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}

private func originalSuggestions(_ entries: [SavedTaskEntry], input: String) -> [SavedTaskEntry] {
    guard let query = SavedTaskShortcutRules.query(in: input) else { return [] }
    return entries.filter {
        query.isEmpty || SavedTaskShortcutRules.aliasKey($0.quickEntryAlias)?.contains(query) == true
            || $0.draft.title.localizedStandardContains(query)
    }.sorted {
        let left = !query.isEmpty && SavedTaskShortcutRules.aliasKey($0.quickEntryAlias) == query
        let right = !query.isEmpty && SavedTaskShortcutRules.aliasKey($1.quickEntryAlias) == query
        if left != right { return left }
        if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
        let order = $0.draft.title.localizedStandardCompare($1.draft.title)
        return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
    }
}

private func originalApplicationSummary(drafts: [TemplateTaskDraft], dates: [Date], tasks: [Task])
    -> TemplateApplicationSummary {
    let normalize: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    let titles = drafts.sorted { $0.order < $1.order }.map { normalize($0.title) }.filter { !$0.isEmpty }
    let days = Set(dates.map(DayKey.key(for:)))
    var count = 0
    for day in days {
        var known = Set(tasks.filter {
            $0.supersededAt == nil && $0.archivedAt == nil && $0.plannedDayKey == day
        }.map { normalize($0.title) })
        for title in titles where known.insert(title).inserted { count += 1 }
    }
    return .init(totalCount: titles.count * days.count, newCount: count)
}

@Test @MainActor
func optimizedTemplateSearchPreservesScopeOrderAndLiveEdits() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    defer { withExtendedLifetime(container) {} }
    let templates = (0..<40).map { index in
        TaskTemplate(name: index % 7 == 0 ? "같은 이름" : "루틴 \(index)", isFavorite: index % 3 == 0)
    }
    var items: [TaskTemplateItem] = []
    for (index, template) in templates.enumerated() {
        context.insert(template)
        let item = TaskTemplateItem(templateId: template.id, title: "항목 \(index) café 운동", order: Double(40 - index))
        context.insert(item)
        items.append(item)
    }
    let hidden = TaskTemplateItem(templateId: templates[1].id, title: "비활성 전용", order: 0,
                                  supersededAt: Date())
    items.append(hidden)
    items.append(TaskTemplateItem(templateId: UUID(), title: "고아 전용", order: 0))
    templates[2].supersededAt = Date()
    // Preserve physical candidates and stable ordering; this optimization must not deduplicate.
    let duplicate = TaskTemplate(id: templates[0].id, name: "같은 이름", isFavorite: true)
    let rows = templates + [duplicate]
    for iteration in 0..<2 {
        if iteration == 1 {
            items[0].title = "바뀐 내용"
            items[1].supersededAt = Date()
            templates[3].name = "새 이름"
            templates[4].isFavorite.toggle()
        }
        for query in ["", "  \n", "항목", "CAFÉ", "운동", "새 이름", "비활성 전용", "고아 전용", "없음"] {
            for scope in TemplateListScope.allCases {
                let result = TemplateListRules.filterAndSort(rows, items: items, query: query, scope: scope)
                #expect(result.map(\.instanceID) == originalTemplateList(rows, items: items, query: query, scope: scope).map(\.instanceID))
            }
        }
    }
}

@Test
func optimizedShortcutSuggestionsPreserveUnicodeAmbiguityAndOrdering() {
    let aliases: [String?] = [nil, "운동", "운동", " /WORK ", "work", "work_more", "invalid alias", "", "🙂"]
    var entries = (0..<90).map { index in
        SavedTaskEntry(id: UUID(), draft: .init(title: index % 4 == 0 ? "같은 제목 work" : "운동 \(index)", order: 0),
                       isFavorite: index % 3 == 0, quickEntryAlias: aliases[index % aliases.count])
    }
    for _ in 0..<2 {
        for input in ["ordinary", "/", " /WORK ", "/wo", "/운", "/운동", "/운동", "/invalid", "/🙂", "/missing"] {
            #expect(SavedTaskShortcutRules.suggestions(entries, input: input).map(\.id)
                    == originalSuggestions(entries, input: input).map(\.id))
        }
        entries.reverse()
        entries[0].quickEntryAlias = "work"
        entries[1].isFavorite.toggle()
    }
}

@Test @MainActor
func optimizedApplicationSummaryPreservesDuplicateAndDateRules() throws {
    let date = try #require(DayKey.date(from: "2026-09-14"))
    let drafts = ["운동", " WORK ", "work", "", " \n", "운동", "새 작업"].enumerated().map {
        TemplateTaskDraft(title: $0.element, order: Double(10 - $0.offset))
    }
    let tasks = (0..<80).map { index in
        let task = Task(title: index % 2 == 0 ? " work " : "운동", plannedAt: DayKey.addingDays(index % 8, to: date), order: 0)
        if index % 3 == 0 { task.supersededAt = date }
        if index % 5 == 0 { task.archivedAt = date }
        return task
    }
    let dates = (0..<12).map { DayKey.addingDays($0, to: date) } + [date, date.addingTimeInterval(3600)]
    for selectedDates in [dates, [], [date]] {
        for selectedDrafts in [drafts, []] {
            #expect(TemplateApplicationRules.summary(drafts: selectedDrafts, dates: selectedDates, tasks: tasks)
                    == originalApplicationSummary(drafts: selectedDrafts, dates: selectedDates, tasks: tasks))
        }
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_FOLLOWUP_PERFORMANCE"] == "1"))
@MainActor
func optimizationFollowupPerformance() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    var templates: [TaskTemplate] = []
    var items: [TaskTemplateItem] = []
    for index in 0..<1_000 {
        let template = TaskTemplate(name: "루틴 \(index)", isFavorite: index % 3 == 0, quickEntryAlias: "work_\(index)")
        context.insert(template)
        templates.append(template)
        for child in 0..<3 {
            let item = TaskTemplateItem(templateId: template.id, title: "작업 \(index)-\(child)", order: Double(child))
            context.insert(item)
            items.append(item)
        }
    }
    let entries = templates.enumerated().map { index, template in
        SavedTaskEntry(id: template.id, draft: .init(title: template.name, order: 0),
                       isFavorite: template.isFavorite, quickEntryAlias: template.quickEntryAlias)
    }
    let date = try #require(DayKey.date(from: "2026-09-14"))
    let dates = (0..<42).map { DayKey.addingDays($0, to: date) }
    let tasks = (0..<2_100).map { index in
        let task = Task(title: "작업 \(index % 50)", plannedAt: dates[index % 42], order: Double(index))
        context.insert(task)
        return task
    }
    try context.save()
    let drafts = (0..<60).map { TemplateTaskDraft(title: "작업 \($0)", order: Double($0)) }
    let cases: [(String, () -> Int)] = [
        ("template-list-empty-1000x3000", { TemplateListRules.filterAndSort(templates, items: items, query: "").count }),
        ("template-list-item-search-1000x3000", { TemplateListRules.filterAndSort(templates, items: items, query: "작업 99").count }),
        ("shortcut-prefix-1000", { SavedTaskShortcutRules.suggestions(entries, input: "/work").count }),
        ("application-summary-42x2100", { TemplateApplicationRules.summary(drafts: drafts, dates: dates, tasks: tasks).newCount }),
    ]
    for (name, operation) in cases {
        let expected = operation()
        var samples: [Double] = []
        for _ in 0..<7 {
            let start = DispatchTime.now().uptimeNanoseconds
            let count = operation()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            #expect(count == expected)
        }
        let sorted = samples.sorted()
        print("FOLLOWUP_BENCHMARK name=\(name) unit=ms n=7 p50=\(sorted[3]) count=\(expected) samples=\(samples)")
    }
}
