import Foundation
import SwiftData

public enum DataIntegrityService {
    public struct Report: Equatable, Sendable {
        public fileprivate(set) var mergedRecords: Int
        public fileprivate(set) var normalizedFields: Int
        public fileprivate(set) var rewiredReferences: Int
        public fileprivate(set) var supersededRecords: Int

        public init(
            mergedRecords: Int = 0,
            normalizedFields: Int = 0,
            rewiredReferences: Int = 0,
            supersededRecords: Int = 0
        ) {
            self.mergedRecords = mergedRecords
            self.normalizedFields = normalizedFields
            self.rewiredReferences = rewiredReferences
            self.supersededRecords = supersededRecords
        }

        public static let noChanges = Report()

        public var hasChanges: Bool {
            mergedRecords > 0 ||
                normalizedFields > 0 ||
                rewiredReferences > 0 ||
                supersededRecords > 0
        }
    }

    @MainActor
    @discardableResult
    public static func reconcile(
        context: ModelContext,
        saveChanges: Bool = true
    ) throws -> Report {
        let events = try context.fetch(FetchDescriptor<CalendarEvent>())
        let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
        let templateItems = try context.fetch(FetchDescriptor<TaskTemplateItem>())
        let placements = try context.fetch(FetchDescriptor<TemplatePlacement>())
        let tasks = try context.fetch(FetchDescriptor<Task>())
        let checklistItems = try context.fetch(FetchDescriptor<TaskChecklistItem>())
        let reviews = try context.fetch(FetchDescriptor<DailyReview>())
        let diaryBlocks = try context.fetch(FetchDescriptor<DiaryBlock>())
        let diaryAttachments = try context.fetch(FetchDescriptor<DiaryAttachment>())

        var report = Report()

        _ = mergeActive(
            events,
            groupedBy: { $0.id },
            report: &report
        )
        _ = mergeActive(
            templates,
            groupedBy: { $0.id },
            report: &report
        )
        _ = mergeActive(
            templateItems,
            groupedBy: { $0.id },
            report: &report
        )
        _ = mergeActive(
            placements,
            groupedBy: { $0.id },
            report: &report
        )
        _ = mergeActive(
            tasks,
            groupedBy: { $0.id },
            report: &report
        )
        _ = mergeActive(
            checklistItems,
            groupedBy: { $0.id },
            report: &report
        )
        _ = mergeActive(
            reviews,
            groupedBy: { $0.id },
            report: &report,
            mergingSupplemental: mergeReviewLegacyFileNames
        )
        _ = mergeActive(
            diaryBlocks,
            groupedBy: { $0.id },
            report: &report
        )
        _ = mergeActive(
            diaryAttachments,
            groupedBy: { $0.id },
            report: &report
        )

        normalizeActive(events, with: normalizeEvent, report: &report)
        normalizeActive(templates, with: normalizeTemplate, report: &report)
        normalizeActive(templateItems, with: normalizeTemplateItem, report: &report)
        normalizeActive(placements, with: normalizePlacement, report: &report)
        normalizeActive(tasks, with: normalizeTask, report: &report)
        normalizeActive(checklistItems, with: normalizeChecklistItem, report: &report)
        normalizeActive(reviews, with: normalizeReview, report: &report)
        normalizeActive(diaryBlocks, with: normalizeDiaryBlock, report: &report)
        normalizeActive(diaryAttachments, with: normalizeDiaryAttachment, report: &report)

        let templateRewrites = mergeActive(
            templates,
            groupedBy: { normalizedNaturalKey($0.seedKey) },
            report: &report
        )
        reconcileTemplateReferences(
            templates: templates,
            items: templateItems,
            placements: placements,
            directRewrites: templateRewrites,
            report: &report
        )

        let activeTemplateIDs = Set(
            templates.lazy.filter(isActive).map(\.id)
        )
        for item in templateItems where isActive(item) {
            guard activeTemplateIDs.contains(item.templateId), !isBlank(item.title) else {
                supersede(item, report: &report)
                continue
            }
        }

        _ = mergeActive(
            templateItems,
            groupedBy: { item -> SeededItemKey? in
                guard let seedKey = normalizedNaturalKey(item.seedKey) else { return nil }
                return SeededItemKey(templateID: item.templateId, seedKey: seedKey)
            },
            report: &report
        )

        let reviewRewrites = mergeActive(
            reviews,
            groupedBy: { validDayKey($0.dayKey) },
            report: &report,
            mergingSupplemental: mergeReviewLegacyFileNames
        )
        reconcileDiaryBlockReferences(
            reviews: reviews,
            blocks: diaryBlocks,
            attachments: diaryAttachments,
            directRewrites: reviewRewrites,
            report: &report
        )

        reconcileTaskReferences(
            events: events,
            placements: placements,
            tasks: tasks,
            report: &report
        )
        reconcileChecklistReferences(
            tasks: tasks,
            items: checklistItems,
            report: &report
        )

        if report.hasChanges && saveChanges {
            try context.save()
        }
        return report
    }

    @MainActor
    @discardableResult
    public static func reconcileCalendarEvents(
        logicalID: UUID,
        context: ModelContext,
        saveChanges: Bool = true
    ) throws -> Report {
        let targetID = logicalID
        let events = try context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate<CalendarEvent> { event in
                event.id == targetID
            }
        ))
        var report = Report()
        _ = mergeActive(
            events,
            groupedBy: { $0.id },
            report: &report
        )
        normalizeActive(events, with: normalizeEvent, report: &report)
        if report.hasChanges && saveChanges {
            try context.save()
        }
        return report
    }
}

private extension DataIntegrityService {
    struct SeededItemKey: Hashable {
        let templateID: UUID
        let seedKey: String
    }

    static let fallbackTimestamp = Date(timeIntervalSince1970: 0)

    @MainActor
    static func mergeActive<Record: IntegrityRecord, Key: Hashable>(
        _ records: [Record],
        groupedBy key: (Record) -> Key?,
        report: inout Report,
        mergingSupplemental: (Record, Record) -> Void = { _, _ in }
    ) -> [UUID: UUID] {
        var groups: [Key: [Record]] = [:]
        for record in records where isActive(record) {
            guard let recordKey = key(record) else { continue }
            groups[recordKey, default: []].append(record)
        }

        let duplicateGroups = groups.values
            .filter { $0.count > 1 }
            .sorted { minimumInstanceID(in: $0) < minimumInstanceID(in: $1) }
        var rewrites: [UUID: UUID] = [:]

        for group in duplicateGroups {
            let ordered = group.sorted { uuidPrecedes($0.instanceID, $1.instanceID) }
            guard var winner = ordered.first else { continue }
            for candidate in ordered.dropFirst() where scalarPrecedes(winner, candidate) {
                winner = candidate
            }

            if let earliestCreatedAt = earliestValidTimestamp(in: ordered) {
                _ = assign(&winner.createdAt, earliestCreatedAt)
            }

            for loser in ordered where loser !== winner {
                mergingSupplemental(loser, winner)
                loser.supersededAt = winner.updatedAt
                report.mergedRecords += 1
                report.supersededRecords += 1
                if loser.id != winner.id {
                    rewrites[loser.id] = winner.id
                }
            }
        }
        return rewrites
    }

    @MainActor
    static func normalizeActive<Record: IntegrityRecord>(
        _ records: [Record],
        with normalize: (Record) -> Int,
        report: inout Report
    ) {
        for record in records where isActive(record) {
            report.normalizedFields += normalize(record)
        }
    }

    static func minimumInstanceID<Record: IntegrityRecord>(in records: [Record]) -> String {
        records.map { $0.instanceID.uuidString }.min() ?? ""
    }

    static func scalarPrecedes<Record: IntegrityRecord>(_ lhs: Record, _ rhs: Record) -> Bool {
        let lhsTimestamp = lhs.updatedAt.timeIntervalSinceReferenceDate
        let rhsTimestamp = rhs.updatedAt.timeIntervalSinceReferenceDate
        if lhsTimestamp.isFinite != rhsTimestamp.isFinite {
            return !lhsTimestamp.isFinite
        }
        if lhsTimestamp.isFinite, lhsTimestamp != rhsTimestamp {
            return lhsTimestamp < rhsTimestamp
        }
        if !lhsTimestamp.isFinite, lhsTimestamp.bitPattern != rhsTimestamp.bitPattern {
            return lhsTimestamp.bitPattern < rhsTimestamp.bitPattern
        }
        return uuidPrecedes(lhs.instanceID, rhs.instanceID)
    }

    static func earliestValidTimestamp<Record: IntegrityRecord>(in records: [Record]) -> Date? {
        records.lazy.map(\.createdAt).filter(isFinite).min()
    }

    static func uuidPrecedes(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    static func isActive<Record: IntegrityRecord>(_ record: Record) -> Bool {
        record.supersededAt == nil
    }

    @MainActor
    static func supersede<Record: IntegrityRecord>(_ record: Record, report: inout Report) {
        guard record.supersededAt == nil else { return }
        record.supersededAt = record.updatedAt
        report.supersededRecords += 1
    }
}

private extension DataIntegrityService {
    @MainActor
    static func reconcileTemplateReferences(
        templates: [TaskTemplate],
        items: [TaskTemplateItem],
        placements: [TemplatePlacement],
        directRewrites: [UUID: UUID],
        report: inout Report
    ) {
        let activeTemplates = templates.filter(isActive)
        let activeTemplateIDs = Set(activeTemplates.map(\.id))
        let canonicalBySeedKey = Dictionary(
            uniqueKeysWithValues: activeTemplates.compactMap { template in
                normalizedNaturalKey(template.seedKey).map { ($0, template.id) }
            }
        )
        var rewrites = directRewrites

        for template in templates.sorted(by: { uuidPrecedes($0.instanceID, $1.instanceID) }) {
            guard !activeTemplateIDs.contains(template.id),
                  let seedKey = normalizedNaturalKey(template.seedKey),
                  let canonicalID = canonicalBySeedKey[seedKey] else { continue }
            rewrites[template.id] = rewrites[template.id] ?? canonicalID
        }

        for item in items where isActive(item) {
            guard let canonicalID = rewrites[item.templateId],
                  canonicalID != item.templateId else { continue }
            item.templateId = canonicalID
            report.rewiredReferences += 1
        }

        for placement in placements where isActive(placement) {
            if let sourceID = placement.sourceTemplateId,
               let canonicalID = rewrites[sourceID],
               canonicalID != sourceID {
                placement.sourceTemplateId = canonicalID
                report.rewiredReferences += 1
            }

            if let sourceID = placement.sourceTemplateId,
               !activeTemplateIDs.contains(sourceID) {
                placement.sourceTemplateId = nil
                report.rewiredReferences += 1
            }

            if !placement.taskIds.isEmpty {
                placement.taskIds = []
                report.normalizedFields += 1
            }
        }
    }

    @MainActor
    static func reconcileDiaryBlockReferences(
        reviews: [DailyReview],
        blocks: [DiaryBlock],
        attachments: [DiaryAttachment],
        directRewrites: [UUID: UUID],
        report: inout Report
    ) {
        let activeReviews = reviews.filter(isActive)
        let activeReviewIDs = Set(activeReviews.map(\.id))
        let activeReviewsByID = activeReviews.reduce(into: [UUID: DailyReview]()) {
            $0[$1.id] = $0[$1.id] ?? $1
        }
        let canonicalByDayKey = activeReviews.reduce(into: [String: UUID]()) {
            guard let dayKey = validDayKey($1.dayKey) else { return }
            $0[dayKey] = $0[dayKey] ?? $1.id
        }
        var rewrites = directRewrites

        for review in reviews.sorted(by: { uuidPrecedes($0.instanceID, $1.instanceID) }) {
            guard !activeReviewIDs.contains(review.id),
                  let dayKey = validDayKey(review.dayKey),
                  let canonicalID = canonicalByDayKey[dayKey] else { continue }
            rewrites[review.id] = rewrites[review.id] ?? canonicalID
        }

        for block in blocks where isActive(block) {
            if let canonicalID = rewrites[block.reviewId], canonicalID != block.reviewId {
                block.reviewId = canonicalID
                report.rewiredReferences += 1
            }

            guard let review = activeReviewsByID[block.reviewId] else {
                supersede(block, report: &report)
                continue
            }

            if block.dayKey != review.dayKey {
                block.dayKey = review.dayKey
                report.rewiredReferences += 1
            }

            if isBlankDiaryBlock(block) {
                supersede(block, report: &report)
            }
        }

        for attachment in attachments where isActive(attachment) {
            if let canonicalID = rewrites[attachment.reviewId],
               canonicalID != attachment.reviewId {
                attachment.reviewId = canonicalID
                report.rewiredReferences += 1
            }

            guard activeReviewIDs.contains(attachment.reviewId),
                  (try? DiaryAttachmentService.inspect(attachment.data)) != nil else {
                supersede(attachment, report: &report)
                continue
            }
        }

        let attachmentsByReview = Dictionary(
            grouping: attachments.filter(isActive),
            by: \.reviewId
        )
        for reviewAttachments in attachmentsByReview.values {
            let ordered = reviewAttachments.sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return uuidPrecedes($0.instanceID, $1.instanceID)
            }
            for (index, attachment) in ordered.enumerated() {
                let normalizedOrder = Double(index) * 100
                if attachment.order != normalizedOrder {
                    attachment.order = normalizedOrder
                    report.normalizedFields += 1
                }
            }
        }
    }

    @MainActor
    static func reconcileTaskReferences(
        events: [CalendarEvent],
        placements: [TemplatePlacement],
        tasks: [Task],
        report: inout Report
    ) {
        let activeEventIDs = Set(events.lazy.filter(isActive).map(\.id))
        let activePlacementIDs = Set(placements.lazy.filter(isActive).map(\.id))

        for task in tasks where isActive(task) {
            if let eventID = task.eventId, !activeEventIDs.contains(eventID) {
                task.eventId = nil
                report.rewiredReferences += 1
            }
            if let placementID = task.templatePlacementId,
               !activePlacementIDs.contains(placementID) {
                task.templatePlacementId = nil
                report.rewiredReferences += 1
            }
        }
    }

    @MainActor
    static func reconcileChecklistReferences(
        tasks: [Task],
        items: [TaskChecklistItem],
        report: inout Report
    ) {
        let activeTaskIDs = Set(tasks.lazy.filter(isActive).map(\.id))

        for item in items where isActive(item) {
            guard activeTaskIDs.contains(item.taskId), !isBlank(item.title) else {
                supersede(item, report: &report)
                continue
            }
        }

        let itemsByTask = Dictionary(
            grouping: items.filter(isActive),
            by: \.taskId
        )
        for taskItems in itemsByTask.values {
            let ordered = taskItems.sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return uuidPrecedes($0.instanceID, $1.instanceID)
            }
            for (index, item) in ordered.enumerated() {
                let normalizedOrder = Double(index + 1) * 100
                if item.order != normalizedOrder {
                    item.order = normalizedOrder
                    report.normalizedFields += 1
                }
            }
        }
    }
}

private extension DataIntegrityService {
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
        let reminderAt = status == .done
            ? nil
            : TaskReminderRules.normalizedDate(task.reminderAt)
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

private extension DataIntegrityService {
    @MainActor
    static func mergeReviewLegacyFileNames(from source: DailyReview, to target: DailyReview) {
        _ = assign(
            &target.imageFileNames,
            mergedLegacyFileNames(target.imageFileNames, source.imageFileNames)
        )
    }
}

private extension DataIntegrityService {
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

private protocol IntegrityRecord: AnyObject {
    var id: UUID { get set }
    var instanceID: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var supersededAt: Date? { get set }
}

extension EasyTaskSchemaV3.CalendarEvent: IntegrityRecord {}
extension EasyTaskSchemaV3.TaskTemplate: IntegrityRecord {}
extension EasyTaskSchemaV3.TaskTemplateItem: IntegrityRecord {}
extension EasyTaskSchemaV3.TemplatePlacement: IntegrityRecord {}
extension EasyTaskSchemaV3.Task: IntegrityRecord {}
extension EasyTaskSchemaV3.DailyReview: IntegrityRecord {}
extension EasyTaskSchemaV3.DiaryBlock: IntegrityRecord {}
extension EasyTaskSchemaV3.DiaryAttachment: IntegrityRecord {}
extension EasyTaskSchemaV4.CalendarEvent: IntegrityRecord {}
extension EasyTaskSchemaV4.TaskTemplate: IntegrityRecord {}
extension EasyTaskSchemaV4.TaskTemplateItem: IntegrityRecord {}
extension EasyTaskSchemaV4.TemplatePlacement: IntegrityRecord {}
extension EasyTaskSchemaV4.Task: IntegrityRecord {}
extension EasyTaskSchemaV4.DailyReview: IntegrityRecord {}
extension EasyTaskSchemaV4.DiaryBlock: IntegrityRecord {}
extension EasyTaskSchemaV4.DiaryAttachment: IntegrityRecord {}
extension EasyTaskSchemaV5.CalendarEvent: IntegrityRecord {}
extension EasyTaskSchemaV5.TaskTemplate: IntegrityRecord {}
extension EasyTaskSchemaV5.TaskTemplateItem: IntegrityRecord {}
extension EasyTaskSchemaV5.TemplatePlacement: IntegrityRecord {}
extension EasyTaskSchemaV5.Task: IntegrityRecord {}
extension EasyTaskSchemaV5.TaskChecklistItem: IntegrityRecord {}
extension EasyTaskSchemaV5.DailyReview: IntegrityRecord {}
extension EasyTaskSchemaV5.DiaryBlock: IntegrityRecord {}
extension EasyTaskSchemaV5.DiaryAttachment: IntegrityRecord {}
