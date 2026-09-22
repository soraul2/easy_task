import CryptoKit
import Foundation
import SwiftData

extension BackupPackageCodec {
    static func normalizedLegacyPayload(_ source: BackupPayload) throws -> BackupPayload {
        try BackupCodec.validate(source)
        guard source.exportedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw BackupServiceError.invalidValue(
                field: "exportedAt",
                value: String(source.exportedAt.timeIntervalSinceReferenceDate)
            )
        }

        var payload = source
        for index in payload.tasks.indices where payload.tasks[index].instanceID == nil {
            payload.tasks[index].instanceID = legacyInstanceID(
                type: "Task",
                id: payload.tasks[index].id
            )
        }
        if var checklistItems = payload.taskChecklistItems {
            for index in checklistItems.indices where checklistItems[index].instanceID == nil {
                checklistItems[index].instanceID = legacyInstanceID(
                    type: "TaskChecklistItem",
                    id: checklistItems[index].id
                )
            }
            payload.taskChecklistItems = checklistItems
        }
        for index in payload.calendarEvents.indices
        where payload.calendarEvents[index].instanceID == nil {
            payload.calendarEvents[index].instanceID = legacyInstanceID(
                type: "CalendarEvent",
                id: payload.calendarEvents[index].id
            )
        }
        for index in payload.taskTemplates.indices
        where payload.taskTemplates[index].instanceID == nil {
            payload.taskTemplates[index].instanceID = legacyInstanceID(
                type: "TaskTemplate",
                id: payload.taskTemplates[index].id
            )
        }
        for index in payload.taskTemplateItems.indices {
            if payload.taskTemplateItems[index].instanceID == nil {
                payload.taskTemplateItems[index].instanceID = legacyInstanceID(
                    type: "TaskTemplateItem",
                    id: payload.taskTemplateItems[index].id
                )
            }
            if payload.taskTemplateItems[index].createdAt == nil {
                payload.taskTemplateItems[index].createdAt = payload.exportedAt
            }
            if payload.taskTemplateItems[index].updatedAt == nil {
                payload.taskTemplateItems[index].updatedAt = payload.exportedAt
            }
        }
        if var placements = payload.templatePlacements {
            for index in placements.indices where placements[index].instanceID == nil {
                placements[index].instanceID = legacyInstanceID(
                    type: "TemplatePlacement",
                    id: placements[index].id
                )
            }
            payload.templatePlacements = placements
        }
        if var memos = payload.memos {
            for index in memos.indices where memos[index].instanceID == nil {
                memos[index].instanceID = legacyInstanceID(
                    type: "Memo",
                    id: memos[index].id
                )
            }
            payload.memos = memos
        }
        if var drawings = payload.memoDrawings {
            for index in drawings.indices where drawings[index].instanceID == nil {
                drawings[index].instanceID = legacyInstanceID(
                    type: "MemoDrawing",
                    id: drawings[index].id
                )
            }
            payload.memoDrawings = drawings
        }
        if var items = payload.memoChecklistItems {
            for index in items.indices where items[index].instanceID == nil {
                items[index].instanceID = legacyInstanceID(
                    type: "MemoChecklistItem",
                    id: items[index].id
                )
            }
            payload.memoChecklistItems = items
        }
        if var reviews = payload.dailyReviews {
            for index in reviews.indices where reviews[index].instanceID == nil {
                reviews[index].instanceID = legacyInstanceID(
                    type: "DailyReview",
                    id: reviews[index].id
                )
            }
            payload.dailyReviews = reviews
        }
        if var blocks = payload.diaryBlocks {
            for index in blocks.indices where blocks[index].instanceID == nil {
                blocks[index].instanceID = legacyInstanceID(
                    type: "DiaryBlock",
                    id: blocks[index].id
                )
            }
            payload.diaryBlocks = blocks
        }
        return payload
    }

    static func legacyInstanceID(type: String, id: UUID) -> UUID {
        let digest = SHA256.hash(data: Data("backup-v1|\(type)|\(id.uuidString)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    @MainActor
    static func mergeEvents(
        _ incoming: [CalendarEventDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<CalendarEvent>()),
            recordType: "CalendarEvent",
            instanceID: \.instanceID
        )
        for dto in incoming {
            guard let instanceID = dto.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(recordType: "CalendarEvent", id: dto.id)
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(recordType: "CalendarEvent", instanceID: instanceID)
                }
                if dto.updatedAt == current.updatedAt {
                    guard sameEvent(dto, current) else {
                        throw BackupPackageError.identityCorruption(recordType: "CalendarEvent", instanceID: instanceID)
                    }
                    report.preservedLocalRecords += 1
                    continue
                }
                guard dto.updatedAt > current.updatedAt else {
                    report.preservedLocalRecords += 1
                    continue
                }
                current.title = dto.title
                current.startAt = dto.startAt
                current.endAt = dto.endAt
                current.startDayKey = dto.startDayKey
                current.endDayKey = dto.endDayKey
                current.note = dto.note
                current.color = dto.color
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let event = CalendarEvent(
                    id: dto.id,
                    instanceID: dto.instanceID ?? UUID(),
                    title: dto.title,
                    startAt: dto.startAt,
                    endAt: dto.endAt,
                    note: dto.note,
                    color: dto.color,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
                event.startDayKey = dto.startDayKey
                event.endDayKey = dto.endDayKey
                context.insert(event)
                existing[instanceID] = event
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergeTemplates(
        _ incoming: [TaskTemplateDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<TaskTemplate>()),
            recordType: "TaskTemplate",
            instanceID: \.instanceID
        )
        for dto in incoming {
            guard let instanceID = dto.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(recordType: "TaskTemplate", id: dto.id)
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(recordType: "TaskTemplate", instanceID: instanceID)
                }
                if dto.updatedAt == current.updatedAt {
                    guard sameTemplate(dto, current) else {
                        throw BackupPackageError.identityCorruption(recordType: "TaskTemplate", instanceID: instanceID)
                    }
                    report.preservedLocalRecords += 1
                    continue
                }
                guard dto.updatedAt > current.updatedAt else {
                    report.preservedLocalRecords += 1
                    continue
                }
                current.seedKey = dto.seedKey
                current.name = dto.name
                current.isFavorite = dto.isFavorite ?? false
                if let alias = dto.quickEntryAlias {
                    current.quickEntryAlias = alias.isEmpty ? nil : alias
                }
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let template = TaskTemplate(
                    id: dto.id,
                    instanceID: dto.instanceID ?? UUID(),
                    seedKey: dto.seedKey,
                    name: dto.name,
                    isFavorite: dto.isFavorite ?? false,
                    quickEntryAlias: dto.quickEntryAlias.flatMap { $0.isEmpty ? nil : $0 },
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
                context.insert(template)
                existing[instanceID] = template
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergeTemplateItems(
        _ incoming: [TaskTemplateItemDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<TaskTemplateItem>()),
            recordType: "TaskTemplateItem",
            instanceID: \.instanceID
        )
        let parents = BackupPackageParentLookup(context: context)
        for dto in incoming {
            guard let instanceID = dto.instanceID,
                  let incomingUpdatedAt = dto.updatedAt else {
                throw BackupPackageError.invalidRecordMetadata(recordType: "TaskTemplateItem", id: dto.id)
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(recordType: "TaskTemplateItem", instanceID: instanceID)
                }
                if incomingUpdatedAt == current.updatedAt {
                    guard try sameTemplateItem(dto, current, parents: parents) else {
                        throw BackupPackageError.identityCorruption(recordType: "TaskTemplateItem", instanceID: instanceID)
                    }
                    report.preservedLocalRecords += 1
                    continue
                }
                guard incomingUpdatedAt > current.updatedAt else {
                    report.preservedLocalRecords += 1
                    continue
                }
                current.templateId = dto.templateId
                current.seedKey = dto.seedKey
                current.title = dto.title
                current.note = dto.note
                current.priority = dto.priority
                current.tags = dto.tags
                current.estimatedMinutes = dto.estimatedMinutes
                if let checklistTitles = dto.checklistTitles {
                    current.checklistTitles = checklistTitles
                }
                current.order = dto.order
                if let createdAt = dto.createdAt {
                    current.createdAt = min(current.createdAt, createdAt)
                }
                current.updatedAt = incomingUpdatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let item = TaskTemplateItem(
                    id: dto.id,
                    instanceID: dto.instanceID ?? UUID(),
                    seedKey: dto.seedKey,
                    templateId: dto.templateId,
                    title: dto.title,
                    note: dto.note,
                    priority: dto.priority,
                    tags: dto.tags,
                    estimatedMinutes: dto.estimatedMinutes,
                    checklistTitles: dto.checklistTitles ?? [],
                    order: dto.order,
                    createdAt: dto.createdAt ?? Date(),
                    updatedAt: dto.updatedAt ?? dto.createdAt ?? Date()
                )
                context.insert(item)
                existing[instanceID] = item
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergePlacements(
        _ incoming: [TemplatePlacementDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<TemplatePlacement>()),
            recordType: "TemplatePlacement",
            instanceID: \.instanceID
        )
        let parents = BackupPackageParentLookup(context: context)
        for dto in incoming {
            guard let instanceID = dto.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(recordType: "TemplatePlacement", id: dto.id)
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(recordType: "TemplatePlacement", instanceID: instanceID)
                }
                if dto.updatedAt == current.updatedAt {
                    guard try samePlacement(dto, current, parents: parents) else {
                        throw BackupPackageError.identityCorruption(recordType: "TemplatePlacement", instanceID: instanceID)
                    }
                    report.preservedLocalRecords += 1
                    continue
                }
                guard dto.updatedAt > current.updatedAt else {
                    report.preservedLocalRecords += 1
                    continue
                }
                current.sourceTemplateId = dto.sourceTemplateId
                current.templateName = dto.templateName
                current.dayKey = dto.dayKey
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let placement = TemplatePlacement(
                    id: dto.id,
                    instanceID: dto.instanceID ?? UUID(),
                    sourceTemplateId: dto.sourceTemplateId,
                    templateName: dto.templateName,
                    dayKey: dto.dayKey,
                    taskIds: [],
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
                context.insert(placement)
                existing[instanceID] = placement
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergeTasks(
        _ incoming: [TaskDTO],
        sourceFormatVersion: Int?,
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<Task>()),
            recordType: "Task",
            instanceID: \.instanceID
        )
        let parents = BackupPackageParentLookup(context: context)
        for dto in incoming {
            guard let instanceID = dto.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(recordType: "Task", id: dto.id)
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(recordType: "Task", instanceID: instanceID)
                }
                if dto.updatedAt == current.updatedAt {
                    guard try sameTask(
                        dto,
                        current,
                        sourceFormatVersion: sourceFormatVersion,
                        parents: parents
                    ) else {
                        throw BackupPackageError.identityCorruption(recordType: "Task", instanceID: instanceID)
                    }
                    report.preservedLocalRecords += 1
                    continue
                }
                guard dto.updatedAt > current.updatedAt else {
                    report.preservedLocalRecords += 1
                    continue
                }
                apply(dto, to: current, sourceFormatVersion: sourceFormatVersion)
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let task = Task(
                    id: dto.id,
                    instanceID: dto.instanceID ?? UUID(),
                    title: dto.title,
                    note: dto.note,
                    status: TaskStatus(rawValue: dto.status) ?? .todo,
                    plannedAt: dto.plannedAt,
                    order: dto.order,
                    eventId: dto.eventId,
                    templatePlacementId: dto.templatePlacementId,
                    priority: dto.priority.flatMap(TaskPriority.init(rawValue:)),
                    tags: dto.tags,
                    estimatedMinutes: dto.estimatedMinutes,
                    reminderAt: nil,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
                apply(dto, to: task, sourceFormatVersion: sourceFormatVersion)
                context.insert(task)
                existing[instanceID] = task
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func apply(
        _ dto: TaskDTO,
        to task: Task,
        sourceFormatVersion: Int?
    ) {
        task.title = dto.title
        task.note = dto.note
        task.status = dto.status
        task.plannedAt = dto.plannedAt
        task.plannedDayKey = dto.plannedDayKey
        task.order = dto.order
        task.eventId = dto.eventId
        task.templatePlacementId = dto.templatePlacementId
        task.priority = dto.priority
        task.tags = dto.tags
        task.estimatedMinutes = dto.estimatedMinutes
        if sourceHasTaskReminderSemantics(sourceFormatVersion) {
            task.reminderAt = TaskReminderRules.normalizedDate(dto.reminderAt)
        }
        task.updatedAt = dto.updatedAt
        task.completedAt = dto.completedAt
        task.completedDayKey = dto.completedDayKey
        task.archivedAt = dto.archivedAt
        task.archivedDayKey = dto.archivedDayKey
    }

}
