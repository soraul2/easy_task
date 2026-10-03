import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func goalPreparedAliasesMatchOriginalRankingAndUnicodeRules() {
    let entries = [
        goalPreparedAliasEntry(1, title: "work 10", alias: "work-extra", favorite: true),
        goalPreparedAliasEntry(2, title: "Zulu", alias: " /WORK ", favorite: false),
        goalPreparedAliasEntry(3, title: "Omega", alias: "work", favorite: true),
        goalPreparedAliasEntry(4, title: "운동 계획", alias: "운동", favorite: false),
        goalPreparedAliasEntry(5, title: "CAFÉ 2", alias: "CAFÉ", favorite: false),
        goalPreparedAliasEntry(6, title: "Cafe\u{301} 10", alias: "cafe\u{301}", favorite: true),
        goalPreparedAliasEntry(7, title: "동일 제목", alias: "tie", favorite: false),
        goalPreparedAliasEntry(8, title: "동일 제목", alias: "tie", favorite: false),
        goalPreparedAliasEntry(9, title: "bad space 제목", alias: "bad space", favorite: true),
        goalPreparedAliasEntry(10, title: "a/b 제목", alias: "a/b", favorite: false),
        goalPreparedAliasEntry(11, title: "기호 🙂 제목", alias: "🙂", favorite: false),
        goalPreparedAliasEntry(12, title: "긴 입력어 제목", alias: String(repeating: "가", count: 25), favorite: false),
        goalPreparedAliasEntry(13, title: "별칭 없는 work", alias: nil, favorite: false),
        goalPreparedAliasEntry(14, title: "빈 별칭 work", alias: " / ", favorite: false),
    ]
    let keys = SavedTaskShortcutRules.aliasKeys(in: entries)
    #expect(keys.count == 8)
    #expect(keys[entries[1].id] == "work")
    #expect(keys[entries[3].id] == "운동")
    #expect(keys[entries[5].id] == "café")
    for entry in entries.dropFirst(8) { #expect(keys[entry.id] == nil) }

    for input in [
        "일반 입력", "", " / ", "/", "/w", "/work", " /WORK ", "/work-extra",
        "/운", "/운동", "/운동", "/cafe", "/CAFÉ", "/cafe\u{301}",
        "/tie", "/bad space", "/a/b", "/🙂", "/없는검색",
    ] {
        let expected = goalPreparedAliasOriginalSuggestions(entries, input: input)
        goalPreparedAliasExpectEqual(SavedTaskShortcutRules.suggestions(entries, input: input), expected)
        goalPreparedAliasExpectEqual(
            SavedTaskShortcutRules.suggestions(entries, input: input, preparedAliasKeys: keys), expected)
    }
    let exactFirst = SavedTaskShortcutRules.suggestions(entries, input: "/work", preparedAliasKeys: keys)
    #expect(Array(exactFirst.prefix(2).map(\.id)) == [entries[2].id, entries[1].id])
    let ties = SavedTaskShortcutRules.suggestions(entries, input: "/tie", preparedAliasKeys: keys)
    #expect(ties.map(\.id) == [entries[6].id, entries[7].id])
}

@Test
func goalPreparedAliasPublicRulesPreserveDuplicateLogicalIDs() throws {
    let sameID = goalPreparedAliasID(1)
    let entries = [
        SavedTaskEntry(id: sameID, draft: .init(title: "Zulu", order: 100),
                       isFavorite: false, quickEntryAlias: "one"),
        SavedTaskEntry(id: sameID, draft: .init(title: "Alpha", order: 200),
                       isFavorite: true, quickEntryAlias: "two"),
        SavedTaskEntry(id: sameID, draft: .init(title: "one title", order: 300),
                       isFavorite: false, quickEntryAlias: "bad space"),
    ]
    for input in ["/", "/one", "/two", "/bad space", "/Zulu"] {
        goalPreparedAliasExpectEqual(
            SavedTaskShortcutRules.suggestions(entries, input: input),
            goalPreparedAliasOriginalSuggestions(entries, input: input))
    }
    #expect(SavedTaskShortcutRules.suggestions(entries, input: "/one").map(\.draft.title)
            == ["Zulu", "one title"])
    #expect(try SavedTaskShortcutRules.exactMatch(in: entries, input: "/one") == sameID)
    var ambiguous = entries
    ambiguous[1].quickEntryAlias = "ONE"
    #expect(throws: SavedTaskShortcutRules.Failure.self) {
        try SavedTaskShortcutRules.exactMatch(in: ambiguous, input: "/one")
    }
}

@Test @MainActor
func goalPreparedAliasesLoadOnlyOnEntryAndReleaseOnOrdinaryInput() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let record = goalPreparedAliasInsert(1, title: "첫 작업", alias: " /ALPHA ", in: context)
    try context.save()
    let probe = GoalPreparedAliasLoadProbe()
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })
    controller.update("일반 입력", in: context)
    controller.refresh(in: context)
    #expect(probe.calls == 0)
    #expect(controller.entries.isEmpty && controller.suggestions.isEmpty && controller.preparedAliasKeys.isEmpty)
    controller.update("/", in: context)
    #expect(probe.calls == 1)
    #expect(controller.preparedAliasKeys == [record.template.id: "alpha"])
    for input in ["/a", "/alpha", "/ALPHA", "/", "/없는검색", "/a"] {
        controller.update(input, in: context)
        goalPreparedAliasExpectControllerMatches(controller)
    }
    #expect(controller.moveSelection(by: 1))
    #expect(controller.dismiss())
    controller.update("/a", in: context)
    #expect(!controller.isPresented)
    controller.update("/al", in: context)
    #expect(controller.isPresented)
    #expect(probe.calls == 1 && controller.preparedAliasKeys.count == 1)
    controller.update("일반 제목", in: context)
    #expect(controller.preparedAliasKeys.isEmpty && controller.entries.isEmpty && controller.suggestions.isEmpty)
    #expect(controller.highlightedID == nil && controller.failure == nil && !controller.isPresented)
    record.template.quickEntryAlias = "beta"
    try context.save()
    controller.update("/beta", in: context)
    #expect(probe.calls == 2 && controller.preparedAliasKeys == [record.template.id: "beta"])
    #expect(controller.suggestions.map(\.id) == [record.template.id])
}

@Test @MainActor
func goalPreparedAliasSameInputRefreshReplacesKeysAndPrunesOnlyRefreshSelection() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let first = goalPreparedAliasInsert(1, title: "첫 작업", alias: "run", in: context)
    let second = goalPreparedAliasInsert(2, title: "둘째 작업", alias: "later", in: context)
    try context.save()
    let controller = SavedTaskQuickEntryController()
    controller.update("/run", in: context)
    #expect(controller.moveSelection(by: 1))
    let original = controller.entries
    first.template.quickEntryAlias = nil
    second.template.quickEntryAlias = " /RUN "
    second.template.isFavorite = true
    second.item.title = "최신 제목"
    second.item.note = "최신 메모"
    try context.save()
    controller.refresh(in: context)
    #expect(controller.input == "/run" && controller.entries.count == original.count)
    #expect(controller.preparedAliasKeys == [second.template.id: "run"])
    #expect(controller.highlightedID == nil)
    #expect(controller.suggestions.first?.draft.title == "최신 제목")
    #expect(controller.suggestions.first?.draft.note == "최신 메모")
    #expect(controller.suggestions.first?.isFavorite == true)
    #expect(original.first { $0.id == first.template.id }?.quickEntryAlias == "run")
    goalPreparedAliasExpectControllerMatches(controller)
    try SavedTaskLibraryService.delete(id: second.template.id, in: context)
    controller.refresh(in: context)
    #expect(controller.preparedAliasKeys.isEmpty && controller.suggestions.isEmpty && controller.entries.count == 1)
    first.template.quickEntryAlias = "운동"
    try context.save()
    controller.refresh(in: context)
    #expect(controller.preparedAliasKeys == [first.template.id: "운동"])
    controller.update("/운동", in: context)
    #expect(controller.suggestions.map(\.id) == [first.template.id])
}

@Test @MainActor
func goalPreparedAliasFailedReloadRetainsSnapshotsAndRetryUsesLatestAlias() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let record = goalPreparedAliasInsert(1, title: "원래 대상", alias: "run", in: context)
    try context.save()
    let probe = GoalPreparedAliasLoadProbe()
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })
    controller.update("/run", in: context)
    #expect(controller.moveSelection(by: 1))
    let previousEntries = controller.entries
    let previousSuggestions = controller.suggestions
    let previousKeys = controller.preparedAliasKeys
    record.template.quickEntryAlias = "other"
    record.item.title = "run 최신 내용"
    try context.save()
    probe.fails = true
    controller.refresh(in: context)
    goalPreparedAliasExpectEqual(controller.entries, previousEntries)
    goalPreparedAliasExpectEqual(controller.suggestions, previousSuggestions)
    #expect(controller.preparedAliasKeys == previousKeys && controller.highlightedID == record.template.id)
    #expect(controller.failure == "isolated library load failure")
    #expect(controller.add(input: "/run", on: Date(), in: context) == nil)
    #expect(controller.preparedAliasKeys == previousKeys && controller.highlightedID == record.template.id)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    probe.fails = false
    controller.refresh(in: context)
    #expect(controller.preparedAliasKeys == [record.template.id: "other"])
    #expect(controller.suggestions.first?.draft.title == "run 최신 내용")
    #expect(controller.failure == "isolated library load failure") // Successful refresh preserves prior failure.
    let task = try #require(controller.add(input: "/run", on: Date(), in: context))
    #expect(task.title == "run 최신 내용") // Preserved explicit highlight is still a current title match.
    #expect(controller.preparedAliasKeys.isEmpty && controller.entries.isEmpty && controller.suggestions.isEmpty)
    #expect(controller.failure == nil && !controller.isPresented)
}

@Test @MainActor
func goalPreparedAliasFailedInitialLoadRetriesWithSameInput() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let record = goalPreparedAliasInsert(1, title: "새 대상", alias: "run", in: context)
    try context.save()
    let probe = GoalPreparedAliasLoadProbe()
    probe.fails = true
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })
    controller.update("/run", in: context)
    #expect(controller.entries.isEmpty && controller.preparedAliasKeys.isEmpty && controller.suggestions.isEmpty)
    let failure = controller.failure
    probe.fails = false
    controller.refresh(in: context)
    #expect(controller.preparedAliasKeys == [record.template.id: "run"])
    #expect(controller.suggestions.map(\.id) == [record.template.id] && controller.failure == failure)
    #expect(controller.add(input: "/run", on: Date(), in: context) != nil)
    #expect(controller.preparedAliasKeys.isEmpty && controller.failure == nil)
    #expect(probe.calls == 3)
}

@Test @MainActor
func goalPreparedAliasLatestSubmitKeepsStaleImplicitSelectionFailure() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let selected = goalPreparedAliasInsert(1, title: "선택 대상", alias: "run", in: context)
    let replacement = goalPreparedAliasInsert(2, title: "다른 대상", alias: "later", in: context)
    try context.save()
    let selectedID = selected.template.id
    let controller = SavedTaskQuickEntryController()
    controller.update("/run", in: context)
    #expect(controller.moveSelection(by: 1))
    try SavedTaskLibraryService.delete(id: selectedID, in: context)
    replacement.template.quickEntryAlias = "run"
    try context.save()
    #expect(controller.add(input: "/run", on: Date(), in: context) == nil)
    #expect(controller.preparedAliasKeys == [replacement.template.id: "run"])
    #expect(controller.suggestions.map(\.id) == [replacement.template.id])
    #expect(controller.highlightedID == selectedID && controller.failure != nil && controller.isPresented)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
}

@Test @MainActor
func goalPreparedAliasLatestExplicitSelectionAndAmbiguousAliasRemainSafe() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let first = goalPreparedAliasInsert(1, title: "첫 대상", alias: "run", in: context)
    let second = goalPreparedAliasInsert(2, title: "둘째 대상", alias: "RUN", in: context)
    try context.save()
    let controller = SavedTaskQuickEntryController()
    #expect(controller.add(input: "/run", on: Date(), in: context) == nil)
    #expect(controller.preparedAliasKeys.count == 2 && controller.suggestions.count == 2)
    #expect(controller.failure?.contains("여러 개") == true)
    first.template.quickEntryAlias = nil
    first.item.title = "run 최신 대상"
    first.item.note = "최신 메모"
    first.item.checklistTitles = ["최신 체크"]
    try context.save()
    let date = try #require(DayKey.date(from: "2026-10-20"))
    let task = try #require(controller.add(input: "/run", selectedID: first.template.id, on: date, in: context))
    #expect(task.title == "run 최신 대상" && task.note == "최신 메모")
    #expect(task.plannedDayKey == "2026-10-20" && task.status == TaskStatus.todo.rawValue)
    #expect(try TaskChecklistService.items(for: task.id, in: context).map(\.title) == ["최신 체크"])
    #expect(controller.preparedAliasKeys.isEmpty && controller.entries.isEmpty && controller.suggestions.isEmpty)
    #expect(controller.add(input: "/run", on: date, in: context)?.title == second.item.title)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 2)
}

@MainActor
private final class GoalPreparedAliasLoadProbe {
    var calls = 0
    var fails = false

    func load(in context: ModelContext) throws -> [SavedTaskEntry] {
        calls += 1
        if fails { throw LoadFailure.failed }
        return try SavedTaskLibraryService.load(in: context)
    }

    private enum LoadFailure: LocalizedError {
        case failed
        var errorDescription: String? { "isolated library load failure" }
    }
}

private func goalPreparedAliasOriginalSuggestions(_ entries: [SavedTaskEntry], input: String) -> [SavedTaskEntry] {
    guard let query = SavedTaskShortcutRules.query(in: input) else { return [] }
    let candidates: [(entry: SavedTaskEntry, isExact: Bool)] = entries.compactMap { entry in
        let alias = query.isEmpty ? nil : SavedTaskShortcutRules.aliasKey(entry.quickEntryAlias)
        guard query.isEmpty || alias?.contains(query) == true || entry.draft.title.localizedStandardContains(query)
        else { return nil }
        return (entry, !query.isEmpty && alias == query)
    }
    return candidates.sorted {
        if $0.isExact != $1.isExact { return $0.isExact }
        if $0.entry.isFavorite != $1.entry.isFavorite { return $0.entry.isFavorite }
        let comparison = $0.entry.draft.title.localizedStandardCompare($1.entry.draft.title)
        return comparison == .orderedSame
            ? $0.entry.id.uuidString < $1.entry.id.uuidString : comparison == .orderedAscending
    }.map(\.entry)
}

private func goalPreparedAliasExpectEqual(_ actual: [SavedTaskEntry], _ expected: [SavedTaskEntry]) {
    #expect(actual.map(\.id) == expected.map(\.id))
    #expect(actual.map(\.draft) == expected.map(\.draft))
    #expect(actual.map(\.quickEntryAlias) == expected.map(\.quickEntryAlias))
    #expect(actual.map(\.isFavorite) == expected.map(\.isFavorite))
}

@MainActor
private func goalPreparedAliasExpectControllerMatches(_ controller: SavedTaskQuickEntryController) {
    goalPreparedAliasExpectEqual(controller.suggestions,
        goalPreparedAliasOriginalSuggestions(controller.entries, input: controller.input))
}

private func goalPreparedAliasEntry(_ index: Int, title: String, alias: String?, favorite: Bool) -> SavedTaskEntry {
    SavedTaskEntry(id: goalPreparedAliasID(index),
                  draft: .init(title: title, note: "메모 \(index)", tags: ["태그"], estimatedMinutes: index,
                               checklistTitles: ["준비", "마무리"], order: Double(index) * 100),
                  isFavorite: favorite, quickEntryAlias: alias)
}

private func goalPreparedAliasID(_ index: Int) -> UUID {
    UUID(uuidString: String(format: "B4000000-0000-0000-0000-%012X", index))!
}

@MainActor @discardableResult
private func goalPreparedAliasInsert(
    _ index: Int, title: String, alias: String?, in context: ModelContext
) -> (template: TaskTemplate, item: TaskTemplateItem) {
    let now = Date(timeIntervalSince1970: 1_788_400_000)
    let id = goalPreparedAliasID(index)
    let template = TaskTemplate(id: id, name: title, isFavorite: false, quickEntryAlias: alias,
                                createdAt: now, updatedAt: now)
    let item = TaskTemplateItem(templateId: id, title: title, note: "메모", checklistTitles: ["준비"],
                                order: Double(index) * 100, createdAt: now, updatedAt: now)
    context.insert(template)
    context.insert(item)
    return (template, item)
}
