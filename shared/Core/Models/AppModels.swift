import Foundation

public typealias CalendarEvent = EasyTaskSchemaV5.CalendarEvent
public typealias TaskTemplate = EasyTaskSchemaV5.TaskTemplate
public typealias TaskTemplateItem = EasyTaskSchemaV5.TaskTemplateItem
public typealias TemplatePlacement = EasyTaskSchemaV5.TemplatePlacement
public typealias Task = EasyTaskSchemaV5.Task
public typealias TaskChecklistItem = EasyTaskSchemaV5.TaskChecklistItem
public typealias DailyReview = EasyTaskSchemaV5.DailyReview
public typealias DiaryBlock = EasyTaskSchemaV5.DiaryBlock
public typealias DiaryAttachment = EasyTaskSchemaV5.DiaryAttachment
public typealias Memo = EasyTaskSchemaV6.Memo

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
