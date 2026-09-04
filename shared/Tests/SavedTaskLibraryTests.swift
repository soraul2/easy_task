import Foundation
import SwiftData
import Testing

@testable import EasyTaskCore

@Test @MainActor
func savedTaskLibraryLoadsAllPagesAsIndependentValues() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    var expected: Set<UUID> = []
    for index in 0..<270 {
        let template = TaskTemplate(name: "작업 \(index)")
        expected.insert(template.id)
        context.insert(template)
        context.insert(TaskTemplateItem(templateId: template.id, title: template.name, order: 100))
    }
    try context.save()
    let values = try SavedTaskLibraryService.load(in: context)
    #expect(Set(values.map(\.id)) == expected)
    let first = try #require(values.first)
    try SavedTaskLibraryService.delete(id: first.id, in: context)
    #expect(values.count == 270 && !first.draft.title.isEmpty)
    #expect(try SavedTaskLibraryService.load(in: context).count == 269)
}

@Test @MainActor
func savedTaskCopiesReusableContentWithoutHistoryOrPlacement() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let yesterday = DayKey.addingDays(-1, to: Date())
    let target = DayKey.addingDays(5, to: Date())
    let source = Task(
        title: "보고서 작성", note: "지난 매출 확인", status: .done, plannedAt: yesterday,
        order: 100, templatePlacementId: UUID(), priority: .high, tags: ["업무"], estimatedMinutes: 45)
    source.reminderAt = yesterday
    source.completedAt = yesterday
    source.eventId = UUID()
    context.insert(source)
    context.insert(TaskChecklistItem(taskId: source.id, title: "매출 집계", isCompleted: true, order: 100))
    context.insert(TaskChecklistItem(taskId: source.id, title: "초안 검토", order: 200))
    context.insert(TaskProgressEvent(taskId: source.id, kind: .started, occurredAt: yesterday))
    context.insert(
        TaskProgressEvent(taskId: source.id, kind: .stopped, occurredAt: yesterday.addingTimeInterval(600)))
    let existing = Task(title: "기존 작업", plannedAt: target, order: 900)
    context.insert(existing)
    let saved = try SavedTaskLibraryService.save(taskID: source.id, in: context)
    let copy = try SavedTaskLibraryService.add(id: saved.id, on: target, in: context)
    #expect(copy.id != source.id)
    #expect(copy.title == source.title && copy.note == source.note)
    #expect(copy.priority == source.priority && copy.tags == source.tags)
    #expect(copy.estimatedMinutes == 45)
    #expect(copy.status == TaskStatus.todo.rawValue)
    #expect(copy.plannedDayKey == DayKey.key(for: target))
    #expect(copy.order > existing.order)
    #expect(
        copy.reminderAt == nil && copy.completedAt == nil && copy.eventId == nil
            && copy.templatePlacementId == nil)
    let items = try TaskChecklistService.items(for: copy.id, in: context)
    #expect(items.map(\.title) == ["매출 집계", "초안 검토"])
    #expect(items.allSatisfy { !$0.isCompleted && $0.completedAt == nil })
    #expect(try context.fetch(FetchDescriptor<TaskProgressEvent>()).count == 2)
    #expect(try context.fetch(FetchDescriptor<TemplatePlacement>()).isEmpty)
    #expect(source.status == TaskStatus.done.rawValue)
    let another = try SavedTaskLibraryService.add(id: saved.id, on: target, in: context)
    #expect(another.id != copy.id && another.order > copy.order)
}

@Test @MainActor
func savedTaskEditsAndDeletesDoNotChangeAlreadyAddedTasks() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let template = try SavedTaskLibraryService.create(
        draft: .init(
            title: "운동", note: "원본 메모", estimatedMinutes: 30, checklistTitles: ["준비 운동"], order: 100),
        isFavorite: false, in: context)
    let added = try SavedTaskLibraryService.add(id: template.id, on: Date(), in: context)
    try SavedTaskLibraryService.update(
        id: template.id,
        draft: .init(title: "근력 운동", estimatedMinutes: 45, checklistTitles: ["스쿼트"], order: 100),
        isFavorite: true, in: context)
    #expect(added.title == "운동" && added.note == "원본 메모" && added.estimatedMinutes == 30)
    #expect(try TaskChecklistService.items(for: added.id, in: context).map(\.title) == ["준비 운동"])
    #expect(template.isFavorite)
    try SavedTaskLibraryService.toggleFavorite(id: template.id, in: context)
    #expect(!template.isFavorite)
    let templateID = template.id
    let snapshot = try SavedTaskLibraryService.load(in: context)
    try SavedTaskLibraryService.delete(id: templateID, in: context)
    #expect(snapshot.first?.draft.title == "근력 운동")
    #expect(try SavedTaskLibraryService.load(in: context).isEmpty)
    #expect(try context.fetch(FetchDescriptor<TaskTemplate>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<TaskTemplateItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<Task>()).map(\.id) == [added.id])
}

@Test @MainActor
func savedTaskLibrarySearchesSingleTaskContentAndDeduplicatesSyncCopies() throws {
    let one = TaskTemplate(name: "혼자", isFavorite: true)
    let older = TaskTemplate(id: one.id, name: "오래된 이름", updatedAt: one.updatedAt.addingTimeInterval(-60))
    let item = TaskTemplateItem(
        templateId: one.id, title: "운동", note: "저녁", tags: ["건강"], checklistTitles: ["스트레칭"], order: 100)
    let duplicate = TaskTemplateItem(
        id: item.id, templateId: one.id, title: "옛날 제목", order: 100,
        updatedAt: item.updatedAt.addingTimeInterval(-60))
    let bundle = TaskTemplate(name: "여러 작업")
    let hidden = TaskTemplate(name: "동기화 이전", supersededAt: Date())
    let templates = [one, older, bundle, hidden]
    let items = [
        item, duplicate,
        TaskTemplateItem(templateId: bundle.id, title: "A", order: 100),
        TaskTemplateItem(templateId: bundle.id, title: "B", order: 200),
        TaskTemplateItem(templateId: hidden.id, title: "숨김", order: 100),
    ]
    let all = SavedTaskLibraryService.entries(templates: templates, items: items)
    #expect(all.count == 1 && all.first?.isFavorite == true)
    for query in ["운동", "저녁", "건강", "스트레칭"] {
        #expect(
            SavedTaskLibraryService.entries(
                templates: templates, items: items, query: query, favoritesOnly: true
            ).count == 1)
    }
    #expect(SavedTaskLibraryService.entries(templates: templates, items: items, query: "없음").isEmpty)
}

@Test @MainActor
func savedTaskRejectsInvalidDraftsAndStaleMultiTaskSelections() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    #expect(throws: SavedTaskLibraryService.Failure.self) {
        try SavedTaskLibraryService.create(
            draft: .init(title: " ", order: 100), isFavorite: false, in: context)
    }
    #expect(try context.fetch(FetchDescriptor<TaskTemplate>()).isEmpty)
    let saved = try SavedTaskLibraryService.create(
        draft: .init(title: "원본", estimatedMinutes: 0, order: 100), isFavorite: false, in: context)
    #expect(try SavedTaskLibraryService.load(in: context).first?.draft.estimatedMinutes == 0)
    #expect(throws: SavedTaskLibraryService.Failure.self) {
        try SavedTaskLibraryService.update(
            id: saved.id, draft: .init(title: "변경", estimatedMinutes: -2, order: 100), isFavorite: true,
            in: context)
    }
    #expect(saved.name == "원본" && !saved.isFavorite)
    context.insert(TaskTemplateItem(templateId: saved.id, title: "다른 기기에서 추가", order: 200))
    try context.save()
    #expect(throws: SavedTaskLibraryService.Failure.self) {
        try SavedTaskLibraryService.add(id: saved.id, on: Date(), in: context)
    }
    #expect(throws: SavedTaskLibraryService.Failure.self) {
        try SavedTaskLibraryService.delete(id: saved.id, in: context)
    }
    #expect(try context.fetch(FetchDescriptor<Task>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<TaskTemplateItem>()).count == 2)
}

@Test @MainActor
func savedTaskSurvivesExistingBackupRoundTrip() throws {
    let sourceContainer = try PlanBaseContainerFactory.makeInMemory()
    let source = sourceContainer.mainContext
    let saved = try SavedTaskLibraryService.create(
        draft: .init(
            title: "장보기", note: "주말", tags: ["생활"], estimatedMinutes: 20, checklistTitles: ["과일", "우유"],
            order: 100),
        isFavorite: true, in: source)
    let payload = try BackupCodec.decode(BackupCodec.encode(BackupCodec.makePayload(context: source)))
    let targetContainer = try PlanBaseContainerFactory.makeInMemory()
    let target = targetContainer.mainContext
    try BackupCodec.replaceAll(with: payload, in: target)
    let entries = SavedTaskLibraryService.entries(
        templates: try target.fetch(FetchDescriptor<TaskTemplate>()),
        items: try target.fetch(FetchDescriptor<TaskTemplateItem>()))
    let entry = try #require(entries.first)
    #expect(entry.id == saved.id && entry.isFavorite)
    #expect(entry.draft.checklistTitles == ["과일", "우유"])
    #expect(entry.draft.estimatedMinutes == 20 && entry.draft.note == "주말")
    let task = try SavedTaskLibraryService.add(id: entry.id, on: Date(), in: target)
    #expect(task.title == "장보기")
}
