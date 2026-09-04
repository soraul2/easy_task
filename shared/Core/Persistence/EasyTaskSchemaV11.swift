import Foundation
import SwiftData

public enum EasyTaskSchemaV11: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(11, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        EasyTaskSchemaV10.models.filter { $0 != EasyTaskSchemaV5.TaskTemplate.self } + [TaskTemplate.self]
    }

    @Model
    public final class TaskTemplate {
        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var seedKey: String?
        public var name: String = ""
        public var isFavorite: Bool = false
        public var quickEntryAlias: String?
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(), instanceID: UUID = UUID(), seedKey: String? = nil,
            name: String, isFavorite: Bool = false, quickEntryAlias: String? = nil,
            createdAt: Date = Date(), updatedAt: Date = Date(), supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.seedKey = seedKey
            self.name = name
            self.isFavorite = isFavorite
            self.quickEntryAlias = quickEntryAlias
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }
}
