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
        case .doing: "지금 집중하고 있어요"
        case .done: "마무리했어요"
        }
    }

    public var emptyStateTitle: String {
        switch self {
        case .todo: "새 할 일을 추가해볼까요?"
        case .doing: "할 일을 시작해볼까요?"
        case .done: "하나씩 마무리해볼까요?"
        }
    }

    public var emptyStateDescription: String {
        switch self {
        case .todo: "빠른 입력이나 템플릿으로 오늘 할 일을 준비해요."
        case .doing: "준비된 작업을 진행 중으로 옮기면 여기에 모여요."
        case .done: "작업을 완료하면 오늘의 성과를 여기서 확인할 수 있어요."
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
