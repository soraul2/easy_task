import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

// Frozen starting implementation: compare the new stage index with the original
// full-table parent resolution, including fetch order and physical duplicates.
private enum OriginalBackupParentResolution {
    @MainActor
    static func canonicalTemplateID(
        for sourceID: UUID?,
        templates: [TaskTemplate]
    ) -> UUID? {
        guard let sourceID else { return nil }
        if templates.contains(where: { $0.id == sourceID && $0.supersededAt == nil }) {
            return sourceID
        }
        guard let source = templates.filter({ $0.id == sourceID }).max(by: {
            BackupPackageCodec.mergeRecordPrecedes(
                lhsUpdatedAt: $0.updatedAt,
                lhsInstanceID: $0.instanceID,
                rhsUpdatedAt: $1.updatedAt,
                rhsInstanceID: $1.instanceID
            )
        }),
              let seedKey = BackupPackageCodec.normalizedNaturalKey(source.seedKey) else {
            return nil
        }
        return templates.first {
            $0.supersededAt == nil && BackupPackageCodec.normalizedNaturalKey($0.seedKey) == seedKey
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
        reviews: [DailyReview]
    ) -> DailyReview? {
        if let active = reviews.first(where: {
            $0.id == sourceID && $0.supersededAt == nil
        }) {
            return active
        }
        guard let source = reviews.filter({ $0.id == sourceID }).max(by: {
            BackupPackageCodec.mergeRecordPrecedes(
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

}

@Test @MainActor
func backupParentIndexPreservesOriginalDuplicateAndNaturalKeyResolution() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let date = Date(timeIntervalSince1970: 1_785_000_000)
    var templates: [TaskTemplate] = []
    var reviews: [DailyReview] = []
    var tasks: [Task] = []
    var events: [CalendarEvent] = []
    var placements: [TemplatePlacement] = []
    for index in 0..<24 {
        // Three physical parents per logical ID, including all-superseded IDs.
        let id = backupLookupID(index / 3 + 1)
        let instanceID = backupLookupID(index + 100)
        let updatedAt = date.addingTimeInterval(Double(index % 2))
        let supersededAt: Date? = index.isMultiple(of: 3) || index < 3 ? date : nil
        let template = TaskTemplate(id: id, instanceID: instanceID,
            seedKey: index.isMultiple(of: 2) ? "  SEED \(index % 4) " : "seed \(index % 4)",
            name: "루틴 \(index)", createdAt: date, updatedAt: updatedAt,
            supersededAt: supersededAt)
        let review = DailyReview(id: id, instanceID: instanceID,
            dayKey: DayKey.key(for: DayKey.addingDays(index % 4, to: date)),
            content: "회고 \(index)", createdAt: date, updatedAt: updatedAt,
            supersededAt: supersededAt)
        let task = Task(id: id, instanceID: instanceID, title: "작업 \(index)",
            plannedAt: date, order: Double(index), createdAt: date, updatedAt: updatedAt,
            supersededAt: supersededAt)
        let event = CalendarEvent(id: id, instanceID: instanceID, title: "일정 \(index)",
            startAt: date, endAt: date, createdAt: date, updatedAt: updatedAt,
            supersededAt: supersededAt)
        let placement = TemplatePlacement(id: id, instanceID: instanceID,
            sourceTemplateId: template.id, templateName: template.name,
            dayKey: DayKey.key(for: date), createdAt: date, updatedAt: updatedAt,
            supersededAt: supersededAt)
        context.insert(template); context.insert(review); context.insert(task)
        context.insert(event); context.insert(placement)
        templates.append(template); reviews.append(review); tasks.append(task)
        events.append(event); placements.append(placement)
    }
    try context.save()
    for round in 0..<3 {
        if round == 1 {
            // A new stage must see unsaved parent edits/imports from prior stages.
            templates[0].supersededAt = nil
            templates[1].seedKey = "  "
            reviews[0].supersededAt = nil
            reviews[1].dayKey = "2026-01-01"
            tasks[0].supersededAt = nil
            events[0].supersededAt = nil
            placements[0].supersededAt = nil
        } else if round == 2 {
            for record in templates { record.supersededAt = date }
            for record in reviews { record.supersededAt = date }
            for record in tasks { record.supersededAt = date }
            for record in events { record.supersededAt = date }
            for record in placements { record.supersededAt = date }
        }
        let lookup = BackupPackageParentLookup(context: context)
        let templateSnapshot = try context.fetch(FetchDescriptor<TaskTemplate>())
        let reviewSnapshot = try context.fetch(FetchDescriptor<DailyReview>())
        // Separate unsorted SwiftData fetches can choose a different physical
        // first row when pending changes are merged. Compare a fixed snapshot,
        // then reverse it to prove input-order semantics in both directions.
        for reversed in [false, true] {
            let orderedTemplates = reversed ? Array(templateSnapshot.reversed()) : templateSnapshot
            let orderedReviews = reversed ? Array(reviewSnapshot.reversed()) : reviewSnapshot
            let templateIndex = BackupPackageParentLookup.templateIndex(orderedTemplates)
            let reviewIndex = BackupPackageParentLookup.reviewIndex(orderedReviews)
            for sourceID in (1...10).map(backupLookupID) {
                #expect(templateIndex[sourceID] == OriginalBackupParentResolution.canonicalTemplateID(for: sourceID, templates: orderedTemplates))
                #expect(reviewIndex[sourceID]?.instanceID == OriginalBackupParentResolution.canonicalReview(for: sourceID, reviews: orderedReviews)?.instanceID)
            }
        }
        for sourceID in (1...10).map(backupLookupID) {
            #expect(try lookup.taskID(for: sourceID) ==
                OriginalBackupParentResolution.canonicalTaskID(for: sourceID, context: context))
            #expect(try lookup.eventID(for: sourceID) ==
                OriginalBackupParentResolution.canonicalEventID(sourceID, context: context))
            #expect(try lookup.placementID(for: sourceID) ==
                OriginalBackupParentResolution.canonicalPlacementID(sourceID, context: context))
        }
        #expect(try lookup.templateID(for: nil) == nil)
        #expect(try lookup.eventID(for: nil) == nil)
        #expect(try lookup.placementID(for: nil) == nil)
    }
    withExtendedLifetime(container) {}
}

private func backupLookupID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}
