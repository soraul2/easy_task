import Foundation
import Testing
import SwiftData
@testable import EasyTaskCore

@Test
func applyingSameDoneStatusPreservesCompletionMetadata() throws {
    let plannedDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let firstCompletionDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let secondCompletionDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
    let task = Task(title: "완료 날짜 보존", plannedAt: plannedDate, order: 100)

    TaskRules.applyStatus(.done, to: task, now: firstCompletionDate)
    let completedAt = task.completedAt
    let completedDayKey = task.completedDayKey
    let updatedAt = task.updatedAt

    TaskRules.applyStatus(.done, to: task, now: secondCompletionDate)

    #expect(task.completedAt == completedAt)
    #expect(task.completedDayKey == completedDayKey)
    #expect(task.updatedAt == updatedAt)
}

@Test
func completionDayCanFollowBoardDateInsteadOfActualCompletionDate() throws {
    let july4 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let july7 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let july8Completion = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 21)))
    let july4Key = DayKey.key(for: july4)
    let july7Key = DayKey.key(for: july7)
    let todayKey = DayKey.key(for: july8Completion)
    let originalBoardTask = Task(title: "7월 4일 보드 완료", plannedAt: july4, order: 100)
    let movedTask = Task(title: "7월 7일로 이월 후 완료", plannedAt: july4, order: 200)

    TaskRules.applyStatus(.done, to: originalBoardTask, now: july8Completion, completionDayKey: july4Key)
    TaskRules.move(movedTask, to: july7)
    TaskRules.applyStatus(.done, to: movedTask, now: july8Completion, completionDayKey: movedTask.plannedDayKey)

    #expect(originalBoardTask.completedAt == july8Completion)
    #expect(originalBoardTask.completedDayKey == july4Key)
    #expect(movedTask.completedAt == july8Completion)
    #expect(movedTask.completedDayKey == july7Key)

    let july4Board = BoardQueryRules.tasksForBoard(
        [originalBoardTask, movedTask],
        selectedDayKey: july4Key,
        todayKey: todayKey
    )
    let july7Board = BoardQueryRules.tasksForBoard(
        [originalBoardTask, movedTask],
        selectedDayKey: july7Key,
        todayKey: todayKey
    )

    #expect(BoardQueryRules.tasks(july4Board, matching: .done).map(\.title) == ["7월 4일 보드 완료"])
    #expect(BoardQueryRules.tasks(july7Board, matching: .done).map(\.title) == ["7월 7일로 이월 후 완료"])
}

@Test
func backupUnsupportedVersionErrorIncludesVersion() {
    let error = BackupServiceError.unsupportedVersion(99)

    #expect(error.errorDescription?.contains("99") == true)
}

@Test
@MainActor
func backupCodecRoundTripsTemplatePlacementLinks() throws {
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

    let date = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 14)))
    let placement = TemplatePlacement(
        sourceTemplateId: UUID(),
        templateName: "백업 루틴",
        dayKey: DayKey.key(for: date)
    )
    let task = Task(title: "백업 작업", plannedAt: date, order: 100, templatePlacementId: placement.id)
    placement.taskIds = [task.id]
    context.insert(placement)
    context.insert(task)

    let payload = try BackupCodec.makePayload(context: context)

    #expect(payload.templatePlacements?.first?.id == placement.id)
    #expect(payload.templatePlacements?.first?.taskIds == [task.id])
    #expect(payload.tasks.first?.templatePlacementId == placement.id)

    let restoredContainer = try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let restoredContext = restoredContainer.mainContext
    try BackupCodec.replaceAll(with: payload, in: restoredContext)

    let restoredPlacement = try #require(restoredContext.fetch(FetchDescriptor<TemplatePlacement>()).first)
    let restoredTask = try #require(restoredContext.fetch(FetchDescriptor<Task>()).first)

    #expect(restoredPlacement.templateName == "백업 루틴")
    #expect(restoredPlacement.taskIds.isEmpty)
    #expect(restoredTask.templatePlacementId == restoredPlacement.id)
    #expect(TemplateService.tasks(for: restoredPlacement, in: [restoredTask]).map(\.id) == [restoredTask.id])
}

@Test
func dayKeyRoundTripsDateString() throws {
    let date = try #require(DayKey.date(from: "2026-07-06"))

    #expect(DayKey.key(for: date) == "2026-07-06")
}

@Test
func carryoverTasksAreOpenPastTasksSortedByDayAndOrder() throws {
    let olderDay = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let laterPastDay = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
    let today = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9)))

    let olderSecond = Task(title: "오래된 두 번째", plannedAt: olderDay, order: 200)
    let olderFirst = Task(title: "오래된 첫 번째", plannedAt: olderDay, order: 100)
    let laterDoing = Task(title: "진행 중 과거 작업", status: .doing, plannedAt: laterPastDay, order: 100)
    let todayTask = Task(title: "오늘 작업", plannedAt: today, order: 100)
    let donePast = Task(title: "완료된 과거 작업", plannedAt: olderDay, order: 300)
    let archivedPast = Task(title: "보관된 과거 작업", plannedAt: olderDay, order: 400)

    TaskRules.applyStatus(.done, to: donePast, now: now)
    archivedPast.archivedAt = now

    let result = TaskRules.carryoverTasks(
        [todayTask, olderSecond, laterDoing, donePast, archivedPast, olderFirst],
        before: DayKey.key(for: today)
    )

    #expect(result.map(\.title) == ["오래된 첫 번째", "오래된 두 번째", "진행 중 과거 작업"])
}

@Test
func movingTaskToDateUpdatesDayKeyOrderAndTimestamp() throws {
    let originalDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let targetDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 15)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 10)))
    let task = Task(title: "날짜 이동", plannedAt: originalDate, order: 100)

    TaskRules.move(task, to: targetDate, order: 500, now: now)

    #expect(task.plannedAt == DayKey.startOfDay(for: targetDate))
    #expect(task.plannedDayKey == "2026-07-08")
    #expect(task.order == 500)
    #expect(task.updatedAt == now)
}

@Test
func bringingCarryoverTaskToTodayMovesAndResetsStatus() throws {
    let originalDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 10)))
    let task = Task(title: "진행 중 이월 작업", status: .doing, plannedAt: originalDate, order: 100)

    TaskRules.bringToToday(task, order: 500, now: now)

    #expect(task.plannedAt == DayKey.startOfDay(for: now))
    #expect(task.plannedDayKey == "2026-07-14")
    #expect(task.status == TaskStatus.todo.rawValue)
    #expect(task.order == 500)
    #expect(task.updatedAt == now)
}

@Test
func completingCarryoverTasksUsesEachOriginalPlannedDay() throws {
    let july4 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 4)))
    let july7 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 21)))
    let first = Task(title: "7월 4일 미완료", plannedAt: july4, order: 100)
    let second = Task(title: "7월 7일 진행 중", status: .doing, plannedAt: july7, order: 200)

    TaskRules.completeOnPlannedDays([first, second], now: now)

    #expect(first.status == TaskStatus.done.rawValue)
    #expect(first.plannedDayKey == "2026-07-04")
    #expect(first.completedDayKey == "2026-07-04")
    #expect(first.completedAt == now)
    #expect(second.status == TaskStatus.done.rawValue)
    #expect(second.plannedDayKey == "2026-07-07")
    #expect(second.completedDayKey == "2026-07-07")
    #expect(second.completedAt == now)

    let todayBoard = BoardQueryRules.tasksForBoard(
        [first, second],
        selectedDayKey: "2026-07-14",
        todayKey: "2026-07-14"
    )
    let july4Board = BoardQueryRules.tasksForBoard(
        [first, second],
        selectedDayKey: "2026-07-04",
        todayKey: "2026-07-14"
    )
    let july7Board = BoardQueryRules.tasksForBoard(
        [first, second],
        selectedDayKey: "2026-07-07",
        todayKey: "2026-07-14"
    )

    #expect(todayBoard.isEmpty)
    #expect(july4Board.map(\.title) == ["7월 4일 미완료"])
    #expect(july7Board.map(\.title) == ["7월 7일 진행 중"])
}

@Test
func completingAllTasksUsesSharedStatusRule() throws {
    let plannedDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let first = Task(title: "첫 번째", plannedAt: plannedDate, order: 100)
    let second = Task(title: "두 번째", status: .doing, plannedAt: plannedDate, order: 200)

    TaskRules.completeAll([first, second], now: now)

    #expect(first.status == TaskStatus.done.rawValue)
    #expect(first.completedAt == now)
    #expect(first.completedDayKey == "2026-07-07")
    #expect(second.status == TaskStatus.done.rawValue)
    #expect(second.completedAt == now)
    #expect(second.completedDayKey == "2026-07-07")
}

@Test
func boardQueryRulesPreserveDesktopAndMobileCarryoverPolicies() throws {
    let yesterday = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
    let today = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let todayKey = DayKey.key(for: today)
    let completionTime = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 11)))

    let todayTask = Task(title: "오늘 작업", plannedAt: today, order: 100)
    let carryoverTask = Task(title: "이월 작업", plannedAt: yesterday, order: 100)
    let doneToday = Task(title: "오늘 완료", plannedAt: yesterday, order: 200)
    TaskRules.applyStatus(.done, to: doneToday, now: completionTime)

    let tasks = [carryoverTask, doneToday, todayTask]
    let desktopBoard = BoardQueryRules.tasksForBoard(
        tasks,
        selectedDayKey: todayKey,
        todayKey: todayKey
    )
    let mobileBoard = BoardQueryRules.tasksForBoard(
        tasks,
        selectedDayKey: todayKey,
        todayKey: todayKey,
        includeCarryoverOnToday: true
    )

    #expect(Set(desktopBoard.map(\.title)) == Set(["오늘 완료", "오늘 작업"]))
    #expect(Set(mobileBoard.map(\.title)) == Set(["오늘 완료", "이월 작업", "오늘 작업"]))
    #expect(BoardQueryRules.tasks(mobileBoard, matching: .todo).map(\.title) == ["이월 작업", "오늘 작업"])
    #expect(BoardQueryRules.tasks(mobileBoard, matching: .done).map(\.title) == ["오늘 완료"])
}

@Test
func boardNextOrderUsesOnlyTargetDayAndStatus() throws {
    let targetDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let otherDate = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let targetKey = DayKey.key(for: targetDate)

    let targetTodo = Task(title: "대상 날짜", plannedAt: targetDate, order: 300)
    let targetDoing = Task(title: "진행 중", status: .doing, plannedAt: targetDate, order: 900)
    let otherTodo = Task(title: "다른 날짜", plannedAt: otherDate, order: 9_000)

    let nextTodoOrder = BoardQueryRules.nextOrder(
        in: [targetTodo, targetDoing, otherTodo],
        dayKey: targetKey,
        status: .todo
    )
    let nextDoingOrder = BoardQueryRules.nextOrder(
        in: [targetTodo, targetDoing, otherTodo],
        dayKey: targetKey,
        status: .doing
    )

    #expect(nextTodoOrder == 400)
    #expect(nextDoingOrder == 1_000)
}

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

@Test
func calendarEventTimelineBadgeText() throws {
    let today = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let tomorrow = DayKey.addingDays(1, to: today)
    let afterTwoDays = DayKey.addingDays(2, to: today)

    let activeEvent = CalendarEvent(title: "TodoApp MVP 설계", startAt: today, endAt: afterTwoDays)
    let futureEvent = CalendarEvent(title: "다음 릴리즈", startAt: tomorrow, endAt: afterTwoDays)
    let endingTodayEvent = CalendarEvent(title: "테스트 일정", startAt: DayKey.addingDays(-2, to: today), endAt: today)
    let singleDayEvent = CalendarEvent(title: "하루 일정", startAt: today, endAt: today)

    #expect(CalendarEventTimeline.badgeText(for: activeEvent, today: today) == "종료 D-2")
    #expect(CalendarEventTimeline.badgeText(for: futureEvent, today: today) == "시작 D-1")
    #expect(CalendarEventTimeline.badgeText(for: endingTodayEvent, today: today) == "오늘 종료")
    #expect(CalendarEventTimeline.badgeText(for: singleDayEvent, today: today) == "오늘")
}

@Test
func calendarEventRulesNormalizeDraftAndUpdateEvent() throws {
    let lateStart = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 18)))
    let earlyEnd = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 9)))
    let createdAt = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 8)))
    let updatedAt = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 10)))

    let event = try #require(CalendarEventRules.makeEvent(
        title: "  릴리즈 준비  ",
        startAt: lateStart,
        endAt: earlyEnd,
        note: "  주요 일정  ",
        color: " blue ",
        now: createdAt
    ))
    let blankEvent = CalendarEventRules.makeEvent(
        title: "   ",
        startAt: earlyEnd,
        endAt: lateStart
    )
    let invalidColorEvent = try #require(CalendarEventRules.makeEvent(
        title: "잘못된 색상",
        startAt: earlyEnd,
        endAt: lateStart,
        color: "indigo"
    ))

    #expect(blankEvent == nil)
    #expect(event.title == "릴리즈 준비")
    #expect(event.startAt == DayKey.startOfDay(for: earlyEnd))
    #expect(event.endAt == DayKey.startOfDay(for: lateStart))
    #expect(event.startDayKey == "2026-07-07")
    #expect(event.endDayKey == "2026-07-09")
    #expect(event.note == "주요 일정")
    #expect(event.color == "blue")
    #expect(event.createdAt == createdAt)
    #expect(event.updatedAt == createdAt)
    #expect(invalidColorEvent.color == nil)

    let didUpdate = CalendarEventRules.update(
        event,
        title: "  일정 수정  ",
        startAt: earlyEnd,
        endAt: earlyEnd,
        note: "   ",
        color: "",
        now: updatedAt
    )

    #expect(didUpdate)
    #expect(event.title == "일정 수정")
    #expect(event.startDayKey == "2026-07-07")
    #expect(event.endDayKey == "2026-07-07")
    #expect(event.note == nil)
    #expect(event.color == nil)
    #expect(event.updatedAt == updatedAt)
}

@Test
func calendarEventRulesQueryEventsByDayAndRangeInStableOrder() throws {
    let july6 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let july7 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let july8 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
    let july9 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 9)))

    let longB = CalendarEvent(title: "B 장기", startAt: july6, endAt: july8)
    let longA = CalendarEvent(title: "A 장기", startAt: july6, endAt: july8)
    let short = CalendarEvent(title: "단기", startAt: july6, endAt: july6)
    let later = CalendarEvent(title: "후속", startAt: july7, endAt: july9)

    let dayEvents = CalendarEventRules.events(on: july6, in: [later, short, longB, longA])
    let rangeEvents = CalendarEventRules.events(
        overlapping: july8,
        through: july9,
        in: [later, short, longB, longA]
    )

    #expect(dayEvents.map(\.title) == ["A 장기", "B 장기", "단기"])
    #expect(rangeEvents.map(\.title) == ["A 장기", "B 장기", "후속"])
}

@Test
func calendarEventRulesDetachLinkedTasksWhenDeletingEvent() throws {
    let day = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let now = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 11)))
    let event = CalendarEvent(title: "연결 일정", startAt: day, endAt: day)
    let otherEventID = UUID()
    let linkedFirst = Task(title: "연결 작업 1", plannedAt: day, order: 100, eventId: event.id)
    let linkedSecond = Task(title: "연결 작업 2", plannedAt: day, order: 200, eventId: event.id)
    let unrelated = Task(title: "다른 일정 작업", plannedAt: day, order: 300, eventId: otherEventID)

    let detachedCount = CalendarEventRules.detachTasks(
        from: event,
        in: [unrelated, linkedFirst, linkedSecond],
        now: now
    )

    #expect(detachedCount == 2)
    #expect(linkedFirst.eventId == nil)
    #expect(linkedSecond.eventId == nil)
    #expect(linkedFirst.updatedAt == now)
    #expect(linkedSecond.updatedAt == now)
    #expect(unrelated.eventId == otherEventID)
}

@Test
func specialDayStoreLoadsBundledKoreanSpecialDays() {
    let store = SpecialDayStore.load()
    let liberationDay = store.days(on: "2026-08-15")
    let overlappingDay = store.days(on: "2028-10-03")

    #expect(liberationDay.contains { $0.name == "광복절" && $0.isPublicHoliday })
    #expect(overlappingDay.contains { $0.name == "개천절" })
    #expect(overlappingDay.contains { $0.name == "추석" })
}

@Test
func dailyReviewContentRuleDetectsTextMetadataAndImages() {
    let emptyReview = DailyReview(dayKey: "2026-07-06", content: "   ")
    let titleOnlyReview = DailyReview(dayKey: "2026-07-06", title: "회고", content: "")
    let weatherOnlyReview = DailyReview(dayKey: "2026-07-06", weather: "맑음", content: "")
    let moodOnlyReview = DailyReview(dayKey: "2026-07-06", mood: "좋음", content: "")
    let imageOnlyReview = DailyReview(dayKey: "2026-07-06", content: "", imageFileNames: ["sample.jpg"])

    #expect(DailyReviewRules.hasContent(emptyReview) == false)
    #expect(DailyReviewRules.hasContent(titleOnlyReview))
    #expect(DailyReviewRules.hasContent(weatherOnlyReview))
    #expect(DailyReviewRules.hasContent(moodOnlyReview))
    #expect(DailyReviewRules.hasContent(imageOnlyReview))
}

@Test
func archiveQueryRulesGroupCompletedTasksAndUseLatestReview() throws {
    let july6 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 6)))
    let july7 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 7)))
    let earlyCompletion = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 9)))
    let lateCompletion = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 11)))
    let day6Task = Task(title: "6일 완료", plannedAt: july6, order: 100)
    let earlyDay7Task = Task(title: "7일 오전 완료", plannedAt: july7, order: 100)
    let lateDay7Task = Task(title: "7일 오후 완료", plannedAt: july7, order: 200)
    let openTask = Task(title: "미완료", plannedAt: july7, order: 300)
    TaskRules.applyStatus(.done, to: day6Task, now: earlyCompletion, completionDayKey: DayKey.key(for: july6))
    TaskRules.applyStatus(.done, to: earlyDay7Task, now: earlyCompletion, completionDayKey: DayKey.key(for: july7))
    TaskRules.applyStatus(.done, to: lateDay7Task, now: lateCompletion, completionDayKey: DayKey.key(for: july7))

    let olderReview = DailyReview(
        dayKey: DayKey.key(for: july7),
        title: "이전 회고",
        content: "이전 내용",
        updatedAt: earlyCompletion
    )
    let latestReview = DailyReview(
        dayKey: DayKey.key(for: july7),
        title: "최신 회고",
        content: "최신 내용",
        updatedAt: lateCompletion
    )

    let records = ArchiveQueryRules.records(
        tasks: [openTask, earlyDay7Task, day6Task, lateDay7Task],
        reviews: [olderReview, latestReview],
        filter: ArchiveFilter(),
        referenceDate: lateCompletion
    )

    #expect(records.map(\.dayKey) == ["2026-07-07", "2026-07-06"])
    #expect(records.first?.tasks.map(\.title) == ["7일 오후 완료", "7일 오전 완료"])
    #expect(records.first?.review?.id == latestReview.id)
    #expect(records.flatMap(\.tasks).contains { $0.id == openTask.id } == false)
}

@Test
func archiveQueryRulesApplyPeriodScopeAndDayLevelSearch() throws {
    let oldDay = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
    let recentDay = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
    let today = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 10)))
    let oldTask = Task(title: "오래된 작업", plannedAt: oldDay, order: 100)
    let recentTask = Task(title: "모바일 보관함 정리", note: "상세 메모", plannedAt: recentDay, order: 100)
    TaskRules.applyStatus(.done, to: oldTask, now: today, completionDayKey: DayKey.key(for: oldDay))
    TaskRules.applyStatus(.done, to: recentTask, now: today, completionDayKey: DayKey.key(for: recentDay))
    let review = DailyReview(
        dayKey: DayKey.key(for: recentDay),
        title: "하루 회고",
        content: "모바일 기록을 확인했다."
    )

    let taskSearch = ArchiveFilter(
        searchText: "보관함",
        period: .last7Days,
        scope: .tasks
    )
    let taskRecords = ArchiveQueryRules.records(
        tasks: [oldTask, recentTask],
        reviews: [review],
        filter: taskSearch,
        referenceDate: today
    )

    #expect(taskRecords.map(\.dayKey) == ["2026-07-08"])
    #expect(taskRecords.first?.review?.id == review.id)
    #expect(taskRecords.first?.matchedTaskIDs == [recentTask.id])
    #expect(taskRecords.first?.reviewMatchesSearch == false)
    #expect(taskRecords.first?.hasSearchQuery == true)

    let taskPresentation = try ArchiveDayPresentation(record: #require(taskRecords.first))
    #expect(taskPresentation.title == "하루 회고")
    #expect(taskPresentation.displayDate == DayKey.display(recentDay))
    #expect(taskPresentation.summaryText == "작업 1 · 회고")
    #expect(taskPresentation.shouldExpandTaskListForSearch)
    #expect(taskPresentation.taskMatchesSearch(recentTask.id))

    let reviewSearch = ArchiveFilter(
        searchText: "회고",
        period: .last7Days,
        scope: .reviews
    )
    let reviewRecords = ArchiveQueryRules.records(
        tasks: [oldTask, recentTask],
        reviews: [review],
        filter: reviewSearch,
        referenceDate: today
    )

    #expect(reviewRecords.first?.tasks.map(\.id) == [recentTask.id])
    #expect(reviewRecords.first?.matchedTaskIDs.isEmpty == true)
    #expect(reviewRecords.first?.reviewMatchesSearch == true)
    #expect(reviewRecords.first.map(ArchiveDayPresentation.init(record:))?.shouldExpandTaskListForSearch == false)

    let mismatchedScope = ArchiveFilter(
        searchText: "회고",
        period: .last7Days,
        scope: .tasks
    )
    #expect(ArchiveQueryRules.records(
        tasks: [oldTask, recentTask],
        reviews: [review],
        filter: mismatchedScope,
        referenceDate: today
    ).isEmpty)
}

@Test
func archivePresentationUsesStableFallbackTitles() {
    let taskOnly = ArchiveDayPresentation(record: ArchiveDayRecord(
        dayKey: "2026-07-06",
        tasks: [],
        review: nil
    ))
    let untitledReview = ArchiveDayPresentation(record: ArchiveDayRecord(
        dayKey: "2026-07-07",
        tasks: [],
        review: DailyReview(dayKey: "2026-07-07", title: "  ", content: "기록")
    ))

    #expect(taskOnly.title == "작업 기록")
    #expect(taskOnly.summaryText.isEmpty)
    #expect(untitledReview.title == "하루 회고")
    #expect(untitledReview.summaryText == "회고")
}

@Test
func archiveQueryRulesNormalizeReversedCustomPeriod() throws {
    let july1 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
    let july2 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 2)))
    let july5 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
    let july8 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
    let july9 = try #require(DayKey.calendar.date(from: DateComponents(year: 2026, month: 7, day: 9)))
    let beforeTask = Task(title: "기간 이전 작업", plannedAt: july1, order: 100)
    let includedTask = Task(title: "기간 내 작업", plannedAt: july5, order: 100)
    let afterTask = Task(title: "기간 이후 작업", plannedAt: july9, order: 100)
    TaskRules.applyStatus(.done, to: beforeTask, now: july8, completionDayKey: DayKey.key(for: july1))
    TaskRules.applyStatus(.done, to: includedTask, now: july8, completionDayKey: DayKey.key(for: july5))
    TaskRules.applyStatus(.done, to: afterTask, now: july8, completionDayKey: DayKey.key(for: july9))
    let filter = ArchiveFilter(
        period: .custom,
        customStartDate: july8,
        customEndDate: july2
    )

    let records = ArchiveQueryRules.records(
        tasks: [beforeTask, includedTask, afterTask],
        reviews: [],
        filter: filter,
        referenceDate: july8
    )

    #expect(records.map(\.dayKey) == ["2026-07-05"])
}

@Test
@MainActor
func dailyReviewServiceSavesReviewAndSynchronizesDiaryBlocks() throws {
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
    let dayKey = "2026-07-06"

    let emptyDraft = DailyReviewService.save(
        review: nil,
        dayKey: dayKey,
        content: "   ",
        in: context
    )
    #expect(emptyDraft == nil)

    let review = try #require(DailyReviewService.save(
        review: nil,
        dayKey: dayKey,
        title: "  회고  ",
        content: "  오늘 메모  ",
        imageFileNames: ["first.jpg"],
        in: context
    ))
    var blocks = try context.fetch(FetchDescriptor<DiaryBlock>())
        .filter { $0.reviewId == review.id }
        .sorted { $0.order < $1.order }

    #expect(review.title == "회고")
    #expect(review.content == "오늘 메모")
    #expect(review.imageFileNames == ["first.jpg"])
    #expect(blocks.map(\.type) == [DiaryBlockType.text.rawValue, DiaryBlockType.image.rawValue])
    #expect(blocks.first?.text == "오늘 메모")
    #expect(blocks.last?.imageFileName == "first.jpg")

    DailyReviewService.save(
        review: review,
        dayKey: dayKey,
        title: "",
        content: "수정된 메모",
        imageFileNames: [],
        in: context
    )
    blocks = try context.fetch(FetchDescriptor<DiaryBlock>())
        .filter { $0.reviewId == review.id }
        .sorted { $0.order < $1.order }

    #expect(review.title == "")
    #expect(review.content == "수정된 메모")
    #expect(review.imageFileNames.isEmpty)
    #expect(blocks.count == 1)
    #expect(blocks.first?.type == DiaryBlockType.text.rawValue)
    #expect(blocks.first?.text == "수정된 메모")
}

@Test
func dailyReviewServiceMigratesLegacyDiaryBlocksIntoSummaryFields() {
    let review = DailyReview(dayKey: "2026-07-06", content: "")
    let textBlock = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .text,
        text: "첫 번째 줄",
        order: 100
    )
    let imageBlock = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .image,
        imageFileName: "legacy.jpg",
        order: 200
    )

    let didMigrate = DailyReviewService.migrateBlockSummaryIfNeeded(
        for: review,
        blocks: [imageBlock, textBlock]
    )

    #expect(didMigrate)
    #expect(review.content == "첫 번째 줄")
    #expect(review.imageFileNames == ["legacy.jpg"])
}

@Test
func appThemePresetsMeetTextContrastTarget() {
    #expect(AppThemePreset.defaultID == "appleSystem")
    #expect(AppThemePreset.all.first?.id == AppThemePreset.defaultID)

    for preset in AppThemePreset.all where preset.targetsWCAGTextContrast {
        for appearance in AppThemeAppearance.allCases {
            let colors = preset.colorSet(for: appearance)
            let sharedSurfaces = [
                colors.backgroundTop,
                colors.backgroundBottom,
                colors.panel,
                colors.input,
                colors.floatingBar,
                colors.selectedTab,
                colors.columnTodo,
                colors.columnDoing,
                colors.columnDone
            ]

            for surface in sharedSurfaces {
                #expect(colors.primaryText.contrastRatio(to: surface) >= 4.5)
                #expect(colors.secondaryText.contrastRatio(to: surface) >= 4.5)
            }

            for cardSurface in [colors.todo, colors.doing, colors.done] {
                #expect(colors.cardText.contrastRatio(to: cardSurface) >= 4.5)
                #expect(colors.cardMutedText.contrastRatio(to: cardSurface) >= 4.5)
            }

            for eventColor in colors.eventPalette {
                #expect(colors.eventText.contrastRatio(to: eventColor) >= 4.5)
            }
        }
    }
}

@Test
func roseLilacThemeUsesRequestedSoftPalette() {
    let preset = AppThemePreset.preset(for: "roseLilac")

    #expect(preset.id == "roseLilac")
    #expect(preset.sourcePaletteHexes == ["#FBEFEF", "#FFE2E2", "#F5CBCB", "#C5B3D3"])
    #expect(!preset.targetsWCAGTextContrast)
}

@Test
func archiveSemanticColorsRemainReadableAcrossEveryTheme() {
    for preset in AppThemePreset.all {
        for appearance in AppThemeAppearance.allCases {
            let colors = preset.colorSet(for: appearance)
            let essentialSurfaces = [
                colors.backgroundTop,
                colors.backgroundBottom,
                colors.panel,
                colors.input,
                colors.floatingBar,
                colors.selectedTab
            ]

            for surface in essentialSurfaces {
                #expect(colors.primaryText.contrastRatio(to: surface) >= 4.5)
                #expect(colors.secondaryText.contrastRatio(to: surface) >= 4.5)
            }
            #expect(colors.resolvedDoneForeground.contrastRatio(to: colors.done) >= 4.5)
            #expect(colors.resolvedEventForeground.contrastRatio(to: colors.event) >= 4.5)
        }
    }
}

@Test
func lightThemeStatusColorsAreDistinctWithinEachPreset() {
    func distance(_ lhs: ThemeColorToken, _ rhs: ThemeColorToken) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        return (red * red + green * green + blue * blue).squareRoot()
    }

    for preset in AppThemePreset.all {
        let colors = preset.colorSet(for: .light)

        #expect(distance(colors.columnTodo, colors.columnDoing) >= 0.06)
        #expect(distance(colors.columnTodo, colors.columnDone) >= 0.06)
        #expect(distance(colors.columnDoing, colors.columnDone) >= 0.06)
        #expect(distance(colors.todo, colors.doing) >= 0.06)
        #expect(distance(colors.todo, colors.done) >= 0.06)
        #expect(distance(colors.doing, colors.done) >= 0.06)
    }
}
