import Foundation
import SwiftData

public struct BackupPayload: Codable {
    public var backupVersion: Int
    public var exportedAt: Date
    public var tasks: [TaskDTO]
    public var calendarEvents: [CalendarEventDTO]
    public var taskTemplates: [TaskTemplateDTO]
    public var taskTemplateItems: [TaskTemplateItemDTO]
    public var templatePlacements: [TemplatePlacementDTO]?
    public var dailyReviews: [DailyReviewDTO]?
    public var diaryBlocks: [DiaryBlockDTO]?
}

public struct TaskDTO: Codable {
    public var id: UUID
    public var title: String
    public var note: String?
    public var status: String
    public var plannedAt: Date
    public var plannedDayKey: String
    public var order: Double
    public var eventId: UUID?
    public var templatePlacementId: UUID?
    public var priority: String?
    public var tags: [String]
    public var estimatedMinutes: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var completedDayKey: String?
    public var archivedAt: Date?
    public var archivedDayKey: String?
}

public struct CalendarEventDTO: Codable {
    public var id: UUID
    public var title: String
    public var startAt: Date
    public var endAt: Date
    public var startDayKey: String
    public var endDayKey: String
    public var note: String?
    public var color: String?
    public var createdAt: Date
    public var updatedAt: Date
}

public struct TaskTemplateDTO: Codable {
    public var id: UUID
    public var name: String
    public var isFavorite: Bool?
    public var createdAt: Date
    public var updatedAt: Date
}

public struct TaskTemplateItemDTO: Codable {
    public var id: UUID
    public var templateId: UUID
    public var title: String
    public var note: String?
    public var priority: String?
    public var tags: [String]
    public var estimatedMinutes: Int?
    public var order: Double
}

public struct TemplatePlacementDTO: Codable {
    public var id: UUID
    public var sourceTemplateId: UUID?
    public var templateName: String
    public var dayKey: String
    public var taskIds: [UUID]
    public var createdAt: Date
    public var updatedAt: Date
}

public struct DailyReviewDTO: Codable {
    public var id: UUID
    public var dayKey: String
    public var title: String?
    public var weather: String?
    public var mood: String?
    public var content: String
    public var imageFileNames: [String]?
    public var createdAt: Date
    public var updatedAt: Date
}

public struct DiaryBlockDTO: Codable {
    public var id: UUID
    public var reviewId: UUID
    public var dayKey: String
    public var type: String
    public var text: String
    public var imageFileName: String?
    public var order: Double
    public var createdAt: Date
    public var updatedAt: Date
}

public enum BackupServiceError: LocalizedError {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "지원하지 않는 백업 버전입니다. version=\(version)"
        }
    }
}

public enum BackupCodec {
    public static let currentVersion = 1

    public static func makePayload(context: ModelContext) throws -> BackupPayload {
        BackupPayload(
            backupVersion: currentVersion,
            exportedAt: Date(),
            tasks: try context.fetch(FetchDescriptor<Task>()).map(TaskDTO.init),
            calendarEvents: try context.fetch(FetchDescriptor<CalendarEvent>()).map(CalendarEventDTO.init),
            taskTemplates: try context.fetch(FetchDescriptor<TaskTemplate>()).map(TaskTemplateDTO.init),
            taskTemplateItems: try context.fetch(FetchDescriptor<TaskTemplateItem>()).map(TaskTemplateItemDTO.init),
            templatePlacements: try context.fetch(FetchDescriptor<TemplatePlacement>()).map(TemplatePlacementDTO.init),
            dailyReviews: try context.fetch(FetchDescriptor<DailyReview>()).map(DailyReviewDTO.init),
            diaryBlocks: try context.fetch(FetchDescriptor<DiaryBlock>()).map(DiaryBlockDTO.init)
        )
    }

    public static func encode(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    public static func decode(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        guard payload.backupVersion == currentVersion else {
            throw BackupServiceError.unsupportedVersion(payload.backupVersion)
        }
        return payload
    }

    public static func replaceAll(with payload: BackupPayload, in context: ModelContext) throws {
        guard payload.backupVersion == currentVersion else {
            throw BackupServiceError.unsupportedVersion(payload.backupVersion)
        }

        for item in try context.fetch(FetchDescriptor<TaskTemplateItem>()) {
            context.delete(item)
        }
        for placement in try context.fetch(FetchDescriptor<TemplatePlacement>()) {
            context.delete(placement)
        }
        for template in try context.fetch(FetchDescriptor<TaskTemplate>()) {
            context.delete(template)
        }
        for task in try context.fetch(FetchDescriptor<Task>()) {
            context.delete(task)
        }
        for event in try context.fetch(FetchDescriptor<CalendarEvent>()) {
            context.delete(event)
        }
        for review in try context.fetch(FetchDescriptor<DailyReview>()) {
            context.delete(review)
        }
        for block in try context.fetch(FetchDescriptor<DiaryBlock>()) {
            context.delete(block)
        }

        for dto in payload.calendarEvents {
            context.insert(CalendarEvent(dto: dto))
        }
        for dto in payload.taskTemplates {
            context.insert(TaskTemplate(dto: dto))
        }
        for dto in payload.taskTemplateItems {
            context.insert(TaskTemplateItem(dto: dto))
        }
        for dto in payload.templatePlacements ?? [] {
            context.insert(TemplatePlacement(dto: dto))
        }
        for dto in payload.tasks {
            context.insert(Task(dto: dto))
        }
        for dto in payload.dailyReviews ?? [] {
            context.insert(DailyReview(dto: dto))
        }
        for dto in payload.diaryBlocks ?? [] {
            context.insert(DiaryBlock(dto: dto))
        }
    }
}

private extension TaskDTO {
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
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        completedAt = task.completedAt
        completedDayKey = task.completedDayKey
        archivedAt = task.archivedAt
        archivedDayKey = task.archivedDayKey
    }
}

private extension CalendarEventDTO {
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
    }
}

private extension TaskTemplateDTO {
    init(template: TaskTemplate) {
        id = template.id
        name = template.name
        isFavorite = template.isFavorite
        createdAt = template.createdAt
        updatedAt = template.updatedAt
    }
}

private extension TaskTemplateItemDTO {
    init(item: TaskTemplateItem) {
        id = item.id
        templateId = item.templateId
        title = item.title
        note = item.note
        priority = item.priority
        tags = item.tags
        estimatedMinutes = item.estimatedMinutes
        order = item.order
    }
}

private extension TemplatePlacementDTO {
    init(placement: TemplatePlacement) {
        id = placement.id
        sourceTemplateId = placement.sourceTemplateId
        templateName = placement.templateName
        dayKey = placement.dayKey
        taskIds = placement.taskIds
        createdAt = placement.createdAt
        updatedAt = placement.updatedAt
    }
}

private extension DailyReviewDTO {
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
    }
}

private extension DiaryBlockDTO {
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
    }
}

private extension CalendarEvent {
    convenience init(dto: CalendarEventDTO) {
        self.init(
            id: dto.id,
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

private extension TaskTemplate {
    convenience init(dto: TaskTemplateDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            isFavorite: dto.isFavorite ?? false,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension TaskTemplateItem {
    convenience init(dto: TaskTemplateItemDTO) {
        self.init(
            id: dto.id,
            templateId: dto.templateId,
            title: dto.title,
            note: dto.note,
            priority: dto.priority,
            tags: dto.tags,
            estimatedMinutes: dto.estimatedMinutes,
            order: dto.order
        )
    }
}

private extension TemplatePlacement {
    convenience init(dto: TemplatePlacementDTO) {
        self.init(
            id: dto.id,
            sourceTemplateId: dto.sourceTemplateId,
            templateName: dto.templateName,
            dayKey: dto.dayKey,
            taskIds: dto.taskIds,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension Task {
    convenience init(dto: TaskDTO) {
        self.init(
            id: dto.id,
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

private extension DailyReview {
    convenience init(dto: DailyReviewDTO) {
        self.init(
            id: dto.id,
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

private extension DiaryBlock {
    convenience init(dto: DiaryBlockDTO) {
        self.init(
            id: dto.id,
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
