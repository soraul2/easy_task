import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func savedTaskSubmissionResolutionMatchesFullLibraryForConvergingCopiesAndCanonicalAliases() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    var templateIDs: [UUID] = []
    func insert(_ title: String, alias: String?, children: [String] = ["대상 작업"]) -> TaskTemplate {
        let template = TaskTemplate(name: title, quickEntryAlias: alias, createdAt: time, updatedAt: time)
        templateIDs.append(template.id)
        context.insert(template)
        for (index, child) in children.enumerated() {
            context.insert(TaskTemplateItem(templateId: template.id, title: child,
                order: Double(index + 1) * 100, createdAt: time, updatedAt: time))
        }
        return template
    }
    for index in 0..<270 { _ = insert("페이지 \(index)", alias: "page\(index)") }
    _ = insert("한글", alias: "운동", children: ["운동 준비"])
    _ = insert("라틴", alias: "CAFÉ", children: ["Cafe\u{301} 준비"])
    _ = insert("충돌 A", alias: "RUN")
    _ = insert("충돌 B", alias: "run")
    _ = insert("빈 항목", alias: "run", children: [" \n"])
    _ = insert("묶음", alias: "run", children: ["A", "B"])
    let changing = insert("이전 이름", alias: "before")
    context.insert(TaskTemplate(id: changing.id, name: "최신 이름", quickEntryAlias: "after",
        createdAt: time, updatedAt: time.addingTimeInterval(60)))
    context.insert(TaskTemplate(id: changing.id, name: "이미 수렴한 복사본", quickEntryAlias: "ignored",
        createdAt: time, updatedAt: time.addingTimeInterval(120), supersededAt: time))

    // A child’s newest physical copy can now belong to another parent. The
    // selected-ID shortcut must use the same global winner as the full library.
    let previousParent = insert("이전 부모", alias: "oldparent", children: [])
    let currentParent = insert("현재 부모", alias: "newparent", children: [])
    let moved = TaskTemplateItem(templateId: previousParent.id, title: "이전 자식",
        order: 100, createdAt: time, updatedAt: time)
    context.insert(moved)
    context.insert(TaskTemplateItem(id: moved.id, templateId: currentParent.id, title: "현재 자식",
        order: 100, createdAt: time, updatedAt: time.addingTimeInterval(60)))
    try context.save()

    let entries = try SavedTaskLibraryService.load(in: context)
    let selectedIDs = [templateIDs[0], templateIDs[269]] + Array(templateIDs.dropFirst(270)) + [UUID()]
    for input in ["/", "/RUN", "/운동", "/운", "/cafe\u{301}", "/before", "/after",
                  "/ignored", "/oldparent", "/newparent", "/page269", "/대상", "/missing", "일반 제목"] {
        let expected = submissionResult { try SavedTaskShortcutRules.exactMatch(in: entries, input: input) }
        let actual = submissionResult {
            try SavedTaskLibraryService.submissionTemplateID(input: input, selectedID: nil, in: context)
        }
        #expect(actual == expected, "Exact shortcut result for \(input)")
        let suggestedIDs = Set(SavedTaskShortcutRules.suggestions(entries, input: input).map(\.id))
        for selectedID in selectedIDs {
            let actual = submissionResult {
                try SavedTaskLibraryService.submissionTemplateID(input: input, selectedID: selectedID, in: context)
            }
            let expected = SavedTaskShortcutRules.query(in: input) == nil ? "selectionRequired"
                : suggestedIDs.contains(selectedID) ? selectedID.uuidString : "unavailable"
            #expect(actual == expected, "Selected shortcut result for \(input)")
        }
    }
    #expect(!context.hasChanges)
    let movedTask = try SavedTaskLibraryService.add(input: "/newparent", on: time, in: context)
    #expect(movedTask.title == "현재 자식")
    #expect(throws: SavedTaskLibraryService.Failure.self) {
        try SavedTaskLibraryService.add(input: "/", selectedID: previousParent.id, on: time, in: context)
    }
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
}

@Test @MainActor
func savedTaskSubmissionRejectsChangedSelectionAndCopiesLatestDraftInsideCommand() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let template = try SavedTaskLibraryService.create(
        draft: .init(title: "원래 작업", note: "원래 내용", checklistTitles: ["원래 항목"], order: 100),
        isFavorite: false, quickEntryAlias: "before", in: context)
    let controller = SavedTaskQuickEntryController()
    controller.update("/before", in: context)
    try SavedTaskLibraryService.update(id: template.id,
        draft: .init(title: "최신 작업", note: "최신 내용", priority: TaskPriority.high.rawValue,
            tags: ["최신"], estimatedMinutes: 25, checklistTitles: ["최신 항목"], order: 100),
        isFavorite: true, quickEntryAlias: "after", in: context)
    #expect(controller.add(input: "/before", selectedID: template.id, on: Date(), in: context) == nil)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    let task = try #require(controller.add(input: "/최신", selectedID: template.id, on: Date(), in: context))
    #expect(task.title == "최신 작업" && task.note == "최신 내용" && task.tags == ["최신"])
    #expect(task.priority == TaskPriority.high.rawValue && task.estimatedMinutes == 25)
    #expect(try TaskChecklistService.items(for: task.id, in: context).map(\.title) == ["최신 항목"])
    #expect(controller.input.isEmpty && controller.failure == nil && !context.hasChanges)
}

@Test @MainActor
func savedTaskInvalidSubmissionKeepsUnrelatedPendingEditsCancellableAndDoesNotInsertTask() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let existing = Task(title: "기존 작업", plannedAt: Date(), order: 100)
    context.insert(existing)
    for alias in ["run", "RUN"] {
        let template = TaskTemplate(name: "충돌 후보", quickEntryAlias: alias)
        context.insert(template)
        context.insert(TaskTemplateItem(templateId: template.id, title: "충돌 후보", order: 100))
    }
    let removed = TaskTemplate(name: "삭제한 후보", quickEntryAlias: "deleted")
    let removedID = removed.id
    context.insert(removed)
    try context.save()
    context.delete(removed)
    try context.save()
    existing.title = "다른 화면의 대기 편집"
    #expect(throws: SavedTaskShortcutRules.Failure.self) {
        try SavedTaskLibraryService.add(input: "/missing", on: Date(), in: context)
    }
    #expect(context.hasChanges)
    #expect(throws: SavedTaskShortcutRules.Failure.self) {
        try SavedTaskLibraryService.add(input: "/run", on: Date(), in: context)
    }
    #expect(context.hasChanges)
    #expect(throws: SavedTaskLibraryService.Failure.self) {
        try SavedTaskLibraryService.add(input: "/", selectedID: removedID, on: Date(), in: context)
    }
    #expect(existing.title == "다른 화면의 대기 편집" && context.hasChanges)
    #expect(try context.fetch(FetchDescriptor<Task>()).map(\.id) == [existing.id])
    #expect(try ModelContext(container).fetch(FetchDescriptor<Task>()).first?.title == "기존 작업")
    context.rollback()
    #expect(existing.title == "기존 작업" && !context.hasChanges)
}

@Test @MainActor
func savedTaskSubmissionReadOnlyEngineFailureRollsBackTaskAndRetainsShortcutDraft() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseShortcutReadOnly-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = directory.appendingPathComponent("shortcut.store")
    try autoreleasepool {
        let writer = try PlanBaseContainerFactory.makePersistent(storeURL: store, mode: .local)
        writer.mainContext.autosaveEnabled = false
        _ = try SavedTaskLibraryService.create(draft: .init(title: "저장할 작업", checklistTitles: ["항목"], order: 100),
            isFavorite: false, quickEntryAlias: "save", in: writer.mainContext)
    }
    try autoreleasepool {
        let schema = PlanBaseContainerFactory.schema
        let configuration = ModelConfiguration(PlanBaseCompatibility.modelConfigurationName,
            schema: schema, url: store, allowsSave: false, cloudKitDatabase: .none)
        let reader = try ModelContainer(for: schema, configurations: [configuration])
        let context = reader.mainContext
        context.autosaveEnabled = false
        let originalLibrary = try SavedTaskLibraryService.load(in: context)
        let notifications = SubmissionReadOnlyNotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification, object: context, queue: nil
        ) { _ in notifications.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        var failure: NSError?
        do { _ = try SavedTaskLibraryService.add(input: "/save", on: Date(), in: context) }
        catch { failure = error as NSError }
        let error = try #require(failure)
        #expect(error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileWriteNoPermission.rawValue)
        // Observe the count API immediately, before a full fetch can refresh
        // registration/cache state. Actual row fetches and the independent
        // persisted graph remain the authoritative rollback assertions below.
        let immediateTaskCount = try context.fetchCount(FetchDescriptor<Task>())
        let immediateChecklistCount = try context.fetchCount(FetchDescriptor<TaskChecklistItem>())
        let immediateInserted = context.insertedModelsArray.count
        let immediateChanged = context.changedModelsArray.count
        let immediateDeleted = context.deletedModelsArray.count
        let persistedContext = ModelContext(reader)
        persistedContext.autosaveEnabled = false
        let persistedTasks = try persistedContext.fetch(FetchDescriptor<Task>())
        let persistedChecklist = try persistedContext.fetch(FetchDescriptor<TaskChecklistItem>())
        let contextTasks = try context.fetch(FetchDescriptor<Task>())
        let contextChecklist = try context.fetch(FetchDescriptor<TaskChecklistItem>())
        let taskCountAfterFullFetch = try context.fetchCount(FetchDescriptor<Task>())
        let checklistCountAfterFullFetch = try context.fetchCount(FetchDescriptor<TaskChecklistItem>())
        let evidence: [String: Any] = [
            "protocol": "shortcut-readonly-rollback-fetch-versus-count-20261013-004",
            "errorDomain": error.domain, "errorCode": error.code,
            "immediateTaskFetchCount": immediateTaskCount,
            "immediateChecklistFetchCount": immediateChecklistCount,
            "immediateInsertedModels": immediateInserted,
            "immediateChangedModels": immediateChanged,
            "immediateDeletedModels": immediateDeleted,
            "persistedTaskRows": persistedTasks.count,
            "persistedChecklistRows": persistedChecklist.count,
            "sameContextTaskRows": contextTasks.count,
            "sameContextChecklistRows": contextChecklist.count,
            "taskFetchCountAfterFullFetch": taskCountAfterFullFetch,
            "checklistFetchCountAfterFullFetch": checklistCountAfterFullFetch,
            "sameContextHasChanges": context.hasChanges,
        ]
        let evidenceBytes = try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
        print("SUBMISSION_READONLY_ROLLBACK_EVIDENCE " + String(decoding: evidenceBytes, as: UTF8.self))
        #expect(persistedTasks.isEmpty && persistedChecklist.isEmpty)
        #expect(contextTasks.isEmpty && contextChecklist.isEmpty)
        #expect(immediateInserted == 0 && immediateChanged == 0 && immediateDeleted == 0)
        #expect(!context.hasChanges)
        #expect(notifications.value == 0)
        #expect(!PersistenceCommandService.isPerformingCommand(in: context))
        let libraryAfterFailure = try SavedTaskLibraryService.load(in: context)
        #expect(libraryAfterFailure.map(\.id) == originalLibrary.map(\.id))
        #expect(libraryAfterFailure.map(\.draft) == originalLibrary.map(\.draft))
        let controller = SavedTaskQuickEntryController()
        controller.update("/save", in: context)
        #expect(controller.add(input: "/save", on: Date(), in: context) == nil)
        #expect(controller.input == "/save" && controller.isPresented && controller.failure != nil)
        #expect(controller.suggestions.count == 1 && controller.suggestions.first?.draft.title == "저장할 작업")
        #expect(try context.fetch(FetchDescriptor<Task>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskChecklistItem>()).isEmpty)
        #expect(try ModelContext(reader).fetch(FetchDescriptor<Task>()).isEmpty)
        #expect(try ModelContext(reader).fetch(FetchDescriptor<TaskChecklistItem>()).isEmpty)
        #expect(!context.hasChanges && notifications.value == 0)
    }
}

private final class SubmissionReadOnlyNotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private func submissionResult(_ operation: () throws -> UUID) -> String {
    do { return try operation().uuidString }
    catch let failure as SavedTaskShortcutRules.Failure {
        switch failure {
        case .invalidAlias: return "invalidAlias"
        case .duplicateAlias: return "duplicateAlias"
        case .unknownAlias: return "unknownAlias"
        case .ambiguousAlias: return "ambiguousAlias"
        case .selectionRequired: return "selectionRequired"
        }
    } catch let failure as SavedTaskLibraryService.Failure {
        switch failure {
        case .unavailable: return "unavailable"
        case .emptyTitle: return "emptyTitle"
        case .invalidEstimate: return "invalidEstimate"
        }
    } catch { return "unexpected-\(error)" }
}
