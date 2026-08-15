import Foundation
import SwiftData

public enum TaskProgressEventKind: String, Codable, CaseIterable, Sendable {
    case started
    case stopped
}

public enum TaskProgressEventOrigin: String, Codable, Sendable {
    case captured
    case compatibilityBoundary
}

public enum EasyTaskSchemaV8: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(8, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        EasyTaskSchemaV7.models + [TaskProgressEvent.self]
    }

    @Model
    public final class TaskProgressEvent {
        #Index<TaskProgressEvent>(
            [\.id],
            [\.taskId],
            [\.taskId, \.occurredAt]
        )

        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var taskId: UUID = UUID()
        public var kindRawValue: String = TaskProgressEventKind.started.rawValue
        public var originRawValue: String = TaskProgressEventOrigin.captured.rawValue
        public var occurredAt: Date = Date.distantPast
        public var createdAt: Date = Date.distantPast
        public var updatedAt: Date = Date.distantPast
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            taskId: UUID,
            kind: TaskProgressEventKind,
            origin: TaskProgressEventOrigin = .captured,
            occurredAt: Date,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.taskId = taskId
            self.kindRawValue = kind.rawValue
            self.originRawValue = origin.rawValue
            self.occurredAt = occurredAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }
}
