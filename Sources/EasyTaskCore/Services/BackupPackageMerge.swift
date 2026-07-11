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
            try mergeTasks(payload.tasks, context: context, report: &report)
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
            try mergeTasks(payload.tasks, context: context, report: &report)
            try mergeReviews(payload.dailyReviews ?? [], context: context, report: &report)
            try mergeDiaryBlocks(payload.diaryBlocks ?? [], context: context, report: &report)
            try mergeAttachments(contents, context: context, report: &report)
            _ = try DataIntegrityService.reconcile(context: context, saveChanges: false)
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
        let records = try context.fetch(FetchDescriptor<CalendarEvent>())
        var existing = try uniqueByInstanceID(
            records,
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
                    guard sameEvent(dto, current) || hasReconciledDuplicate(
                        in: records,
                        current: current,
                        instanceID: \.instanceID,
                        recordUpdatedAt: \.updatedAt,
                        supersededAt: \.supersededAt,
                        sharesGroup: { $0.id == current.id },
                        sameScalars: sameEventScalars
                    ) else {
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
        let records = try context.fetch(FetchDescriptor<TaskTemplate>())
        var existing = try uniqueByInstanceID(
            records,
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
                    guard sameTemplate(dto, current) || hasReconciledDuplicate(
                        in: records,
                        current: current,
                        instanceID: \.instanceID,
                        recordUpdatedAt: \.updatedAt,
                        supersededAt: \.supersededAt,
                        sharesGroup: {
                            if $0.id == current.id { return true }
                            guard let currentSeedKey = normalizedNaturalKey(current.seedKey) else {
                                return false
                            }
                            return normalizedNaturalKey($0.seedKey) == currentSeedKey
                        },
                        sameScalars: sameTemplateScalars
                    ) else {
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
        let records = try context.fetch(FetchDescriptor<TaskTemplateItem>())
        var existing = try uniqueByInstanceID(
            records,
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
                    guard sameTemplateItem(dto, current) || hasReconciledDuplicate(
                        in: records,
                        current: current,
                        instanceID: \.instanceID,
                        recordUpdatedAt: \.updatedAt,
                        supersededAt: \.supersededAt,
                        sharesGroup: {
                            $0.id == current.id ||
                                (normalizedNaturalKey($0.seedKey) != nil &&
                                    normalizedNaturalKey($0.seedKey) == normalizedNaturalKey(current.seedKey) &&
                                    $0.templateId == current.templateId)
                        },
                        sameScalars: sameTemplateItemScalars
                    ) else {
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
        let records = try context.fetch(FetchDescriptor<TemplatePlacement>())
        var existing = try uniqueByInstanceID(
            records,
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
                    guard samePlacement(dto, current) || hasReconciledDuplicate(
                        in: records,
                        current: current,
                        instanceID: \.instanceID,
                        recordUpdatedAt: \.updatedAt,
                        supersededAt: \.supersededAt,
                        sharesGroup: { $0.id == current.id },
                        sameScalars: samePlacementScalars
                    ) else {
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
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        let records = try context.fetch(FetchDescriptor<Task>())
        var existing = try uniqueByInstanceID(
            records,
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
                    guard sameTask(dto, current) || hasReconciledDuplicate(
                        in: records,
                        current: current,
                        instanceID: \.instanceID,
                        recordUpdatedAt: \.updatedAt,
                        supersededAt: \.supersededAt,
                        sharesGroup: { $0.id == current.id },
                        sameScalars: sameTaskScalars
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
                apply(dto, to: current)
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
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
                apply(dto, to: task)
                context.insert(task)
                existing[instanceID] = task
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func apply(_ dto: TaskDTO, to task: Task) {
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
        task.updatedAt = dto.updatedAt
        task.completedAt = dto.completedAt
        task.completedDayKey = dto.completedDayKey
        task.archivedAt = dto.archivedAt
        task.archivedDayKey = dto.archivedDayKey
    }

    @MainActor
    static func mergeReviews(
        _ incoming: [DailyReviewDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport,
        preserveLegacyImages: Bool = false
    ) throws {
        let records = try context.fetch(FetchDescriptor<DailyReview>())
        var existing = try uniqueByInstanceID(
            records,
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
                    ) || hasReconciledDuplicate(
                        in: records,
                        current: current,
                        instanceID: \.instanceID,
                        recordUpdatedAt: \.updatedAt,
                        supersededAt: \.supersededAt,
                        sharesGroup: {
                            $0.id == current.id || $0.dayKey == current.dayKey
                        },
                        sameScalars: sameReviewScalars
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
        let records = try context.fetch(FetchDescriptor<DiaryBlock>())
        var existing = try uniqueByInstanceID(
            records,
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
                    guard sameDiaryBlock(
                        dto,
                        current,
                        preserveLegacyImages: preserveLegacyImages
                    ) || hasReconciledDuplicate(
                        in: records,
                        current: current,
                        instanceID: \.instanceID,
                        recordUpdatedAt: \.updatedAt,
                        supersededAt: \.supersededAt,
                        sharesGroup: { $0.id == current.id },
                        sameScalars: sameDiaryBlockScalars
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
        let records = try context.fetch(FetchDescriptor<DiaryAttachment>())
        var existing = try uniqueByInstanceID(
            records,
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
                    guard sameAttachment(record, data: data, current) || hasReconciledDuplicate(
                        in: records,
                        current: current,
                        instanceID: \.instanceID,
                        recordUpdatedAt: \.updatedAt,
                        supersededAt: \.supersededAt,
                        sharesGroup: { $0.id == current.id },
                        sameScalars: sameAttachmentScalars
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

    static func sameTemplateItem(
        _ dto: TaskTemplateItemDTO,
        _ item: TaskTemplateItem
    ) -> Bool {
        item.seedKey == dto.seedKey &&
            item.title == dto.title &&
            item.note == dto.note &&
            item.priority == dto.priority &&
            item.tags == dto.tags &&
            item.estimatedMinutes == dto.estimatedMinutes &&
            item.order == dto.order
    }

    static func samePlacement(
        _ dto: TemplatePlacementDTO,
        _ placement: TemplatePlacement
    ) -> Bool {
        placement.templateName == dto.templateName &&
            placement.dayKey == dto.dayKey
    }

    static func sameTask(_ dto: TaskDTO, _ task: Task) -> Bool {
        task.title == dto.title &&
            task.note == dto.note &&
            task.status == dto.status &&
            task.plannedAt == dto.plannedAt &&
            task.plannedDayKey == dto.plannedDayKey &&
            task.order == dto.order &&
            task.priority == dto.priority &&
            task.tags == dto.tags &&
            task.estimatedMinutes == dto.estimatedMinutes &&
            task.completedAt == dto.completedAt &&
            task.completedDayKey == dto.completedDayKey &&
            task.archivedAt == dto.archivedAt &&
            task.archivedDayKey == dto.archivedDayKey
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

    static func sameDiaryBlock(
        _ dto: DiaryBlockDTO,
        _ block: DiaryBlock,
        preserveLegacyImages: Bool
    ) -> Bool {
        let imageFileName = preserveLegacyImages ? dto.imageFileName : nil
        return block.type == dto.type &&
            block.text == dto.text &&
            block.imageFileName == imageFileName &&
            block.order == dto.order
    }

    static func sameAttachment(
        _ record: BackupPackageAttachmentRecord,
        data: Data,
        _ attachment: DiaryAttachment
    ) -> Bool {
        attachment.originalFileName == record.originalFileName &&
            attachment.mimeType == record.mimeType &&
            attachment.byteCount == record.byteCount &&
            attachment.sha256 == record.sha256 &&
            attachment.data == data
    }

    static func sameEventScalars(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        lhs.title == rhs.title &&
            lhs.startAt == rhs.startAt &&
            lhs.endAt == rhs.endAt &&
            lhs.startDayKey == rhs.startDayKey &&
            lhs.endDayKey == rhs.endDayKey &&
            lhs.note == rhs.note &&
            lhs.color == rhs.color
    }

    static func sameTemplateScalars(_ lhs: TaskTemplate, _ rhs: TaskTemplate) -> Bool {
        lhs.seedKey == rhs.seedKey &&
            lhs.name == rhs.name &&
            lhs.isFavorite == rhs.isFavorite
    }

    static func sameTemplateItemScalars(
        _ lhs: TaskTemplateItem,
        _ rhs: TaskTemplateItem
    ) -> Bool {
        lhs.seedKey == rhs.seedKey &&
            lhs.title == rhs.title &&
            lhs.note == rhs.note &&
            lhs.priority == rhs.priority &&
            lhs.tags == rhs.tags &&
            lhs.estimatedMinutes == rhs.estimatedMinutes &&
            lhs.order == rhs.order
    }

    static func samePlacementScalars(
        _ lhs: TemplatePlacement,
        _ rhs: TemplatePlacement
    ) -> Bool {
        lhs.templateName == rhs.templateName &&
            lhs.dayKey == rhs.dayKey
    }

    static func sameTaskScalars(_ lhs: Task, _ rhs: Task) -> Bool {
        lhs.title == rhs.title &&
            lhs.note == rhs.note &&
            lhs.status == rhs.status &&
            lhs.plannedAt == rhs.plannedAt &&
            lhs.plannedDayKey == rhs.plannedDayKey &&
            lhs.order == rhs.order &&
            lhs.priority == rhs.priority &&
            lhs.tags == rhs.tags &&
            lhs.estimatedMinutes == rhs.estimatedMinutes &&
            lhs.completedAt == rhs.completedAt &&
            lhs.completedDayKey == rhs.completedDayKey &&
            lhs.archivedAt == rhs.archivedAt &&
            lhs.archivedDayKey == rhs.archivedDayKey
    }

    static func sameReviewScalars(_ lhs: DailyReview, _ rhs: DailyReview) -> Bool {
        lhs.dayKey == rhs.dayKey &&
            lhs.title == rhs.title &&
            lhs.weather == rhs.weather &&
            lhs.mood == rhs.mood &&
            lhs.content == rhs.content
    }

    static func sameDiaryBlockScalars(_ lhs: DiaryBlock, _ rhs: DiaryBlock) -> Bool {
        lhs.type == rhs.type &&
            lhs.text == rhs.text &&
            lhs.imageFileName == rhs.imageFileName &&
            lhs.order == rhs.order
    }

    static func sameAttachmentScalars(
        _ lhs: DiaryAttachment,
        _ rhs: DiaryAttachment
    ) -> Bool {
        lhs.originalFileName == rhs.originalFileName &&
            lhs.mimeType == rhs.mimeType &&
            lhs.byteCount == rhs.byteCount &&
            lhs.sha256 == rhs.sha256 &&
            lhs.data == rhs.data
    }

    static func hasReconciledDuplicate<Record>(
        in records: [Record],
        current: Record,
        instanceID instanceIDKeyPath: KeyPath<Record, UUID>,
        recordUpdatedAt updatedAtKeyPath: KeyPath<Record, Date>,
        supersededAt supersededAtKeyPath: KeyPath<Record, Date?>,
        sharesGroup: (Record) -> Bool,
        sameScalars: (Record, Record) -> Bool
    ) -> Bool {
        let currentInstanceID = current[keyPath: instanceIDKeyPath]
        let currentUpdatedAt = current[keyPath: updatedAtKeyPath]
        let candidates = records.filter { record in
            record[keyPath: instanceIDKeyPath] != currentInstanceID &&
                record[keyPath: supersededAtKeyPath] != nil &&
                record[keyPath: updatedAtKeyPath] == currentUpdatedAt &&
                sharesGroup(record)
        }
        guard let winner = candidates.max(by: {
            $0[keyPath: instanceIDKeyPath].uuidString <
                $1[keyPath: instanceIDKeyPath].uuidString
        }),
              winner[keyPath: instanceIDKeyPath].uuidString > currentInstanceID.uuidString else {
            return false
        }
        return sameScalars(current, winner)
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
}
