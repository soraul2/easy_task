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
        memo.content == dto.content && memo.isPinned == dto.isPinned
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
