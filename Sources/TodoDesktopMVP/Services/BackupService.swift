import AppKit
import Foundation
import SwiftData

struct BackupPayload: Codable {
    var backupVersion: Int
    var exportedAt: Date
    var tasks: [TaskDTO]
    var calendarEvents: [CalendarEventDTO]
    var taskTemplates: [TaskTemplateDTO]
    var taskTemplateItems: [TaskTemplateItemDTO]
    var dailyReviews: [DailyReviewDTO]?
}

struct TaskDTO: Codable {
    var id: UUID
    var title: String
    var note: String?
    var status: String
    var plannedAt: Date
    var plannedDayKey: String
    var order: Double
    var eventId: UUID?
    var priority: String?
    var tags: [String]
    var estimatedMinutes: Int?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var completedDayKey: String?
    var archivedAt: Date?
    var archivedDayKey: String?
}

struct CalendarEventDTO: Codable {
    var id: UUID
    var title: String
    var startAt: Date
    var endAt: Date
    var startDayKey: String
    var endDayKey: String
    var note: String?
    var color: String?
    var createdAt: Date
    var updatedAt: Date
}

struct TaskTemplateDTO: Codable {
    var id: UUID
    var name: String
    var isFavorite: Bool?
    var createdAt: Date
    var updatedAt: Date
}

struct TaskTemplateItemDTO: Codable {
    var id: UUID
    var templateId: UUID
    var title: String
    var note: String?
    var priority: String?
    var tags: [String]
    var estimatedMinutes: Int?
    var order: Double
}

struct DailyReviewDTO: Codable {
    var id: UUID
    var dayKey: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
}

enum BackupServiceResult {
    case completed
    case cancelled
}

enum BackupServiceError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "지원하지 않는 백업 버전입니다. version=\(version)"
        }
    }
}

enum BackupService {
    @MainActor
    static func exportJSON(context: ModelContext) throws -> BackupServiceResult {
        let payload = BackupPayload(
            backupVersion: 1,
            exportedAt: Date(),
            tasks: try context.fetch(FetchDescriptor<Task>()).map(TaskDTO.init),
            calendarEvents: try context.fetch(FetchDescriptor<CalendarEvent>()).map(CalendarEventDTO.init),
            taskTemplates: try context.fetch(FetchDescriptor<TaskTemplate>()).map(TaskTemplateDTO.init),
            taskTemplateItems: try context.fetch(FetchDescriptor<TaskTemplateItem>()).map(TaskTemplateItemDTO.init),
            dailyReviews: try context.fetch(FetchDescriptor<DailyReview>()).map(DailyReviewDTO.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "todoapp-backup-\(DayKey.today).json"
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        try data.write(to: url)
        return .completed
    }

    @MainActor
    static func importReplacingAll(context: ModelContext) throws -> BackupServiceResult {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        guard payload.backupVersion == 1 else {
            throw BackupServiceError.unsupportedVersion(payload.backupVersion)
        }

        for item in try context.fetch(FetchDescriptor<TaskTemplateItem>()) {
            context.delete(item)
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

        for dto in payload.calendarEvents {
            context.insert(CalendarEvent(dto: dto))
        }
        for dto in payload.taskTemplates {
            context.insert(TaskTemplate(dto: dto))
        }
        for dto in payload.taskTemplateItems {
            context.insert(TaskTemplateItem(dto: dto))
        }
        for dto in payload.tasks {
            context.insert(Task(dto: dto))
        }
        for dto in payload.dailyReviews ?? [] {
            context.insert(DailyReview(dto: dto))
        }

        return .completed
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

private extension DailyReviewDTO {
    init(review: DailyReview) {
        id = review.id
        dayKey = review.dayKey
        content = review.content
        createdAt = review.createdAt
        updatedAt = review.updatedAt
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
            content: dto.content,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}
