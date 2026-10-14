import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func quickEntryReusesCleanLibraryAcrossCommandEntriesAndIgnoresTaskOnlySaves() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let record = insertQuickEntryCacheRecord(title: "운동 준비", alias: "운동", in: context)
    try context.save()
    let probe = QuickEntryCacheLoadProbe()
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })

    controller.update("/", in: context)
    #expect(probe.calls == 1)
    controller.update("일반 작업", in: context)
    #expect(controller.entries.isEmpty && controller.suggestions.isEmpty && controller.preparedAliasKeys.isEmpty)
    #expect(!controller.isPresented && controller.highlightedID == nil && controller.failure == nil)
    context.insert(Task(title: "다른 일반 작업", plannedAt: Date(), order: 100))
    try context.save()
    controller.update("/운동", in: context)
    #expect(probe.calls == 1)
    #expect(controller.suggestions.map(\.id) == [record.template.id])
    #expect(controller.preparedAliasKeys == [record.template.id: "운동"])

    controller.update("일반 제목", in: context)
    controller.refresh(in: context)
    #expect(probe.calls == 1)
    controller.update("/", in: context)
    #expect(probe.calls == 2 && controller.entries.count == 1)
}

@Test @MainActor
func quickEntryCachedLibraryInvalidatesForDirectTemplateSaveAndPendingRollback() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let record = insertQuickEntryCacheRecord(title: "원래 작업", alias: "before", in: context)
    try context.save()
    let probe = QuickEntryCacheLoadProbe()
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })
    controller.update("/before", in: context)
    controller.update("일반 입력", in: context)
    record.template.quickEntryAlias = "after"
    record.item.title = "저장한 최신 작업"
    try context.save()
    controller.update("/after", in: context)
    #expect(probe.calls == 2 && controller.suggestions.first?.draft.title == "저장한 최신 작업")

    controller.update("일반 입력", in: context)
    record.item.title = "되돌릴 미저장 작업"
    controller.update("/after", in: context)
    #expect(probe.calls == 3 && controller.suggestions.first?.draft.title == "되돌릴 미저장 작업")
    controller.update("일반 입력", in: context)
    context.rollback()
    controller.update("/after", in: context)
    #expect(probe.calls == 4 && controller.suggestions.first?.draft.title == "저장한 최신 작업")
    #expect(!context.hasChanges)
}

@Test @MainActor
func quickEntryNeverReusesLibraryFromAnotherContext() throws {
    let first = try PlanBaseContainerFactory.makeInMemory()
    let second = try PlanBaseContainerFactory.makeInMemory()
    insertQuickEntryCacheRecord(title: "첫 저장소", alias: "first", in: first.mainContext)
    insertQuickEntryCacheRecord(title: "둘째 저장소", alias: "second", in: second.mainContext)
    try first.mainContext.save()
    try second.mainContext.save()
    let probe = QuickEntryCacheLoadProbe()
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })
    controller.update("/", in: first.mainContext)
    controller.update("/", in: second.mainContext)
    #expect(probe.calls == 2 && controller.suggestions.map(\.draft.title) == ["둘째 저장소"])
    controller.update("일반 작업", in: second.mainContext)
    controller.update("/", in: first.mainContext)
    #expect(probe.calls == 3 && controller.suggestions.map(\.draft.title) == ["첫 저장소"])
}

@Test @MainActor
func quickEntrySubmissionAvoidsFullLibraryLoadAndStillValidatesLatestAlias() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let record = insertQuickEntryCacheRecord(title: "운동 준비", alias: "run", in: context)
    try context.save()
    let probe = QuickEntryCacheLoadProbe()
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })
    let first = try #require(controller.add(input: "/run", on: Date(), in: context))
    #expect(first.title == "운동 준비" && probe.calls == 0)
    controller.update("/run", in: context)
    #expect(probe.calls == 1)
    record.template.quickEntryAlias = "changed"
    record.item.title = "최신 제목"
    try context.save()
    #expect(controller.add(input: "/run", on: Date(), in: context) == nil)
    #expect(probe.calls == 2 && controller.failure != nil && controller.input == "/run")
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
    let second = try #require(controller.add(input: "/changed", on: Date(), in: context))
    #expect(second.title == "최신 제목" && probe.calls == 2)
    #expect(controller.input.isEmpty && controller.entries.isEmpty && controller.failure == nil)
}

@Test @MainActor
func quickEntryCachedSubmissionRejectsNewDuplicateAliasAndDeletedSelection() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let record = insertQuickEntryCacheRecord(title: "첫 대상", alias: "run", in: context)
    try context.save()
    let controller = SavedTaskQuickEntryController()
    controller.update("/run", in: context)
    let duplicate = insertQuickEntryCacheRecord(title: "다른 대상", alias: "RUN", in: context)
    try context.save()
    #expect(controller.add(input: "/run", on: Date(), in: context) == nil)
    #expect(controller.failure?.contains("여러 개") == true)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    controller.update("/", in: context)
    try SavedTaskLibraryService.delete(id: record.template.id, in: context)
    #expect(controller.add(input: "/", selectedID: record.template.id, on: Date(), in: context) == nil)
    #expect(controller.suggestions.map(\.id) == [duplicate.template.id])
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
}

@Test @MainActor
func quickEntryOrdinaryInputAndSubmissionNeverLoadLibrary() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let probe = QuickEntryCacheLoadProbe()
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })
    controller.update("일반 작업", in: container.mainContext)
    controller.refresh(in: container.mainContext)
    #expect(controller.add(input: "일반 작업", on: Date(), in: container.mainContext) == nil)
    #expect(probe.calls == 0 && controller.entries.isEmpty && controller.suggestions.isEmpty)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<Task>()) == 0)
}

@Test @MainActor
func quickEntrySuccessfulImportInvalidatesHiddenCacheButOtherSyncEventsDoNot() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    insertQuickEntryCacheRecord(title: "저장한 작업", alias: "saved", in: context)
    try context.save()
    let probe = QuickEntryCacheLoadProbe()
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })
    controller.update("/", in: context)
    for event in [
        CloudKitSyncEventSummary(kind: .export, isCompleted: true, succeeded: true),
        CloudKitSyncEventSummary(kind: .import, isCompleted: false, succeeded: true),
        CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: false),
    ] {
        controller.update("일반 입력", in: context)
        controller.refresh(after: event, in: context)
        controller.update("/", in: context)
        #expect(probe.calls == 1)
    }
    controller.update("일반 입력", in: context)
    controller.refresh(after: .init(kind: .import, isCompleted: true, succeeded: true), in: context)
    #expect(probe.calls == 1 && controller.entries.isEmpty)
    controller.update("/", in: context)
    #expect(probe.calls == 2)
}

@Test @MainActor
func quickEntryFailedRefreshCannotLeaveReusableCachedLibrary() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    insertQuickEntryCacheRecord(title: "저장한 작업", alias: "saved", in: context)
    try context.save()
    let probe = QuickEntryCacheLoadProbe()
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })
    controller.update("/", in: context)
    probe.fails = true
    controller.refresh(in: context)
    #expect(probe.calls == 2 && controller.failure != nil)
    #expect(controller.suggestions.count == 1)
    controller.update("일반 입력", in: context)
    probe.fails = false
    controller.update("/", in: context)
    #expect(probe.calls == 3 && controller.suggestions.count == 1)
}

@Test @MainActor
func quickEntryFailedSubmissionKeepsOriginalErrorIfDisplayRefreshAlsoFails() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let record = insertQuickEntryCacheRecord(title: "저장한 작업", alias: "saved", in: context)
    try context.save()
    let probe = QuickEntryCacheLoadProbe()
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })
    controller.update("/saved", in: context)
    record.template.quickEntryAlias = "changed"
    try context.save()
    probe.fails = true
    #expect(controller.add(input: "/saved", on: Date(), in: context) == nil)
    #expect(controller.failure == SavedTaskShortcutRules.Failure.unknownAlias.errorDescription)
    #expect(controller.input == "/saved" && controller.isPresented)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    controller.update("일반 입력", in: context)
    probe.fails = false
    controller.update("/changed", in: context)
    #expect(probe.calls == 3 && controller.suggestions.first?.id == record.template.id)
}

@Test @MainActor
func quickEntryCachedReentryRecomputesLocaleRankingWithoutFetching() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    insertQuickEntryCacheRecord(title: "Cafe\u{301} 10", alias: "CAFÉ", in: context)
    insertQuickEntryCacheRecord(title: "CAFÉ 2", alias: "cafe\u{301}", in: context)
    try context.save()
    let probe = QuickEntryCacheLoadProbe()
    let controller = SavedTaskQuickEntryController(loadLibrary: { try probe.load(in: $0) })
    controller.update("/", in: context)
    controller.update("일반 입력", in: context)
    NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
    for _ in 0..<50 { await Swift.Task.yield() }
    controller.update("/cafe\u{301}", in: context)
    #expect(probe.calls == 1)
    #expect(controller.suggestions.map(\.id) == SavedTaskShortcutRules.suggestions(controller.entries, input: controller.input).map(\.id))
    #expect(controller.preparedAliasKeys.values.allSatisfy { $0 == "café" })
}

@MainActor
private final class QuickEntryCacheLoadProbe {
    var calls = 0
    var fails = false

    func load(in context: ModelContext) throws -> [SavedTaskEntry] {
        calls += 1
        if fails { throw Failure.failed }
        return try SavedTaskLibraryService.load(in: context)
    }

    private enum Failure: Error { case failed }
}

@MainActor @discardableResult
private func insertQuickEntryCacheRecord(title: String, alias: String, in context: ModelContext)
    -> (template: TaskTemplate, item: TaskTemplateItem)
{
    let template = TaskTemplate(name: title, quickEntryAlias: alias)
    let item = TaskTemplateItem(templateId: template.id, title: title, order: 100)
    context.insert(template)
    context.insert(item)
    return (template, item)
}
