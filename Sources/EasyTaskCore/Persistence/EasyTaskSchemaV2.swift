import Foundation
import SwiftData

public enum EasyTaskSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [
            Task.self,
            CalendarEvent.self,
            TaskTemplate.self,
            TaskTemplateItem.self,
            TemplatePlacement.self,
            DailyReview.self,
            DiaryBlock.self
        ]
    }

    @Model
    public final class CalendarEvent {
        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var title: String = ""
        public var startAt: Date = Date()
        public var endAt: Date = Date()
        public var startDayKey: String = ""
        public var endDayKey: String = ""
        public var note: String?
        public var color: String?

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            title: String,
            startAt: Date,
            endAt: Date,
            note: String? = nil,
            color: String? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.title = title
            self.startAt = startAt
            self.endAt = endAt
            self.startDayKey = DayKey.key(for: startAt)
            self.endDayKey = DayKey.key(for: endAt)
            self.note = note
            self.color = color
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }

    @Model
    public final class TaskTemplate {
        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var seedKey: String?
        public var name: String = ""
        public var isFavorite: Bool = false

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            seedKey: String? = nil,
            name: String,
            isFavorite: Bool = false,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.seedKey = seedKey
            self.name = name
            self.isFavorite = isFavorite
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }

    @Model
    public final class TaskTemplateItem {
        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var seedKey: String?
        public var templateId: UUID = UUID()
        public var title: String = ""
        public var note: String?
        public var priority: String?
        public var tags: [String] = []
        public var estimatedMinutes: Int?
        public var order: Double = 0

        public var createdAt: Date = Date.distantPast
        public var updatedAt: Date = Date.distantPast
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            seedKey: String? = nil,
            templateId: UUID,
            title: String,
            note: String? = nil,
            priority: String? = nil,
            tags: [String] = [],
            estimatedMinutes: Int? = nil,
            order: Double,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.seedKey = seedKey
            self.templateId = templateId
            self.title = title
            self.note = note
            self.priority = priority
            self.tags = tags
            self.estimatedMinutes = estimatedMinutes
            self.order = order
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }

    @Model
    public final class TemplatePlacement {
        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var sourceTemplateId: UUID?
        public var templateName: String = ""
        public var dayKey: String = ""
        @Transient public var taskIds: [UUID] = []

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            sourceTemplateId: UUID?,
            templateName: String,
            dayKey: String,
            taskIds: [UUID] = [],
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.sourceTemplateId = sourceTemplateId
            self.templateName = templateName
            self.dayKey = dayKey
            self.taskIds = taskIds
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }

    @Model
    public final class Task {
        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var title: String = ""
        public var note: String?

        public var status: String = TaskStatus.todo.rawValue
        public var plannedAt: Date = Date()
        public var plannedDayKey: String = ""
        public var order: Double = 0

        public var eventId: UUID?
        public var templatePlacementId: UUID?
        public var priority: String?
        public var tags: [String] = []
        public var estimatedMinutes: Int?

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var completedAt: Date?
        public var completedDayKey: String?
        public var archivedAt: Date?
        public var archivedDayKey: String?
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            title: String,
            note: String? = nil,
            status: TaskStatus = .todo,
            plannedAt: Date,
            order: Double,
            eventId: UUID? = nil,
            templatePlacementId: UUID? = nil,
            priority: TaskPriority? = nil,
            tags: [String] = [],
            estimatedMinutes: Int? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.title = title
            self.note = note
            self.status = status.rawValue
            self.plannedAt = plannedAt
            self.plannedDayKey = DayKey.key(for: plannedAt)
            self.order = order
            self.eventId = eventId
            self.templatePlacementId = templatePlacementId
            self.priority = priority?.rawValue
            self.tags = tags
            self.estimatedMinutes = estimatedMinutes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }

    @Model
    public final class DailyReview {
        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var dayKey: String = ""
        public var title: String = ""
        public var weather: String = ""
        public var mood: String = ""
        public var content: String = ""
        public var imageFileNames: [String] = []

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            dayKey: String,
            title: String = "",
            weather: String = "",
            mood: String = "",
            content: String,
            imageFileNames: [String] = [],
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.dayKey = dayKey
            self.title = title
            self.weather = weather
            self.mood = mood
            self.content = content
            self.imageFileNames = imageFileNames
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }

    @Model
    public final class DiaryBlock {
        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var reviewId: UUID = UUID()
        public var dayKey: String = ""
        public var type: String = DiaryBlockType.text.rawValue
        public var text: String = ""
        public var imageFileName: String?
        public var order: Double = 0

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            reviewId: UUID,
            dayKey: String,
            type: DiaryBlockType,
            text: String = "",
            imageFileName: String? = nil,
            order: Double,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.reviewId = reviewId
            self.dayKey = dayKey
            self.type = type.rawValue
            self.text = text
            self.imageFileName = imageFileName
            self.order = order
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }
}
