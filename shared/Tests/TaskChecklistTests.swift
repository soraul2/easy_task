import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func checklistDraftSaveNormalizesAndCancelLeavesPersistenceUntouched() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-14"))
    let task = Task(title: "장보기", plannedAt: day, order: 100)
    let existing = TaskChecklistItem(
        taskId: task.id,
        title: "기존 항목",
        order: 100,
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 10)
    )
    context.insert(task)
    context.insert(existing)
    try context.save()

    let newID = UUID()
    let saved = try PersistenceCommandService.perform(in: context) {
        TaskChecklistService.replaceItems(
            for: task.id,
            drafts: [
                ChecklistItemDraft(id: existing.id, title: "  우유  ", isCompleted: true, order: 300),
                ChecklistItemDraft(id: newID, title: "계란", isCompleted: true, order: 100),
                ChecklistItemDraft(title: "   ", order: 200)
            ],
            existingItems: try TaskChecklistService.items(for: task.id, in: context),
            in: context,
            now: Date(timeIntervalSince1970: 20)
        )
    }

    #expect(saved.map(\.title) == ["계란", "우유"])
    #expect(saved.map(\.order) == [100, 200])
    #expect(TaskChecklistService.progress(in: saved) == ChecklistProgress(
        completedCount: 2,
        totalCount: 2
    ))
    #expect(task.status == TaskStatus.todo.rawValue)

    var cancelledDrafts = TaskChecklistService.drafts(from: saved)
    cancelledDrafts[0].title = "저장하면 안 되는 제목"
    let persisted = try TaskChecklistService.items(for: task.id, in: context)
    #expect(persisted.map(\.title) == ["계란", "우유"])
}

@Test
@MainActor
func checklistCardToggleUpdatesOnlyChecklistCompletion() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-14"))
    let task = Task(title: "장보기", status: .doing, plannedAt: day, order: 100)
    let initialUpdatedAt = Date(timeIntervalSince1970: 10)
    let completedAt = Date(timeIntervalSince1970: 20)
    let item = TaskChecklistItem(
        taskId: task.id,
        title: "우유",
        order: 100,
        updatedAt: initialUpdatedAt
    )
    context.insert(task)
    context.insert(item)
    try context.save()

    let didComplete = try PersistenceCommandService.perform(in: context) {
        TaskChecklistService.setCompletion(true, for: item, now: completedAt)
    }

    #expect(didComplete)
    #expect(item.isCompleted)
    #expect(item.completedAt == completedAt)
    #expect(item.updatedAt == completedAt)
    #expect(task.status == TaskStatus.doing.rawValue)
    #expect(task.completedAt == nil)

    let reopenedAt = Date(timeIntervalSince1970: 30)
    let didReopen = try PersistenceCommandService.perform(in: context) {
        TaskChecklistService.setCompletion(false, for: item, now: reopenedAt)
    }

    #expect(didReopen)
    #expect(!item.isCompleted)
    #expect(item.completedAt == nil)
    #expect(item.updatedAt == reopenedAt)
    #expect(task.status == TaskStatus.doing.rawValue)
}

@Test
@MainActor
func checklistSurvivesTaskMovesAndStatusChangesButDeletesWithTask() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let firstDay = try #require(DayKey.date(from: "2026-07-13"))
    let secondDay = try #require(DayKey.date(from: "2026-07-14"))
    let task = Task(title: "준비", plannedAt: firstDay, order: 100)
    let item = TaskChecklistItem(taskId: task.id, title: "충전기", order: 100)
    context.insert(task)
    context.insert(item)
    try context.save()

    TaskRules.move(task, to: secondDay, now: secondDay)
    TaskRules.applyStatus(.done, to: task, now: secondDay)
    TaskRules.applyStatus(.todo, to: task, now: secondDay.addingTimeInterval(60))
    let retained = try TaskChecklistService.items(for: task.id, in: context)
    #expect(retained.map(\.id) == [item.id])
    #expect(retained.first?.isCompleted == false)

    try PersistenceCommandService.perform(in: context) {
        try TaskRules.delete(task, from: context)
    }
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<TaskChecklistItem>()) == 0)
}

@Test
@MainActor
func templateCopiesChecklistTitlesAndAppliesAllItemsUnchecked() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let sourceDay = try #require(DayKey.date(from: "2026-07-14"))
    let targetDay = try #require(DayKey.date(from: "2026-07-15"))
    let task = Task(title: "운동", plannedAt: sourceDay, order: 100)
    context.insert(task)
    context.insert(TaskChecklistItem(
        taskId: task.id,
        title: "스트레칭",
        isCompleted: true,
        order: 100,
        completedAt: sourceDay
    ))
    context.insert(TaskChecklistItem(taskId: task.id, title: "달리기", order: 200))
    try context.save()

    let template = try #require(try TemplateService.saveTemplateIncludingChecklists(
        named: "운동 루틴",
        from: [task],
        in: context
    ))
    let templateItems = try context.fetch(FetchDescriptor<TaskTemplateItem>())
    #expect(templateItems.first?.checklistTitles == ["스트레칭", "달리기"])

    let created = TemplateService.applyTemplate(
        template,
        items: templateItems,
        selectedDate: targetDay,
        existingTasks: [task],
        in: context
    )
    #expect(created == 1)
    let targetKey = DayKey.key(for: targetDay)
    let createdTask = try #require(try context.fetch(FetchDescriptor<Task>()).first {
        $0.plannedDayKey == targetKey
    })
    let appliedItems = try TaskChecklistService.items(for: createdTask.id, in: context)
    #expect(appliedItems.map(\.title) == ["스트레칭", "달리기"])
    #expect(appliedItems.allSatisfy { !$0.isCompleted && $0.completedAt == nil })
}

@Test
func archiveSearchMatchesChecklistTitleAndReturnsParentTaskDate() throws {
    let day = try #require(DayKey.date(from: "2026-07-14"))
    let task = Task(title: "장보기", plannedAt: day, order: 100)
    TaskRules.applyStatus(.done, to: task, now: day, completionDayKey: "2026-07-14")
    let item = TaskChecklistItem(taskId: task.id, title: "오트밀", order: 100)

    let records = ArchiveQueryRules.records(
        tasks: [task],
        reviews: [],
        filter: ArchiveFilter(searchText: "오트밀", scope: .tasks),
        checklistItems: [item],
        referenceDate: day
    )

    #expect(records.map(\.dayKey) == ["2026-07-14"])
    #expect(records.first?.tasks.map(\.id) == [task.id])
    #expect(records.first?.matchedTaskIDs == [task.id])
    #expect(records.first?.matchedChecklistItemIDs == [item.id])

    let presentation = try #require(records.first.map(ArchiveDayPresentation.init(record:)))
    #expect(presentation.shouldExpandTaskListForSearch)
    #expect(presentation.checklistItemMatchesSearch(item.id))
}

@Test
@MainActor
func integrityReconcilesChecklistDuplicatesOrphansBlanksAndCompletionMetadata() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-14"))
    let task = Task(title: "무결성", plannedAt: day, order: 100)
    let duplicateID = UUID()
    let old = TaskChecklistItem(
        id: duplicateID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        taskId: task.id,
        title: "이전 값",
        order: 900,
        updatedAt: Date(timeIntervalSince1970: 10)
    )
    let winner = TaskChecklistItem(
        id: duplicateID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        taskId: task.id,
        title: "최신 값",
        isCompleted: true,
        order: 500,
        updatedAt: Date(timeIntervalSince1970: 20)
    )
    let blank = TaskChecklistItem(taskId: task.id, title: "  ", order: 100)
    let orphan = TaskChecklistItem(taskId: UUID(), title: "부모 없음", order: 100)
    context.insert(task)
    context.insert(old)
    context.insert(winner)
    context.insert(blank)
    context.insert(orphan)
    try context.save()

    let first = try DataIntegrityService.reconcile(context: context)
    let active = try TaskChecklistService.items(for: task.id, in: context)
    #expect(first.hasChanges)
    #expect(active.count == 1)
    #expect(active.first?.title == "최신 값")
    #expect(active.first?.order == 100)
    #expect(active.first?.completedAt == winner.updatedAt)
    #expect(blank.supersededAt != nil)
    #expect(orphan.supersededAt != nil)

    let second = try DataIntegrityService.reconcile(context: context)
    #expect(second == .noChanges)
}

@Test
@MainActor
func backupV5RoundTripPreservesChecklistAndIsIdempotent() throws {
    let source = try PlanBaseContainerFactory.makeInMemory()
    let day = try #require(DayKey.date(from: "2026-07-14"))
    let task = Task(title: "백업", plannedAt: day, order: 100)
    let checklist = TaskChecklistItem(
        taskId: task.id,
        title: "검증",
        isCompleted: true,
        order: 100,
        completedAt: day
    )
    let template = TaskTemplate(name: "백업 템플릿")
    let templateItem = TaskTemplateItem(
        templateId: template.id,
        title: "백업",
        checklistTitles: ["검증", "배포"],
        order: 100
    )
    source.mainContext.insert(task)
    source.mainContext.insert(checklist)
    source.mainContext.insert(template)
    source.mainContext.insert(templateItem)
    try source.mainContext.save()

    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    #expect(contents.manifest.formatVersion == 5)
    #expect(contents.records.payload.taskChecklistItems?.count == 1)
    #expect(contents.records.payload.taskTemplateItems.first?.checklistTitles == ["검증", "배포"])

    let destination = try PlanBaseContainerFactory.makeInMemory()
    let first = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    let second = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    let restored = try destination.mainContext.fetch(FetchDescriptor<TaskChecklistItem>())
    let restoredTemplateItem = try #require(
        destination.mainContext.fetch(FetchDescriptor<TaskTemplateItem>()).first
    )
    #expect(first.insertedRecords > 0)
    #expect(second.insertedRecords == 0)
    #expect(restored.count == 1)
    #expect(restored.first?.instanceID == checklist.instanceID)
    #expect(restored.first?.isCompleted == true)
    #expect(restoredTemplateItem.checklistTitles == ["검증", "배포"])
}

@Test
@MainActor
func v3PackageWithoutChecklistFieldsPreservesLocalChecklistData() throws {
    let taskID = UUID()
    let taskInstanceID = UUID()
    let templateID = UUID()
    let templateInstanceID = UUID()
    let templateItemID = UUID()
    let templateItemInstanceID = UUID()
    let day = try #require(DayKey.date(from: "2026-07-14"))

    let destination = try PlanBaseContainerFactory.makeInMemory()
    let localTask = Task(
        id: taskID,
        instanceID: taskInstanceID,
        title: "로컬 작업",
        plannedAt: day,
        order: 100,
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    let localTemplate = TaskTemplate(
        id: templateID,
        instanceID: templateInstanceID,
        name: "기존 템플릿",
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    let localTemplateItem = TaskTemplateItem(
        id: templateItemID,
        instanceID: templateItemInstanceID,
        templateId: templateID,
        title: "기존 항목",
        checklistTitles: ["로컬 제목"],
        order: 100,
        createdAt: Date(timeIntervalSince1970: 50),
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    destination.mainContext.insert(localTask)
    destination.mainContext.insert(TaskChecklistItem(
        taskId: taskID,
        title: "로컬 체크리스트",
        order: 100
    ))
    destination.mainContext.insert(localTemplate)
    destination.mainContext.insert(localTemplateItem)
    try destination.mainContext.save()

    let source = try PlanBaseContainerFactory.makeInMemory()
    source.mainContext.insert(Task(
        id: taskID,
        instanceID: taskInstanceID,
        title: "V3에서 수정한 작업",
        plannedAt: day,
        order: 100,
        updatedAt: Date(timeIntervalSince1970: 200)
    ))
    source.mainContext.insert(TaskTemplate(
        id: templateID,
        instanceID: templateInstanceID,
        name: "기존 템플릿",
        updatedAt: Date(timeIntervalSince1970: 100)
    ))
    source.mainContext.insert(TaskTemplateItem(
        id: templateItemID,
        instanceID: templateItemInstanceID,
        templateId: templateID,
        title: "V3에서 수정한 항목",
        checklistTitles: [],
        order: 100,
        createdAt: Date(timeIntervalSince1970: 50),
        updatedAt: Date(timeIntervalSince1970: 200)
    ))
    try source.mainContext.save()

    var contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    contents.manifest.formatVersion = 3
    contents.records.formatVersion = 3
    contents.records.payload.taskChecklistItems = nil
    contents.records.payload.taskTemplateItems[0].checklistTitles = nil
    refreshChecklistRecordsMetadata(&contents)

    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    let restoredTask = try #require(
        destination.mainContext.fetch(FetchDescriptor<Task>()).first
    )
    let restoredTemplateItem = try #require(
        destination.mainContext.fetch(FetchDescriptor<TaskTemplateItem>()).first
    )
    let restoredChecklist = try TaskChecklistService.items(for: taskID, in: destination.mainContext)
    #expect(restoredTask.title == "V3에서 수정한 작업")
    #expect(restoredTemplateItem.title == "V3에서 수정한 항목")
    #expect(restoredTemplateItem.checklistTitles == ["로컬 제목"])
    #expect(restoredChecklist.map(\.title) == ["로컬 체크리스트"])
}

@Test
@MainActor
func cloudKitChecklistProbeVerifiesParentChildrenAndCleanup() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let token = UUID()
    let writer = try await CloudKitConvergenceProbe.runChecklistProbe(
        configuration: CloudKitProbeConfiguration(role: .writer, token: token),
        sourceBundleIdentifier: "probe.checklist.writer",
        context: container.mainContext
    )
    #expect(writer.passed)
    #expect(writer.checklistSnapshot?.matchingTaskCount == 1)
    #expect(writer.checklistSnapshot?.matchingItemCount == 2)
    #expect(writer.checklistSnapshot?.completedItemCount == 1)

    let reader = try await CloudKitConvergenceProbe.runChecklistProbe(
        configuration: CloudKitProbeConfiguration(
            kind: .checklist,
            role: .reader,
            token: token,
            timeoutSeconds: 1
        ),
        sourceBundleIdentifier: "probe.checklist.reader",
        context: container.mainContext
    )
    #expect(reader.passed)

    let cleanup = try await CloudKitConvergenceProbe.runChecklistProbe(
        configuration: CloudKitProbeConfiguration(
            kind: .checklist,
            role: .cleanup,
            token: token
        ),
        sourceBundleIdentifier: "probe.checklist.cleanup",
        context: container.mainContext
    )
    #expect(cleanup.passed)
    #expect(cleanup.checklistSnapshot?.totalTaskCount == 0)
    #expect(cleanup.checklistSnapshot?.totalItemCount == 0)
}

@Test
func cloudKitChecklistProbeKindParsesFromArguments() {
    let token = UUID()
    let configuration = CloudKitConvergenceProbe.configuration(arguments: [
        "PlanBase",
        "--cloudkit-probe-kind", "checklist",
        "--cloudkit-probe-role", "reader",
        "--cloudkit-probe-token", token.uuidString
    ])
    #expect(configuration?.kind == .checklist)
}

private func refreshChecklistRecordsMetadata(_ contents: inout BackupPackageContents) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try! encoder.encode(contents.records)
    contents.manifest.recordsByteCount = data.count
    contents.manifest.recordsSHA256 = SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}
