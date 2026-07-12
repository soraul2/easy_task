import CryptoKit
import Foundation
import SwiftData

public enum EasyTaskMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [
            EasyTaskSchemaV1.self,
            EasyTaskSchemaV2.self,
            EasyTaskSchemaV3.self,
            EasyTaskSchemaV4.self
        ]
    }

    public static var stages: [MigrationStage] {
        [migrateV1ToV2, migrateV2ToV3, migrateV3ToV4]
    }

    public static let migrateV1ToV2 = MigrationStage.custom(
        fromVersion: EasyTaskSchemaV1.self,
        toVersion: EasyTaskSchemaV2.self,
        willMigrate: { context in
            let tasks = try context.fetch(FetchDescriptor<EasyTaskSchemaV1.Task>())
            let tasksByID = Dictionary(grouping: tasks, by: \.id)
            let placements = try context.fetch(FetchDescriptor<EasyTaskSchemaV1.TemplatePlacement>())
                .sorted { $0.id.uuidString < $1.id.uuidString }

            for placement in placements {
                for taskID in placement.taskIds.sorted(by: { $0.uuidString < $1.uuidString }) {
                    for task in tasksByID[taskID] ?? [] where task.templatePlacementId == nil {
                        task.templatePlacementId = placement.id
                    }
                }
            }
            try context.save()
        },
        didMigrate: { context in
            for event in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.CalendarEvent>()) {
                event.instanceID = migratedInstanceID(for: event)
            }
            for template in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.TaskTemplate>()) {
                template.instanceID = migratedInstanceID(for: template)
            }
            for item in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.TaskTemplateItem>()) {
                item.instanceID = migratedInstanceID(for: item)
            }
            for placement in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.TemplatePlacement>()) {
                placement.instanceID = migratedInstanceID(for: placement)
            }
            for task in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.Task>()) {
                task.instanceID = migratedInstanceID(for: task)
            }
            for review in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.DailyReview>()) {
                review.instanceID = migratedInstanceID(for: review)
            }
            for block in try context.fetch(FetchDescriptor<EasyTaskSchemaV2.DiaryBlock>()) {
                block.instanceID = migratedInstanceID(for: block)
            }
            try context.save()
        }
    )

    public static let migrateV2ToV3 = MigrationStage.lightweight(
        fromVersion: EasyTaskSchemaV2.self,
        toVersion: EasyTaskSchemaV3.self
    )

    public static let migrateV3ToV4 = MigrationStage.lightweight(
        fromVersion: EasyTaskSchemaV3.self,
        toVersion: EasyTaskSchemaV4.self
    )
}

private extension EasyTaskMigrationPlan {
    static func migratedInstanceID(for event: EasyTaskSchemaV2.CalendarEvent) -> UUID {
        stableInstanceID(
            type: "CalendarEvent",
            id: event.id,
            createdAt: event.createdAt,
            updatedAt: event.updatedAt,
            fields: [
                event.title,
                dateValue(event.startAt),
                dateValue(event.endAt),
                event.startDayKey,
                event.endDayKey,
                optionalValue(event.note),
                optionalValue(event.color)
            ]
        )
    }

    static func migratedInstanceID(for template: EasyTaskSchemaV2.TaskTemplate) -> UUID {
        stableInstanceID(
            type: "TaskTemplate",
            id: template.id,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt,
            fields: [template.name, String(template.isFavorite)]
        )
    }

    static func migratedInstanceID(for item: EasyTaskSchemaV2.TaskTemplateItem) -> UUID {
        stableInstanceID(
            type: "TaskTemplateItem",
            id: item.id,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            fields: [
                item.templateId.uuidString,
                item.title,
                optionalValue(item.note),
                optionalValue(item.priority),
                String(item.tags.count)
            ] + item.tags + [
                optionalValue(item.estimatedMinutes.map(String.init)),
                String(item.order.bitPattern)
            ]
        )
    }

    static func migratedInstanceID(for placement: EasyTaskSchemaV2.TemplatePlacement) -> UUID {
        stableInstanceID(
            type: "TemplatePlacement",
            id: placement.id,
            createdAt: placement.createdAt,
            updatedAt: placement.updatedAt,
            fields: [
                optionalValue(placement.sourceTemplateId?.uuidString),
                placement.templateName,
                placement.dayKey
            ]
        )
    }

    static func migratedInstanceID(for task: EasyTaskSchemaV2.Task) -> UUID {
        stableInstanceID(
            type: "Task",
            id: task.id,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            fields: [
                task.title,
                optionalValue(task.note),
                task.status,
                dateValue(task.plannedAt),
                task.plannedDayKey,
                String(task.order.bitPattern),
                optionalValue(task.eventId?.uuidString),
                optionalValue(task.templatePlacementId?.uuidString),
                optionalValue(task.priority),
                String(task.tags.count)
            ] + task.tags + [
                optionalValue(task.estimatedMinutes.map(String.init)),
                optionalDateValue(task.completedAt),
                optionalValue(task.completedDayKey),
                optionalDateValue(task.archivedAt),
                optionalValue(task.archivedDayKey)
            ]
        )
    }

    static func migratedInstanceID(for review: EasyTaskSchemaV2.DailyReview) -> UUID {
        stableInstanceID(
            type: "DailyReview",
            id: review.id,
            createdAt: review.createdAt,
            updatedAt: review.updatedAt,
            fields: [
                review.dayKey,
                review.title,
                review.weather,
                review.mood,
                review.content,
                String(review.imageFileNames.count)
            ] + review.imageFileNames
        )
    }

    static func migratedInstanceID(for block: EasyTaskSchemaV2.DiaryBlock) -> UUID {
        stableInstanceID(
            type: "DiaryBlock",
            id: block.id,
            createdAt: block.createdAt,
            updatedAt: block.updatedAt,
            fields: [
                block.reviewId.uuidString,
                block.dayKey,
                block.type,
                block.text,
                optionalValue(block.imageFileName),
                String(block.order.bitPattern)
            ]
        )
    }

    static func stableInstanceID(
        type: String,
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        fields: [String]
    ) -> UUID {
        let components = [
            type,
            id.uuidString,
            dateValue(createdAt),
            dateValue(updatedAt)
        ] + fields
        var data = Data()
        for component in components {
            let bytes = Data(component.utf8)
            var byteCount = UInt64(bytes.count).bigEndian
            withUnsafeBytes(of: &byteCount) { data.append(contentsOf: $0) }
            data.append(bytes)
        }

        var bytes = Array(SHA256.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func dateValue(_ value: Date) -> String {
        String(value.timeIntervalSinceReferenceDate.bitPattern)
    }

    static func optionalDateValue(_ value: Date?) -> String {
        value.map(dateValue) ?? "0:"
    }

    static func optionalValue(_ value: String?) -> String {
        value.map { "1:\($0)" } ?? "0:"
    }
}
