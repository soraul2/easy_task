import Foundation
import SwiftData

/// iPhone owns database writes. The journal makes repeated WatchConnectivity deliveries safe,
/// including the crash window between a database commit and a receipt-file commit.
@available(watchOS 11, *)
@MainActor
public final class WatchCompanionService {
    private struct Journal: Codable {
        var version = WatchCompanionProtocol.version
        var phoneID = UUID()
        var revision = 0
        var prepared: Set<UUID> = []
        var receipts: [WatchCompanionReceipt] = []
    }

    private let journalURL: URL
    private var journal: Journal

    public init(journalURL: URL) throws {
        self.journalURL = journalURL
        if FileManager.default.fileExists(atPath: journalURL.path) {
            journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
            guard journal.version == WatchCompanionProtocol.version else {
                throw WatchCompanionError.unsupportedVersion
            }
        } else {
            journal = Journal()
            try saveJournal()
        }
    }

    public func respond(to request: WatchCompanionRequest, in context: ModelContext,
                        now: Date = Date()) throws -> WatchCompanionResponse {
        guard request.version == WatchCompanionProtocol.version,
              request.commands.count <= WatchCompanionProtocol.maximumBatchCount else {
            throw WatchCompanionError.unsupportedVersion
        }
        var receipts: [WatchCompanionReceipt] = []
        for command in request.commands {
            if let receipt = journal.receipts.first(where: { $0.commandID == command.id }) {
                receipts.append(receipt)
                continue
            }
            let receipt: WatchCompanionReceipt
            do {
                try validate(command, now: now)
                if journal.prepared.contains(command.id) {
                    guard try wasApplied(command, in: context) else {
                        throw CommandFailure.message("이전 전송의 저장 결과를 확인할 수 없습니다. iPhone에서 작업을 확인해 주세요.")
                    }
                } else {
                    journal.prepared.insert(command.id)
                    try saveJournal()
                    do {
                        try PersistenceCommandService.perform(in: context) {
                            try apply(command, in: context, now: now)
                        }
                    } catch {
                        // A known rollback can be retried. An interrupted process leaves the
                        // prepared marker, and recovery above never blindly repeats a write.
                        journal.prepared.remove(command.id)
                        try saveJournal()
                        throw error
                    }
                }
                receipt = WatchCompanionReceipt(commandID: command.id, accepted: true, processedAt: now)
            } catch let error as CommandFailure {
                receipt = WatchCompanionReceipt(commandID: command.id, accepted: false,
                    message: error.localizedDescription, processedAt: now)
            }
            journal.receipts.append(receipt)
            journal.prepared.remove(command.id)
            journal.receipts.removeAll { now.timeIntervalSince($0.processedAt) > WatchCompanionProtocol.maximumCommandAge + 86_400 }
            try saveJournal()
            receipts.append(receipt)
        }
        return WatchCompanionResponse(snapshot: try snapshot(in: context, now: now), receipts: receipts)
    }

    public func snapshot(in context: ModelContext, now: Date = Date()) throws -> WatchCompanionSnapshot {
        let dayKey = DayKey.key(for: now)
        let descriptor = BoundedQueryService.boardTasksDescriptor(selectedDayKey: dayKey)
        let tasks = BoardQueryRules.tasksForBoard(try context.fetch(descriptor), selectedDayKey: dayKey)
        let events = try BoundedQueryService.events(overlappingStartDayKey: dayKey, endDayKey: dayKey, in: context)
        journal.revision += 1
        try saveJournal()
        var result = WatchCompanionSnapshot(phoneID: journal.phoneID, revision: journal.revision,
            generatedAt: now, dayKey: dayKey,
            tasks: tasks.prefix(100).map {
                WatchCompanionTask(id: $0.id, title: boundedTitle($0.title), status: $0.status,
                    updatedAt: $0.updatedAt, plannedDayKey: $0.plannedDayKey,
                    reminderAt: $0.reminderAt, estimatedMinutes: $0.estimatedMinutes)
            },
            events: events.prefix(10).map { WatchCompanionEvent(id: $0.id, title: boundedTitle($0.title)) },
            hasMoreTasks: tasks.count > 100,
            todoCount: tasks.filter { $0.status == "todo" }.count,
            doingCount: tasks.filter { $0.status == "doing" }.count,
            doneCount: tasks.filter { $0.status == "done" }.count,
            eventCount: events.count)
        // Leave room for command receipts within WatchConnectivity's message envelope.
        while try JSONEncoder().encode(result).count > 45_000, !result.tasks.isEmpty {
            result.tasks.removeLast()
            result.hasMoreTasks = true
        }
        return result
    }

    private func saveJournal() throws {
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
    }

    private func boundedTitle(_ value: String) -> String {
        var bytes = Array(value.prefix(160).utf8.prefix(640))
        while String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private enum CommandFailure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(message) = self { message } else { nil } }
    }

    private func validate(_ command: WatchCompanionCommand, now: Date) throws {
        guard command.phoneID == journal.phoneID else {
            throw CommandFailure.message("연결된 iPhone이 변경되었습니다. 작업을 다시 확인해 주세요.")
        }
        guard command.createdAt <= now.addingTimeInterval(300),
              now.timeIntervalSince(command.createdAt) <= WatchCompanionProtocol.maximumCommandAge else {
            throw CommandFailure.message("오래되었거나 시간이 맞지 않는 변경입니다. iPhone에서 확인해 주세요.")
        }
    }

    private func task(_ id: UUID, in context: ModelContext) throws -> Task? {
        BoundedQueryService.representativeTask(from: try context.fetch(BoundedQueryService.taskCandidatesDescriptor(id: id)))
    }

    private func wasApplied(_ command: WatchCompanionCommand, in context: ModelContext) throws -> Bool {
        switch command.action {
        case let .addTask(id, _, _):
            return try task(id, in: context) != nil
        case let .setStatus(id, _, _, status, _, _):
            guard let task = try task(id, in: context) else { return false }
            return task.status == status && abs(task.updatedAt.timeIntervalSince(command.createdAt)) < 0.001
        case let .recordFocus(record):
            let id = record.id
            return try !context.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })).isEmpty
        }
    }

    private func apply(_ command: WatchCompanionCommand, in context: ModelContext, now: Date) throws {
        switch command.action {
        case let .addTask(id, title, dayKey):
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 500, title.utf8.count <= 2_000,
                  let day = DayKey.date(from: dayKey), DayKey.key(for: day) == dayKey else {
                throw CommandFailure.message("작업 제목 또는 날짜를 확인해 주세요.")
            }
            guard try task(id, in: context) == nil else { return }
            let order = try BoundedQueryService.nextOrder(in: context, dayKey: dayKey, status: .todo)
            context.insert(Task(id: id, title: title, plannedAt: day, order: order,
                                createdAt: command.createdAt, updatedAt: command.createdAt))
        case let .setStatus(id, expectedStatus, expectedUpdatedAt, rawStatus, completionDayKey, confirmedReminderAt):
            guard let task = try task(id, in: context), let status = TaskStatus(rawValue: rawStatus),
                  task.status == expectedStatus, abs(task.updatedAt.timeIntervalSince(expectedUpdatedAt)) < 0.001 else {
                throw CommandFailure.message("iPhone에서 작업이 변경되었거나 삭제되어 Watch 변경을 적용하지 않았습니다.")
            }
            guard let day = DayKey.date(from: completionDayKey), DayKey.key(for: day) == completionDayKey else {
                throw CommandFailure.message("완료 날짜를 확인해 주세요.")
            }
            if status == .done, let reminder = TaskReminderRules.upcomingReminderDate(for: task, now: now),
               confirmedReminderAt != reminder {
                throw CommandFailure.message("작업 알림이 변경되었습니다. iPhone에서 완료해 주세요.")
            }
            _ = try TaskLifecycleService.applyStatus(status, to: task, in: context, now: command.createdAt,
                                                      completionDayKey: status == .done ? completionDayKey : nil)
        case let .recordFocus(record):
            let id = record.id
            guard try context.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })).isEmpty else { return }
            guard try task(record.taskID, in: context) != nil,
                  let outcome = FocusSessionOutcome(rawValue: record.outcome),
                  record.startedAt <= record.endedAt, record.endedAt <= now.addingTimeInterval(300),
                  record.plannedSeconds == FocusTimerRules.normalizedFocusSeconds(record.plannedSeconds),
                  record.focusedSeconds >= 0, record.focusedSeconds <= record.plannedSeconds,
                  Double(record.focusedSeconds) <= record.endedAt.timeIntervalSince(record.startedAt) + 1 else {
                throw CommandFailure.message("집중 기록을 반영할 수 없습니다. 작업과 시간을 확인해 주세요.")
            }
            context.insert(FocusSession(id: record.id, instanceID: record.instanceID, taskId: record.taskID,
                startedAt: record.startedAt, endedAt: record.endedAt, plannedDurationSeconds: record.plannedSeconds,
                focusedDurationSeconds: record.focusedSeconds, outcome: outcome,
                createdAt: record.endedAt, updatedAt: record.endedAt))
        }
    }
}
