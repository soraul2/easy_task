import Foundation

/// Value-only protocol shared with watchOS 10. No SwiftData model crosses the wire.
public enum WatchCompanionProtocol {
    public static let version = 1
    public static let payloadKey = "planbase.watch.companion.v1"
    public static let maximumPayloadBytes = 60_000
    public static let maximumBatchCount = 10
    public static let focusNotificationID = "PlanBaseWatchCompanionFocus"
    public static let maximumCommandAge: TimeInterval = 30 * 24 * 60 * 60

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumPayloadBytes else { throw WatchCompanionError.payloadTooLarge }
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= maximumPayloadBytes else { throw WatchCompanionError.payloadTooLarge }
        return try JSONDecoder().decode(type, from: data)
    }
}

public enum WatchCompanionError: LocalizedError {
    case payloadTooLarge, unsupportedVersion, invalidCommand, storageUnavailable, queueFull

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge: "전송할 데이터가 너무 많습니다."
        case .unsupportedVersion: "iPhone과 Watch의 PlanBase를 모두 업데이트해 주세요."
        case .invalidCommand: "작업 상태가 변경되었습니다. iPhone과 다시 동기화해 주세요."
        case .storageUnavailable: "Watch 저장소를 열 수 없습니다."
        case .queueFull: "대기 중인 변경이 많습니다. iPhone과 동기화한 뒤 다시 시도해 주세요."
        }
    }
}

public struct WatchCompanionTask: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var status: String
    public var updatedAt: Date
    public var plannedDayKey: String
    public var reminderAt: Date?
    public var estimatedMinutes: Int?

    public init(id: UUID, title: String, status: String, updatedAt: Date,
                plannedDayKey: String, reminderAt: Date? = nil, estimatedMinutes: Int? = nil) {
        self.id = id; self.title = title; self.status = status; self.updatedAt = updatedAt
        self.plannedDayKey = plannedDayKey; self.reminderAt = reminderAt
        self.estimatedMinutes = estimatedMinutes
    }
}

public struct WatchCompanionEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
}

public struct WatchCompanionSnapshot: Codable, Equatable, Sendable {
    public var version = WatchCompanionProtocol.version
    public var phoneID: UUID
    public var revision: Int
    public var generatedAt: Date
    public var dayKey: String
    public var tasks: [WatchCompanionTask]
    public var events: [WatchCompanionEvent]
    public var hasMoreTasks: Bool
    public var todoCount: Int
    public var doingCount: Int
    public var doneCount: Int
    public var eventCount: Int

    public init(phoneID: UUID, revision: Int, generatedAt: Date, dayKey: String,
                tasks: [WatchCompanionTask], events: [WatchCompanionEvent] = [], hasMoreTasks: Bool = false,
                todoCount: Int? = nil, doingCount: Int? = nil, doneCount: Int? = nil, eventCount: Int? = nil) {
        self.phoneID = phoneID; self.revision = revision; self.generatedAt = generatedAt
        self.dayKey = dayKey; self.tasks = tasks; self.events = events; self.hasMoreTasks = hasMoreTasks
        self.todoCount = todoCount ?? tasks.filter { $0.status == "todo" }.count
        self.doingCount = doingCount ?? tasks.filter { $0.status == "doing" }.count
        self.doneCount = doneCount ?? tasks.filter { $0.status == "done" }.count
        self.eventCount = eventCount ?? events.count
    }
}

public struct WatchCompanionFocusRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var instanceID: UUID
    public var taskID: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var plannedSeconds: Int
    public var focusedSeconds: Int
    public var outcome: String

    public init(_ draft: FocusSessionTerminalDraft) {
        id = draft.id; instanceID = draft.instanceID; taskID = draft.taskID
        startedAt = draft.startedAt; endedAt = draft.endedAt
        plannedSeconds = draft.plannedDurationSeconds; focusedSeconds = draft.focusedDurationSeconds
        outcome = draft.outcome.rawValue
    }
}

public enum WatchCompanionAction: Codable, Equatable, Sendable {
    case addTask(id: UUID, title: String, dayKey: String)
    case setStatus(taskID: UUID, expectedStatus: String, expectedUpdatedAt: Date,
                   status: String, completionDayKey: String, confirmedReminderAt: Date?)
    case recordFocus(WatchCompanionFocusRecord)
}

public struct WatchCompanionCommand: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var phoneID: UUID
    public var createdAt: Date
    public var action: WatchCompanionAction

    public init(id: UUID = UUID(), phoneID: UUID, createdAt: Date = Date(), action: WatchCompanionAction) {
        self.id = id; self.phoneID = phoneID; self.createdAt = createdAt; self.action = action
    }
}

public struct WatchCompanionRequest: Codable, Sendable {
    public var version = WatchCompanionProtocol.version
    public var commands: [WatchCompanionCommand]
    public init(commands: [WatchCompanionCommand] = []) { self.commands = commands }
}

public struct WatchCompanionReceipt: Codable, Equatable, Sendable {
    public var commandID: UUID
    public var accepted: Bool
    public var message: String?
    public var processedAt: Date
    public init(commandID: UUID, accepted: Bool, message: String? = nil, processedAt: Date = Date()) {
        self.commandID = commandID; self.accepted = accepted; self.message = message; self.processedAt = processedAt
    }
}

public struct WatchCompanionResponse: Codable, Sendable {
    public var version = WatchCompanionProtocol.version
    public var snapshot: WatchCompanionSnapshot
    public var receipts: [WatchCompanionReceipt]
    public init(snapshot: WatchCompanionSnapshot, receipts: [WatchCompanionReceipt] = []) {
        self.snapshot = snapshot; self.receipts = receipts
    }
}

/// Snapshot, durable outbox and active timer are committed in one atomic file.
public struct WatchCompanionState: Codable, Equatable, Sendable {
    public var version = WatchCompanionProtocol.version
    public var snapshot: WatchCompanionSnapshot?
    public var pending: [WatchCompanionCommand] = []
    public var failed: [WatchCompanionCommand] = []
    public var activeFocus: FocusActiveSessionSnapshot?
    public var completedFocus: FocusActiveSessionSnapshot?
    public var lastFailure: String?
    public init() {}

    public var projectedTasks: [WatchCompanionTask] {
        guard let snapshot else { return [] }
        var tasks = snapshot.tasks
        for command in pending where command.phoneID == snapshot.phoneID {
            switch command.action {
            case let .addTask(id, title, dayKey):
                guard dayKey == snapshot.dayKey, !tasks.contains(where: { $0.id == id }) else { continue }
                tasks.append(WatchCompanionTask(id: id, title: title, status: "todo",
                    updatedAt: command.createdAt, plannedDayKey: dayKey))
            case let .setStatus(id, _, _, status, _, _):
                if let index = tasks.firstIndex(where: { $0.id == id }) {
                    tasks[index].status = status
                    tasks[index].updatedAt = command.createdAt
                }
            case .recordFocus: break
            }
        }
        return tasks
    }

    public mutating func enqueue(_ action: WatchCompanionAction, now: Date = Date()) throws {
        guard let phoneID = snapshot?.phoneID else { throw WatchCompanionError.invalidCommand }
        guard pending.count < 500 else { throw WatchCompanionError.queueFull }
        pending.append(WatchCompanionCommand(phoneID: phoneID, createdAt: now, action: action))
    }

    public mutating func receive(_ response: WatchCompanionResponse) throws {
        guard response.version == WatchCompanionProtocol.version,
              response.snapshot.version == WatchCompanionProtocol.version else {
            throw WatchCompanionError.unsupportedVersion
        }
        // A delayed response can acknowledge a command but must not replace newer data.
        let pendingIDs = Set(pending.map(\.id))
        let receipts = response.receipts.filter { pendingIDs.contains($0.commandID) }
        let failedIDs = Set(receipts.filter { !$0.accepted }.map(\.commandID))
        failed.append(contentsOf: pending.filter { failedIDs.contains($0.id) })
        let receivedIDs = Set(receipts.map(\.commandID))
        pending.removeAll { receivedIDs.contains($0.id) }
        if let failure = receipts.last(where: { !$0.accepted }) {
            lastFailure = failure.message ?? "일부 변경을 반영하지 못했습니다."
        }
        if let current = snapshot, current.phoneID == response.snapshot.phoneID,
           current.revision > response.snapshot.revision { return }
        if let current = snapshot, current.phoneID != response.snapshot.phoneID,
           current.generatedAt > response.snapshot.generatedAt { return }
        snapshot = response.snapshot
    }

    @discardableResult
    public mutating func finishFocus(outcome: FocusSessionOutcome, now: Date = Date()) throws -> Bool {
        guard let active = activeFocus else { return false }
        if active.phase == .focus {
            let draft = try FocusTimerRules.terminalDraft(for: active, requestedOutcome: outcome, now: now)
            try enqueue(.recordFocus(WatchCompanionFocusRecord(draft)), now: now)
        }
        completedFocus = active
        activeFocus = nil
        return true
    }
}

public enum WatchCompanionStateStore {
    public static func fileURL() throws -> URL {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PlanBaseCompatibility.applicationGroupIdentifier
        ) else { throw WatchCompanionError.storageUnavailable }
        return group.appendingPathComponent("WatchCompanion/state-v1.json")
    }

    public static func read(from url: URL) throws -> WatchCompanionState {
        guard FileManager.default.fileExists(atPath: url.path) else { return WatchCompanionState() }
        let state = try JSONDecoder().decode(WatchCompanionState.self, from: Data(contentsOf: url))
        guard state.version == WatchCompanionProtocol.version else { throw WatchCompanionError.unsupportedVersion }
        if let focus = state.activeFocus, !FocusTimerRules.isValid(focus) {
            throw FocusTimerRulesError.invalidSnapshot
        }
        return state
    }

    public static func write(_ state: WatchCompanionState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
