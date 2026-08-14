import Foundation
import SwiftData

public enum TaskCompletionActivityOrigin: String, Codable, Sendable {
    case captured
    case legacyBackfill
}

public enum EasyTaskSchemaV7: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(7, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        EasyTaskSchemaV6.models + [TaskCompletionActivity.self]
    }

    @Model
    public final class TaskCompletionActivity {
        #Index<TaskCompletionActivity>(
            [\.activityDayKey],
            [\.id],
            [\.taskId, \.activityDayKey],
            [\.taskId, \.occurredAt]
        )

        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var taskId: UUID = UUID()
        public var activityDayKey: String = ""
        public var occurredAt: Date = Date.distantPast
        public var originRawValue: String = TaskCompletionActivityOrigin.captured.rawValue

        public var createdAt: Date = Date.distantPast
        public var updatedAt: Date = Date.distantPast
        public var supersededAt: Date?

        public init(
            id: UUID,
            instanceID: UUID = UUID(),
            taskId: UUID,
            activityDayKey: String,
            occurredAt: Date,
            origin: TaskCompletionActivityOrigin = .captured,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.taskId = taskId
            self.activityDayKey = activityDayKey
            self.occurredAt = occurredAt
            self.originRawValue = origin.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }
}
