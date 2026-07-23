import Foundation
import Testing
import SwiftData
@testable import EasyTaskCore

@Test
@MainActor
func calendarTemplatePlacementSkipsDuplicateTitles() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let targetDate = DayKey.startOfDay(for: Date())
    let targetDayKey = DayKey.key(for: targetDate)
    let template = TaskTemplate(name: "운동 루틴")
    let duplicateItem = TaskTemplateItem(templateId: template.id, title: "스트레칭 10분", order: 100)
    let newItem = TaskTemplateItem(
        templateId: template.id,
        title: "근력 운동 30분",
        estimatedMinutes: 30,
        order: 200
    )
    let existingTask = Task(
        title: "스트레칭 10분",
        plannedAt: targetDate,
        order: 100
    )

    context.insert(template)
    context.insert(duplicateItem)
    context.insert(newItem)
    context.insert(existingTask)

    let createdCount = TemplateService.applyTemplate(
        template,
        items: [duplicateItem, newItem],
        selectedDates: [targetDate],
        existingTasks: [existingTask],
        in: context
    )

    let tasks = try context.fetch(FetchDescriptor<Task>())
        .filter { $0.plannedDayKey == targetDayKey }

    #expect(createdCount == 1)
    #expect(tasks.count == 2)
    #expect(tasks.contains { $0.title == "근력 운동 30분" })
    #expect(tasks.first { $0.title == "근력 운동 30분" }?.estimatedMinutes == 30)
}

@Test
@MainActor
func singleDateTemplatePlacementUsesTargetDayOrderAndSkipsBlankTitles() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let targetDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
    let otherDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 9)))
    let template = TaskTemplate(name: "아침 루틴")
    let blankItem = TaskTemplateItem(templateId: template.id, title: "   ", order: 100)
    let newItem = TaskTemplateItem(templateId: template.id, title: "  물 마시기  ", order: 200)
    let existingSameDay = Task(title: "기존 작업", plannedAt: targetDate, order: 400)
    let existingOtherDay = Task(title: "다른 날 작업", plannedAt: otherDate, order: 9_000)

    context.insert(template)
    context.insert(blankItem)
    context.insert(newItem)
    context.insert(existingSameDay)
    context.insert(existingOtherDay)

    let createdCount = TemplateService.applyTemplate(
        template,
        items: [newItem, blankItem],
        selectedDate: targetDate,
        existingTasks: [existingSameDay, existingOtherDay],
        in: context
    )

    let tasks = try context.fetch(FetchDescriptor<Task>())
        .filter { $0.plannedDayKey == "2026-07-08" }

    #expect(createdCount == 1)
    #expect(tasks.count == 2)
    #expect(tasks.first { $0.title == "물 마시기" }?.order == 500)
}

@Test
@MainActor
func templateDraftPlacementUsesEditedTasksWithoutChangingTemplate() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let targetDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 10)))
    let template = TaskTemplate(name: "회의 준비")
    let originalItem = TaskTemplateItem(
        templateId: template.id,
        title: "자료 정리",
        note: "원본 메모",
        priority: TaskPriority.high.rawValue,
        tags: ["meeting"],
        estimatedMinutes: 30,
        order: 100
    )
    let skippedItem = TaskTemplateItem(templateId: template.id, title: "제외할 작업", order: 200)

    context.insert(template)
    context.insert(originalItem)
    context.insert(skippedItem)

    var drafts = TemplateService.drafts(from: template, items: [skippedItem, originalItem])
    drafts[0].title = "  발표 자료 최종 점검  "
    drafts[0].note = "  수정된 메모  "
    drafts.removeAll { $0.id == skippedItem.id }

    let createdCount = TemplateService.applyTemplate(
        template,
        drafts: drafts,
        selectedDates: [targetDate],
        existingTasks: [],
        in: context
    )
    let tasks = try context.fetch(FetchDescriptor<Task>())

    #expect(createdCount == 1)
    #expect(tasks.count == 1)
    #expect(tasks.first?.title == "발표 자료 최종 점검")
    #expect(tasks.first?.note == "수정된 메모")
    #expect(tasks.first?.priority == TaskPriority.high.rawValue)
    #expect(tasks.first?.tags == ["meeting"])
    #expect(tasks.first?.estimatedMinutes == 30)
    #expect(originalItem.title == "자료 정리")
    #expect(originalItem.note == "원본 메모")
}

@Test
@MainActor
func templateCanBeSavedFromEditedDraftsWithoutMutatingBoardTasks() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let boardTask = Task(title: "원래 작업", plannedAt: Date(), order: 100)
    context.insert(boardTask)

    let drafts = [
        TemplateTaskDraft(
            title: "  수정한 템플릿 작업  ",
            note: "템플릿 전용 메모",
            priority: TaskPriority.high.rawValue,
            tags: ["집중"],
            estimatedMinutes: 45,
            order: 100
        ),
        TemplateTaskDraft(title: "   ", order: 200)
    ]

    let template = try #require(TemplateService.saveTemplate(
        named: "  집중 루틴  ",
        from: drafts,
        in: context
    ))
    try context.save()

    let items = try context.fetch(FetchDescriptor<TaskTemplateItem>())
    #expect(template.name == "집중 루틴")
    #expect(items.count == 1)
    #expect(items.first?.title == "수정한 템플릿 작업")
    #expect(items.first?.note == "템플릿 전용 메모")
    #expect(items.first?.estimatedMinutes == 45)
    #expect(boardTask.title == "원래 작업")
}

@Test
@MainActor
func templatePlacementHistoryIsCreatedPerSelectedDate() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let firstDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 11)))
    let secondDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 12)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 9)))
    let template = TaskTemplate(name: "운동 루틴")
    let firstItem = TaskTemplateItem(templateId: template.id, title: "스트레칭", order: 100)
    let secondItem = TaskTemplateItem(templateId: template.id, title: "근력 운동", order: 200)

    context.insert(template)
    context.insert(firstItem)
    context.insert(secondItem)

    let result = TemplateService.applyTemplateWithPlacements(
        template,
        drafts: TemplateService.drafts(from: template, items: [secondItem, firstItem]),
        selectedDates: [secondDate, firstDate],
        existingTasks: [],
        in: context,
        now: now
    )
    let tasks = try context.fetch(FetchDescriptor<Task>())
    let placements = try context.fetch(FetchDescriptor<TemplatePlacement>())
        .sorted { $0.dayKey < $1.dayKey }

    #expect(result.createdTaskCount == 4)
    #expect(result.placements.count == 2)
    #expect(placements.map(\.dayKey) == ["2026-07-11", "2026-07-12"])
    #expect(placements.allSatisfy { $0.sourceTemplateId == template.id })
    #expect(placements.allSatisfy { $0.templateName == "운동 루틴" })
    #expect(placements.allSatisfy { $0.taskIds.isEmpty })
    #expect(TemplateService.placements(onDayKey: "2026-07-11", in: placements).map(\.id) == [placements[0].id])

    for placement in placements {
        let placedTasks = TemplateService.tasks(for: placement, in: tasks)
        #expect(placedTasks.count == 2)
        #expect(placedTasks.allSatisfy { $0.templatePlacementId == placement.id })
    }
}

@Test
@MainActor
func deleteTemplateRemovesOnlyTemplateAndItems() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let date = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 10)))
    let template = TaskTemplate(name: "삭제 대상")
    let otherTemplate = TaskTemplate(name: "유지 대상")
    let firstItem = TaskTemplateItem(templateId: template.id, title: "삭제 1", order: 100)
    let secondItem = TaskTemplateItem(templateId: template.id, title: "삭제 2", order: 200)
    let otherItem = TaskTemplateItem(templateId: otherTemplate.id, title: "유지", order: 100)
    let existingTask = Task(title: "이미 생성된 작업", plannedAt: date, order: 100)
    let placement = TemplatePlacement(
        sourceTemplateId: template.id,
        templateName: template.name,
        dayKey: DayKey.key(for: date),
        taskIds: [existingTask.id]
    )
    existingTask.templatePlacementId = placement.id

    context.insert(template)
    context.insert(otherTemplate)
    context.insert(firstItem)
    context.insert(secondItem)
    context.insert(otherItem)
    context.insert(existingTask)
    context.insert(placement)

    let deletedItemCount = TemplateService.deleteTemplate(
        template,
        items: [firstItem, secondItem, otherItem],
        in: context
    )
    let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
    let items = try context.fetch(FetchDescriptor<TaskTemplateItem>())
    let tasks = try context.fetch(FetchDescriptor<Task>())
    let placements = try context.fetch(FetchDescriptor<TemplatePlacement>())

    #expect(deletedItemCount == 2)
    #expect(templates.map(\.name) == ["유지 대상"])
    #expect(items.map(\.title) == ["유지"])
    #expect(tasks.map(\.title) == ["이미 생성된 작업"])
    #expect(tasks.first?.templatePlacementId == placement.id)
    #expect(placements.map(\.templateName) == ["삭제 대상"])
}

@Test
@MainActor
func deleteTemplatePlacementRemovesOnlyGeneratedTasksAndPlacement() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let date = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
    let placement = TemplatePlacement(
        sourceTemplateId: UUID(),
        templateName: "적용된 루틴",
        dayKey: DayKey.key(for: date)
    )
    let firstTask = Task(title: "생성 작업 1", plannedAt: date, order: 100, templatePlacementId: placement.id)
    let secondTask = Task(title: "생성 작업 2", plannedAt: date, order: 200, templatePlacementId: placement.id)
    let manualTask = Task(title: "수동 작업", plannedAt: date, order: 300)
    placement.taskIds = [firstTask.id, secondTask.id]

    context.insert(placement)
    context.insert(firstTask)
    context.insert(secondTask)
    context.insert(manualTask)

    let deletedTaskCount = try TemplateService.deletePlacement(
        placement,
        tasks: [manualTask, secondTask, firstTask],
        in: context
    )
    let tasks = try context.fetch(FetchDescriptor<Task>())
    let placements = try context.fetch(FetchDescriptor<TemplatePlacement>())

    #expect(deletedTaskCount == 2)
    #expect(tasks.map(\.title) == ["수동 작업"])
    #expect(placements.isEmpty)
}

@Test
@MainActor
func deleteTemplatePlacementBlocksTaskDeletionAfterProgressStarts() throws {
    let container = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let date = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)))
    let placement = TemplatePlacement(
        sourceTemplateId: UUID(),
        templateName: "진행 보호 루틴",
        dayKey: DayKey.key(for: date)
    )
    let todoTask = Task(title: "아직 시작 전", plannedAt: date, order: 100, templatePlacementId: placement.id)
    let doingTask = Task(
        title: "진행 중",
        status: .doing,
        plannedAt: date,
        order: 200,
        templatePlacementId: placement.id
    )
    let doneTask = Task(
        title: "완료됨",
        status: .done,
        plannedAt: date,
        order: 300,
        templatePlacementId: placement.id
    )
    placement.taskIds = [todoTask.id, doingTask.id, doneTask.id]

    context.insert(placement)
    context.insert(todoTask)
    context.insert(doingTask)
    context.insert(doneTask)

    let summary = TemplateService.deleteSummary(
        for: placement,
        in: [todoTask, doingTask, doneTask]
    )
    let blockedDeleteCount = try TemplateService.deletePlacement(
        placement,
        tasks: [todoTask, doingTask, doneTask],
        in: context,
        deleteTasks: true
    )
    var tasks = try context.fetch(FetchDescriptor<Task>())
    var placements = try context.fetch(FetchDescriptor<TemplatePlacement>())

    #expect(summary.taskCount == 3)
    #expect(summary.deletableTaskCount == 1)
    #expect(summary.protectedTaskCount == 2)
    #expect(summary.canDeleteTasks == false)
    #expect(blockedDeleteCount == 0)
    #expect(tasks.count == 3)
    #expect(placements.count == 1)

    let detachedCount = try TemplateService.deletePlacement(
        placement,
        tasks: [todoTask, doingTask, doneTask],
        in: context,
        deleteTasks: false
    )
    tasks = try context.fetch(FetchDescriptor<Task>())
    placements = try context.fetch(FetchDescriptor<TemplatePlacement>())

    #expect(detachedCount == 3)
    #expect(tasks.count == 3)
    #expect(tasks.allSatisfy { $0.templatePlacementId == nil })
    #expect(placements.isEmpty)
}

@Test
func templateListRulesSearchAndSortFavoritesFirst() {
    let work = TaskTemplate(name: "업무 정리 루틴", isFavorite: false)
    let workout = TaskTemplate(name: "운동 루틴", isFavorite: true)
    let review = TaskTemplate(name: "주간 회고 루틴", isFavorite: false)
    let items = [
        TaskTemplateItem(templateId: work.id, title: "막힌 이슈 정리", order: 100),
        TaskTemplateItem(templateId: workout.id, title: "스트레칭 10분", order: 100),
        TaskTemplateItem(templateId: review.id, title: "완료 작업 확인", order: 100)
    ]

    let sorted = TemplateListRules.filterAndSort([work, review, workout], items: items, query: "")
    let favoritesOnly = TemplateListRules.filterAndSort(
        [work, review, workout],
        items: items,
        query: "",
        scope: .favorites
    )
    let searchedByItem = TemplateListRules.filterAndSort([work, review, workout], items: items, query: "스트레칭")

    #expect(sorted.map(\.name) == ["운동 루틴", "업무 정리 루틴", "주간 회고 루틴"])
    #expect(favoritesOnly.map(\.name) == ["운동 루틴"])
    #expect(searchedByItem.map(\.name) == ["운동 루틴"])
    #expect(TemplateListRules.preferredScope(for: [work, review]) == .all)
    #expect(TemplateListRules.preferredScope(for: [workout, work, review]) == .favorites)
}
