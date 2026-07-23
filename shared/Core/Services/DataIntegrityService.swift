import Foundation
import SwiftData

public enum DataIntegrityService {
    public struct Report: Equatable, Sendable {
        public internal(set) var mergedRecords: Int
        public internal(set) var normalizedFields: Int
        public internal(set) var rewiredReferences: Int
        public internal(set) var supersededRecords: Int

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
        let memos = try context.fetch(FetchDescriptor<Memo>())

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
        _ = mergeActive(
            memos,
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
        normalizeActive(memos, with: normalizeMemo, report: &report)

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
