import Foundation
import SwiftData

public struct BackupPayload: Codable {
    public var backupVersion: Int
    public var exportedAt: Date
    public var tasks: [TaskDTO]
    public var taskChecklistItems: [TaskChecklistItemDTO]? = nil
    public var calendarEvents: [CalendarEventDTO]
    public var taskTemplates: [TaskTemplateDTO]
    public var taskTemplateItems: [TaskTemplateItemDTO]
    public var templatePlacements: [TemplatePlacementDTO]?
    public var dailyReviews: [DailyReviewDTO]?
    public var diaryBlocks: [DiaryBlockDTO]?
}

public struct TaskDTO: Codable {
    public var id: UUID
    public var title: String
    public var note: String?
    public var status: String
    public var plannedAt: Date
    public var plannedDayKey: String
    public var order: Double
    public var eventId: UUID?
    public var templatePlacementId: UUID?
    public var priority: String?
    public var tags: [String]
    public var estimatedMinutes: Int?
    public var reminderAt: Date? = nil
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var completedDayKey: String?
    public var archivedAt: Date?
    public var archivedDayKey: String?
    public var instanceID: UUID? = nil
}

public struct TaskChecklistItemDTO: Codable {
    public var id: UUID
    public var taskId: UUID
    public var title: String
    public var isCompleted: Bool
    public var order: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var instanceID: UUID? = nil
}

public struct CalendarEventDTO: Codable {
    public var id: UUID
    public var title: String
    public var startAt: Date
    public var endAt: Date
    public var startDayKey: String
    public var endDayKey: String
    public var note: String?
    public var color: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var instanceID: UUID? = nil
}

public struct TaskTemplateDTO: Codable {
    public var id: UUID
    public var name: String
    public var isFavorite: Bool?
    public var createdAt: Date
    public var updatedAt: Date
    public var instanceID: UUID? = nil
    public var seedKey: String? = nil
}

public struct TaskTemplateItemDTO: Codable {
    public var id: UUID
    public var templateId: UUID
    public var title: String
    public var note: String?
    public var priority: String?
    public var tags: [String]
    public var estimatedMinutes: Int?
    public var checklistTitles: [String]? = nil
    public var order: Double
    public var instanceID: UUID? = nil
    public var seedKey: String? = nil
    public var createdAt: Date? = nil
    public var updatedAt: Date? = nil
}

public struct TemplatePlacementDTO: Codable {
    public var id: UUID
    public var sourceTemplateId: UUID?
    public var templateName: String
    public var dayKey: String
    public var taskIds: [UUID]
    public var createdAt: Date
    public var updatedAt: Date
    public var instanceID: UUID? = nil
}

public struct DailyReviewDTO: Codable {
    public var id: UUID
    public var dayKey: String
    public var title: String?
    public var weather: String?
    public var mood: String?
    public var content: String
    public var imageFileNames: [String]?
    public var createdAt: Date
    public var updatedAt: Date
    public var instanceID: UUID? = nil
}

public struct DiaryBlockDTO: Codable {
    public var id: UUID
    public var reviewId: UUID
    public var dayKey: String
    public var type: String
    public var text: String
    public var imageFileName: String?
    public var order: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var instanceID: UUID? = nil
}

public enum BackupServiceError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case duplicateIdentifier(recordType: String, id: UUID)
    case duplicateReference(field: String, id: UUID)
    case invalidEnum(field: String, value: String)
    case invalidDayKey(field: String, value: String)
    case inconsistentDayKey(field: String, expected: String, actual: String)
    case danglingReference(field: String, id: UUID)
    case inconsistentReference(String)
    case invalidValue(field: String, value: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "지원하지 않는 백업 버전입니다. version=\(version)"
        case .duplicateIdentifier(let recordType, let id):
            return "백업에 중복 ID가 있습니다. type=\(recordType), id=\(id)"
        case .duplicateReference(let field, let id):
            return "백업 참조 목록에 중복 ID가 있습니다. field=\(field), id=\(id)"
        case .invalidEnum(let field, let value):
            return "백업 enum 값이 올바르지 않습니다. field=\(field), value=\(value)"
        case .invalidDayKey(let field, let value):
            return "백업 날짜 키가 올바르지 않습니다. field=\(field), value=\(value)"
        case .inconsistentDayKey(let field, let expected, let actual):
            return "백업 날짜 키가 원본 날짜와 일치하지 않습니다. field=\(field), expected=\(expected), actual=\(actual)"
        case .danglingReference(let field, let id):
            return "백업에 대상이 없는 참조가 있습니다. field=\(field), id=\(id)"
        case .inconsistentReference(let description):
            return "백업 참조가 서로 일치하지 않습니다. \(description)"
        case .invalidValue(let field, let value):
            return "백업 값이 올바르지 않습니다. field=\(field), value=\(value)"
        }
    }
}

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
                .map(DiaryBlockDTO.init)
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
}

private extension TaskDTO {
    init(task: Task) {
        id = task.id
        title = task.title
        note = task.note
        status = task.status
        plannedAt = task.plannedAt
        plannedDayKey = task.plannedDayKey
        order = task.order
        eventId = task.eventId
        templatePlacementId = task.templatePlacementId
        priority = task.priority
        tags = task.tags
        estimatedMinutes = task.estimatedMinutes
        reminderAt = task.reminderAt
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        completedAt = task.completedAt
        completedDayKey = task.completedDayKey
        archivedAt = task.archivedAt
        archivedDayKey = task.archivedDayKey
        instanceID = task.instanceID
    }
}

private extension TaskChecklistItemDTO {
    init(item: TaskChecklistItem) {
        id = item.id
        taskId = item.taskId
        title = item.title
        isCompleted = item.isCompleted
        order = item.order
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        completedAt = item.completedAt
        instanceID = item.instanceID
    }
}

private extension CalendarEventDTO {
    init(event: CalendarEvent) {
        id = event.id
        title = event.title
        startAt = event.startAt
        endAt = event.endAt
        startDayKey = event.startDayKey
        endDayKey = event.endDayKey
        note = event.note
        color = event.color
        createdAt = event.createdAt
        updatedAt = event.updatedAt
        instanceID = event.instanceID
    }
}

private extension TaskTemplateDTO {
    init(template: TaskTemplate) {
        id = template.id
        name = template.name
        isFavorite = template.isFavorite
        createdAt = template.createdAt
        updatedAt = template.updatedAt
        instanceID = template.instanceID
        seedKey = template.seedKey
    }
}

private extension TaskTemplateItemDTO {
    init(item: TaskTemplateItem) {
        id = item.id
        templateId = item.templateId
        title = item.title
        note = item.note
        priority = item.priority
        tags = item.tags
        estimatedMinutes = item.estimatedMinutes
        checklistTitles = item.checklistTitles
        order = item.order
        instanceID = item.instanceID
        seedKey = item.seedKey
        createdAt = item.createdAt
        updatedAt = item.updatedAt
    }
}

private extension TemplatePlacementDTO {
    init(placement: TemplatePlacement) {
        id = placement.id
        sourceTemplateId = placement.sourceTemplateId
        templateName = placement.templateName
        dayKey = placement.dayKey
        taskIds = []
        createdAt = placement.createdAt
        updatedAt = placement.updatedAt
        instanceID = placement.instanceID
    }
}

private extension DailyReviewDTO {
    init(review: DailyReview) {
        id = review.id
        dayKey = review.dayKey
        title = review.title
        weather = review.weather
        mood = review.mood
        content = review.content
        imageFileNames = review.imageFileNames
        createdAt = review.createdAt
        updatedAt = review.updatedAt
        instanceID = review.instanceID
    }
}

private extension DiaryBlockDTO {
    init(block: DiaryBlock) {
        id = block.id
        reviewId = block.reviewId
        dayKey = block.dayKey
        type = block.type
        text = block.text
        imageFileName = block.imageFileName
        order = block.order
        createdAt = block.createdAt
        updatedAt = block.updatedAt
        instanceID = block.instanceID
    }
}

private extension CalendarEvent {
    convenience init(dto: CalendarEventDTO) {
        self.init(
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
        startDayKey = dto.startDayKey
        endDayKey = dto.endDayKey
    }
}

private extension TaskTemplate {
    convenience init(dto: TaskTemplateDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            seedKey: dto.seedKey,
            name: dto.name,
            isFavorite: dto.isFavorite ?? false,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension TaskTemplateItem {
    convenience init(dto: TaskTemplateItemDTO) {
        self.init(
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
    }
}

private extension TemplatePlacement {
    convenience init(dto: TemplatePlacementDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            sourceTemplateId: dto.sourceTemplateId,
            templateName: dto.templateName,
            dayKey: dto.dayKey,
            taskIds: dto.taskIds,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension Task {
    convenience init(dto: TaskDTO) {
        self.init(
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
            reminderAt: TaskReminderRules.normalizedDate(dto.reminderAt),
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
        plannedDayKey = dto.plannedDayKey
        status = dto.status
        priority = dto.priority
        completedAt = dto.completedAt
        completedDayKey = dto.completedDayKey
        archivedAt = dto.archivedAt
        archivedDayKey = dto.archivedDayKey
    }
}

private extension TaskChecklistItem {
    convenience init(dto: TaskChecklistItemDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            taskId: dto.taskId,
            title: dto.title,
            isCompleted: dto.isCompleted,
            order: dto.order,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            completedAt: dto.completedAt
        )
    }
}

private extension DailyReview {
    convenience init(dto: DailyReviewDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            dayKey: dto.dayKey,
            title: dto.title ?? "",
            weather: dto.weather ?? "",
            mood: dto.mood ?? "",
            content: dto.content,
            imageFileNames: dto.imageFileNames ?? [],
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension DiaryBlock {
    convenience init(dto: DiaryBlockDTO) {
        self.init(
            id: dto.id,
            instanceID: dto.instanceID ?? UUID(),
            reviewId: dto.reviewId,
            dayKey: dto.dayKey,
            type: DiaryBlockType(rawValue: dto.type) ?? .text,
            text: dto.text,
            imageFileName: dto.imageFileName,
            order: dto.order,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}
