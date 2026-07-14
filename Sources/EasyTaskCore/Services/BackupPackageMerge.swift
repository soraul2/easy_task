import CryptoKit
import Foundation
import SwiftData

public struct LegacyJSONMergeReport: Equatable, Sendable {
    public var merge: BackupPackageMergeReport
    public var referencedImageFileNames: [String]

    public init(
        merge: BackupPackageMergeReport,
        referencedImageFileNames: [String]
    ) {
        self.merge = merge
        self.referencedImageFileNames = referencedImageFileNames
    }
}

public extension BackupPackageCodec {
    @MainActor
    @discardableResult
    static func restoreMerging(
        _ contents: BackupPackageContents,
        into context: ModelContext
    ) throws -> BackupPackageMergeReport {
        try restoreMerging(contents, into: context, beforeFinalSave: {})
    }

    @MainActor
    @discardableResult
    static func restoreLegacyJSONMerging(
        _ source: BackupPayload,
        into context: ModelContext
    ) throws -> LegacyJSONMergeReport {
        let payload = try normalizedLegacyPayload(source)
        try BackupCodec.validate(payload)
        try context.save()
        var report = BackupPackageMergeReport()
        do {
            _ = try DataIntegrityService.reconcile(context: context, saveChanges: false)
            try mergeEvents(payload.calendarEvents, context: context, report: &report)
            try mergeTemplates(payload.taskTemplates, context: context, report: &report)
            try mergeTemplateItems(payload.taskTemplateItems, context: context, report: &report)
            try mergePlacements(payload.templatePlacements ?? [], context: context, report: &report)
            try mergeTasks(
                payload.tasks,
                sourceFormatVersion: nil,
                context: context,
                report: &report
            )
            try mergeChecklistItems(
                payload.taskChecklistItems ?? [],
                context: context,
                report: &report
            )
            try mergeReviews(
                payload.dailyReviews ?? [],
                context: context,
                report: &report,
                preserveLegacyImages: true
            )
            try mergeDiaryBlocks(
                payload.diaryBlocks ?? [],
                context: context,
                report: &report,
                preserveLegacyImages: true
            )
            _ = try DataIntegrityService.reconcile(context: context, saveChanges: false)
            try validateFinalAttachmentCounts(context: context)
            try context.save()

            let reviewNames = (payload.dailyReviews ?? []).flatMap { $0.imageFileNames ?? [] }
            let blockNames = (payload.diaryBlocks ?? []).compactMap(\.imageFileName)
            return LegacyJSONMergeReport(
                merge: report,
                referencedImageFileNames: Array(Set(reviewNames + blockNames)).sorted()
            )
        } catch {
            context.rollback()
            throw error
        }
    }
}

extension BackupPackageCodec {
    @MainActor
    @discardableResult
    static func restoreMerging(
        _ contents: BackupPackageContents,
        into context: ModelContext,
        beforeFinalSave: () throws -> Void
    ) throws -> BackupPackageMergeReport {
        try validate(contents)
        // Persist pending edits as the rollback baseline before package mutations begin.
        try context.save()
        var report = BackupPackageMergeReport()
        do {
            _ = try DataIntegrityService.reconcile(context: context, saveChanges: false)
            let payload = contents.records.payload
            try mergeEvents(payload.calendarEvents, context: context, report: &report)
            try mergeTemplates(payload.taskTemplates, context: context, report: &report)
            try mergeTemplateItems(payload.taskTemplateItems, context: context, report: &report)
            try mergePlacements(payload.templatePlacements ?? [], context: context, report: &report)
            try mergeTasks(
                payload.tasks,
                sourceFormatVersion: contents.records.formatVersion,
                context: context,
                report: &report
            )
            try mergeChecklistItems(
                payload.taskChecklistItems ?? [],
                context: context,
                report: &report
            )
            try mergeReviews(payload.dailyReviews ?? [], context: context, report: &report)
            try mergeDiaryBlocks(payload.diaryBlocks ?? [], context: context, report: &report)
            try mergeAttachments(contents, context: context, report: &report)
            _ = try DataIntegrityService.reconcile(context: context, saveChanges: false)
            try validateImportedAttachmentRelativeOrder(contents, context: context)
            try validateFinalAttachmentCounts(context: context)
            try beforeFinalSave()
            try context.save()
            return report
        } catch {
            context.rollback()
            throw error
        }
    }
}

private extension BackupPackageCodec {
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
                    guard try sameTemplateItem(dto, current, context: context) else {
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
        for dto in incoming {
            guard let instanceID = dto.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(recordType: "TemplatePlacement", id: dto.id)
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(recordType: "TemplatePlacement", instanceID: instanceID)
                }
                if dto.updatedAt == current.updatedAt {
                    guard try samePlacement(dto, current, context: context) else {
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
                        context: context
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

    @MainActor
    static func mergeChecklistItems(
        _ incoming: [TaskChecklistItemDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<TaskChecklistItem>()),
            recordType: "TaskChecklistItem",
            instanceID: \.instanceID
        )
        for dto in incoming {
            guard let instanceID = dto.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(
                    recordType: "TaskChecklistItem",
                    id: dto.id
                )
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(
                        recordType: "TaskChecklistItem",
                        instanceID: instanceID
                    )
                }
                if dto.updatedAt == current.updatedAt {
                    guard try sameChecklistItem(dto, current, context: context) else {
                        throw BackupPackageError.identityCorruption(
                            recordType: "TaskChecklistItem",
                            instanceID: instanceID
                        )
                    }
                    report.preservedLocalRecords += 1
                    continue
                }
                guard dto.updatedAt > current.updatedAt else {
                    report.preservedLocalRecords += 1
                    continue
                }
                current.taskId = try canonicalTaskID(for: dto.taskId, context: context) ?? dto.taskId
                current.title = dto.title
                current.isCompleted = dto.isCompleted
                current.order = dto.order
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.completedAt = dto.isCompleted ? (dto.completedAt ?? dto.updatedAt) : nil
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let item = TaskChecklistItem(
                    id: dto.id,
                    instanceID: instanceID,
                    taskId: try canonicalTaskID(for: dto.taskId, context: context) ?? dto.taskId,
                    title: dto.title,
                    isCompleted: dto.isCompleted,
                    order: dto.order,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt,
                    completedAt: dto.isCompleted ? (dto.completedAt ?? dto.updatedAt) : nil
                )
                context.insert(item)
                existing[instanceID] = item
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergeReviews(
        _ incoming: [DailyReviewDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport,
        preserveLegacyImages: Bool = false
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<DailyReview>()),
            recordType: "DailyReview",
            instanceID: \.instanceID
        )
        for dto in incoming {
            guard let instanceID = dto.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(recordType: "DailyReview", id: dto.id)
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(recordType: "DailyReview", instanceID: instanceID)
                }
                if dto.updatedAt == current.updatedAt {
                    guard sameReview(
                        dto,
                        current,
                        preserveLegacyImages: preserveLegacyImages
                    ) else {
                        throw BackupPackageError.identityCorruption(recordType: "DailyReview", instanceID: instanceID)
                    }
                    report.preservedLocalRecords += 1
                    continue
                }
                guard dto.updatedAt > current.updatedAt else {
                    report.preservedLocalRecords += 1
                    continue
                }
                current.dayKey = dto.dayKey
                current.title = dto.title ?? ""
                current.weather = dto.weather ?? ""
                current.mood = dto.mood ?? ""
                current.content = dto.content
                if preserveLegacyImages {
                    current.imageFileNames = dto.imageFileNames ?? []
                }
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let review = DailyReview(
                    id: dto.id,
                    instanceID: dto.instanceID ?? UUID(),
                    dayKey: dto.dayKey,
                    title: dto.title ?? "",
                    weather: dto.weather ?? "",
                    mood: dto.mood ?? "",
                    content: dto.content,
                    imageFileNames: preserveLegacyImages ? (dto.imageFileNames ?? []) : [],
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
                context.insert(review)
                existing[instanceID] = review
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergeDiaryBlocks(
        _ incoming: [DiaryBlockDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport,
        preserveLegacyImages: Bool = false
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<DiaryBlock>()),
            recordType: "DiaryBlock",
            instanceID: \.instanceID
        )
        for dto in incoming {
            guard let instanceID = dto.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(recordType: "DiaryBlock", id: dto.id)
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(recordType: "DiaryBlock", instanceID: instanceID)
                }
                if dto.updatedAt == current.updatedAt {
                    guard try sameDiaryBlock(
                        dto,
                        current,
                        preserveLegacyImages: preserveLegacyImages,
                        context: context
                    ) else {
                        throw BackupPackageError.identityCorruption(recordType: "DiaryBlock", instanceID: instanceID)
                    }
                    report.preservedLocalRecords += 1
                    continue
                }
                guard dto.updatedAt > current.updatedAt else {
                    report.preservedLocalRecords += 1
                    continue
                }
                current.reviewId = dto.reviewId
                current.dayKey = dto.dayKey
                current.type = dto.type
                current.text = dto.text
                current.imageFileName = preserveLegacyImages ? dto.imageFileName : nil
                current.order = dto.order
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let block = DiaryBlock(
                    id: dto.id,
                    instanceID: dto.instanceID ?? UUID(),
                    reviewId: dto.reviewId,
                    dayKey: dto.dayKey,
                    type: DiaryBlockType(rawValue: dto.type) ?? .text,
                    text: dto.text,
                    imageFileName: preserveLegacyImages ? dto.imageFileName : nil,
                    order: dto.order,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
                context.insert(block)
                existing[instanceID] = block
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergeAttachments(
        _ contents: BackupPackageContents,
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<DiaryAttachment>()),
            recordType: "DiaryAttachment",
            instanceID: \.instanceID
        )
        for record in contents.records.attachments {
            guard let data = contents.attachmentData[record.id] else {
                throw BackupPackageError.missingAttachmentData(record.id)
            }
            if let current = existing[record.instanceID] {
                guard current.id == record.id else {
                    throw BackupPackageError.identityCorruption(
                        recordType: "DiaryAttachment",
                        instanceID: record.instanceID
                    )
                }
                if record.updatedAt == current.updatedAt {
                    guard try sameAttachment(
                        record,
                        data: data,
                        current,
                        allRecords: contents.records.attachments,
                        context: context
                    ) else {
                        throw BackupPackageError.identityCorruption(
                            recordType: "DiaryAttachment",
                            instanceID: record.instanceID
                        )
                    }
                    continue
                }
                guard record.updatedAt > current.updatedAt else { continue }
                current.reviewId = record.reviewId
                current.order = record.order
                current.originalFileName = record.originalFileName
                current.mimeType = record.mimeType
                current.byteCount = record.byteCount
                current.sha256 = record.sha256
                current.data = data
                current.createdAt = min(current.createdAt, record.createdAt)
                current.updatedAt = record.updatedAt
                current.supersededAt = nil
                report.updatedAttachments += 1
            } else {
                let attachment = DiaryAttachment(
                    id: record.id,
                    instanceID: record.instanceID,
                    reviewId: record.reviewId,
                    order: record.order,
                    originalFileName: record.originalFileName,
                    mimeType: record.mimeType,
                    byteCount: record.byteCount,
                    sha256: record.sha256,
                    data: data,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
                context.insert(attachment)
                existing[record.instanceID] = attachment
                report.insertedAttachments += 1
            }
        }
    }

    static func sameEvent(_ dto: CalendarEventDTO, _ event: CalendarEvent) -> Bool {
        event.title == dto.title &&
            event.startAt == dto.startAt &&
            event.endAt == dto.endAt &&
            event.startDayKey == dto.startDayKey &&
            event.endDayKey == dto.endDayKey &&
            event.note == dto.note &&
            event.color == dto.color
    }

    static func uniqueByInstanceID<Record>(
        _ records: [Record],
        recordType: String,
        instanceID: KeyPath<Record, UUID>
    ) throws -> [UUID: Record] {
        var result: [UUID: Record] = [:]
        for record in records {
            let value = record[keyPath: instanceID]
            guard result[value] == nil else {
                throw BackupPackageError.identityCorruption(
                    recordType: recordType,
                    instanceID: value
                )
            }
            result[value] = record
        }
        return result
    }

    static func sameTemplate(_ dto: TaskTemplateDTO, _ template: TaskTemplate) -> Bool {
        template.seedKey == dto.seedKey &&
            template.name == dto.name &&
            template.isFavorite == (dto.isFavorite ?? false)
    }

    @MainActor
    static func sameTemplateItem(
        _ dto: TaskTemplateItemDTO,
        _ item: TaskTemplateItem,
        context: ModelContext
    ) throws -> Bool {
        let expectedTemplateID = item.supersededAt == nil
            ? try canonicalTemplateID(for: dto.templateId, context: context)
            : dto.templateId
        return item.seedKey == dto.seedKey &&
            item.templateId == expectedTemplateID &&
            item.title == dto.title &&
            item.note == dto.note &&
            item.priority == dto.priority &&
            item.tags == dto.tags &&
            item.estimatedMinutes == dto.estimatedMinutes &&
            (dto.checklistTitles == nil || item.checklistTitles == dto.checklistTitles) &&
            item.order == dto.order
    }

    @MainActor
    static func sameChecklistItem(
        _ dto: TaskChecklistItemDTO,
        _ item: TaskChecklistItem,
        context: ModelContext
    ) throws -> Bool {
        let expectedTaskID = item.supersededAt == nil
            ? try canonicalTaskID(for: dto.taskId, context: context)
            : dto.taskId
        return item.taskId == expectedTaskID &&
            item.title == dto.title &&
            item.isCompleted == dto.isCompleted &&
            item.order == dto.order &&
            item.completedAt == (dto.isCompleted ? (dto.completedAt ?? dto.updatedAt) : nil)
    }

    @MainActor
    static func samePlacement(
        _ dto: TemplatePlacementDTO,
        _ placement: TemplatePlacement,
        context: ModelContext
    ) throws -> Bool {
        let expectedTemplateID = placement.supersededAt == nil
            ? try canonicalTemplateID(for: dto.sourceTemplateId, context: context)
            : dto.sourceTemplateId
        return placement.sourceTemplateId == expectedTemplateID &&
            placement.templateName == dto.templateName &&
            placement.dayKey == dto.dayKey
    }

    @MainActor
    static func sameTask(
        _ dto: TaskDTO,
        _ task: Task,
        sourceFormatVersion: Int?,
        context: ModelContext
    ) throws -> Bool {
        let expectedEventID = task.supersededAt == nil
            ? try canonicalEventID(dto.eventId, context: context)
            : dto.eventId
        let expectedPlacementID = task.supersededAt == nil
            ? try canonicalPlacementID(dto.templatePlacementId, context: context)
            : dto.templatePlacementId
        let reminderMatches = !sourceHasTaskReminderSemantics(sourceFormatVersion) ||
            task.reminderAt == TaskReminderRules.normalizedDate(dto.reminderAt)
        return task.title == dto.title &&
            task.note == dto.note &&
            task.status == dto.status &&
            task.plannedAt == dto.plannedAt &&
            task.plannedDayKey == dto.plannedDayKey &&
            task.order == dto.order &&
            task.eventId == expectedEventID &&
            task.templatePlacementId == expectedPlacementID &&
            task.priority == dto.priority &&
            task.tags == dto.tags &&
            task.estimatedMinutes == dto.estimatedMinutes &&
            reminderMatches &&
            task.completedAt == dto.completedAt &&
            task.completedDayKey == dto.completedDayKey &&
            task.archivedAt == dto.archivedAt &&
            task.archivedDayKey == dto.archivedDayKey
    }

    static func sourceHasTaskReminderSemantics(_ formatVersion: Int?) -> Bool {
        formatVersion.map { $0 >= 3 } == true
    }

    static func sameReview(
        _ dto: DailyReviewDTO,
        _ review: DailyReview,
        preserveLegacyImages: Bool
    ) -> Bool {
        let sameScalars = review.dayKey == dto.dayKey &&
            review.title == (dto.title ?? "") &&
            review.weather == (dto.weather ?? "") &&
            review.mood == (dto.mood ?? "") &&
            review.content == dto.content
        guard preserveLegacyImages else { return sameScalars }
        return sameScalars && containsLegacyFileNames(
            review.imageFileNames,
            expected: dto.imageFileNames ?? []
        )
    }

    @MainActor
    static func sameDiaryBlock(
        _ dto: DiaryBlockDTO,
        _ block: DiaryBlock,
        preserveLegacyImages: Bool,
        context: ModelContext
    ) throws -> Bool {
        let canonicalReview = block.supersededAt == nil
            ? try canonicalReview(for: dto.reviewId, context: context)
            : nil
        let expectedReviewID = canonicalReview?.id ?? dto.reviewId
        let expectedDayKey = canonicalReview?.dayKey ?? dto.dayKey
        let imageFileName = preserveLegacyImages ? dto.imageFileName : nil
        return block.reviewId == expectedReviewID &&
            block.dayKey == expectedDayKey &&
            block.type == dto.type &&
            block.text == dto.text &&
            block.imageFileName == imageFileName &&
            block.order == dto.order
    }

    @MainActor
    static func sameAttachment(
        _ record: BackupPackageAttachmentRecord,
        data: Data,
        _ attachment: DiaryAttachment,
        allRecords: [BackupPackageAttachmentRecord],
        context: ModelContext
    ) throws -> Bool {
        let canonicalReview = attachment.supersededAt == nil
            ? try canonicalReview(for: record.reviewId, context: context)
            : nil
        let expectedReviewID = canonicalReview?.id ?? record.reviewId
        let reviewWasRewritten = expectedReviewID != record.reviewId
        let preservesRelativeOrder = reviewWasRewritten
            ? try preservesRelativeAttachmentOrder(
                sourceReviewID: record.reviewId,
                canonicalReviewID: expectedReviewID,
                allRecords: allRecords,
                context: context
            )
            : false
        let orderMatches = reviewWasRewritten
            ? preservesRelativeOrder
            : attachment.order == record.order
        return attachment.reviewId == expectedReviewID &&
            orderMatches &&
            attachment.originalFileName == record.originalFileName &&
            attachment.mimeType == record.mimeType &&
            attachment.byteCount == record.byteCount &&
            attachment.sha256 == record.sha256 &&
            attachment.data == data
    }

    @MainActor
    static func canonicalTemplateID(
        for sourceID: UUID?,
        context: ModelContext
    ) throws -> UUID? {
        guard let sourceID else { return nil }
        let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
        if templates.contains(where: { $0.id == sourceID && $0.supersededAt == nil }) {
            return sourceID
        }
        guard let source = templates.filter({ $0.id == sourceID }).max(by: {
            mergeRecordPrecedes(
                lhsUpdatedAt: $0.updatedAt,
                lhsInstanceID: $0.instanceID,
                rhsUpdatedAt: $1.updatedAt,
                rhsInstanceID: $1.instanceID
            )
        }),
              let seedKey = normalizedNaturalKey(source.seedKey) else {
            return nil
        }
        return templates.first {
            $0.supersededAt == nil && normalizedNaturalKey($0.seedKey) == seedKey
        }?.id
    }

    @MainActor
    static func canonicalTaskID(
        for sourceID: UUID,
        context: ModelContext
    ) throws -> UUID? {
        try context.fetch(FetchDescriptor<Task>()).first {
            $0.id == sourceID && $0.supersededAt == nil
        }?.id
    }

    @MainActor
    static func canonicalReview(
        for sourceID: UUID,
        context: ModelContext
    ) throws -> DailyReview? {
        let reviews = try context.fetch(FetchDescriptor<DailyReview>())
        if let active = reviews.first(where: {
            $0.id == sourceID && $0.supersededAt == nil
        }) {
            return active
        }
        guard let source = reviews.filter({ $0.id == sourceID }).max(by: {
            mergeRecordPrecedes(
                lhsUpdatedAt: $0.updatedAt,
                lhsInstanceID: $0.instanceID,
                rhsUpdatedAt: $1.updatedAt,
                rhsInstanceID: $1.instanceID
            )
        }) else { return nil }
        return reviews.first {
            $0.supersededAt == nil && $0.dayKey == source.dayKey
        }
    }

    @MainActor
    static func canonicalEventID(
        _ sourceID: UUID?,
        context: ModelContext
    ) throws -> UUID? {
        guard let sourceID else { return nil }
        return try context.fetch(FetchDescriptor<CalendarEvent>()).first {
            $0.id == sourceID && $0.supersededAt == nil
        }?.id
    }

    @MainActor
    static func canonicalPlacementID(
        _ sourceID: UUID?,
        context: ModelContext
    ) throws -> UUID? {
        guard let sourceID else { return nil }
        return try context.fetch(FetchDescriptor<TemplatePlacement>()).first {
            $0.id == sourceID && $0.supersededAt == nil
        }?.id
    }

    @MainActor
    static func preservesRelativeAttachmentOrder(
        sourceReviewID: UUID,
        canonicalReviewID: UUID,
        allRecords: [BackupPackageAttachmentRecord],
        context: ModelContext
    ) throws -> Bool {
        let incomingInstanceIDs = allRecords
            .filter { $0.reviewId == sourceReviewID }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
            .map(\.instanceID)
        guard !incomingInstanceIDs.isEmpty else { return false }
        let incomingInstanceIDSet = Set(incomingInstanceIDs)
        let localInstanceIDs = try context.fetch(FetchDescriptor<DiaryAttachment>())
            .filter {
                $0.supersededAt == nil &&
                    $0.reviewId == canonicalReviewID &&
                    incomingInstanceIDSet.contains($0.instanceID)
            }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
            .map(\.instanceID)
        let localInstanceIDSet = Set(localInstanceIDs)
        let commonIncomingInstanceIDs = incomingInstanceIDs.filter(
            localInstanceIDSet.contains
        )
        return localInstanceIDs == commonIncomingInstanceIDs
    }

    @MainActor
    static func validateImportedAttachmentRelativeOrder(
        _ contents: BackupPackageContents,
        context: ModelContext
    ) throws {
        let localAttachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
        for (sourceReviewID, records) in Dictionary(
            grouping: contents.records.attachments,
            by: \.reviewId
        ) {
            guard let canonicalReview = try canonicalReview(
                for: sourceReviewID,
                context: context
            ) else {
                throw BackupPackageError.danglingReviewReference(sourceReviewID)
            }
            let orderedIncomingRecords = records
                .sorted {
                    if $0.order != $1.order { return $0.order < $1.order }
                    return $0.instanceID.uuidString < $1.instanceID.uuidString
                }
            let activeLocalByInstanceID = Dictionary(
                uniqueKeysWithValues: localAttachments.compactMap { attachment in
                    attachment.supersededAt == nil
                        ? (attachment.instanceID, attachment)
                        : nil
                }
            )
            let expectedInstanceIDs: [UUID] = orderedIncomingRecords.compactMap { record -> UUID? in
                guard let local = activeLocalByInstanceID[record.instanceID],
                      local.updatedAt <= record.updatedAt else {
                    return nil
                }
                return record.instanceID
            }
            let expectedInstanceIDSet = Set(expectedInstanceIDs)
            let actualInstanceIDs = localAttachments
                .filter {
                    $0.supersededAt == nil &&
                        $0.reviewId == canonicalReview.id &&
                        expectedInstanceIDSet.contains($0.instanceID)
                }
                .sorted {
                    if $0.order != $1.order { return $0.order < $1.order }
                    return $0.instanceID.uuidString < $1.instanceID.uuidString
                }
                .map(\.instanceID)
            guard actualInstanceIDs == expectedInstanceIDs else {
                throw BackupPackageError.identityCorruption(
                    recordType: "DiaryAttachment",
                    instanceID: expectedInstanceIDs.first ?? records[0].instanceID
                )
            }
        }
    }

    static func containsLegacyFileNames(_ actual: [String], expected: [String]) -> Bool {
        var remaining = Dictionary(grouping: actual, by: { $0 }).mapValues(\.count)
        for fileName in expected {
            guard let count = remaining[fileName], count > 0 else { return false }
            remaining[fileName] = count - 1
        }
        return true
    }

    static func normalizedNaturalKey(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    static func mergeRecordPrecedes(
        lhsUpdatedAt: Date,
        lhsInstanceID: UUID,
        rhsUpdatedAt: Date,
        rhsInstanceID: UUID
    ) -> Bool {
        if lhsUpdatedAt != rhsUpdatedAt {
            return lhsUpdatedAt < rhsUpdatedAt
        }
        return lhsInstanceID.uuidString < rhsInstanceID.uuidString
    }
}
