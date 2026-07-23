import Foundation

extension DataIntegrityService {
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

extension DataIntegrityService {
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
