import Foundation
import SwiftData

extension BackupPackageCodec {
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
        let parents = BackupPackageParentLookup(context: context)
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
                    guard try sameChecklistItem(dto, current, parents: parents) else {
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
                current.taskId = try parents.taskID(for: dto.taskId) ?? dto.taskId
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
                    taskId: try parents.taskID(for: dto.taskId) ?? dto.taskId,
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
        let parents = BackupPackageParentLookup(context: context)
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
                        parents: parents
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
    static func mergeMemos(
        _ incoming: [MemoDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<Memo>()),
            recordType: "Memo",
            instanceID: \.instanceID
        )
        for dto in incoming {
            guard let instanceID = dto.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(recordType: "Memo", id: dto.id)
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(
                        recordType: "Memo",
                        instanceID: instanceID
                    )
                }
                if dto.updatedAt == current.updatedAt {
                    guard sameMemo(dto, current) else {
                        throw BackupPackageError.identityCorruption(
                            recordType: "Memo",
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
                current.content = dto.content
                current.isPinned = dto.isPinned
                current.preferredModeRawValue = dto.preferredModeRawValue
                    ?? MemoEditorMode.text.rawValue
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let memo = Memo(
                    id: dto.id,
                    instanceID: instanceID,
                    content: dto.content,
                    isPinned: dto.isPinned,
                    preferredMode: dto.preferredModeRawValue
                        .flatMap(MemoEditorMode.init(rawValue:)) ?? .text,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
                context.insert(memo)
                existing[instanceID] = memo
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergeMemoDrawings(
        _ incoming: [MemoDrawingDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<MemoDrawing>()),
            recordType: "MemoDrawing",
            instanceID: \.instanceID
        )
        for dto in incoming {
            guard let instanceID = dto.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(
                    recordType: "MemoDrawing",
                    id: dto.id
                )
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(
                        recordType: "MemoDrawing",
                        instanceID: instanceID
                    )
                }
                if dto.updatedAt == current.updatedAt {
                    guard sameMemoDrawing(dto, current) else {
                        throw BackupPackageError.identityCorruption(
                            recordType: "MemoDrawing",
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
                current.memoId = dto.memoId
                current.drawingData = dto.drawingData
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let drawing = MemoDrawing(dto: dto)
                context.insert(drawing)
                existing[instanceID] = drawing
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergeMemoChecklistItems(
        _ incoming: [MemoChecklistItemDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<MemoChecklistItem>()),
            recordType: "MemoChecklistItem",
            instanceID: \.instanceID
        )
        for dto in incoming {
            guard let instanceID = dto.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(
                    recordType: "MemoChecklistItem",
                    id: dto.id
                )
            }
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(
                        recordType: "MemoChecklistItem",
                        instanceID: instanceID
                    )
                }
                if dto.updatedAt == current.updatedAt {
                    guard sameMemoChecklistItem(dto, current) else {
                        throw BackupPackageError.identityCorruption(
                            recordType: "MemoChecklistItem",
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
                current.memoId = dto.memoId
                current.title = dto.title
                current.isCompleted = dto.isCompleted
                current.order = dto.order
                current.completedAt = dto.completedAt
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let item = MemoChecklistItem(dto: dto)
                context.insert(item)
                existing[instanceID] = item
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergeTaskCompletionActivities(
        _ incoming: [TaskCompletionActivityDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<TaskCompletionActivity>()),
            recordType: "TaskCompletionActivity",
            instanceID: \.instanceID
        )
        for dto in incoming {
            let instanceID = dto.instanceID
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(
                        recordType: "TaskCompletionActivity",
                        instanceID: instanceID
                    )
                }
                if dto.updatedAt == current.updatedAt {
                    guard sameTaskCompletionActivity(dto, current) else {
                        throw BackupPackageError.identityCorruption(
                            recordType: "TaskCompletionActivity",
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
                current.taskId = dto.taskId
                current.activityDayKey = dto.activityDayKey
                current.occurredAt = dto.occurredAt
                current.originRawValue = dto.originRawValue
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let activity = TaskCompletionActivity(dto: dto)
                context.insert(activity)
                existing[instanceID] = activity
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergeTaskProgressEvents(
        _ incoming: [TaskProgressEventDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<TaskProgressEvent>()),
            recordType: "TaskProgressEvent",
            instanceID: \.instanceID
        )
        for dto in incoming {
            let instanceID = dto.instanceID
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(
                        recordType: "TaskProgressEvent",
                        instanceID: instanceID
                    )
                }
                if dto.updatedAt == current.updatedAt {
                    guard sameTaskProgressEvent(dto, current) else {
                        throw BackupPackageError.identityCorruption(
                            recordType: "TaskProgressEvent",
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
                current.taskId = dto.taskId
                current.kindRawValue = dto.kindRawValue
                current.originRawValue = dto.originRawValue
                current.occurredAt = dto.occurredAt
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let event = TaskProgressEvent(dto: dto)
                context.insert(event)
                existing[instanceID] = event
                report.insertedRecords += 1
            }
        }
    }

    @MainActor
    static func mergeFocusSessions(
        _ incoming: [FocusSessionDTO],
        context: ModelContext,
        report: inout BackupPackageMergeReport
    ) throws {
        var existing = try uniqueByInstanceID(
            context.fetch(FetchDescriptor<FocusSession>()),
            recordType: "FocusSession",
            instanceID: \.instanceID
        )
        for dto in incoming {
            let instanceID = dto.instanceID
            if let current = existing[instanceID] {
                guard current.id == dto.id else {
                    throw BackupPackageError.identityCorruption(
                        recordType: "FocusSession",
                        instanceID: instanceID
                    )
                }
                if dto.updatedAt == current.updatedAt {
                    guard sameFocusSession(dto, current) else {
                        throw BackupPackageError.identityCorruption(
                            recordType: "FocusSession",
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
                current.taskId = dto.taskId
                current.startedAt = dto.startedAt
                current.endedAt = dto.endedAt
                current.plannedDurationSeconds = dto.plannedDurationSeconds
                current.focusedDurationSeconds = dto.focusedDurationSeconds
                current.outcomeRawValue = dto.outcomeRawValue
                current.createdAt = min(current.createdAt, dto.createdAt)
                current.updatedAt = dto.updatedAt
                current.supersededAt = nil
                report.updatedRecords += 1
            } else {
                let session = FocusSession(dto: dto)
                context.insert(session)
                existing[instanceID] = session
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
        let parents = BackupPackageParentLookup(context: context)
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
                        context: context,
                        parents: parents
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

}
