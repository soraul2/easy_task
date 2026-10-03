import Foundation
import Observation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func goalQuickEntryLocaleSignalRecomputesWithoutReloadOrPresentationChange() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    // This fixture explicitly keeps a draft pending across asynchronous locale
    // notifications; ModelContext's timed autosave is outside that contract.
    context.autosaveEnabled = false
    let record = insertGoalQuickEntryRecord(1, title: "운동 준비", alias: "운동", favorite: true, in: context)
    try context.save()
    let controller = SavedTaskQuickEntryController()
    controller.update("/", in: context)
    #expect(controller.moveSelection(by: 1))
    let selection = controller.highlightedID
    let original = controller.entries
    record.item.title = "미저장 수정은 라이브러리 갱신 때 읽는다"
    await confirmation("locale changes invalidate observable ranked results") { changed in
        withObservationTracking { _ = controller.suggestions } onChange: { changed() }
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        for _ in 0..<50 { await Swift.Task.yield() }
    }
    #expect(controller.entries.map(\.id) == original.map(\.id))
    #expect(controller.entries.map(\.draft) == original.map(\.draft))
    #expect(controller.entries.map(\.quickEntryAlias) == original.map(\.quickEntryAlias))
    #expect(controller.entries.map(\.isFavorite) == original.map(\.isFavorite))
    #expect(controller.highlightedID == selection && controller.isPresented)
    expectGoalQuickEntryMatchesRules(controller)
    #expect(context.hasChanges)
    #expect(controller.dismiss())
    NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
    for _ in 0..<50 { await Swift.Task.yield() }
    #expect(!controller.isPresented && controller.highlightedID == nil)
    controller.update("일반 입력", in: context)
    NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
    for _ in 0..<50 { await Swift.Task.yield() }
    #expect(controller.entries.isEmpty && controller.suggestions.isEmpty && !controller.isPresented)
}

@Test @MainActor
func goalQuickEntryResultsMatchExistingRulesAcrossQueriesAndSelection() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    insertGoalQuickEntryRecord(1, title: "운동 준비", alias: "운동", favorite: true, in: context)
    insertGoalQuickEntryRecord(2, title: "동일 제목", alias: "WORK", favorite: false, in: context)
    insertGoalQuickEntryRecord(3, title: "동일 제목", alias: "work", favorite: true, in: context)
    insertGoalQuickEntryRecord(4, title: "별칭 없는 작업", alias: nil, favorite: false, in: context)
    try context.save()
    let controller = SavedTaskQuickEntryController()
    for query in ["일반 작업", "/", "/운", "/운동", "/운동", " /WORK ", "/없는검색", "/wo", "/", "일반 입력"] {
        controller.update(query, in: context)
        expectGoalQuickEntryMatchesRules(controller)
        #expect(controller.input == query)
        #expect(controller.highlightedID == nil)
    }
    controller.update("/", in: context)
    let ranked = controller.suggestions.map(\.id)
    #expect(controller.moveSelection(by: 1))
    #expect(controller.highlightedID == ranked.first)
    #expect(controller.moveSelection(by: 100))
    #expect(controller.highlightedID == ranked.last)
    #expect(controller.moveSelection(by: -100))
    #expect(controller.highlightedID == ranked.first)
    #expect(controller.suggestions.map(\.id) == ranked)
    controller.update("/운동", in: context)
    #expect(controller.highlightedID == nil)
    #expect(controller.suggestions.count == 1)
    controller.update("/운동", in: context)
    #expect(controller.highlightedID == nil)
    expectGoalQuickEntryMatchesRules(controller)
}

@Test @MainActor
func goalQuickEntrySameInputRefreshReplacesMetadataRankingAndNewEntries() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let first = insertGoalQuickEntryRecord(1, title: "첫 작업", alias: "first", favorite: true, in: context)
    let second = insertGoalQuickEntryRecord(2, title: "둘째 작업", alias: "second", favorite: false, in: context)
    try context.save()
    let controller = SavedTaskQuickEntryController()
    controller.update("/", in: context)
    #expect(controller.moveSelection(by: 1))
    #expect(controller.highlightedID == first.template.id)
    let previous = try #require(controller.suggestions.first)

    first.template.isFavorite = false
    first.template.quickEntryAlias = "new-first"
    first.item.title = "바뀐 첫 작업"
    first.item.note = "최신 메모"
    first.item.checklistTitles = ["새 체크"]
    second.template.isFavorite = true
    let added = insertGoalQuickEntryRecord(3, title: "새 작업", alias: "third", favorite: false, in: context)
    try context.save()
    // Value snapshots remain independent of changed models until an explicit refresh.
    #expect(previous.draft.title == "첫 작업" && previous.quickEntryAlias == "first")
    #expect(controller.suggestions.count == 2)

    controller.refresh(in: context)
    #expect(controller.input == "/")
    #expect(controller.suggestions.count == 3)
    #expect(controller.suggestions.first?.id == second.template.id)
    #expect(controller.highlightedID == first.template.id)
    let updated = try #require(controller.suggestions.first { $0.id == first.template.id })
    #expect(updated.draft.title == "바뀐 첫 작업")
    #expect(updated.draft.note == "최신 메모" && updated.draft.checklistTitles == ["새 체크"])
    #expect(updated.quickEntryAlias == "new-first" && !updated.isFavorite)
    #expect(controller.suggestions.contains { $0.id == added.template.id })
    expectGoalQuickEntryMatchesRules(controller)
}

@Test @MainActor
func goalQuickEntryRefreshPrunesRemovedAliasAndDeletedLibraryValues() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let record = insertGoalQuickEntryRecord(1, title: "원래 대상", alias: "run", favorite: false, in: context)
    try context.save()
    let controller = SavedTaskQuickEntryController()
    controller.update("/run", in: context)
    #expect(controller.moveSelection(by: 1))
    record.template.quickEntryAlias = nil
    try context.save()
    controller.refresh(in: context)
    #expect(controller.input == "/run" && controller.suggestions.isEmpty)
    #expect(controller.highlightedID == nil)
    #expect(controller.entries.count == 1)

    controller.update("/", in: context)
    let snapshot = try #require(controller.suggestions.first)
    try SavedTaskLibraryService.delete(id: record.template.id, in: context)
    #expect(snapshot.draft.title == "원래 대상")
    #expect(controller.suggestions.count == 1)
    controller.refresh(in: context)
    #expect(controller.entries.isEmpty && controller.suggestions.isEmpty)
    #expect(controller.highlightedID == nil)
}

@Test @MainActor
func goalQuickEntryDismissAndOrdinaryInputKeepReentryContract() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    insertGoalQuickEntryRecord(1, title: "첫 작업", alias: "alpha", favorite: false, in: context)
    try context.save()
    let controller = SavedTaskQuickEntryController()
    controller.update("/", in: context)
    #expect(controller.moveSelection(by: 1))
    #expect(controller.dismiss())
    #expect(!controller.isPresented && controller.highlightedID == nil)
    #expect(controller.suggestions.count == 1)
    controller.update("/", in: context)
    #expect(!controller.isPresented && !controller.moveSelection(by: 1))
    controller.update("/a", in: context)
    #expect(controller.isPresented && controller.suggestions.count == 1)

    controller.update("일반 제목", in: context)
    #expect(controller.entries.isEmpty && controller.suggestions.isEmpty)
    #expect(!controller.isPresented && controller.highlightedID == nil && controller.failure == nil)
    insertGoalQuickEntryRecord(2, title: "새 작업", alias: "beta", favorite: false, in: context)
    try context.save()
    controller.refresh(in: context)
    #expect(controller.entries.isEmpty && controller.suggestions.isEmpty)
    controller.update("/", in: context)
    #expect(controller.entries.count == 2 && controller.suggestions.count == 2)
    #expect(controller.input == "/" && controller.isPresented)
}

@Test @MainActor
func goalQuickEntryStaleHighlightNeverFallsBackToAnotherExactAlias() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let selected = insertGoalQuickEntryRecord(1, title: "선택 대상", alias: "run", favorite: false, in: context)
    let replacement = insertGoalQuickEntryRecord(2, title: "다른 대상", alias: "later", favorite: false, in: context)
    try context.save()
    let selectedID = selected.template.id
    let controller = SavedTaskQuickEntryController()
    controller.update("/run", in: context)
    #expect(controller.moveSelection(by: 1))
    #expect(controller.highlightedID == selectedID)
    try SavedTaskLibraryService.delete(id: selectedID, in: context)
    replacement.template.quickEntryAlias = "run"
    try context.save()

    #expect(controller.add(input: "/run", on: Date(), in: context) == nil)
    #expect(controller.suggestions.map(\.id) == [replacement.template.id])
    #expect(controller.highlightedID == selectedID)
    #expect(controller.input == "/run" && controller.isPresented && controller.failure != nil)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
}

@Test @MainActor
func goalQuickEntryExplicitSelectionUsesLatestTitleMatchButUnselectedAliasFails() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let record = insertGoalQuickEntryRecord(1, title: "run 작업", alias: "run", favorite: false, in: context)
    try context.save()
    let controller = SavedTaskQuickEntryController()
    controller.update("/run", in: context)
    record.template.quickEntryAlias = "other"
    record.item.title = "run 최신 작업"
    record.item.note = "최신 내용"
    try context.save()
    let date = try #require(DayKey.date(from: "2026-10-20"))
    let task = try #require(controller.add(input: "/run", selectedID: record.template.id, on: date, in: context))
    #expect(task.title == "run 최신 작업" && task.note == "최신 내용")
    #expect(task.plannedDayKey == "2026-10-20" && task.status == TaskStatus.todo.rawValue)
    #expect(controller.input.isEmpty && controller.entries.isEmpty && controller.suggestions.isEmpty)
    #expect(controller.failure == nil && !controller.isPresented)
    #expect(controller.add(input: "/run", on: date, in: context) == nil)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
    #expect(controller.input == "/run" && controller.failure != nil)
}

@Test @MainActor
func goalQuickEntrySameInputRetryPreservesFailureUntilSuccessfulAddition() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    insertGoalQuickEntryRecord(1, title: "첫 대상", alias: "run", favorite: false, in: context)
    let second = insertGoalQuickEntryRecord(2, title: "둘째 대상", alias: "run", favorite: false, in: context)
    try context.save()
    let controller = SavedTaskQuickEntryController()
    #expect(controller.add(input: "/run", on: Date(), in: context) == nil)
    let failure = try #require(controller.failure)
    #expect(controller.suggestions.count == 2 && controller.input == "/run")
    second.template.quickEntryAlias = "other"
    try context.save()
    controller.refresh(in: context)
    #expect(controller.suggestions.count == 1)
    #expect(controller.failure == failure) // Preserve the existing refresh failure contract.
    #expect(controller.add(input: "/run", on: Date(), in: context) != nil)
    #expect(controller.entries.isEmpty && controller.suggestions.isEmpty && controller.input.isEmpty)
    #expect(controller.failure == nil && !controller.isPresented)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
}

@Test @MainActor
func goalQuickEntryResultsAndHighlightRemainObservableIndependently() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let record = insertGoalQuickEntryRecord(1, title: "첫 대상", alias: "alpha", favorite: true, in: context)
    insertGoalQuickEntryRecord(2, title: "둘째 대상", alias: "beta", favorite: false, in: context)
    try context.save()
    let controller = SavedTaskQuickEntryController()
    controller.update("/", in: context)
    await confirmation("Query changes invalidate existing suggestion readers") { changed in
        withObservationTracking {
            _ = controller.suggestions.map(\.id)
        } onChange: { changed() }
        controller.update("/alpha", in: context)
    }
    #expect(controller.suggestions.map(\.id) == [record.template.id])
    try await confirmation("Same-input library refresh invalidates displayed values") { changed in
        withObservationTracking {
            _ = controller.suggestions.first?.draft.title
        } onChange: { changed() }
        record.item.title = "최신 대상"
        try context.save()
        controller.refresh(in: context)
    }
    #expect(controller.suggestions.first?.draft.title == "최신 대상")
    controller.update("/", in: context)
    await confirmation("Highlight movement leaves the suggestion projection unchanged", expectedCount: 0) { changed in
        withObservationTracking {
            _ = controller.suggestions.map(\.id)
        } onChange: { changed() }
        #expect(controller.moveSelection(by: 1))
    }
    await confirmation("Rows still observe highlight changes") { changed in
        withObservationTracking {
            _ = controller.highlightedID
        } onChange: { changed() }
        #expect(controller.moveSelection(by: 1))
    }
    expectGoalQuickEntryMatchesRules(controller)
}

@MainActor
private func expectGoalQuickEntryMatchesRules(_ controller: SavedTaskQuickEntryController) {
    let expected = SavedTaskShortcutRules.suggestions(controller.entries, input: controller.input)
    #expect(controller.suggestions.map(\.id) == expected.map(\.id))
    #expect(controller.suggestions.map(\.draft) == expected.map(\.draft))
    #expect(controller.suggestions.map(\.quickEntryAlias) == expected.map(\.quickEntryAlias))
    #expect(controller.suggestions.map(\.isFavorite) == expected.map(\.isFavorite))
}

@MainActor @discardableResult
private func insertGoalQuickEntryRecord(
    _ index: Int, title: String, alias: String?, favorite: Bool, in context: ModelContext
) -> (template: TaskTemplate, item: TaskTemplateItem) {
    let now = Date(timeIntervalSince1970: 1_788_400_000)
    let id = UUID(uuidString: String(format: "10000000-0000-0000-0000-%012X", index))!
    let template = TaskTemplate(id: id, name: title, isFavorite: favorite, quickEntryAlias: alias,
                                createdAt: now, updatedAt: now)
    let item = TaskTemplateItem(templateId: id, title: title, note: "초기 메모", checklistTitles: ["준비"],
                                order: Double(index) * 100, createdAt: now, updatedAt: now)
    context.insert(template)
    context.insert(item)
    return (template, item)
}
