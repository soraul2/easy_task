import CryptoKit
import Foundation
import SwiftData

public enum TaskProgressEventService {
    public static let fetchBatchSize = 100

    @MainActor
    @discardableResult
    public static func recordTransition(
        taskID: UUID,
        from oldStatus: TaskStatus,
        to newStatus: TaskStatus,
        occurredAt: Date,
        in context: ModelContext
    ) -> TaskProgressEvent? {
        guard let kind = TaskProgressEventRules.eventKind(from: oldStatus, to: newStatus) else {
            return nil
        }
        let recordedAt = Date()
        let event = TaskProgressEvent(
            taskId: taskID,
            kind: kind,
            origin: .captured,
            occurredAt: occurredAt,
            createdAt: recordedAt,
            updatedAt: recordedAt
        )
        context.insert(event)
        return event
    }

    @MainActor
    @discardableResult
    public static func recordCompatibilityBoundary(
        taskID: UUID,
        occurredAt: Date,
        in context: ModelContext
    ) throws -> TaskProgressEvent? {
        let eventID = compatibilityBoundaryID(taskID: taskID, occurredAt: occurredAt)
        let descriptor = FetchDescriptor<TaskProgressEvent>(
            predicate: #Predicate<TaskProgressEvent> { event in
                event.id == eventID && event.supersededAt == nil
            }
        )
        guard try context.fetchCount(descriptor) == 0 else { return nil }

        let recordedAt = Date()
        let event = TaskProgressEvent(
            id: eventID,
            taskId: taskID,
            kind: .stopped,
            origin: .compatibilityBoundary,
            occurredAt: occurredAt,
            createdAt: recordedAt,
            updatedAt: recordedAt
        )
        context.insert(event)
        return event
    }

    @MainActor
    public static func events(
        forTaskIDs taskIDs: Set<UUID>,
        in context: ModelContext
    ) throws -> [TaskProgressEvent] {
        guard !taskIDs.isEmpty else { return [] }
        let ids = taskIDs.sorted { $0.uuidString < $1.uuidString }
        var result: [TaskProgressEvent] = []

        for start in stride(from: 0, to: ids.count, by: fetchBatchSize) {
            let end = min(start + fetchBatchSize, ids.count)
            let batch = Array(ids[start..<end])
            let descriptor = FetchDescriptor<TaskProgressEvent>(
                predicate: #Predicate<TaskProgressEvent> { event in
                    batch.contains(event.taskId)
                },
                sortBy: [
                    SortDescriptor(\TaskProgressEvent.occurredAt),
                    SortDescriptor(\TaskProgressEvent.instanceID)
                ]
            )
            result.append(contentsOf: try context.fetch(descriptor))
        }
        return result
    }

    @MainActor
    public static func deleteEvents(
        forTaskID taskID: UUID,
        in context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<TaskProgressEvent>(
            predicate: #Predicate<TaskProgressEvent> { event in
                event.taskId == taskID
            }
        )
        for event in try context.fetch(descriptor) {
            context.delete(event)
        }
    }

    public static func compatibilityBoundaryID(
        taskID: UUID,
        occurredAt: Date
    ) -> UUID {
        let components = [
            taskID.uuidString,
            TaskProgressEventKind.stopped.rawValue,
            TaskProgressEventOrigin.compatibilityBoundary.rawValue,
            String(occurredAt.timeIntervalSinceReferenceDate.bitPattern)
        ]
        var data = Data()
        for component in components {
            let bytes = Data(component.utf8)
            var byteCount = UInt64(bytes.count).bigEndian
            withUnsafeBytes(of: &byteCount) { data.append(contentsOf: $0) }
            data.append(bytes)
        }
        var bytes = Array(SHA256.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

public enum TaskProgressCompatibilityService {
    public struct Report: Equatable, Sendable {
        public var insertedBoundaries: Int

        public init(insertedBoundaries: Int = 0) {
            self.insertedBoundaries = insertedBoundaries
        }
    }

    @MainActor
    @discardableResult
    public static func reconcile(
        tasks: [Task],
        in context: ModelContext
    ) throws -> Report {
        let activeTasks = tasks.filter { $0.supersededAt == nil }
        let events = try TaskProgressEventService.events(
            forTaskIDs: Set(activeTasks.map(\.id)),
            in: context
        )
        let eventsByTask = Dictionary(grouping: events, by: \.taskId)
        var report = Report()

        for task in activeTasks {
            let status = TaskStatus(rawValue: task.status) ?? .todo
            guard status != .doing else { continue }
            let projection = TaskProgressEventRules.projection(for: eventsByTask[task.id] ?? [])
            guard let startedAt = projection.currentStartedAt else { continue }
            let preferredBoundary = status == .done ? (task.completedAt ?? task.updatedAt) : task.updatedAt
            let boundary = max(startedAt, preferredBoundary)
            if try TaskProgressEventService.recordCompatibilityBoundary(
                taskID: task.id,
                occurredAt: boundary,
                in: context
            ) != nil {
                report.insertedBoundaries += 1
            }
        }
        return report
    }
}
