import Foundation
import SwiftData

extension CloudKitConvergenceProbe {
    static let checklistMarkerTitle = "__PLANBASE_CLOUDKIT_CHECKLIST_PROBE__"
    static let checklistMarkerDayKey = "2099-12-28"
    static let checklistMarkerItemTitles = [
        "__PLANBASE_CHECKLIST_ITEM_A__",
        "__PLANBASE_CHECKLIST_ITEM_B__"
    ]

    @MainActor
    static func runChecklistProbe(
        configuration: CloudKitProbeConfiguration,
        sourceBundleIdentifier: String,
        context: ModelContext
    ) async throws -> CloudKitProbeRunResult {
        let snapshot: CloudKitChecklistProbeSnapshot
        switch configuration.role {
        case .writer:
            try await performMutationAwaitingExportIfRequested(
                configuration: configuration
            ) {
                try writeChecklistMarker(
                    token: configuration.token,
                    sourceBundleIdentifier: sourceBundleIdentifier,
                    context: context
                )
            }
            snapshot = try checklistSnapshot(
                token: configuration.token,
                expectation: .present,
                context: context
            )
        case .reader:
            snapshot = try await waitForChecklistExpectation(
                configuration.expectation,
                token: configuration.token,
                timeoutSeconds: configuration.timeoutSeconds,
                context: context
            )
        case .cleanup:
            try await performMutationAwaitingExportIfRequested(
                configuration: configuration
            ) {
                try cleanupChecklistMarker(token: configuration.token, context: context)
            }
            snapshot = try checklistSnapshot(
                token: configuration.token,
                expectation: .absent,
                context: context
            )
        }

        return CloudKitProbeRunResult(
            kind: .checklist,
            role: configuration.role,
            token: configuration.token,
            passed: snapshot.passed,
            checklistSnapshot: snapshot,
            error: !snapshot.passed && configuration.role == .reader
                ? "CloudKit checklist probe timed out"
                : nil
        )
    }

    @MainActor
    static func writeChecklistMarker(
        token: UUID,
        sourceBundleIdentifier: String,
        context: ModelContext
    ) throws {
        let tasks = try checklistTasks(token: token, context: context)
        let items = try checklistItems(token: token, context: context)
        guard tasks.isEmpty, items.isEmpty else {
            throw probeFileExistsError("Checklist probe token already exists")
        }
        guard let plannedAt = DayKey.date(from: checklistMarkerDayKey) else {
            throw CocoaError(.formatting)
        }

        let now = Date()
        let task = Task(
            id: token,
            instanceID: UUID(),
            title: checklistMarkerTitle,
            note: "\(token.uuidString)|\(sourceBundleIdentifier)",
            plannedAt: plannedAt,
            order: 100,
            createdAt: now,
            updatedAt: now
        )
        let first = TaskChecklistItem(
            taskId: token,
            title: checklistMarkerItemTitles[0],
            isCompleted: true,
            order: 100,
            createdAt: now,
            updatedAt: now,
            completedAt: now
        )
        let second = TaskChecklistItem(
            taskId: token,
            title: checklistMarkerItemTitles[1],
            order: 200,
            createdAt: now,
            updatedAt: now
        )
        try PersistenceCommandService.perform(in: context) {
            context.insert(task)
            context.insert(first)
            context.insert(second)
        }
        log("LOCAL_CHECKLIST_SAVED token=\(token.uuidString)")
    }

    @MainActor
    static func cleanupChecklistMarker(
        token: UUID,
        context: ModelContext
    ) throws {
        let tasks = try checklistTasks(token: token, context: context)
        let items = try checklistItems(token: token, context: context)
        let markerTasks = tasks.filter { isChecklistTaskMarker($0, token: token) }
        let markerItems = items.filter(isChecklistItemMarker)
        guard markerTasks.count == tasks.count, markerItems.count == items.count else {
            log("LOCAL_CHECKLIST_DELETE_SKIPPED token=\(token.uuidString) collision=true")
            return
        }

        try PersistenceCommandService.perform(in: context) {
            for item in markerItems {
                context.delete(item)
            }
            for task in markerTasks {
                context.delete(task)
            }
        }
        log(
            "LOCAL_CHECKLIST_DELETED token=\(token.uuidString) " +
                "tasks=\(markerTasks.count) items=\(markerItems.count)"
        )
    }

    @MainActor
    static func checklistSnapshot(
        token: UUID,
        expectation: CloudKitProbeExpectation,
        context: ModelContext
    ) throws -> CloudKitChecklistProbeSnapshot {
        let tasks = try checklistTasks(token: token, context: context)
        let items = try checklistItems(token: token, context: context)
        let activeTasks = tasks.filter { $0.supersededAt == nil }
        let activeItems = items.filter { $0.supersededAt == nil }
        let matchingTasks = activeTasks.filter { isChecklistTaskMarker($0, token: token) }
        let matchingItems = activeItems.filter(isChecklistItemMarker)
        let completedItems = matchingItems.filter {
            $0.isCompleted && $0.completedAt != nil
        }
        let source = matchingTasks.first?.note?
            .split(separator: "|", maxSplits: 1)
            .dropFirst()
            .first
            .map(String.init)
        let passed: Bool
        switch expectation {
        case .present:
            passed = activeTasks.count == 1 &&
                matchingTasks.count == 1 &&
                activeItems.count == 2 &&
                matchingItems.count == 2 &&
                completedItems.count == 1
        case .absent:
            passed = tasks.isEmpty && items.isEmpty
        }

        return CloudKitChecklistProbeSnapshot(
            token: token,
            totalTaskCount: tasks.count,
            activeTaskCount: activeTasks.count,
            matchingTaskCount: matchingTasks.count,
            totalItemCount: items.count,
            activeItemCount: activeItems.count,
            matchingItemCount: matchingItems.count,
            completedItemCount: completedItems.count,
            sourceBundleIdentifier: source,
            expectation: expectation,
            passed: passed
        )
    }

    @MainActor
    static func waitForChecklistExpectation(
        _ expectation: CloudKitProbeExpectation,
        token: UUID,
        timeoutSeconds: Int,
        context: ModelContext
    ) async throws -> CloudKitChecklistProbeSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        var latest = try checklistSnapshot(
            token: token,
            expectation: expectation,
            context: context
        )
        while !latest.passed && clock.now < deadline {
            try await Swift.Task.sleep(for: .seconds(1))
            latest = try checklistSnapshot(
                token: token,
                expectation: expectation,
                context: context
            )
        }
        return latest
    }
}

private extension CloudKitConvergenceProbe {
    @MainActor
    static func checklistTasks(
        token: UUID,
        context: ModelContext
    ) throws -> [Task] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<Task> { task in
                task.id == token
            }
        ))
    }

    @MainActor
    static func checklistItems(
        token: UUID,
        context: ModelContext
    ) throws -> [TaskChecklistItem] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<TaskChecklistItem> { item in
                item.taskId == token
            }
        ))
    }

    static func isChecklistTaskMarker(_ task: Task, token: UUID) -> Bool {
        task.id == token &&
            task.title == checklistMarkerTitle &&
            task.plannedDayKey == checklistMarkerDayKey &&
            task.note?.hasPrefix("\(token.uuidString)|") == true
    }

    static func isChecklistItemMarker(_ item: TaskChecklistItem) -> Bool {
        guard let index = checklistMarkerItemTitles.firstIndex(of: item.title) else {
            return false
        }
        let expectedOrder = Double(index + 1) * 100
        if index == 0 {
            return item.order == expectedOrder && item.isCompleted && item.completedAt != nil
        }
        return item.order == expectedOrder && !item.isCompleted && item.completedAt == nil
    }
}
