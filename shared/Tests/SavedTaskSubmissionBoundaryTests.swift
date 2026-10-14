import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func savedTaskValidShortcutReadOnlyPreSaveFailureKeepsUnrelatedDirtyEditAndInput() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseShortcutPreSave-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = directory.appendingPathComponent("shortcut.store")
    let existingID = UUID()
    try autoreleasepool {
        let writer = try PlanBaseContainerFactory.makePersistent(storeURL: store, mode: .local)
        writer.mainContext.autosaveEnabled = false
        _ = try SavedTaskLibraryService.create(
            draft: .init(title: "추가할 작업", checklistTitles: ["항목"], order: 100),
            isFavorite: false, quickEntryAlias: "save", in: writer.mainContext)
        writer.mainContext.insert(Task(id: existingID, title: "저장된 원본", plannedAt: Date(), order: 100))
        try writer.mainContext.save()
    }
    try autoreleasepool {
        let schema = PlanBaseContainerFactory.schema
        let configuration = ModelConfiguration(PlanBaseCompatibility.modelConfigurationName,
            schema: schema, url: store, allowsSave: false, cloudKitDatabase: .none)
        let reader = try ModelContainer(for: schema, configurations: [configuration])
        let context = reader.mainContext
        context.autosaveEnabled = false
        let existing = try #require(context.fetch(FetchDescriptor<Task>()).first { $0.id == existingID })
        existing.title = "취소할 수 있어야 하는 대기 편집"
        let notifications = SubmissionBoundaryNotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification, object: context, queue: nil
        ) { _ in notifications.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        var failure: NSError?
        do { _ = try SavedTaskLibraryService.add(input: "/save", on: Date(), in: context) }
        catch { failure = error as NSError }
        let error = try #require(failure, "A valid shortcut must reach the actual dirty pre-save failure.")
        #expect(error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileWriteNoPermission.rawValue)
        #expect(existing.title == "취소할 수 있어야 하는 대기 편집" && context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TaskChecklistItem>()) == 0)
        #expect(try ModelContext(reader).fetch(FetchDescriptor<Task>()).first?.title == "저장된 원본")
        #expect(notifications.value == 0 && !PersistenceCommandService.isPerformingCommand(in: context))

        let controller = SavedTaskQuickEntryController()
        controller.update("/save", in: context)
        #expect(controller.add(input: "/save", on: Date(), in: context) == nil)
        #expect(controller.input == "/save" && controller.isPresented && controller.failure != nil)
        #expect(controller.suggestions.map(\.draft.title) == ["추가할 작업"])
        #expect(existing.title == "취소할 수 있어야 하는 대기 편집" && context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
        #expect(notifications.value == 0)
        context.rollback()
        #expect(existing.title == "저장된 원본" && !context.hasChanges)
    }
}

@Test @MainActor
func savedTaskGloballyEligibleParentWithStaleMovedChildKeepsFinalResolveFailureCheckpoint() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    let parent = TaskTemplate(name: "현재 부모", quickEntryAlias: "parent", createdAt: time, updatedAt: time)
    let other = TaskTemplate(name: "이동한 부모", quickEntryAlias: "other", createdAt: time, updatedAt: time)
    let current = TaskTemplateItem(templateId: parent.id, title: "현재 자식", order: 100,
        createdAt: time, updatedAt: time)
    let stale = TaskTemplateItem(templateId: parent.id, title: "이동 전 자식", order: 200,
        createdAt: time, updatedAt: time)
    let moved = TaskTemplateItem(id: stale.id, templateId: other.id, title: "이동 후 자식", order: 100,
        createdAt: time, updatedAt: time.addingTimeInterval(60))
    let existing = Task(title: "저장된 원본", plannedAt: time, order: 100)
    for template in [parent, other] { context.insert(template) }
    for item in [current, stale, moved] { context.insert(item) }
    context.insert(existing)
    try context.save()
    let entries = try SavedTaskLibraryService.load(in: context)
    #expect(SavedTaskShortcutRules.suggestions(entries, input: "/parent").map(\.id) == [parent.id])
    #expect(try SavedTaskLibraryService.submissionTemplateID(input: "/parent", selectedID: nil,
        in: context) == parent.id)

    // The frozen path validated the global library first, then parent-filtered
    // resolve rejected its two logical children after the normal checkpoint.
    let selectedIDs: [UUID?] = [nil, parent.id]
    for (index, selectedID) in selectedIDs.enumerated() {
        let pendingTitle = "실패 전 저장된 대기 편집 \(index)"
        existing.title = pendingTitle
        var failure: SavedTaskLibraryService.Failure?
        do {
            _ = try SavedTaskLibraryService.add(input: "/parent", selectedID: selectedID,
                on: time, in: context)
        } catch let error as SavedTaskLibraryService.Failure { failure = error }
        guard case .unavailable? = failure else {
            Issue.record("The existing final parent-filtered resolve must reject the stale extra child.")
            return
        }
        #expect(existing.title == pendingTitle && !context.hasChanges)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Task>()).first?.title == pendingTitle)
        #expect(try context.fetch(FetchDescriptor<Task>()).map(\.id) == [existing.id])
        context.rollback()
        #expect(existing.title == pendingTitle)
    }
}

@Test @MainActor
func savedTaskValidShortcutInvalidEstimateKeepsExistingCommandCheckpoint() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let template = TaskTemplate(name: "손상된 예상 시간", quickEntryAlias: "badestimate")
    let item = TaskTemplateItem(templateId: template.id, title: "손상된 예상 시간",
        estimatedMinutes: -1, order: 100)
    let existing = Task(title: "저장된 원본", plannedAt: Date(), order: 100)
    context.insert(template)
    context.insert(item)
    context.insert(existing)
    try context.save()
    #expect(try SavedTaskLibraryService.submissionTemplateID(input: "/badestimate", selectedID: nil,
        in: context) == template.id)
    existing.title = "명령 전 저장할 대기 편집"
    var failure: SavedTaskLibraryService.Failure?
    do { _ = try SavedTaskLibraryService.add(input: "/badestimate", on: Date(), in: context) }
    catch let error as SavedTaskLibraryService.Failure { failure = error }
    guard case .invalidEstimate? = failure else {
        Issue.record("Draft normalization must retain its existing failure inside the command.")
        return
    }
    #expect(existing.title == "명령 전 저장할 대기 편집" && !context.hasChanges)
    #expect(try ModelContext(container).fetch(FetchDescriptor<Task>()).first?.title == "명령 전 저장할 대기 편집")
    #expect(try context.fetch(FetchDescriptor<Task>()).map(\.id) == [existing.id])
    #expect(try context.fetchCount(FetchDescriptor<TaskChecklistItem>()) == 0)
    context.rollback()
    #expect(existing.title == "명령 전 저장할 대기 편집")
}

private final class SubmissionBoundaryNotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
