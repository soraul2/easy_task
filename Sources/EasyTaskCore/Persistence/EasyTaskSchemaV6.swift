import Foundation
import SwiftData

public enum EasyTaskSchemaV6: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(6, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        EasyTaskSchemaV5.models + [Memo.self]
    }

    @Model
    public final class Memo {
        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var content: String = ""
        public var isPinned: Bool = false

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            content: String,
            isPinned: Bool = false,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.content = content
            self.isPinned = isPinned
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }
}
