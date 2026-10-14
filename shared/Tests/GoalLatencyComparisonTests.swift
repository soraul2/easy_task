#if DEBUG && canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import EasyTaskCore

/// The identical file can run against both frozen baseline and candidate sources.
/// Only pre-existing public APIs are used; no source-label-dependent code paths.
/// Every store is a uniquely owned temporary local store with CloudKit disabled.
/// These are synchronous function wall times, excluding setup and validation.
/// They are not launch/UI/frame/CloudKit latency; fresh files do not flush OS caches.
/// Each record has one separately timed first observation and 20 repeat samples.
private let goalLatencyComparisonEnabled = ProcessInfo.processInfo.environment["PLANBASE_GOAL_LATENCY_COMPARISON"] == "1"
private let goalLatencyRepeatCount = 20

@Test(.enabled(if: goalLatencyComparisonEnabled))
@MainActor
func goalLatencyQuickEntryComparison() throws {
    try withGoalLatencyDirectory { directory in
        let date = try #require(DayKey.date(from: "2026-10-12"))
        for libraryCount in [100, 1_000] {
            let container = try PlanBaseContainerFactory.makePersistent(
                storeURL: directory.appendingPathComponent("library-\(libraryCount).store"), mode: .local)
            let context = container.mainContext
            context.autosaveEnabled = false
            try seedGoalLatencyLibrary(count: libraryCount, date: date, in: context)
            let expectedEntries = try SavedTaskLibraryService.load(in: context)
            let expectedIDs = SavedTaskShortcutRules.suggestions(expectedEntries, input: "/perf12").map(\.id)
            let condition = GoalLatencyCondition(libraryCount: libraryCount, datasetMode: "saved-library-reused")

            try measureGoalLatency(
                "quickentry-fresh-controller-entry", condition: condition,
                firstMeaning: "first-observed-entry-on-a-new-controller; saved-store-warm",
                prepare: { _ in SavedTaskQuickEntryController() },
                operation: { controller, _ in
                    controller.update("/perf12", in: context)
                    return controller.suggestions
                },
                validate: { _, values, _ in
                    #expect(values.map(\.id) == expectedIDs)
                    #expect(!context.hasChanges)
                }
            )

            let reentry = SavedTaskQuickEntryController()
            reentry.update("/", in: context) // Initial library preparation is outside this interval.
            try measureGoalLatency(
                "quickentry-command-reentry", condition: condition,
                firstMeaning: "first-measured-command-reentry; initial-library-preparation-untimed",
                prepare: { _ in reentry.update("ordinary title", in: context) },
                operation: { _, _ in
                    reentry.update("/perf12", in: context)
                    return reentry.suggestions
                },
                validate: { _, values, _ in
                    #expect(values.map(\.id) == expectedIDs)
                    #expect(!context.hasChanges)
                }
            )

            try measureGoalLatency(
                "quickentry-first-submit", condition: condition,
                firstMeaning: "first-observed-submit; every-sample-uses-a-new-controller",
                prepare: { _ in SavedTaskQuickEntryController() },
                operation: { controller, _ in controller.add(input: "/perf12", on: date, in: context) },
                validate: { controller, value, index in
                    let task = try #require(value)
                    let checklistCount = try TaskChecklistService.items(for: task.id, in: context).count
                    let savedTaskCount = try context.fetchCount(FetchDescriptor<Task>())
                    #expect(task.title == "Latency library 0012" && task.plannedDayKey == DayKey.key(for: date))
                    #expect(checklistCount == 2)
                    #expect(savedTaskCount == index + 1)
                    #expect(controller.input.isEmpty && controller.failure == nil && !context.hasChanges)
                }
            )

            let ordinary = SavedTaskQuickEntryController()
            try measureGoalLatency(
                "quickentry-ordinary-title-control", condition: condition,
                firstMeaning: "first-observed-ordinary-title-update",
                prepare: { _ in () },
                operation: { _, index in
                    ordinary.update("ordinary title \(index)", in: context)
                    return ordinary.suggestions
                },
                validate: { _, values, _ in
                    #expect(values.isEmpty && ordinary.entries.isEmpty && ordinary.failure == nil)
                    #expect(!context.hasChanges)
                }
            )
            withExtendedLifetime(container) {}
        }
    }
}

@Test(.enabled(if: goalLatencyComparisonEnabled))
@MainActor
func goalLatencyPlainMutationComparison() throws {
    try withGoalLatencyDirectory { directory in
        let date = try #require(DayKey.date(from: "2026-10-12"))
        let dayKey = DayKey.key(for: date)
        for taskCount in [100, 1_000, 3_000] {
            let container = try PlanBaseContainerFactory.makePersistent(
                storeURL: directory.appendingPathComponent("mutations-\(taskCount).store"), mode: .local)
            let context = container.mainContext
            context.autosaveEnabled = false
            try seedGoalLatencyTasks(count: taskCount, date: date, in: context)
            let createCondition = GoalLatencyCondition(taskCount: taskCount, datasetMode: "one-saved-store-appends-21-tasks")
            try measureGoalLatency(
                "plain-create-atomic-command", condition: createCondition,
                firstMeaning: "first-create-command-after-fixture-save; no-rendered-subscribers",
                prepare: { _ in () },
                operation: { _, index in
                    try PersistenceCommandService.perform(in: context) {
                        let order = try BoundedQueryService.nextOrder(in: context, dayKey: dayKey, status: .todo)
                        let task = Task(title: "Latency added task \(index)", plannedAt: date, order: order)
                        context.insert(task)
                        return task
                    }
                },
                validate: { _, task, index in
                    let savedTaskCount = try context.fetchCount(FetchDescriptor<Task>())
                    #expect(task.title == "Latency added task \(index)" && task.plannedDayKey == dayKey)
                    #expect(savedTaskCount == taskCount + index + 1)
                    #expect(!context.hasChanges)
                }
            )

            var deletionIDs: [UUID] = []
            for index in 0...goalLatencyRepeatCount {
                let task = Task(id: goalLatencyID(namespace: 10, index: index),
                                title: "Latency deletion \(index)", plannedAt: date, order: Double(index))
                context.insert(task)
                context.insert(TaskChecklistItem(taskId: task.id, title: "First", order: 100))
                context.insert(TaskChecklistItem(taskId: task.id, title: "Second", order: 200))
                context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: date))
                context.insert(TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: date.addingTimeInterval(60)))
                deletionIDs.append(task.id)
            }
            try context.save()
            let beforeDeletionCount = try context.fetchCount(FetchDescriptor<Task>())
            let deleteCondition = GoalLatencyCondition(taskCount: taskCount, datasetMode: "one-saved-store-deletes-21-targets; each-target-has-2-checklist-and-2-progress-rows")
            try measureGoalLatency(
                "task-rules-delete-atomic-command", condition: deleteCondition,
                firstMeaning: "first-delete-command; selected-task-lookup-is-untimed; no-rendered-subscribers",
                prepare: { index in
                    let id = deletionIDs[index]
                    return try #require(context.fetch(FetchDescriptor<Task>(predicate: #Predicate { $0.id == id })).first)
                },
                operation: { task, _ in
                    try PersistenceCommandService.perform(in: context) { try TaskRules.delete(task, from: context) }
                },
                validate: { _, _, index in
                    let id = deletionIDs[index]
                    let selectedCount = try context.fetchCount(FetchDescriptor<Task>(predicate: #Predicate { $0.id == id }))
                    let checklist = try TaskChecklistService.items(for: id, in: context)
                    let progress = try TaskProgressEventService.events(forTaskIDs: [id], in: context)
                    let savedTaskCount = try context.fetchCount(FetchDescriptor<Task>())
                    #expect(selectedCount == 0)
                    #expect(checklist.isEmpty && progress.isEmpty)
                    #expect(savedTaskCount == beforeDeletionCount - index - 1)
                    #expect(!context.hasChanges)
                }
            )
            withExtendedLifetime(container) {}
        }
    }
}

@Test(.enabled(if: goalLatencyComparisonEnabled))
@MainActor
func goalLatencyStoreOpenComparison() throws {
    try withGoalLatencyDirectory { directory in
        try measureGoalLatency(
            "local-new-file-store-open", condition: .init(datasetMode: "21-distinct-empty-store-urls"),
            firstMeaning: "first-makePersistent-call-in-this-test; fresh-file-not-physical-cold-boot",
            prepare: { index in directory.appendingPathComponent("new-\(index).store") },
            operation: { url, _ in try PlanBaseContainerFactory.makePersistent(storeURL: url, mode: .local) },
            validate: { _, container, _ in
                let savedTaskCount = try container.mainContext.fetchCount(FetchDescriptor<Task>())
                #expect(savedTaskCount == 0)
            }
        )
        let date = try #require(DayKey.date(from: "2026-10-12"))
        for taskCount in [100, 1_000, 3_000] {
            let url = directory.appendingPathComponent("reopen-\(taskCount).store")
            // Initial construction, inserts, saves and container destruction are untimed.
            try autoreleasepool {
                let container = try PlanBaseContainerFactory.makePersistent(storeURL: url, mode: .local)
                container.mainContext.autosaveEnabled = false
                try seedGoalLatencyTasks(count: taskCount, date: date, in: container.mainContext)
            }
            try measureGoalLatency(
                "local-existing-file-store-reopen", condition: .init(taskCount: taskCount, datasetMode: "same-saved-local-store-reopened-21-times"),
                firstMeaning: "first-reopen-after-seeding; OS-file-cache-not-flushed",
                prepare: { _ in () },
                operation: { _, _ in try PlanBaseContainerFactory.makePersistent(storeURL: url, mode: .local) },
                validate: { _, container, _ in
                    let savedTaskCount = try container.mainContext.fetchCount(FetchDescriptor<Task>())
                    #expect(savedTaskCount == taskCount)
                }
            )
        }
    }
}

@Test(.enabled(if: goalLatencyComparisonEnabled))
@MainActor
func goalLatencyStartupIntegrityComparison() throws {
    try withGoalLatencyDirectory { directory in
        let date = try #require(DayKey.date(from: "2026-10-12"))
        for taskCount in [100, 1_000, 3_000] {
            for attachmentCount in [0, 20] {
                let container = try PlanBaseContainerFactory.makePersistent(
                    storeURL: directory.appendingPathComponent("integrity-\(taskCount)-\(attachmentCount).store"), mode: .local)
                let writer = container.mainContext
                writer.autosaveEnabled = false
                try seedGoalLatencyTasks(count: taskCount, date: date, includeProgress: true, in: writer)
                try seedGoalLatencyAttachments(count: attachmentCount, date: date, in: writer)
                // Normalize fixture metadata once. This benchmark measures full
                // startup no-op convergence, not a missing-record migration/backfill.
                _ = try DataIntegrityService.reconcile(context: writer)
                try writer.save()
                let condition = GoalLatencyCondition(taskCount: taskCount, attachmentCount: attachmentCount,
                    datasetMode: "fresh-context-per-sample; same-saved-normalized-store; 2-progress-per-task; 1x1-distinct-synthetic-PNG")
                try measureGoalLatency(
                    "startup-full-reconcile-main-context", condition: condition,
                    firstMeaning: "first-observed-full-reconcile-after-untimed-normalization; fresh-context-each-time",
                    prepare: { _ in
                        let context = ModelContext(container)
                        context.autosaveEnabled = false
                        return context
                    },
                    operation: { context, _ in try DataIntegrityService.reconcile(context: context) },
                    validate: { context, report, _ in
                        let savedTaskCount = try context.fetchCount(FetchDescriptor<Task>())
                        let savedAttachmentCount = try context.fetchCount(FetchDescriptor<DiaryAttachment>())
                        #expect(!report.hasChanges && !context.hasChanges)
                        #expect(savedTaskCount == taskCount)
                        #expect(savedAttachmentCount == attachmentCount)
                    }
                )
                withExtendedLifetime(container) {}
            }
        }
    }
}

private struct GoalLatencyCondition {
    var taskCount = 0
    var libraryCount = 0
    var attachmentCount = 0
    var datasetMode: String
}

private struct GoalLatencyResult: Encodable {
    let name: String
    let source: String
    let unit = "ms"
    let scope = "synchronous-core-function-wall-time; mainActor; local-file; no-UI-or-CloudKit"
    let setupTimed = false
    let validationTimed = false
    let physicalColdBoot = false
    let n: Int
    let firstMs: Double
    let firstMeaning: String
    let firstIncludedInRepeatStatistics = false
    let rawMs: [Double]
    let p50Ms: Double
    let p95Ms: Double
    let maxMs: Double
    let p95Method = "nearest-rank; n20-is-second-largest; finite-sample-tail-only"
    let taskCount: Int
    let libraryCount: Int
    let attachmentCount: Int
    let datasetMode: String
}

@MainActor
private func measureGoalLatency<Prepared, Result>(
    _ name: String,
    condition: GoalLatencyCondition,
    firstMeaning: String,
    prepare: (Int) throws -> Prepared,
    operation: (Prepared, Int) throws -> Result,
    validate: (Prepared, Result, Int) throws -> Void
) throws {
    var firstMs = 0.0
    var rawMs: [Double] = []
    for index in 0...goalLatencyRepeatCount {
        try autoreleasepool {
            let prepared = try prepare(index)
            let start = DispatchTime.now().uptimeNanoseconds
            let result = try operation(prepared, index)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            if index == 0 { firstMs = elapsed } else { rawMs.append(elapsed) }
            try validate(prepared, result, index)
        }
    }
    let ordered = rawMs.sorted()
    let report = GoalLatencyResult(
        name: name,
        source: ProcessInfo.processInfo.environment["PLANBASE_GOAL_SOURCE_LABEL"] ?? "unspecified",
        n: rawMs.count,
        firstMs: firstMs,
        firstMeaning: firstMeaning,
        rawMs: rawMs,
        p50Ms: (ordered[9] + ordered[10]) / 2,
        p95Ms: ordered[Int(ceil(Double(ordered.count) * 0.95)) - 1],
        maxMs: ordered.last ?? 0,
        taskCount: condition.taskCount,
        libraryCount: condition.libraryCount,
        attachmentCount: condition.attachmentCount,
        datasetMode: condition.datasetMode
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    print("GOAL_LATENCY_RESULT \(String(decoding: try encoder.encode(report), as: UTF8.self))")
}

@MainActor
private func withGoalLatencyDirectory(_ operation: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PlanBaseGoalLatency-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try operation(directory)
}

@MainActor
private func seedGoalLatencyLibrary(count: Int, date: Date, in context: ModelContext) throws {
    for index in 0..<count {
        let id = goalLatencyID(namespace: 1, index: index)
        let title = String(format: "Latency library %04d", index)
        context.insert(TaskTemplate(id: id, instanceID: goalLatencyID(namespace: 2, index: index), name: title,
                                    isFavorite: index % 7 == 0, quickEntryAlias: "perf\(index)", createdAt: date, updatedAt: date))
        context.insert(TaskTemplateItem(id: goalLatencyID(namespace: 3, index: index),
                                        instanceID: goalLatencyID(namespace: 4, index: index), templateId: id,
                                        title: title, note: "Synthetic note", checklistTitles: ["First", "Second"],
                                        order: Double(index), createdAt: date, updatedAt: date))
    }
    try context.save()
}

@MainActor
private func seedGoalLatencyTasks(count: Int, date: Date, includeProgress: Bool = false, in context: ModelContext) throws {
    for index in 0..<count {
        let day = index < min(240, count) ? date : DayKey.addingDays(-(1 + index % 120), to: date)
        let task = Task(id: goalLatencyID(namespace: 5, index: index),
                        instanceID: goalLatencyID(namespace: 6, index: index), title: "Latency task \(index)",
                        plannedAt: day, order: Double(index) * 100, createdAt: date, updatedAt: date)
        context.insert(task)
        if includeProgress {
            context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: day.addingTimeInterval(3600)))
            context.insert(TaskProgressEvent(taskId: task.id, kind: .stopped, occurredAt: day.addingTimeInterval(3660)))
        }
        if index % 250 == 249 { try context.save() }
    }
    try context.save()
}

@MainActor
private func seedGoalLatencyAttachments(count: Int, date: Date, in context: ModelContext) throws {
    var reviewIDs: [UUID] = []
    for index in 0..<count {
        if index % 10 == 0 {
            let review = DailyReview(dayKey: DayKey.key(for: DayKey.addingDays(-(index / 10), to: date)),
                                    content: "Synthetic image review", createdAt: date, updatedAt: date)
            context.insert(review)
            reviewIDs.append(review.id)
        }
        let data = try goalLatencyPNG(variant: index)
        let metadata = try DiaryAttachmentService.inspect(data)
        context.insert(DiaryAttachment(reviewId: reviewIDs[index / 10], order: Double(index % 10) * 100,
                                       mimeType: metadata.mediaType.rawValue, byteCount: metadata.byteCount,
                                       sha256: metadata.sha256, data: data, createdAt: date, updatedAt: date))
    }
    try context.save()
}

private func goalLatencyPNG(variant: Int) throws -> Data {
    let pixel = Data([UInt8(variant % 256), 0x30, 0x50, 0xFF])
    let provider = try #require(CGDataProvider(data: pixel as CFData))
    let image = try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return output as Data
}

private func goalLatencyID(namespace: Int, index: Int) -> UUID {
    UUID(uuidString: String(format: "A6000000-%04X-4000-8000-%012X", namespace, index + 1))!
}
#endif
