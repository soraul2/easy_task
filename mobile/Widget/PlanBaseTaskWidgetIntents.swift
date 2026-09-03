#if os(iOS)
import AppIntents
import Foundation

enum PlanBaseTaskIntentCommand: Hashable, Sendable {
    case start(taskID: UUID)
    case complete(taskID: UUID, taskSessionID: String)
    case advance(taskID: UUID, taskSessionID: String)
    case pauseFocus(sessionID: UUID, revision: Int)
    case resumeFocus(sessionID: UUID, revision: Int)
    case stopFocus(sessionID: UUID, revision: Int)
}

struct PausePlanBaseFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "PlanBase 집중 일시정지"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @Parameter(title: "집중 세션") var sessionID: String
    @Parameter(title: "상태 버전") var revision: Int
    @AppDependency(key: PlanBaseTaskIntentDependency.key)
    private var handler: any PlanBaseTaskIntentCommandHandling

    init() {}

    init(sessionID: UUID, revision: Int) {
        self.sessionID = sessionID.uuidString
        self.revision = revision
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID) else {
            throw PlanBaseTaskIntentError.invalidTask
        }
        try await handler.perform(.pauseFocus(sessionID: id, revision: revision))
        return .result()
    }
}

struct ResumePlanBaseFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "PlanBase 집중 계속"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @Parameter(title: "집중 세션") var sessionID: String
    @Parameter(title: "상태 버전") var revision: Int
    @AppDependency(key: PlanBaseTaskIntentDependency.key)
    private var handler: any PlanBaseTaskIntentCommandHandling

    init() {}

    init(sessionID: UUID, revision: Int) {
        self.sessionID = sessionID.uuidString
        self.revision = revision
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID) else {
            throw PlanBaseTaskIntentError.invalidTask
        }
        try await handler.perform(.resumeFocus(sessionID: id, revision: revision))
        return .result()
    }
}

struct StopPlanBaseFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "PlanBase 집중 종료"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @Parameter(title: "집중 세션") var sessionID: String
    @Parameter(title: "상태 버전") var revision: Int
    @AppDependency(key: PlanBaseTaskIntentDependency.key)
    private var handler: any PlanBaseTaskIntentCommandHandling

    init() {}

    init(sessionID: UUID, revision: Int) {
        self.sessionID = sessionID.uuidString
        self.revision = revision
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID) else {
            throw PlanBaseTaskIntentError.invalidTask
        }
        try await handler.perform(.stopFocus(sessionID: id, revision: revision))
        return .result()
    }
}

@MainActor
protocol PlanBaseTaskIntentCommandHandling: Sendable {
    func perform(_ command: PlanBaseTaskIntentCommand) async throws
}

enum PlanBaseTaskIntentDependency {
    static let key = "PlanBaseTaskIntentCommandHandler"
}

struct StartPlanBaseTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "PlanBase 작업 시작"
    static let description = IntentDescription("오늘의 예정 작업을 진행 중으로 옮깁니다.")
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @Parameter(title: "작업 ID")
    var taskID: String

    @AppDependency(key: PlanBaseTaskIntentDependency.key)
    private var handler: any PlanBaseTaskIntentCommandHandling

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let taskID = UUID(uuidString: taskID) else {
            throw PlanBaseTaskIntentError.invalidTask
        }
        try await handler.perform(.start(taskID: taskID))
        return .result()
    }
}

struct CompletePlanBaseTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "PlanBase 작업 완료"
    static let description = IntentDescription("현재 진행 중인 작업을 완료합니다.")
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @Parameter(title: "작업 ID")
    var taskID: String

    @Parameter(title: "작업 세션")
    var taskSessionID: String

    @AppDependency(key: PlanBaseTaskIntentDependency.key)
    private var handler: any PlanBaseTaskIntentCommandHandling

    init() {}

    init(taskID: UUID, taskSessionID: String) {
        self.taskID = taskID.uuidString
        self.taskSessionID = taskSessionID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let taskID = UUID(uuidString: taskID), !taskSessionID.isEmpty else {
            throw PlanBaseTaskIntentError.invalidTask
        }
        try await handler.perform(.complete(
            taskID: taskID,
            taskSessionID: taskSessionID
        ))
        return .result()
    }
}

struct AdvancePlanBaseTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "PlanBase 다음 작업"
    static let description = IntentDescription("현재 작업을 예정으로 돌리고 다음 작업을 진행합니다.")
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @Parameter(title: "작업 ID")
    var taskID: String

    @Parameter(title: "작업 세션")
    var taskSessionID: String

    @AppDependency(key: PlanBaseTaskIntentDependency.key)
    private var handler: any PlanBaseTaskIntentCommandHandling

    init() {}

    init(taskID: UUID, taskSessionID: String) {
        self.taskID = taskID.uuidString
        self.taskSessionID = taskSessionID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let taskID = UUID(uuidString: taskID), !taskSessionID.isEmpty else {
            throw PlanBaseTaskIntentError.invalidTask
        }
        try await handler.perform(.advance(
            taskID: taskID,
            taskSessionID: taskSessionID
        ))
        return .result()
    }
}

private enum PlanBaseTaskIntentError: LocalizedError {
    case invalidTask

    var errorDescription: String? {
        "작업 정보가 올바르지 않습니다."
    }
}
#endif
