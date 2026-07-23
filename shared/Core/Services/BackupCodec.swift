import Foundation
import SwiftData

public enum BackupCodec {
    public static let currentVersion = 1

    @MainActor
    public static func makePayload(context: ModelContext) throws -> BackupPayload {
        _ = try DataIntegrityService.reconcile(context: context)
        let tasks = try context.fetch(FetchDescriptor<Task>()).filter { $0.supersededAt == nil }
        let placements = try context.fetch(FetchDescriptor<TemplatePlacement>())
            .filter { $0.supersededAt == nil }
            .map { placement in
            var dto = TemplatePlacementDTO(placement: placement)
            dto.taskIds = tasks
                .filter { $0.templatePlacementId == placement.id }
                .sorted {
                    if $0.order != $1.order { return $0.order < $1.order }
                    return $0.id.uuidString < $1.id.uuidString
                }
                .map(\.id)
            return dto
        }

        let payload = BackupPayload(
            backupVersion: currentVersion,
            exportedAt: Date(),
            tasks: tasks.map(TaskDTO.init),
            taskChecklistItems: try context.fetch(FetchDescriptor<TaskChecklistItem>())
                .filter { $0.supersededAt == nil }
                .map(TaskChecklistItemDTO.init),
            calendarEvents: try context.fetch(FetchDescriptor<CalendarEvent>())
                .filter { $0.supersededAt == nil }
                .map(CalendarEventDTO.init),
            taskTemplates: try context.fetch(FetchDescriptor<TaskTemplate>())
                .filter { $0.supersededAt == nil }
                .map(TaskTemplateDTO.init),
            taskTemplateItems: try context.fetch(FetchDescriptor<TaskTemplateItem>())
                .filter { $0.supersededAt == nil }
                .map(TaskTemplateItemDTO.init),
            templatePlacements: placements,
            dailyReviews: try context.fetch(FetchDescriptor<DailyReview>())
                .filter { $0.supersededAt == nil }
                .map(DailyReviewDTO.init),
            diaryBlocks: try context.fetch(FetchDescriptor<DiaryBlock>())
                .filter { $0.supersededAt == nil }
                .map(DiaryBlockDTO.init),
            memos: try context.fetch(FetchDescriptor<Memo>())
                .filter { $0.supersededAt == nil }
                .map(MemoDTO.init)
        )
        return try validatedPayload(payload)
    }

    public static func encode(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    public static func decode(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        return try validatedPayload(payload)
    }

    public static func replaceAll(with payload: BackupPayload, in context: ModelContext) throws {
        try replaceAll(with: payload, in: context, beforeFinalSave: {})
    }

    static func replaceAll(
        with payload: BackupPayload,
        in context: ModelContext,
        beforeFinalSave: () throws -> Void
    ) throws {
        let payload = try validatedPayload(payload)

        // Preserve pending user edits as the rollback point before replace-all starts.
        try context.save()

        do {
            for item in try context.fetch(FetchDescriptor<TaskChecklistItem>()) {
                context.delete(item)
            }
            for item in try context.fetch(FetchDescriptor<TaskTemplateItem>()) {
                context.delete(item)
            }
            for placement in try context.fetch(FetchDescriptor<TemplatePlacement>()) {
                context.delete(placement)
            }
            for template in try context.fetch(FetchDescriptor<TaskTemplate>()) {
                context.delete(template)
            }
            for task in try context.fetch(FetchDescriptor<Task>()) {
                context.delete(task)
            }
            for event in try context.fetch(FetchDescriptor<CalendarEvent>()) {
                context.delete(event)
            }
            for attachment in try context.fetch(FetchDescriptor<DiaryAttachment>()) {
                context.delete(attachment)
            }
            for block in try context.fetch(FetchDescriptor<DiaryBlock>()) {
                context.delete(block)
            }
            for review in try context.fetch(FetchDescriptor<DailyReview>()) {
                context.delete(review)
            }
            for memo in try context.fetch(FetchDescriptor<Memo>()) {
                context.delete(memo)
            }

            for dto in payload.calendarEvents {
                context.insert(CalendarEvent(dto: dto))
            }
            for dto in payload.taskTemplates {
                context.insert(TaskTemplate(dto: dto))
            }
            for dto in payload.taskTemplateItems {
                context.insert(TaskTemplateItem(dto: dto))
            }
            for dto in payload.templatePlacements ?? [] {
                context.insert(TemplatePlacement(dto: dto))
            }
            for dto in payload.tasks {
                context.insert(Task(dto: dto))
            }
            for dto in payload.taskChecklistItems ?? [] {
                context.insert(TaskChecklistItem(dto: dto))
            }
            for dto in payload.dailyReviews ?? [] {
                context.insert(DailyReview(dto: dto))
            }
            for dto in payload.diaryBlocks ?? [] {
                context.insert(DiaryBlock(dto: dto))
            }
            for dto in payload.memos ?? [] {
                context.insert(Memo(dto: dto))
            }

            try beforeFinalSave()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public static func validate(_ payload: BackupPayload) throws {
        _ = try validatedPayload(payload)
    }
}

private extension BackupCodec {
    static func validatedPayload(_ source: BackupPayload) throws -> BackupPayload {
        guard source.backupVersion == currentVersion else {
            throw BackupServiceError.unsupportedVersion(source.backupVersion)
        }

        var payload = source
        let taskIDs = try uniqueIDs(payload.tasks.map(\.id), recordType: "Task")
        _ = try uniqueIDs(
            (payload.taskChecklistItems ?? []).map(\.id),
            recordType: "TaskChecklistItem"
        )
        let eventIDs = try uniqueIDs(payload.calendarEvents.map(\.id), recordType: "CalendarEvent")
        let templateIDs = try uniqueIDs(payload.taskTemplates.map(\.id), recordType: "TaskTemplate")
        _ = try uniqueIDs(payload.taskTemplateItems.map(\.id), recordType: "TaskTemplateItem")
        let placements = payload.templatePlacements ?? []
        let placementIDs = try uniqueIDs(placements.map(\.id), recordType: "TemplatePlacement")
        let reviews = payload.dailyReviews ?? []
        let reviewIDs = try uniqueIDs(reviews.map(\.id), recordType: "DailyReview")
        _ = try uniqueIDs((payload.diaryBlocks ?? []).map(\.id), recordType: "DiaryBlock")
        _ = try uniqueIDs((payload.memos ?? []).map(\.id), recordType: "Memo")

        try validateEvents(payload.calendarEvents)
        try validateTemplates(payload.taskTemplateItems, templateIDs: templateIDs)
        try validateTasks(payload.tasks, eventIDs: eventIDs, placementIDs: placementIDs)
        try validateChecklistItems(
            payload.taskChecklistItems ?? [],
            taskIDs: taskIDs
        )
        try validatePlacements(
            placements,
            tasks: payload.tasks,
            taskIDs: taskIDs
        )

        if var dailyReviews = payload.dailyReviews {
            for index in dailyReviews.indices {
                try validateDayKey(
                    dailyReviews[index].dayKey,
                    field: "dailyReviews[\(index)].dayKey"
                )
                if let imageFileNames = dailyReviews[index].imageFileNames {
                    dailyReviews[index].imageFileNames = try imageFileNames.map {
                        try validatedAttachmentName($0)
                    }
                }
            }
            payload.dailyReviews = dailyReviews
        }

        if var diaryBlocks = payload.diaryBlocks {
            for index in diaryBlocks.indices {
                let block = diaryBlocks[index]
                let field = "diaryBlocks[\(index)]"
                guard let type = DiaryBlockType(rawValue: block.type) else {
                    throw BackupServiceError.invalidEnum(field: "\(field).type", value: block.type)
                }
                try validateDayKey(block.dayKey, field: "\(field).dayKey")
                try validateFinite(block.order, field: "\(field).order")
                guard reviewIDs.contains(block.reviewId) else {
                    throw BackupServiceError.danglingReference(
                        field: "\(field).reviewId",
                        id: block.reviewId
                    )
                }
                if let review = reviews.first(where: { $0.id == block.reviewId }),
                   review.dayKey != block.dayKey {
                    throw BackupServiceError.inconsistentDayKey(
                        field: "\(field).dayKey",
                        expected: review.dayKey,
                        actual: block.dayKey
                    )
                }

                switch (type, block.imageFileName) {
                case (.image, .some(let fileName)):
                    diaryBlocks[index].imageFileName = try validatedAttachmentName(fileName)
                case (.image, .none):
                    throw BackupServiceError.invalidValue(
                        field: "\(field).imageFileName",
                        value: "nil"
                    )
                case (.text, .some):
                    throw BackupServiceError.invalidValue(
                        field: "\(field).imageFileName",
                        value: "text block contains an image"
                    )
                case (.text, .none):
                    break
                }
            }
            payload.diaryBlocks = diaryBlocks
        }

        for (index, memo) in (payload.memos ?? []).enumerated() {
            let field = "memos[\(index)]"
            try validateDate(memo.createdAt, field: "\(field).createdAt")
            try validateDate(memo.updatedAt, field: "\(field).updatedAt")
            guard memo.createdAt <= memo.updatedAt else {
                throw BackupServiceError.invalidValue(
                    field: "\(field).updatedAt",
                    value: "before createdAt"
                )
            }
        }

        return payload
    }

    static func validateEvents(_ events: [CalendarEventDTO]) throws {
        for (index, event) in events.enumerated() {
            let field = "calendarEvents[\(index)]"
            try validateDayKey(event.startDayKey, field: "\(field).startDayKey")
            try validateDayKey(event.endDayKey, field: "\(field).endDayKey")
            guard event.startDayKey <= event.endDayKey else {
                throw BackupServiceError.invalidValue(
                    field: "\(field).endDayKey",
                    value: "before startDayKey"
                )
            }
            if let color = event.color, CalendarEventColor(rawValue: color) == nil {
                throw BackupServiceError.invalidEnum(field: "\(field).color", value: color)
            }
            guard event.startAt <= event.endAt else {
                throw BackupServiceError.invalidValue(
                    field: "\(field).endAt",
                    value: "before startAt"
                )
            }
        }
    }

    static func validateTemplates(
        _ items: [TaskTemplateItemDTO],
        templateIDs: Set<UUID>
    ) throws {
        for (index, item) in items.enumerated() {
            let field = "taskTemplateItems[\(index)]"
            guard templateIDs.contains(item.templateId) else {
                throw BackupServiceError.danglingReference(
                    field: "\(field).templateId",
                    id: item.templateId
                )
            }
            try validatePriority(item.priority, field: "\(field).priority")
            try validateEstimatedMinutes(item.estimatedMinutes, field: "\(field).estimatedMinutes")
            try validateFinite(item.order, field: "\(field).order")
            for (titleIndex, title) in (item.checklistTitles ?? []).enumerated() {
                try validateNonBlank(
                    title,
                    field: "\(field).checklistTitles[\(titleIndex)]"
                )
            }
        }
    }

    static func validateChecklistItems(
        _ items: [TaskChecklistItemDTO],
        taskIDs: Set<UUID>
    ) throws {
        for (index, item) in items.enumerated() {
            let field = "taskChecklistItems[\(index)]"
            guard taskIDs.contains(item.taskId) else {
                throw BackupServiceError.danglingReference(
                    field: "\(field).taskId",
                    id: item.taskId
                )
            }
            try validateNonBlank(item.title, field: "\(field).title")
            try validateFinite(item.order, field: "\(field).order")
            try validateOptionalDate(item.completedAt, field: "\(field).completedAt")
            guard item.isCompleted == (item.completedAt != nil) else {
                throw BackupServiceError.invalidValue(
                    field: "\(field).completedAt",
                    value: "completion state mismatch"
                )
            }
        }
    }

    static func validateTasks(
        _ tasks: [TaskDTO],
        eventIDs: Set<UUID>,
        placementIDs: Set<UUID>
    ) throws {
        for (index, task) in tasks.enumerated() {
            let field = "tasks[\(index)]"
            guard TaskStatus(rawValue: task.status) != nil else {
                throw BackupServiceError.invalidEnum(field: "\(field).status", value: task.status)
            }
            try validatePriority(task.priority, field: "\(field).priority")
            try validateEstimatedMinutes(task.estimatedMinutes, field: "\(field).estimatedMinutes")
            try validateOptionalDate(task.reminderAt, field: "\(field).reminderAt")
            try validateFinite(task.order, field: "\(field).order")
            try validateDayKey(task.plannedDayKey, field: "\(field).plannedDayKey")
            if let completedDayKey = task.completedDayKey {
                try validateDayKey(completedDayKey, field: "\(field).completedDayKey")
            }
            if let archivedDayKey = task.archivedDayKey {
                try validateDayKey(archivedDayKey, field: "\(field).archivedDayKey")
            }
            if let eventID = task.eventId, !eventIDs.contains(eventID) {
                throw BackupServiceError.danglingReference(
                    field: "\(field).eventId",
                    id: eventID
                )
            }
            if let placementID = task.templatePlacementId, !placementIDs.contains(placementID) {
                throw BackupServiceError.danglingReference(
                    field: "\(field).templatePlacementId",
                    id: placementID
                )
            }
        }
    }

    static func validatePlacements(
        _ placements: [TemplatePlacementDTO],
        tasks: [TaskDTO],
        taskIDs: Set<UUID>
    ) throws {
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let placementsByID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })

        for (index, placement) in placements.enumerated() {
            let field = "templatePlacements[\(index)]"
            try validateDayKey(placement.dayKey, field: "\(field).dayKey")
            // Source templates may be deleted while placements remain as history.
            _ = try uniqueReferences(placement.taskIds, field: "\(field).taskIds")

            for taskID in placement.taskIds {
                guard taskIDs.contains(taskID), let task = tasksByID[taskID] else {
                    throw BackupServiceError.danglingReference(
                        field: "\(field).taskIds",
                        id: taskID
                    )
                }
                guard task.templatePlacementId == placement.id else {
                    throw BackupServiceError.inconsistentReference(
                        "placement=\(placement.id), task=\(taskID)"
                    )
                }
            }
        }

        for task in tasks {
            guard let placementID = task.templatePlacementId,
                  let placement = placementsByID[placementID] else { continue }
            guard placement.taskIds.contains(task.id) else {
                throw BackupServiceError.inconsistentReference(
                    "task=\(task.id), placement=\(placementID)"
                )
            }
        }
    }

    static func validatedAttachmentName(_ fileName: String) throws -> String {
        _ = try DiaryImageFileStore.validateAttachmentFileName(fileName)
        return fileName
    }

    static func uniqueIDs(_ ids: [UUID], recordType: String) throws -> Set<UUID> {
        var uniqueIDs: Set<UUID> = []
        for id in ids where !uniqueIDs.insert(id).inserted {
            throw BackupServiceError.duplicateIdentifier(recordType: recordType, id: id)
        }
        return uniqueIDs
    }

    static func uniqueReferences(_ ids: [UUID], field: String) throws -> Set<UUID> {
        var uniqueIDs: Set<UUID> = []
        for id in ids where !uniqueIDs.insert(id).inserted {
            throw BackupServiceError.duplicateReference(field: field, id: id)
        }
        return uniqueIDs
    }

    static func validateDayKey(_ dayKey: String, field: String) throws {
        guard let date = DayKey.date(from: dayKey), DayKey.key(for: date) == dayKey else {
            throw BackupServiceError.invalidDayKey(field: field, value: dayKey)
        }
    }

    static func validatePriority(_ priority: String?, field: String) throws {
        guard let priority else { return }
        guard TaskPriority(rawValue: priority) != nil else {
            throw BackupServiceError.invalidEnum(field: field, value: priority)
        }
    }

    static func validateEstimatedMinutes(_ minutes: Int?, field: String) throws {
        guard let minutes else { return }
        guard minutes >= 0 else {
            throw BackupServiceError.invalidValue(field: field, value: String(minutes))
        }
    }

    static func validateFinite(_ value: Double, field: String) throws {
        guard value.isFinite else {
            throw BackupServiceError.invalidValue(field: field, value: String(value))
        }
    }

    static func validateNonBlank(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackupServiceError.invalidValue(field: field, value: "blank")
        }
    }

    static func validateOptionalDate(_ value: Date?, field: String) throws {
        guard let value else { return }
        guard value.timeIntervalSinceReferenceDate.isFinite else {
            throw BackupServiceError.invalidValue(field: field, value: String(describing: value))
        }
    }

    static func validateDate(_ value: Date, field: String) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else {
            throw BackupServiceError.invalidValue(field: field, value: String(describing: value))
        }
    }
}
