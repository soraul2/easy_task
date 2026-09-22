import Foundation
import SwiftData

extension BackupPackageCodec {
    static func sameEvent(_ dto: CalendarEventDTO, _ event: CalendarEvent) -> Bool {
        event.title == dto.title &&
            event.startAt == dto.startAt &&
            event.endAt == dto.endAt &&
            event.startDayKey == dto.startDayKey &&
            event.endDayKey == dto.endDayKey &&
            event.note == dto.note &&
            event.color == dto.color
    }

    static func sameMemo(_ dto: MemoDTO, _ memo: Memo) -> Bool {
        memo.content == dto.content &&
            memo.isPinned == dto.isPinned &&
            memo.preferredModeRawValue == (
                dto.preferredModeRawValue ?? MemoEditorMode.text.rawValue
            )
    }

    static func sameMemoDrawing(_ dto: MemoDrawingDTO, _ drawing: MemoDrawing) -> Bool {
        drawing.memoId == dto.memoId && drawing.drawingData == dto.drawingData
    }

    static func sameMemoChecklistItem(
        _ dto: MemoChecklistItemDTO,
        _ item: MemoChecklistItem
    ) -> Bool {
        item.memoId == dto.memoId &&
            item.title == dto.title &&
            item.isCompleted == dto.isCompleted &&
            item.order == dto.order &&
            item.completedAt == dto.completedAt
    }

    static func sameTaskCompletionActivity(
        _ dto: TaskCompletionActivityDTO,
        _ activity: TaskCompletionActivity
    ) -> Bool {
        activity.taskId == dto.taskId &&
            activity.activityDayKey == dto.activityDayKey &&
            activity.occurredAt == dto.occurredAt &&
            activity.originRawValue == dto.originRawValue &&
            activity.createdAt == dto.createdAt
    }

    static func sameTaskProgressEvent(
        _ dto: TaskProgressEventDTO,
        _ event: TaskProgressEvent
    ) -> Bool {
        event.taskId == dto.taskId &&
            event.kindRawValue == dto.kindRawValue &&
            event.originRawValue == dto.originRawValue &&
            event.occurredAt == dto.occurredAt &&
            event.createdAt == dto.createdAt
    }

    static func sameFocusSession(
        _ dto: FocusSessionDTO,
        _ session: FocusSession
    ) -> Bool {
        session.taskId == dto.taskId &&
            session.startedAt == dto.startedAt &&
            session.endedAt == dto.endedAt &&
            session.plannedDurationSeconds == dto.plannedDurationSeconds &&
            session.focusedDurationSeconds == dto.focusedDurationSeconds &&
            session.outcomeRawValue == dto.outcomeRawValue &&
            session.createdAt == dto.createdAt
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
            template.isFavorite == (dto.isFavorite ?? false) &&
            (dto.quickEntryAlias == nil || (template.quickEntryAlias ?? "") == dto.quickEntryAlias)
    }

    @MainActor
    static func sameTemplateItem(
        _ dto: TaskTemplateItemDTO,
        _ item: TaskTemplateItem,
        parents: BackupPackageParentLookup
    ) throws -> Bool {
        let expectedTemplateID = item.supersededAt == nil
            ? try parents.templateID(for: dto.templateId)
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
        parents: BackupPackageParentLookup
    ) throws -> Bool {
        let expectedTaskID = item.supersededAt == nil
            ? try parents.taskID(for: dto.taskId)
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
        parents: BackupPackageParentLookup
    ) throws -> Bool {
        let expectedTemplateID = placement.supersededAt == nil
            ? try parents.templateID(for: dto.sourceTemplateId)
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
        parents: BackupPackageParentLookup
    ) throws -> Bool {
        let expectedEventID = task.supersededAt == nil
            ? try parents.eventID(for: dto.eventId)
            : dto.eventId
        let expectedPlacementID = task.supersededAt == nil
            ? try parents.placementID(for: dto.templatePlacementId)
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
        parents: BackupPackageParentLookup
    ) throws -> Bool {
        let canonicalReview = block.supersededAt == nil
            ? try parents.review(for: dto.reviewId)
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
        context: ModelContext,
        parents: BackupPackageParentLookup
    ) throws -> Bool {
        let canonicalReview = attachment.supersededAt == nil
            ? try parents.review(for: record.reviewId)
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
        let parents = BackupPackageParentLookup(context: context)
        for (sourceReviewID, records) in Dictionary(
            grouping: contents.records.attachments,
            by: \.reviewId
        ) {
            guard let canonicalReview = try parents.review(for: sourceReviewID) else {
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
