import Foundation

public typealias CalendarEvent = EasyTaskSchemaV2.CalendarEvent
public typealias TaskTemplate = EasyTaskSchemaV2.TaskTemplate
public typealias TaskTemplateItem = EasyTaskSchemaV2.TaskTemplateItem
public typealias TemplatePlacement = EasyTaskSchemaV2.TemplatePlacement
public typealias Task = EasyTaskSchemaV2.Task
public typealias DailyReview = EasyTaskSchemaV2.DailyReview
public typealias DiaryBlock = EasyTaskSchemaV2.DiaryBlock

public enum TaskStatus: String, CaseIterable, Identifiable {
    case todo
    case doing
    case done

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .todo: "할 일"
        case .doing: "진행 중"
        case .done: "완료"
        }
    }
}

public enum TaskPriority: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .low: "낮음"
        case .medium: "보통"
        case .high: "높음"
        }
    }
}

public enum DiaryBlockType: String, CaseIterable, Identifiable {
    case text
    case image

    public var id: String { rawValue }
}
