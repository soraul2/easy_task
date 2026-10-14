import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import EasyTaskCore

private enum BootstrapTestError: Error {
    case beforeCommit
}

@Test @MainActor
func bootstrapActorMatchesSynchronousConvergenceBeforeOpeningUIContext() async throws {
    let baseline = try PlanBaseContainerFactory.makeInMemory()
    let candidate = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapRepairFixture(in: baseline.mainContext)
    try seedBootstrapRepairFixture(in: candidate.mainContext)

    let expected = try DataIntegrityService.reconcile(context: baseline.mainContext)
    let actual = try await PlanBaseBootstrapService.prepare(container: candidate)
    let freshUIContext = ModelContext(candidate)

    #expect(actual == expected)
    #expect(actual.mergedRecords >= 3)
    #expect(actual.normalizedFields > 0)
    #expect(actual.rewiredReferences > 0)
    #expect(try bootstrapCanonicalPayload(in: freshUIContext)
            == bootstrapCanonicalPayload(in: ModelContext(baseline)))

    let boardRows = try freshUIContext.fetch(
        BoundedQueryService.boardTasksDescriptor(selectedDayKey: "2026-09-04"))
    #expect(boardRows.filter { $0.id == bootstrapID(10) }.count == 1)
    #expect(boardRows.first { $0.id == bootstrapID(10) }?.title == "현재 작업")
    #expect(boardRows.first { $0.id == bootstrapID(10) }?.tags == ["유지"])
    #expect(boardRows.first { $0.id == bootstrapID(10) }?.eventId == nil)

    let templates = try freshUIContext.fetch(FetchDescriptor<TaskTemplate>())
    #expect(templates.filter { $0.supersededAt == nil }.map(\.id) == [bootstrapID(41)])
    let items = try freshUIContext.fetch(FetchDescriptor<TaskTemplateItem>())
    #expect(items.first?.templateId == bootstrapID(41))
    let blocks = try freshUIContext.fetch(FetchDescriptor<DiaryBlock>())
    #expect(blocks.first?.reviewId == bootstrapID(61))
    let checklist = try freshUIContext.fetch(FetchDescriptor<TaskChecklistItem>())
    #expect(checklist.first?.supersededAt != nil)
}

@Test @MainActor
func bootstrapCapturesLegacyCompletionAndClosesProgressWithoutInventingDuration() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapRepairFixture(in: container.mainContext)
    let report = try await PlanBaseBootstrapService.prepare(container: container)
    let uiContext = ModelContext(container)

    let activities = try uiContext.fetch(FetchDescriptor<TaskCompletionActivity>())
    let completion = try #require(activities.first { $0.taskId == bootstrapID(20) })
    #expect(completion.originRawValue == TaskCompletionActivityOrigin.legacyBackfill.rawValue)
    #expect(completion.activityDayKey == TaskActivityRules.legacyDayKey(
        for: bootstrapDay.addingTimeInterval(600)))
    #expect(completion.occurredAt == bootstrapDay.addingTimeInterval(600))
    let events = try TaskProgressEventService.events(forTaskIDs: [bootstrapID(20)], in: uiContext)
    #expect(events.count == 2)
    let boundary = try #require(events.first {
        $0.originRawValue == TaskProgressEventOrigin.compatibilityBoundary.rawValue
    })
    #expect(boundary.id == TaskProgressEventService.compatibilityBoundaryID(
        taskID: bootstrapID(20), occurredAt: bootstrapDay.addingTimeInterval(600)))
    let progress = TaskProgressEventRules.projection(for: events)
    #expect(progress.currentStartedAt == nil)
    #expect(progress.hasUnknownDuration)
    #expect(progress.recordedDuration == 0)
    #expect(report.insertedRecords == 2)

    let sessions = try uiContext.fetch(FetchDescriptor<FocusSession>())
    #expect(sessions.first?.focusedDurationSeconds == 300)
    let second = try await PlanBaseBootstrapService.prepare(container: container)
    #expect(!second.hasChanges)
    #expect(try ModelContext(container).fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 1)
}

@Test @MainActor
func bootstrapFacadeExecutionRemainsOffMainForMainActorCaller() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let probe = try await PlanBaseBootstrapService.withWorker(container: container) { worker in
        let probe = await worker.executionProbe()
        _ = try await worker.reconcile(beforeSave: {
            #expect(!Thread.isMainThread)
        })
        return probe
    }
    print("BOOTSTRAP_FACADE_EXECUTION_PROBE createdOnMain=\(probe.createdOnMainThread) "
          + "workerOnMain=\(probe.executingOnMainThread)")
    #expect(!probe.createdOnMainThread)
    #expect(!probe.executingOnMainThread)
}

@Test @MainActor
func failedBootstrapRollsBackRepairsAndInsertedActivityBeforeRetry() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapRepairFixture(in: container.mainContext)
    try await PlanBaseBootstrapService.withWorker(container: container) { worker in
        do {
            _ = try await worker.reconcile(beforeSave: {
                #expect(!Thread.isMainThread)
                throw BootstrapTestError.beforeCommit
            })
            Issue.record("Injected bootstrap failure was not propagated")
        } catch BootstrapTestError.beforeCommit {
            // The failed pass must leave the previously committed fixture intact.
        }
        // Each reader context and its rows stay in this synchronous scope;
        // neither crosses the following worker call or the detached boundary.
        do {
            let afterFailure = ModelContext(container)
            let taskRows = try afterFailure.fetch(FetchDescriptor<Task>())
            #expect(taskRows.filter { $0.id == bootstrapID(10) && $0.supersededAt == nil }.count == 2)
            #expect(taskRows.first { $0.instanceID == bootstrapID(12) }?.plannedDayKey == "broken")
            #expect(try afterFailure.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 0)
            #expect(try afterFailure.fetchCount(FetchDescriptor<TaskProgressEvent>()) == 1)
        }

        _ = try await worker.reconcile(beforeSave: {
            #expect(!Thread.isMainThread)
        })
        let afterRetry = ModelContext(container)
        #expect(try afterRetry.fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 1)
        let repaired = try afterRetry.fetch(FetchDescriptor<Task>())
        #expect(repaired.filter { $0.id == bootstrapID(10) && $0.supersededAt == nil }.count == 1)
    }
}

@Test @MainActor
func asynchronousLocalContainerOpenRetainsDataOnReopen() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseBootstrapTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("test.store")
    let container = try await PlanBaseContainerFactory.makeAppPersistentAsync(storeURL: storeURL, mode: .local)
    try seedBootstrapRepairFixture(in: container.mainContext)
    _ = try await PlanBaseBootstrapService.prepare(container: container)
    let reopened = try await PlanBaseContainerFactory.makeAppPersistentAsync(storeURL: storeURL, mode: .local)
    let report = try await PlanBaseBootstrapService.prepare(container: reopened)
    #expect(!report.hasChanges)
    #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<TaskCompletionActivity>()) == 1)
    #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<Task>()) == 3)
}

@Test @MainActor
func bootstrapValidatesImageBytesAndRepairsMetadataLikeSynchronousConvergence() async throws {
    let baseline = try PlanBaseContainerFactory.makeInMemory()
    let candidate = try PlanBaseContainerFactory.makeInMemory()
    let png = try bootstrapPNG()
    let corrupt = Data(png.prefix(8))
    for container in [baseline, candidate] {
        let context = container.mainContext
        context.insert(DailyReview(id: bootstrapID(80), instanceID: bootstrapID(180),
                                   dayKey: "2026-09-04", content: "첨부 검사",
                                   createdAt: bootstrapDay, updatedAt: bootstrapDay))
        for (index, data) in [png, corrupt].enumerated() {
            context.insert(DiaryAttachment(
                id: bootstrapID(81 + index), instanceID: bootstrapID(181 + index),
                reviewId: bootstrapID(80), order: Double(index) * 100,
                originalFileName: " image.png ", mimeType: "invalid", byteCount: -1,
                sha256: "invalid", data: data, createdAt: bootstrapDay, updatedAt: bootstrapDay))
        }
        try context.save()
    }
    let expected = try DataIntegrityService.reconcile(context: baseline.mainContext)
    let actual = try await PlanBaseBootstrapService.prepare(container: candidate)
    #expect(actual == expected)
    let context = ModelContext(candidate)
    let rows = try context.fetch(FetchDescriptor<DiaryAttachment>())
    let valid = try #require(rows.first { $0.id == bootstrapID(81) })
    let invalid = try #require(rows.first { $0.id == bootstrapID(82) })
    let metadata = try DiaryAttachmentService.inspect(png)
    #expect(valid.supersededAt == nil)
    #expect(valid.mimeType == metadata.mediaType.rawValue)
    #expect(valid.byteCount == metadata.byteCount)
    #expect(valid.sha256 == metadata.sha256)
    #expect(valid.originalFileName == "image.png")
    #expect(valid.data == png)
    #expect(invalid.supersededAt != nil)
    #expect(invalid.data == corrupt)
    #expect(try await PlanBaseBootstrapService.prepare(container: candidate) == .noChanges)
}

@Test @MainActor
func startupSessionOpensOnceAcrossScenesAndHandsOffFreshContext() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapRepairFixture(in: container.mainContext)
    let session = PlanBaseStartupSession()
    var openCount = 0
    var installationCount = 0
    var installedContext: ModelContext?
    let install: @MainActor (ModelContainer, ModelContext) -> Void = { _, context in
        installationCount += 1
        installedContext = context
    }
    let firstWindow = Swift.Task { @MainActor in
        await session.load(open: {
            openCount += 1
            await Swift.Task.yield()
            return container
        }, onReady: install)
    }
    await Swift.Task.yield()
    await session.load(open: { openCount += 1; return container }, onReady: install)
    await firstWindow.value
    #expect(openCount == 1)
    #expect(installationCount == 1)
    guard case .ready(let opened, let context) = session.state else {
        Issue.record("Startup did not become ready")
        return
    }
    #expect(opened === container)
    #expect(context !== container.mainContext)
    #expect(installedContext === context)
    let board = try context.fetch(BoundedQueryService.boardTasksDescriptor(selectedDayKey: "2026-09-04"))
    #expect(board.filter { $0.id == bootstrapID(10) }.count == 1)
    #expect(board.first { $0.id == bootstrapID(10) }?.title == "현재 작업")
}

@Test @MainActor
func startupSessionReconcilesImportsDuringBootstrapAndRetainsHandoffImport() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapRepairFixture(in: container.mainContext)
    let imported = CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: true)
    let recorder = BootstrapImportTestRecorder()
    let session = PlanBaseStartupSession(prepare: { container, configuration in
        recorder.passes += 1
        if recorder.passes == 1 { recorder.session?.recordImport(imported) }
        return try await PlanBaseBootstrapService.prepare(
            container: container, legacyImageMigration: configuration
        )
    })
    recorder.session = session
    await session.load(open: { container })
    #expect(recorder.passes == 2)
    #expect(session.takePendingImport() == nil)
    // A successful import between ready and root-listener installation is replayed
    // directly exactly once. Failed imports cannot replace that pending event.
    session.recordImport(imported)
    session.recordImport(CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: false))
    #expect(session.takePendingImport() == imported)
    #expect(session.takePendingImport() == nil)
}

@Test @MainActor
func startupSessionCanRetryOpeningFailureWithoutInstallingWriters() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let session = PlanBaseStartupSession()
    var installationCount = 0
    await session.load(open: { throw BootstrapTestError.beforeCommit },
                       onReady: { _, _ in installationCount += 1 })
    guard case .failed = session.state else {
        Issue.record("Opening failure was not displayed")
        return
    }
    #expect(installationCount == 0)
    session.retry()
    #expect(session.attempt == 1)
    await session.load(open: { container }, onReady: { _, _ in installationCount += 1 })
    #expect(installationCount == 1)
    guard case .ready = session.state else {
        Issue.record("Retry did not become ready")
        return
    }
}

@MainActor
private final class BootstrapImportTestRecorder {
    weak var session: PlanBaseStartupSession?
    var passes = 0
}

private var bootstrapDay: Date { DayKey.date(from: "2026-09-04")! }

private func bootstrapID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}

private func bootstrapPNG() throws -> Data {
    let pixels = Data([0xF0, 0x30, 0x50, 0xFF])
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(
        width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return output as Data
}

@MainActor
private func seedBootstrapRepairFixture(in context: ModelContext) throws {
    let day = bootstrapDay
    let older = day.addingTimeInterval(10)
    let newer = day.addingTimeInterval(20)
    context.insert(Task(id: bootstrapID(10), instanceID: bootstrapID(11), title: "이전 작업",
                        plannedAt: day, order: 100, createdAt: older, updatedAt: older))
    let winner = Task(id: bootstrapID(10), instanceID: bootstrapID(12), title: "현재 작업",
                      plannedAt: day, order: 100, eventId: bootstrapID(999),
                      tags: [" 유지 ", "유지", " "], estimatedMinutes: -1,
                      createdAt: older, updatedAt: newer)
    winner.plannedDayKey = "broken"
    context.insert(winner)
    let completed = Task(id: bootstrapID(20), instanceID: bootstrapID(21), title: "기존 완료",
                         status: .done, plannedAt: day, order: 200,
                         createdAt: older, updatedAt: newer)
    completed.completedAt = day.addingTimeInterval(600)
    completed.completedDayKey = "broken"
    context.insert(completed)
    context.insert(TaskProgressEvent(id: bootstrapID(22), instanceID: bootstrapID(23),
                                     taskId: completed.id, kind: .started, occurredAt: day,
                                     createdAt: older, updatedAt: older))
    context.insert(CalendarEvent(id: bootstrapID(30), instanceID: bootstrapID(31), title: "날짜 수리",
                                 startAt: DayKey.addingDays(1, to: day), endAt: day,
                                 createdAt: older, updatedAt: newer))
    context.insert(TaskTemplate(id: bootstrapID(40), instanceID: bootstrapID(140), seedKey: " routine ",
                               name: "이전 템플릿", createdAt: older, updatedAt: older))
    context.insert(TaskTemplate(id: bootstrapID(41), instanceID: bootstrapID(141), seedKey: "routine",
                               name: "현재 템플릿", createdAt: older, updatedAt: newer))
    context.insert(TaskTemplateItem(id: bootstrapID(42), instanceID: bootstrapID(142),
                                   templateId: bootstrapID(40), title: "템플릿 항목", order: 100,
                                   createdAt: older, updatedAt: newer))
    context.insert(TaskChecklistItem(id: bootstrapID(50), instanceID: bootstrapID(150),
                                    taskId: bootstrapID(999), title: "끊어진 참조", order: 100,
                                    createdAt: older, updatedAt: newer))
    context.insert(DailyReview(id: bootstrapID(60), instanceID: bootstrapID(160),
                              dayKey: "2026-09-04", content: "이전 회고", createdAt: older, updatedAt: older))
    context.insert(DailyReview(id: bootstrapID(61), instanceID: bootstrapID(161),
                              dayKey: "2026-09-04", content: "현재 회고", createdAt: older, updatedAt: newer))
    context.insert(DiaryBlock(id: bootstrapID(62), instanceID: bootstrapID(162), reviewId: bootstrapID(60),
                             dayKey: "2026-09-04", type: .text, text: "회고 블록", order: 100,
                             createdAt: older, updatedAt: newer))
    context.insert(FocusSession(id: bootstrapID(70), instanceID: bootstrapID(170), taskId: completed.id,
                               startedAt: day, endedAt: day.addingTimeInterval(300),
                               plannedDurationSeconds: 300, focusedDurationSeconds: 900, outcome: .completed,
                               createdAt: older, updatedAt: newer))
    try context.save()
}

@MainActor
private func bootstrapCanonicalPayload(in context: ModelContext) throws -> Data {
    var payload = try BackupCodec.makePayloadAfterReconciliation(context: context)
    payload.exportedAt = .distantPast
    payload.tasks.sort { $0.id.uuidString < $1.id.uuidString }
    payload.calendarEvents.sort { $0.id.uuidString < $1.id.uuidString }
    payload.taskTemplates.sort { $0.id.uuidString < $1.id.uuidString }
    payload.taskTemplateItems.sort { $0.id.uuidString < $1.id.uuidString }
    payload.dailyReviews?.sort { $0.id.uuidString < $1.id.uuidString }
    payload.diaryBlocks?.sort { $0.id.uuidString < $1.id.uuidString }
    payload.taskChecklistItems?.sort { $0.id.uuidString < $1.id.uuidString }
    payload.focusSessions?.sort { $0.id.uuidString < $1.id.uuidString }
    // Only new capture metadata differs across independent executions. Their
    // logical IDs, origin, actual occurrence times and all existing rows stay exact.
    payload.taskCompletionActivities = payload.taskCompletionActivities?.map { original in
        var activity = original
        if activity.originRawValue == TaskCompletionActivityOrigin.legacyBackfill.rawValue {
            activity.instanceID = bootstrapID(900)
            activity.createdAt = .distantPast
            activity.updatedAt = .distantPast
        }
        return activity
    }.sorted { $0.id.uuidString < $1.id.uuidString }
    payload.taskProgressEvents = payload.taskProgressEvents?.map { original in
        var event = original
        if event.originRawValue == TaskProgressEventOrigin.compatibilityBoundary.rawValue {
            event.instanceID = bootstrapID(901)
            event.createdAt = .distantPast
            event.updatedAt = .distantPast
        }
        return event
    }.sorted { $0.id.uuidString < $1.id.uuidString }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(payload)
}
