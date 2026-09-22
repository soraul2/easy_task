import Foundation
import SwiftData

/// A short-lived view of parents for one child merge stage. Create a new lookup
/// after each parent merge or reconciliation; never retain it across a restore.
/// Loading is lazy so untouched parent tables are neither fetched nor indexed.
@MainActor
final class BackupPackageParentLookup {
    private let context: ModelContext
    private var templateIDs: [UUID: UUID]?
    private var taskIDs: Set<UUID>?
    private var reviews: [UUID: DailyReview]?
    private var eventIDs: Set<UUID>?
    private var placementIDs: Set<UUID>?

    init(context: ModelContext) {
        self.context = context
    }

    func templateID(for sourceID: UUID?) throws -> UUID? {
        guard let sourceID else { return nil }
        if templateIDs == nil {
            let records = try context.fetch(FetchDescriptor<TaskTemplate>())
            templateIDs = Self.templateIndex(records)
        }
        return templateIDs?[sourceID]
    }

    // Preserve the input fetch order for first-active selection; unordered
    // SwiftData fetches are not assumed to have a stable order across calls.
    static func templateIndex(_ records: [TaskTemplate]) -> [UUID: UUID] {
        var resolved: [UUID: UUID] = [:]
        var latestByID: [UUID: TaskTemplate] = [:]
        var firstActiveBySeed: [String: UUID] = [:]
        for record in records {
            if record.supersededAt == nil {
                resolved[record.id] = record.id
                if let key = BackupPackageCodec.normalizedNaturalKey(record.seedKey),
                   firstActiveBySeed[key] == nil {
                    firstActiveBySeed[key] = record.id
                }
            }
            if let previous = latestByID[record.id],
               !BackupPackageCodec.mergeRecordPrecedes(
                   lhsUpdatedAt: previous.updatedAt, lhsInstanceID: previous.instanceID,
                   rhsUpdatedAt: record.updatedAt, rhsInstanceID: record.instanceID
               ) { continue }
            latestByID[record.id] = record
        }
        for (id, record) in latestByID where resolved[id] == nil {
            if let key = BackupPackageCodec.normalizedNaturalKey(record.seedKey) {
                resolved[id] = firstActiveBySeed[key]
            }
        }
        return resolved
    }

    func taskID(for sourceID: UUID) throws -> UUID? {
        if taskIDs == nil {
            taskIDs = Set(try context.fetch(FetchDescriptor<Task>())
                .filter { $0.supersededAt == nil }.map(\.id))
        }
        return taskIDs?.contains(sourceID) == true ? sourceID : nil
    }

    func review(for sourceID: UUID) throws -> DailyReview? {
        if reviews == nil {
            let records = try context.fetch(FetchDescriptor<DailyReview>())
            reviews = Self.reviewIndex(records)
        }
        return reviews?[sourceID]
    }

    // Preserve the input fetch order for first-active selection; unordered
    // SwiftData fetches are not assumed to have a stable order across calls.
    static func reviewIndex(_ records: [DailyReview]) -> [UUID: DailyReview] {
        var resolved: [UUID: DailyReview] = [:]
        var latestByID: [UUID: DailyReview] = [:]
        var firstActiveByDay: [String: DailyReview] = [:]
        for record in records {
            if record.supersededAt == nil {
                if resolved[record.id] == nil { resolved[record.id] = record }
                if firstActiveByDay[record.dayKey] == nil {
                    firstActiveByDay[record.dayKey] = record
                }
            }
            if let previous = latestByID[record.id],
               !BackupPackageCodec.mergeRecordPrecedes(
                   lhsUpdatedAt: previous.updatedAt, lhsInstanceID: previous.instanceID,
                   rhsUpdatedAt: record.updatedAt, rhsInstanceID: record.instanceID
               ) { continue }
            latestByID[record.id] = record
        }
        for (id, record) in latestByID where resolved[id] == nil {
            resolved[id] = firstActiveByDay[record.dayKey]
        }
        return resolved
    }

    func eventID(for sourceID: UUID?) throws -> UUID? {
        guard let sourceID else { return nil }
        if eventIDs == nil {
            eventIDs = Set(try context.fetch(FetchDescriptor<CalendarEvent>())
                .filter { $0.supersededAt == nil }.map(\.id))
        }
        return eventIDs?.contains(sourceID) == true ? sourceID : nil
    }

    func placementID(for sourceID: UUID?) throws -> UUID? {
        guard let sourceID else { return nil }
        if placementIDs == nil {
            placementIDs = Set(try context.fetch(FetchDescriptor<TemplatePlacement>())
                .filter { $0.supersededAt == nil }.map(\.id))
        }
        return placementIDs?.contains(sourceID) == true ? sourceID : nil
    }
}
