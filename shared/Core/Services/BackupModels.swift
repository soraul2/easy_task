import Foundation
import SwiftData

public struct BackupPayload: Codable {
    public var backupVersion: Int
    public var exportedAt: Date
    public var tasks: [TaskDTO]
    public var taskChecklistItems: [TaskChecklistItemDTO]? = nil
    public var calendarEvents: [CalendarEventDTO]
    public var taskTemplates: [TaskTemplateDTO]
    public var taskTemplateItems: [TaskTemplateItemDTO]
    public var templatePlacements: [TemplatePlacementDTO]?
    public var dailyReviews: [DailyReviewDTO]?
    public var diaryBlocks: [DiaryBlockDTO]?
    public var memos: [MemoDTO]? = nil
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
    public var reminderAt: Date? = nil
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var completedDayKey: String?
    public var archivedAt: Date?
    public var archivedDayKey: String?
    public var instanceID: UUID? = nil
}

public struct TaskChecklistItemDTO: Codable {
    public var id: UUID
    public var taskId: UUID
    public var title: String
    public var isCompleted: Bool
    public var order: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var instanceID: UUID? = nil
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
    public var instanceID: UUID? = nil
}

public struct TaskTemplateDTO: Codable {
    public var id: UUID
    public var name: String
    public var isFavorite: Bool?
    public var createdAt: Date
    public var updatedAt: Date
    public var instanceID: UUID? = nil
    public var seedKey: String? = nil
}

public struct TaskTemplateItemDTO: Codable {
    public var id: UUID
    public var templateId: UUID
    public var title: String
    public var note: String?
    public var priority: String?
    public var tags: [String]
    public var estimatedMinutes: Int?
    public var checklistTitles: [String]? = nil
    public var order: Double
    public var instanceID: UUID? = nil
    public var seedKey: String? = nil
    public var createdAt: Date? = nil
    public var updatedAt: Date? = nil
}

public struct TemplatePlacementDTO: Codable {
    public var id: UUID
    public var sourceTemplateId: UUID?
    public var templateName: String
    public var dayKey: String
    public var taskIds: [UUID]
    public var createdAt: Date
    public var updatedAt: Date
    public var instanceID: UUID? = nil
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
    public var instanceID: UUID? = nil
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
    public var instanceID: UUID? = nil
}

public struct MemoDTO: Codable {
    public var id: UUID
    public var content: String
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var instanceID: UUID? = nil
}

public enum BackupServiceError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case duplicateIdentifier(recordType: String, id: UUID)
    case duplicateReference(field: String, id: UUID)
    case invalidEnum(field: String, value: String)
    case invalidDayKey(field: String, value: String)
    case inconsistentDayKey(field: String, expected: String, actual: String)
    case danglingReference(field: String, id: UUID)
    case inconsistentReference(String)
    case invalidValue(field: String, value: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "지원하지 않는 백업 버전입니다. version=\(version)"
        case .duplicateIdentifier(let recordType, let id):
            return "백업에 중복 ID가 있습니다. type=\(recordType), id=\(id)"
        case .duplicateReference(let field, let id):
            return "백업 참조 목록에 중복 ID가 있습니다. field=\(field), id=\(id)"
        case .invalidEnum(let field, let value):
            return "백업 enum 값이 올바르지 않습니다. field=\(field), value=\(value)"
        case .invalidDayKey(let field, let value):
            return "백업 날짜 키가 올바르지 않습니다. field=\(field), value=\(value)"
        case .inconsistentDayKey(let field, let expected, let actual):
            return "백업 날짜 키가 원본 날짜와 일치하지 않습니다. field=\(field), expected=\(expected), actual=\(actual)"
        case .danglingReference(let field, let id):
            return "백업에 대상이 없는 참조가 있습니다. field=\(field), id=\(id)"
        case .inconsistentReference(let description):
            return "백업 참조가 서로 일치하지 않습니다. \(description)"
        case .invalidValue(let field, let value):
            return "백업 값이 올바르지 않습니다. field=\(field), value=\(value)"
        }
    }
}
