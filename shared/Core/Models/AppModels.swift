import Foundation

@available(watchOS 11, *)
public typealias CalendarEvent = EasyTaskSchemaV5.CalendarEvent
@available(watchOS 11, *)
public typealias TaskTemplate = EasyTaskSchemaV11.TaskTemplate
@available(watchOS 11, *)
public typealias TaskTemplateItem = EasyTaskSchemaV5.TaskTemplateItem
@available(watchOS 11, *)
public typealias TemplatePlacement = EasyTaskSchemaV5.TemplatePlacement
@available(watchOS 11, *)
public typealias Task = EasyTaskSchemaV5.Task
@available(watchOS 11, *)
public typealias TaskChecklistItem = EasyTaskSchemaV5.TaskChecklistItem
@available(watchOS 11, *)
public typealias DailyReview = EasyTaskSchemaV5.DailyReview
@available(watchOS 11, *)
public typealias DiaryBlock = EasyTaskSchemaV5.DiaryBlock
@available(watchOS 11, *)
public typealias DiaryAttachment = EasyTaskSchemaV5.DiaryAttachment
@available(watchOS 11, *)
public typealias Memo = EasyTaskSchemaV9.Memo
@available(watchOS 11, *)
public typealias TaskCompletionActivity = EasyTaskSchemaV7.TaskCompletionActivity
@available(watchOS 11, *)
public typealias TaskProgressEvent = EasyTaskSchemaV8.TaskProgressEvent
@available(watchOS 11, *)
public typealias MemoDrawing = EasyTaskSchemaV9.MemoDrawing
@available(watchOS 11, *)
public typealias MemoChecklistItem = EasyTaskSchemaV9.MemoChecklistItem
@available(watchOS 11, *)
public typealias FocusSession = EasyTaskSchemaV10.FocusSession

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

    public var systemImage: String {
        switch self {
        case .todo: "circle.dashed"
        case .doing: "play.circle.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    public var guidanceText: String {
        switch self {
        case .todo: "시작을 기다려요"
        case .doing: "진행 중인 작업이에요"
        case .done: "마무리했어요"
        }
    }

    public var emptyStateTitle: String {
        switch self {
        case .todo: "할 일이 없어요"
        case .doing: "진행 중인 작업이 없어요"
        case .done: "완료한 작업이 없어요"
        }
    }

    public func emptyStateTitle(isBoardEmpty: Bool) -> String {
        self == .todo && isBoardEmpty ? "첫 할 일을 추가해 보세요" : emptyStateTitle
    }

    public var emptyStateSystemImage: String {
        switch self {
        case .todo: "circle.dashed"
        case .doing: "play.circle"
        case .done: "checkmark.circle"
        }
    }

    public var emptyStateDescription: String {
        switch self {
        case .todo: "위 입력창에서 작업을 추가할 수 있어요."
        case .doing: "작업을 시작하면 여기에 표시돼요."
        case .done: "완료한 작업이 여기에 모여요."
        }
    }

    public var primaryActionTitle: String {
        switch self {
        case .todo: "진행 시작"
        case .doing: "완료"
        case .done: "다시 진행"
        }
    }

    public var primaryActionSystemImage: String {
        switch self {
        case .todo, .done: "play.fill"
        case .doing: "checkmark"
        }
    }

    public var primaryActionStatus: TaskStatus {
        switch self {
        case .todo: .doing
        case .doing: .done
        case .done: .doing
        }
    }

    public var transitionNotice: String {
        switch self {
        case .todo: "할 일로 옮겼어요"
        case .doing: "진행을 시작했어요"
        case .done: "완료했어요"
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
