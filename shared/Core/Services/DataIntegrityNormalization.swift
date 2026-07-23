import Foundation

extension DataIntegrityService {
    @MainActor
    static func normalizeEvent(_ event: CalendarEvent) -> Int {
        var changes = normalizeTimestamps(event)
        var startAt = isFinite(event.startAt) ? event.startAt : nil
        var endAt = isFinite(event.endAt) ? event.endAt : nil

        if startAt == nil {
            startAt = validDayKey(event.startDayKey).flatMap(DayKey.date(from:)) ?? event.createdAt
        }
        if endAt == nil {
            endAt = validDayKey(event.endDayKey).flatMap(DayKey.date(from:)) ?? event.updatedAt
        }
        if let startAtValue = startAt, let endAtValue = endAt, startAtValue > endAtValue {
            swap(&startAt, &endAt)
        }

        let dateDerivedStartAt = startAt ?? fallbackTimestamp
        let dateDerivedEndAt = endAt ?? dateDerivedStartAt

        var startDayKey = validDayKey(event.startDayKey) ?? DayKey.key(for: dateDerivedStartAt)
        var endDayKey = validDayKey(event.endDayKey) ?? DayKey.key(for: dateDerivedEndAt)
        if startDayKey > endDayKey {
            swap(&startDayKey, &endDayKey)
        }
        let normalizedStartAt = DayKey.date(from: startDayKey) ?? dateDerivedStartAt
        let normalizedEndAt = DayKey.date(from: endDayKey) ?? dateDerivedEndAt
        changes += assign(&event.startAt, normalizedStartAt)
        changes += assign(&event.endAt, normalizedEndAt)
        changes += assign(&event.startDayKey, startDayKey)
        changes += assign(&event.endDayKey, endDayKey)

        let color = normalizedOptionalText(event.color).flatMap {
            CalendarEventColor(rawValue: $0)?.rawValue
        }
        changes += assign(&event.color, color)
        return changes
    }

    @MainActor
    static func normalizeTemplate(_ template: TaskTemplate) -> Int {
        var changes = normalizeTimestamps(template)
        changes += assign(&template.seedKey, normalizedNaturalKey(template.seedKey))
        return changes
    }

    @MainActor
    static func normalizeTemplateItem(_ item: TaskTemplateItem) -> Int {
        var changes = normalizeTimestamps(item)
        changes += assign(&item.seedKey, normalizedNaturalKey(item.seedKey))
        changes += assign(&item.priority, normalizedPriority(item.priority))
        changes += assign(&item.tags, normalizedTags(item.tags))
        changes += assign(
            &item.checklistTitles,
            normalizedChecklistTitles(item.checklistTitles)
        )
        if let estimate = item.estimatedMinutes, estimate < 0 {
            changes += assign(&item.estimatedMinutes, nil)
        }
        if !item.order.isFinite {
            changes += assign(&item.order, 0)
        }
        return changes
    }

    @MainActor
    static func normalizePlacement(_ placement: TemplatePlacement) -> Int {
        var changes = normalizeTimestamps(placement)
        if validDayKey(placement.dayKey) == nil {
            changes += assign(&placement.dayKey, DayKey.key(for: placement.createdAt))
        }
        return changes
    }

    @MainActor
    static func normalizeTask(_ task: Task) -> Int {
        var changes = normalizeTimestamps(task)
        let hasCompletionEvidence = task.completedAt != nil ||
            task.completedDayKey != nil ||
            task.archivedAt != nil ||
            task.archivedDayKey != nil
        let status = TaskStatus(rawValue: task.status) ?? (hasCompletionEvidence ? .done : .todo)
        changes += assign(&task.status, status.rawValue)
        changes += assign(&task.priority, normalizedPriority(task.priority))
        changes += assign(&task.tags, normalizedTags(task.tags))

        if let estimate = task.estimatedMinutes, estimate < 0 {
            changes += assign(&task.estimatedMinutes, nil)
        }
        if !task.order.isFinite {
            changes += assign(&task.order, 0)
        }
        let reminderAt = TaskReminderRules.normalizedDate(task.reminderAt)
        changes += assign(&task.reminderAt, reminderAt)

        let dateDerivedPlannedAt = isFinite(task.plannedAt) ? task.plannedAt : task.createdAt
        let plannedDayKey = validDayKey(task.plannedDayKey)
            ?? DayKey.key(for: dateDerivedPlannedAt)
        let plannedAt = DayKey.date(from: plannedDayKey)
            ?? DayKey.startOfDay(for: dateDerivedPlannedAt)
        changes += assign(&task.plannedAt, plannedAt)
        changes += assign(&task.plannedDayKey, plannedDayKey)

        if status != .done {
            changes += assign(&task.completedAt, nil)
            changes += assign(&task.completedDayKey, nil)
            changes += assign(&task.archivedAt, nil)
            changes += assign(&task.archivedDayKey, nil)
            return changes
        }

        let completedAt = finiteDate(task.completedAt)
            ?? validDayKey(task.completedDayKey ?? "").flatMap(DayKey.date(from:))
            ?? task.updatedAt
        changes += assign(&task.completedAt, completedAt)
        if validDayKey(task.completedDayKey ?? "") == nil {
            changes += assign(&task.completedDayKey, DayKey.key(for: completedAt))
        }

        if task.archivedAt != nil || task.archivedDayKey != nil {
            var archivedAt = finiteDate(task.archivedAt)
                ?? validDayKey(task.archivedDayKey ?? "").flatMap(DayKey.date(from:))
                ?? completedAt
            if archivedAt < completedAt {
                archivedAt = completedAt
            }
            changes += assign(&task.archivedAt, archivedAt)
            if validDayKey(task.archivedDayKey ?? "") == nil {
                changes += assign(&task.archivedDayKey, DayKey.key(for: archivedAt))
            }
        }
        return changes
    }

    @MainActor
    static func normalizeChecklistItem(_ item: TaskChecklistItem) -> Int {
        var changes = normalizeTimestamps(item)
        changes += assign(
            &item.title,
            item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if !item.order.isFinite {
            changes += assign(&item.order, 0)
        }
        let completedAt = item.isCompleted
            ? finiteDate(item.completedAt) ?? item.updatedAt
            : nil
        changes += assign(&item.completedAt, completedAt)
        return changes
    }

    @MainActor
    static func normalizeReview(_ review: DailyReview) -> Int {
        var changes = normalizeTimestamps(review)
        if validDayKey(review.dayKey) == nil {
            changes += assign(&review.dayKey, DayKey.key(for: review.createdAt))
        }
        return changes
    }

    @MainActor
    static func normalizeDiaryBlock(_ block: DiaryBlock) -> Int {
        var changes = normalizeTimestamps(block)
        if validDayKey(block.dayKey) == nil {
            changes += assign(&block.dayKey, DayKey.key(for: block.createdAt))
        }
        if !block.order.isFinite {
            changes += assign(&block.order, 0)
        }

        let imageFileName = normalizedOptionalText(block.imageFileName)
        let type = DiaryBlockType(rawValue: block.type)
            ?? (imageFileName == nil ? .text : .image)
        changes += assign(&block.type, type.rawValue)
        if type == .text {
            changes += assign(&block.imageFileName, nil)
        } else {
            changes += assign(&block.imageFileName, imageFileName)
        }
        return changes
    }

    @MainActor
    static func normalizeDiaryAttachment(_ attachment: DiaryAttachment) -> Int {
        var changes = normalizeTimestamps(attachment)
        if !attachment.order.isFinite {
            changes += assign(&attachment.order, 0)
        }
        changes += assign(
            &attachment.originalFileName,
            normalizedOptionalText(attachment.originalFileName).map { String($0.prefix(255)) }
        )
        if let metadata = try? DiaryAttachmentService.inspect(attachment.data) {
            changes += assign(&attachment.mimeType, metadata.mediaType.rawValue)
            changes += assign(&attachment.byteCount, metadata.byteCount)
            changes += assign(&attachment.sha256, metadata.sha256)
        }
        return changes
    }

    @MainActor
    static func normalizeMemo(_ memo: Memo) -> Int {
        normalizeTimestamps(memo)
    }

    @MainActor
    static func normalizeTimestamps<Record: IntegrityRecord>(_ record: Record) -> Int {
        var createdAt = finiteDate(record.createdAt)
        var updatedAt = finiteDate(record.updatedAt)

        switch (createdAt, updatedAt) {
        case (.none, .none):
            createdAt = fallbackTimestamp
            updatedAt = fallbackTimestamp
        case (.none, .some(let validUpdatedAt)):
            createdAt = validUpdatedAt
        case (.some(let validCreatedAt), .none):
            updatedAt = validCreatedAt
        case (.some(let validCreatedAt), .some(let validUpdatedAt))
            where validCreatedAt > validUpdatedAt:
            createdAt = validUpdatedAt
        default:
            break
        }

        var changes = assign(&record.createdAt, createdAt ?? fallbackTimestamp)
        changes += assign(&record.updatedAt, updatedAt ?? fallbackTimestamp)
        return changes
    }
}

extension DataIntegrityService {
    @MainActor
    static func mergeReviewLegacyFileNames(from source: DailyReview, to target: DailyReview) {
        _ = assign(
            &target.imageFileNames,
            mergedLegacyFileNames(target.imageFileNames, source.imageFileNames)
        )
    }
}

extension DataIntegrityService {
    static func validDayKey(_ value: String) -> String? {
        guard let date = DayKey.date(from: value), DayKey.key(for: date) == value else {
            return nil
        }
        return value
    }

    static func normalizedNaturalKey(_ value: String?) -> String? {
        normalizedOptionalText(value)?.lowercased()
    }

    static func normalizedOptionalText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedPriority(_ value: String?) -> String? {
        guard let value = normalizedOptionalText(value) else { return nil }
        return TaskPriority(rawValue: value)?.rawValue
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    static func normalizedChecklistTitles(_ titles: [String]) -> [String] {
        titles.compactMap { normalizedOptionalText($0) }
    }

    static func mergedLegacyFileNames(_ preferred: [String], _ other: [String]) -> [String] {
        var remainingCounts = Dictionary(grouping: preferred, by: { $0 }).mapValues(\.count)
        var result = preferred
        for fileName in other {
            let count = remainingCounts[fileName, default: 0]
            if count > 0 {
                remainingCounts[fileName] = count - 1
            } else {
                result.append(fileName)
            }
        }
        return result
    }

    static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isBlankDiaryBlock(_ block: DiaryBlock) -> Bool {
        switch DiaryBlockType(rawValue: block.type) ?? .text {
        case .text:
            isBlank(block.text)
        case .image:
            normalizedOptionalText(block.imageFileName) == nil
        }
    }

    static func finiteDate(_ value: Date?) -> Date? {
        guard let value, isFinite(value) else { return nil }
        return value
    }

    static func isFinite(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }

    @MainActor
    @discardableResult
    static func assign<Value: Equatable>(_ target: inout Value, _ value: Value) -> Int {
        guard target != value else { return 0 }
        target = value
        return 1
    }
}
