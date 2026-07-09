import SwiftData

public enum EasyTaskMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [EasyTaskSchemaV1.self, EasyTaskSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV1ToV2]
    }

    public static let migrateV1ToV2 = MigrationStage.custom(
        fromVersion: EasyTaskSchemaV1.self,
        toVersion: EasyTaskSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            for event in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.CalendarEvent>()) {
                event.instanceID = event.id
            }
            for template in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.TaskTemplate>()) {
                template.instanceID = template.id
            }
            for item in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.TaskTemplateItem>()) {
                item.instanceID = item.id
            }
            for placement in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.TemplatePlacement>()) {
                placement.instanceID = placement.id
            }
            for task in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.Task>()) {
                task.instanceID = task.id
            }
            for review in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.DailyReview>()) {
                review.instanceID = review.id
            }
            for block in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.DiaryBlock>()) {
                block.instanceID = block.id
            }
            try context.save()
        }
    )
}
