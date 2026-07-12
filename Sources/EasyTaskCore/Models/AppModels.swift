import Foundation

public typealias CalendarEvent = EasyTaskSchemaV4.CalendarEvent
public typealias TaskTemplate = EasyTaskSchemaV4.TaskTemplate
public typealias TaskTemplateItem = EasyTaskSchemaV4.TaskTemplateItem
public typealias TemplatePlacement = EasyTaskSchemaV4.TemplatePlacement
public typealias Task = EasyTaskSchemaV4.Task
public typealias DailyReview = EasyTaskSchemaV4.DailyReview
public typealias DiaryBlock = EasyTaskSchemaV4.DiaryBlock
public typealias DiaryAttachment = EasyTaskSchemaV4.DiaryAttachment

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
