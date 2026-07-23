import Foundation

extension TaskDTO {
    init(task: Task) {
        id = task.id
        title = task.title
        note = task.note
        status = task.status
        plannedAt = task.plannedAt
        plannedDayKey = task.plannedDayKey
        order = task.order
        eventId = task.eventId
        templatePlacementId = task.templatePlacementId
        priority = task.priority
        tags = task.tags
        estimatedMinutes = task.estimatedMinutes
        reminderAt = task.reminderAt
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        completedAt = task.completedAt
        completedDayKey = task.completedDayKey
        archivedAt = task.archivedAt
        archivedDayKey = task.archivedDayKey
        instanceID = task.instanceID
    }
}

extension TaskChecklistItemDTO {
    init(item: TaskChecklistItem) {
        id = item.id
        taskId = item.taskId
        title = item.title
        isCompleted = item.isCompleted
        order = item.order
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        completedAt = item.completedAt
        instanceID = item.instanceID
    }
}

extension CalendarEventDTO {
    init(event: CalendarEvent) {
        id = event.id
        title = event.title
        startAt = event.startAt
        endAt = event.endAt
        startDayKey = event.startDayKey
        endDayKey = event.endDayKey
        note = event.note
        color = event.color
        createdAt = event.createdAt
        updatedAt = event.updatedAt
        instanceID = event.instanceID
    }
}

extension TaskTemplateDTO {
    init(template: TaskTemplate) {
        id = template.id
        name = template.name
        isFavorite = template.isFavorite
        createdAt = template.createdAt
        updatedAt = template.updatedAt
        instanceID = template.instanceID
        seedKey = template.seedKey
    }
}

extension TaskTemplateItemDTO {
    init(item: TaskTemplateItem) {
        id = item.id
        templateId = item.templateId
        title = item.title
        note = item.note
        priority = item.priority
        tags = item.tags
        estimatedMinutes = item.estimatedMinutes
        checklistTitles = item.checklistTitles
        order = item.order
        instanceID = item.instanceID
        seedKey = item.seedKey
        createdAt = item.createdAt
        updatedAt = item.updatedAt
    }
}

extension TemplatePlacementDTO {
    init(placement: TemplatePlacement) {
        id = placement.id
        sourceTemplateId = placement.sourceTemplateId
        templateName = placement.templateName
        dayKey = placement.dayKey
        taskIds = []
        createdAt = placement.createdAt
        updatedAt = placement.updatedAt
        instanceID = placement.instanceID
    }
}

extension DailyReviewDTO {
    init(review: DailyReview) {
        id = review.id
        dayKey = review.dayKey
        title = review.title
        weather = review.weather
        mood = review.mood
        content = review.content
        imageFileNames = review.imageFileNames
        createdAt = review.createdAt
        updatedAt = review.updatedAt
        instanceID = review.instanceID
    }
}

extension DiaryBlockDTO {
    init(block: DiaryBlock) {
        id = block.id
        reviewId = block.reviewId
        dayKey = block.dayKey
        type = block.type
        text = block.text
        imageFileName = block.imageFileName
        order = block.order
        createdAt = block.createdAt
        updatedAt = block.updatedAt
        instanceID = block.instanceID
    }
}

extension MemoDTO {
    init(memo: Memo) {
        id = memo.id
        content = memo.content
        isPinned = memo.isPinned
        createdAt = memo.createdAt
        updatedAt = memo.updatedAt
        instanceID = memo.instanceID
    }
}

extension CalendarEvent {
    convenience init(dto: CalendarEventDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            title: dto.title,
            startAt: dto.startAt,
            endAt: dto.endAt,
            note: dto.note,
            color: dto.color,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
        startDayKey = dto.startDayKey
        endDayKey = dto.endDayKey
    }
}

extension TaskTemplate {
    convenience init(dto: TaskTemplateDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            seedKey: dto.seedKey,
            name: dto.name,
            isFavorite: dto.isFavorite ?? false,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

extension TaskTemplateItem {
    convenience init(dto: TaskTemplateItemDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            seedKey: dto.seedKey,
            templateId: dto.templateId,
            title: dto.title,
            note: dto.note,
            priority: dto.priority,
            tags: dto.tags,
            estimatedMinutes: dto.estimatedMinutes,
            checklistTitles: dto.checklistTitles ?? [],
            order: dto.order,
            createdAt: dto.createdAt ?? Date(),
            updatedAt: dto.updatedAt ?? dto.createdAt ?? Date()
        )
    }
}

extension TemplatePlacement {
    convenience init(dto: TemplatePlacementDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            sourceTemplateId: dto.sourceTemplateId,
            templateName: dto.templateName,
            dayKey: dto.dayKey,
            taskIds: dto.taskIds,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

extension Task {
    convenience init(dto: TaskDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            title: dto.title,
            note: dto.note,
            status: TaskStatus(rawValue: dto.status) ?? .todo,
            plannedAt: dto.plannedAt,
            order: dto.order,
            eventId: dto.eventId,
            templatePlacementId: dto.templatePlacementId,
            priority: dto.priority.flatMap(TaskPriority.init(rawValue:)),
            tags: dto.tags,
            estimatedMinutes: dto.estimatedMinutes,
            reminderAt: TaskReminderRules.normalizedDate(dto.reminderAt),
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
        plannedDayKey = dto.plannedDayKey
        status = dto.status
        priority = dto.priority
        completedAt = dto.completedAt
        completedDayKey = dto.completedDayKey
        archivedAt = dto.archivedAt
        archivedDayKey = dto.archivedDayKey
    }
}

extension TaskChecklistItem {
    convenience init(dto: TaskChecklistItemDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            taskId: dto.taskId,
            title: dto.title,
            isCompleted: dto.isCompleted,
            order: dto.order,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            completedAt: dto.completedAt
        )
    }
}

extension DailyReview {
    convenience init(dto: DailyReviewDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            dayKey: dto.dayKey,
            title: dto.title ?? "",
            weather: dto.weather ?? "",
            mood: dto.mood ?? "",
            content: dto.content,
            imageFileNames: dto.imageFileNames ?? [],
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

extension DiaryBlock {
    convenience init(dto: DiaryBlockDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            reviewId: dto.reviewId,
            dayKey: dto.dayKey,
            type: DiaryBlockType(rawValue: dto.type) ?? .text,
            text: dto.text,
            imageFileName: dto.imageFileName,
            order: dto.order,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

extension Memo {
    convenience init(dto: MemoDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            content: dto.content,
            isPinned: dto.isPinned,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}
