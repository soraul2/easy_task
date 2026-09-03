import Foundation
import SwiftData

public enum FocusSessionOutcome: String, Codable, CaseIterable, Sendable {
    case completed
    case stopped
    case taskCompleted
    case interrupted
}

public enum EasyTaskSchemaV10: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(10, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        EasyTaskSchemaV9.models + [FocusSession.self]
    }

    @Model
    public final class FocusSession {
        #Index<FocusSession>(
            [\.id],
            [\.taskId],
            [\.startedAt],
            [\.endedAt],
            [\.taskId, \.endedAt]
        )

        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var taskId: UUID = UUID()
        public var startedAt: Date = Date.distantPast
        public var endedAt: Date = Date.distantPast
        public var plannedDurationSeconds: Int = 0
        public var focusedDurationSeconds: Int = 0
        public var outcomeRawValue: String = FocusSessionOutcome.completed.rawValue
        public var createdAt: Date = Date.distantPast
        public var updatedAt: Date = Date.distantPast
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            taskId: UUID,
            startedAt: Date,
            endedAt: Date,
            plannedDurationSeconds: Int,
            focusedDurationSeconds: Int,
            outcome: FocusSessionOutcome,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.taskId = taskId
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.plannedDurationSeconds = plannedDurationSeconds
            self.focusedDurationSeconds = focusedDurationSeconds
            self.outcomeRawValue = outcome.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }
}
