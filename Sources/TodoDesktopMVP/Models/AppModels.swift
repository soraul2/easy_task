import Foundation
import SwiftData

enum TaskStatus: String, CaseIterable, Identifiable {
    case todo
    case doing
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "할 일"
        case .doing: "진행 중"
        case .done: "완료"
        }
    }
}

enum TaskPriority: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "낮음"
        case .medium: "보통"
        case .high: "높음"
        }
    }
}

enum DiaryBlockType: String, CaseIterable, Identifiable {
    case text
    case image

    var id: String { rawValue }
}

@Model
final class CalendarEvent {
    var id: UUID = UUID()
    var title: String = ""
    var startAt: Date = Date()
    var endAt: Date = Date()
    var startDayKey: String = ""
    var endDayKey: String = ""
    var note: String?
    var color: String?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String,
        startAt: Date,
        endAt: Date,
        note: String? = nil,
        color: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.startDayKey = DayKey.key(for: startAt)
        self.endDayKey = DayKey.key(for: endAt)
        self.note = note
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TaskTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var isFavorite: Bool = false

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TaskTemplateItem {
    var id: UUID = UUID()
    var templateId: UUID = UUID()
    var title: String = ""
    var note: String?
    var priority: String?
    var tags: [String] = []
    var estimatedMinutes: Int?
    var order: Double = 0

    init(
        id: UUID = UUID(),
        templateId: UUID,
        title: String,
        note: String? = nil,
        priority: String? = nil,
        tags: [String] = [],
        estimatedMinutes: Int? = nil,
        order: Double
    ) {
        self.id = id
        self.templateId = templateId
        self.title = title
        self.note = note
        self.priority = priority
        self.tags = tags
        self.estimatedMinutes = estimatedMinutes
        self.order = order
    }
}

@Model
final class Task {
    var id: UUID = UUID()
    var title: String = ""
    var note: String?

    var status: String = TaskStatus.todo.rawValue
    var plannedAt: Date = Date()
    var plannedDayKey: String = ""
    var order: Double = 0

    var eventId: UUID?
    var priority: String?
    var tags: [String] = []
    var estimatedMinutes: Int?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date?
    var completedDayKey: String?
    var archivedAt: Date?
    var archivedDayKey: String?

    init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        status: TaskStatus = .todo,
        plannedAt: Date,
        order: Double,
        eventId: UUID? = nil,
        priority: TaskPriority? = nil,
        tags: [String] = [],
        estimatedMinutes: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.status = status.rawValue
        self.plannedAt = plannedAt
        self.plannedDayKey = DayKey.key(for: plannedAt)
        self.order = order
        self.eventId = eventId
        self.priority = priority?.rawValue
        self.tags = tags
        self.estimatedMinutes = estimatedMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class DailyReview {
    var id: UUID = UUID()
    var dayKey: String = ""
    var title: String = ""
    var weather: String = ""
    var mood: String = ""
    var content: String = ""
    var imageFileNames: [String] = []

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        dayKey: String,
        title: String = "",
        weather: String = "",
        mood: String = "",
        content: String,
        imageFileNames: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.dayKey = dayKey
        self.title = title
        self.weather = weather
        self.mood = mood
        self.content = content
        self.imageFileNames = imageFileNames
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class DiaryBlock {
    var id: UUID = UUID()
    var reviewId: UUID = UUID()
    var dayKey: String = ""
    var type: String = DiaryBlockType.text.rawValue
    var text: String = ""
    var imageFileName: String?
    var order: Double = 0

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        reviewId: UUID,
        dayKey: String,
        type: DiaryBlockType,
        text: String = "",
        imageFileName: String? = nil,
        order: Double,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.reviewId = reviewId
        self.dayKey = dayKey
        self.type = type.rawValue
        self.text = text
        self.imageFileName = imageFileName
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
