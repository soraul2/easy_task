import SwiftData

public enum EasyTaskMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [EasyTaskSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
