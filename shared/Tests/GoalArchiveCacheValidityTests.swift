import CryptoKit
import Foundation
import Observation
import SwiftData
import Testing
@testable import EasyTaskCore

private enum GoalArchiveCacheFailure: Error { case unavailable }

private func goalArchiveCacheID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", Int64(value)))!
}

@MainActor
private struct GoalArchiveCacheFixture {
    let container: ModelContainer
    let day: Date
    let task: Task
    let stop: TaskProgressEvent
    let review: DailyReview

    var context: ModelContext { container.mainContext }
    var filter: ArchiveFilter { filter(from: day, through: day) }

    init() throws {
        container = try PlanBaseContainerFactory.makeInMemory()
        container.mainContext.autosaveEnabled = false
        day = try #require(DayKey.date(from: "2026-08-06"))
        task = Task(id: goalArchiveCacheID(1), title: "첫 작업", plannedAt: day, order: 100,
                    createdAt: day, updatedAt: day)
        stop = TaskProgressEvent(id: goalArchiveCacheID(3), taskId: task.id, kind: .stopped,
                                 occurredAt: day.addingTimeInterval(4_200), createdAt: day, updatedAt: day)
        review = DailyReview(dayKey: DayKey.key(for: day), content: "첫 회고", createdAt: day, updatedAt: day)
        container.mainContext.insert(task)
        container.mainContext.insert(TaskProgressEvent(id: goalArchiveCacheID(2), taskId: task.id,
            kind: .started, occurredAt: day.addingTimeInterval(3_600), createdAt: day, updatedAt: day))
        container.mainContext.insert(stop)
        container.mainContext.insert(review)
        try container.mainContext.save()
    }

    func filter(from lower: Date, through upper: Date) -> ArchiveFilter {
        ArchiveFilter(contentMode: .dailyActivity, period: .custom,
                      customStartDate: lower, customEndDate: upper)
    }

    @discardableResult
    func addEarlierTask(offset: Int = 5, identity: Int = 10) throws -> Task {
        let earlier = DayKey.addingDays(-offset, to: day)
        let row = Task(id: goalArchiveCacheID(identity), title: "이전 작업 \(identity)",
                       plannedAt: earlier, order: 100, createdAt: earlier, updatedAt: earlier)
        context.insert(row)
        context.insert(TaskProgressEvent(taskId: row.id, kind: .started,
            occurredAt: earlier.addingTimeInterval(3_600), createdAt: earlier, updatedAt: earlier))
        context.insert(TaskProgressEvent(taskId: row.id, kind: .stopped,
            occurredAt: earlier.addingTimeInterval(4_200), createdAt: earlier, updatedAt: earlier))
        try context.save()
        return row
    }
}

@MainActor
private final class GoalArchiveCacheProbe {
    private(set) var requests: [DailyProgressIndexRequest] = []
    var failNext = false

    func read(_ request: DailyProgressIndexRequest, in container: ModelContainer) async throws
        -> [UUID: TaskProgressProjection] {
        requests.append(request)
        if failNext {
            failNext = false
            throw GoalArchiveCacheFailure.unavailable
        }
        return try await DailyActivityQueryService.readProgressIndex(request, in: container)
    }
}

/// Actual dedicated-context results are frozen after capture, without sleeps or timing assumptions.
@MainActor
private final class GoalArchiveCacheGate {
    private(set) var requests: [DailyProgressIndexRequest] = []
    let blockedCalls: Set<Int>
    private var held: [Int: (value: [UUID: TaskProgressProjection],
                            continuation: CheckedContinuation<[UUID: TaskProgressProjection], Error>)] = [:]
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(blockedCalls: Set<Int>) { self.blockedCalls = blockedCalls }

    func read(_ request: DailyProgressIndexRequest, in container: ModelContainer) async throws
        -> [UUID: TaskProgressProjection] {
        let call = requests.count
        requests.append(request)
        let value = try await DailyActivityQueryService.readProgressIndex(request, in: container)
        guard blockedCalls.contains(call) else { return value }
        return try await withCheckedThrowingContinuation { continuation in
            held[call] = (value, continuation)
            for waiter in waiters.removeValue(forKey: call) ?? [] { waiter.resume() }
        }
    }

    func waitForHeldCall(_ call: Int) async {
        guard held[call] == nil else { return }
        await withCheckedContinuation { waiters[call, default: []].append($0) }
    }

    func release(_ call: Int) {
        guard let result = held.removeValue(forKey: call) else {
            Issue.record("Expected a held archive reader at call \(call)")
            return
        }
        result.continuation.resume(returning: result.value)
    }
}

@MainActor
private final class GoalArchiveCacheCompletion {
    let session: ArchiveQuerySession
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ session: ArchiveQuerySession) { self.session = session }

    func wait() async {
        guard session.isLoading else { return }
        await withCheckedContinuation {
            continuation = $0
            observe()
        }
    }

    private func observe() {
        guard session.isLoading else {
            let pending = continuation
            continuation = nil
            pending?.resume()
            return
        }
        withObservationTracking { _ = session.isLoading } onChange: { [weak self] in
            Swift.Task { @MainActor [weak self] in self?.observe() }
        }
    }
}

@MainActor
private func goalArchiveCacheEntry(_ page: ArchiveQueryPage, taskID: UUID) throws -> DailyActivityEntry {
    try #require(page.records.flatMap { $0.activityEntries ?? [] }.first { $0.id == taskID })
}

@MainActor
private func goalArchiveCacheExpectInvalidated(_ request: Swift.Task<Void, Error>) async {
    do {
        _ = try await request.value
        Issue.record("A superseded archive read must not return a current page")
    } catch is DailyActivityReadInvalidated {
        // This is source invalidation, distinct from caller cancellation.
    } catch {
        Issue.record("Unexpected archive read error: \(error)")
    }
}

@Test @MainActor
func goalArchiveCacheReviewSavesRefreshValuesWithoutRebuildingIndex() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let probe = GoalArchiveCacheProbe()
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await probe.read(request, in: fixture.container)
    }
    let session = ArchiveQuerySession(context: fixture.context, dailyService: service)
    session.apply(fixture.filter, debounceSearch: false)
    await GoalArchiveCacheCompletion(session).wait()
    #expect(probe.requests.count == 1)
    try PersistenceCommandService.perform(in: fixture.context) {
        fixture.review.content = "명령으로 수정"
        fixture.review.updatedAt = fixture.day.addingTimeInterval(1)
    }
    session.refreshIfNeeded()
    await GoalArchiveCacheCompletion(session).wait()
    #expect(probe.requests.count == 1)
    #expect(session.records.first?.review === fixture.review)
    #expect(session.records.first?.review?.content == "명령으로 수정")
    #expect(session.records.first?.activityEntries?.first?.evidence.progressSeconds == 600)
    fixture.review.content = "직접 저장 수정"
    try fixture.context.save()
    session.refreshIfNeeded()
    await GoalArchiveCacheCompletion(session).wait()
    #expect(probe.requests.count == 1)
    #expect(session.records.first?.review?.content == "직접 저장 수정")
    #expect(session.loadedPageCount == 1 && !session.hasMore && session.errorMessage == nil)
    session.refreshIfNeeded()
    #expect(!session.isLoading)
    #expect(probe.requests.count == 1)
    session.cancel()
}

@Test @MainActor
func goalArchiveCacheTaskAndSameIDRawSaveInvalidateActualProjection() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let probe = GoalArchiveCacheProbe()
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await probe.read(request, in: fixture.container)
    }
    _ = try await service.page(filter: fixture.filter)
    let eventID = fixture.stop.id
    let updatedAt = fixture.stop.updatedAt
    try PersistenceCommandService.perform(in: fixture.context) {
        fixture.stop.occurredAt = fixture.day.addingTimeInterval(4_500)
        fixture.task.title = "수정 작업"
        fixture.task.status = TaskStatus.doing.rawValue
    }
    let page = try await service.page(filter: fixture.filter)
    let entry = try goalArchiveCacheEntry(page, taskID: fixture.task.id)
    #expect(probe.requests.count == 2)
    #expect(entry.evidence.progressSeconds == 900)
    #expect(entry.title == "수정 작업" && entry.currentStatusRawValue == TaskStatus.doing.rawValue)
    #expect(fixture.stop.id == eventID && fixture.stop.updatedAt == updatedAt)
    _ = try await service.page(filter: fixture.filter)
    #expect(probe.requests.count == 2)
}

@Test @MainActor
func goalArchiveCacheUnknownSignalIncludesLateSiblingContextProgress() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let probe = GoalArchiveCacheProbe()
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await probe.read(request, in: fixture.container)
    }
    _ = try await service.page(filter: fixture.filter)
    let sibling = ModelContext(fixture.container)
    sibling.autosaveEnabled = false
    let eventID = fixture.stop.id
    let imported = try #require(sibling.fetch(FetchDescriptor<TaskProgressEvent>(
        predicate: #Predicate { $0.id == eventID })).first)
    imported.occurredAt = fixture.day.addingTimeInterval(4_800)
    try sibling.save()
    // Explicit all-domain proxy; no CloudKit event or silent-write detection is claimed.
    NotificationCenter.default.post(name: PersistenceCommandService.dataChangedNotification, object: fixture.context)
    let page = try await service.page(filter: fixture.filter)
    #expect(probe.requests.count == 2)
    #expect(try goalArchiveCacheEntry(page, taskID: fixture.task.id).evidence.progressSeconds == 1_200)
}

@Test @MainActor
func goalArchiveCacheDirtyOverlayNeverSeedsReusableCacheAndRollbackRestoresFacts() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let probe = GoalArchiveCacheProbe()
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await probe.read(request, in: fixture.container)
    }
    _ = try await service.page(filter: fixture.filter)
    fixture.stop.occurredAt = fixture.day.addingTimeInterval(4_500)
    let pending = try await service.page(filter: fixture.filter)
    #expect(try goalArchiveCacheEntry(pending, taskID: fixture.task.id).evidence.progressSeconds == 900)
    _ = try await service.page(filter: fixture.filter)
    #expect(probe.requests.count == 3)
    #expect(fixture.context.hasChanges)
    fixture.context.rollback()
    let restored = try await service.page(filter: fixture.filter)
    #expect(try goalArchiveCacheEntry(restored, taskID: fixture.task.id).evidence.progressSeconds == 600)
    _ = try await service.page(filter: fixture.filter)
    #expect(probe.requests.count == 4)
    fixture.review.content = "저장 전 회고"
    _ = try await service.page(filter: fixture.filter)
    _ = try await service.page(filter: fixture.filter)
    #expect(probe.requests.count == 6)
    fixture.context.rollback()
}

@Test @MainActor
func goalArchiveCachePendingDeletionAndInsertionRetainOverlaySemantics() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let service = DailyActivityQueryService(context: fixture.context)
    _ = try await service.page(filter: fixture.filter)
    fixture.context.delete(fixture.stop)
    let deleted = try await service.page(filter: fixture.filter)
    #expect(try goalArchiveCacheEntry(deleted, taskID: fixture.task.id).evidence.progressSeconds == 0)
    fixture.context.rollback()
    fixture.context.insert(TaskProgressEvent(taskId: fixture.task.id, kind: .started,
        occurredAt: fixture.day.addingTimeInterval(7_200)))
    fixture.context.insert(TaskProgressEvent(taskId: fixture.task.id, kind: .stopped,
        occurredAt: fixture.day.addingTimeInterval(7_800)))
    let inserted = try await service.page(filter: fixture.filter)
    #expect(try goalArchiveCacheEntry(inserted, taskID: fixture.task.id).evidence.progressSeconds == 1_200)
    fixture.context.rollback()
    let restored = try await service.page(filter: fixture.filter)
    #expect(try goalArchiveCacheEntry(restored, taskID: fixture.task.id).evidence.progressSeconds == 600)
}

@Test(arguments: ["occurred", "kind", "origin", "task", "superseded", "created", "updated", "instance", "id"])
@MainActor
func goalArchiveCachePendingValueChangeDuringReadRejectsSameRow(field: String) async throws {
    let fixture = try GoalArchiveCacheFixture()
    fixture.stop.occurredAt = fixture.day.addingTimeInterval(4_500)
    let gate = GoalArchiveCacheGate(blockedCalls: [0])
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await gate.read(request, in: fixture.container)
    }
    let old = Swift.Task { @MainActor in _ = try await service.page(filter: fixture.filter) }
    await gate.waitForHeldCall(0)
    switch field {
    case "occurred": fixture.stop.occurredAt = fixture.day.addingTimeInterval(4_800)
    case "kind": fixture.stop.kindRawValue = TaskProgressEventKind.started.rawValue
    case "origin": fixture.stop.originRawValue = TaskProgressEventOrigin.compatibilityBoundary.rawValue
    case "task": fixture.stop.taskId = goalArchiveCacheID(90)
    case "superseded": fixture.stop.supersededAt = fixture.day
    case "created": fixture.stop.createdAt = fixture.day.addingTimeInterval(1)
    case "updated": fixture.stop.updatedAt = fixture.day.addingTimeInterval(1)
    case "instance": fixture.stop.instanceID = goalArchiveCacheID(91)
    case "id": fixture.stop.id = goalArchiveCacheID(92)
    default: Issue.record("Unexpected signature field")
    }
    gate.release(0)
    await goalArchiveCacheExpectInvalidated(old)
    fixture.context.rollback()
    let current = try await service.page(filter: fixture.filter)
    #expect(try goalArchiveCacheEntry(current, taskID: fixture.task.id).evidence.progressSeconds == 600)
    #expect(gate.requests.count == 2)
}

@Test @MainActor
func goalArchiveCacheStaleReaderCannotOverwriteNewSharedReader() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let gate = GoalArchiveCacheGate(blockedCalls: [0])
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await gate.read(request, in: fixture.container)
    }
    let old = Swift.Task { @MainActor in _ = try await service.page(filter: fixture.filter) }
    await gate.waitForHeldCall(0)
    try PersistenceCommandService.perform(in: fixture.context) {
        fixture.stop.occurredAt = fixture.day.addingTimeInterval(4_500)
    }
    let current = try await service.page(filter: fixture.filter)
    #expect(try goalArchiveCacheEntry(current, taskID: fixture.task.id).evidence.progressSeconds == 900)
    gate.release(0)
    await goalArchiveCacheExpectInvalidated(old)
    let cached = try await service.page(filter: fixture.filter)
    #expect(try goalArchiveCacheEntry(cached, taskID: fixture.task.id).evidence.progressSeconds == 900)
    #expect(gate.requests.count == 2)
}

@Test(arguments: [true, false]) @MainActor
func goalArchiveCacheConcurrentCoverageOnlyWidens(wideCompletesFirst: Bool) async throws {
    let fixture = try GoalArchiveCacheFixture()
    let earlier = try fixture.addEarlierTask()
    let wideFilter = fixture.filter(from: DayKey.addingDays(-5, to: fixture.day), through: fixture.day)
    let gate = GoalArchiveCacheGate(blockedCalls: [0, 1])
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await gate.read(request, in: fixture.container)
    }
    let narrow = Swift.Task { @MainActor in _ = try await service.page(filter: fixture.filter) }
    await gate.waitForHeldCall(0)
    let wide = Swift.Task { @MainActor in _ = try await service.page(filter: wideFilter) }
    await gate.waitForHeldCall(1)
    if wideCompletesFirst {
        gate.release(1)
        _ = try await wide.value
        gate.release(0)
        _ = try await narrow.value
    } else {
        gate.release(0)
        _ = try await narrow.value
        gate.release(1)
        _ = try await wide.value
    }
    let current = try await service.page(filter: wideFilter)
    #expect(Set(current.records.flatMap { $0.activityEntries ?? [] }.map(\.id)) == Set([fixture.task.id, earlier.id]))
    #expect(current.records.count == 2)
    #expect(gate.requests.count == 2)
}

@Test @MainActor
func goalArchiveCacheFailedExpansionKeepsEarlierValidCoverage() async throws {
    let fixture = try GoalArchiveCacheFixture()
    _ = try fixture.addEarlierTask()
    let probe = GoalArchiveCacheProbe()
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await probe.read(request, in: fixture.container)
    }
    _ = try await service.page(filter: fixture.filter)
    let wide = fixture.filter(from: DayKey.addingDays(-5, to: fixture.day), through: fixture.day)
    probe.failNext = true
    do {
        _ = try await service.page(filter: wide)
        Issue.record("Expected failed coverage expansion")
    } catch is GoalArchiveCacheFailure {}
    _ = try await service.page(filter: fixture.filter)
    #expect(probe.requests.count == 2)
    let retry = try await service.page(filter: wide)
    #expect(retry.records.count == 2)
    #expect(probe.requests.count == 3)
}

@Test @MainActor
func goalArchiveCacheSessionFailurePreservesDepthRowsAndAttachments() async throws {
    let fixture = try GoalArchiveCacheFixture()
    for offset in 1..<35 { try fixture.addEarlierTask(offset: offset, identity: offset + 10) }
    let block = DiaryBlock(reviewId: fixture.review.id, dayKey: DayKey.key(for: fixture.day),
                           type: .text, text: "보존할 블록", order: 100)
    let image = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
    let hash = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
    let attachment = DiaryAttachment(reviewId: fixture.review.id, order: 100, mimeType: "image/png",
        byteCount: image.count, sha256: hash, data: image)
    fixture.context.insert(block)
    fixture.context.insert(attachment)
    try fixture.context.save()
    let probe = GoalArchiveCacheProbe()
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await probe.read(request, in: fixture.container)
    }
    let filter = fixture.filter(from: DayKey.addingDays(-34, to: fixture.day), through: fixture.day)
    let session = ArchiveQuerySession(context: fixture.context, dailyService: service)
    session.apply(filter, debounceSearch: false)
    await GoalArchiveCacheCompletion(session).wait()
    session.loadNextPage()
    await GoalArchiveCacheCompletion(session).wait()
    #expect(session.records.count == 35 && session.loadedPageCount == 2 && !session.hasMore)
    let keys = session.records.map(\.dayKey)
    let taskIDs = session.records.flatMap(\.tasks).map(\.instanceID)
    service.invalidate()
    probe.failNext = true
    session.refreshPreservingDepth()
    await GoalArchiveCacheCompletion(session).wait()
    #expect(session.errorMessage != nil && !session.isLoading)
    #expect(session.records.map(\.dayKey) == keys)
    #expect(session.records.flatMap(\.tasks).map(\.instanceID) == taskIDs)
    #expect(session.loadedPageCount == 2 && !session.hasMore)
    #expect(session.records.first?.review === fixture.review)
    #expect(session.blocks.map(\.instanceID) == [block.instanceID])
    #expect(session.attachments.map(\.instanceID) == [attachment.instanceID])
    session.retry()
    await GoalArchiveCacheCompletion(session).wait()
    #expect(session.errorMessage == nil && !session.isLoading)
    #expect(session.records.map(\.dayKey) == keys)
    #expect(session.loadedPageCount == 2 && !session.hasMore)
    session.cancel()
}

@Test @MainActor
func goalArchiveCacheCancellingOneSessionKeepsSharedDaySessionCurrent() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let gate = GoalArchiveCacheGate(blockedCalls: [0])
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await gate.read(request, in: fixture.container)
    }
    let first = ArchiveQuerySession(context: fixture.context, dailyService: service)
    first.apply(fixture.filter, debounceSearch: false)
    await gate.waitForHeldCall(0)
    let day = first.makeDaySession()
    day.apply(fixture.filter, debounceSearch: false)
    await GoalArchiveCacheCompletion(day).wait()
    first.cancel()
    gate.release(0)
    #expect(!first.isLoading && !day.isLoading)
    #expect(day.records.first?.activityEntries?.first?.evidence.progressSeconds == 600)
    let current = try await service.page(filter: fixture.filter)
    #expect(try goalArchiveCacheEntry(current, taskID: fixture.task.id).evidence.progressSeconds == 600)
    #expect(gate.requests.count == 2)
    day.cancel()
}

@Test @MainActor
func goalArchiveCacheReviewChangesDuringReadPreserveRowsAndSettleLoading() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let gate = GoalArchiveCacheGate(blockedCalls: [1])
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await gate.read(request, in: fixture.container)
    }
    let session = ArchiveQuerySession(context: fixture.context, dailyService: service)
    session.apply(fixture.filter, debounceSearch: false)
    await GoalArchiveCacheCompletion(session).wait()
    let keys = session.records.map(\.dayKey)
    service.invalidate()
    session.refreshPreservingDepth()
    await gate.waitForHeldCall(1)
    try PersistenceCommandService.perform(in: fixture.context) { fixture.review.content = "읽는 동안 수정" }
    gate.release(1)
    await GoalArchiveCacheCompletion(session).wait()
    #expect(!session.isLoading && session.errorMessage != nil)
    #expect(session.records.map(\.dayKey) == keys && session.loadedPageCount == 1)
    session.retry()
    await GoalArchiveCacheCompletion(session).wait()
    #expect(!session.isLoading && session.errorMessage == nil)
    #expect(session.records.first?.review?.content == "읽는 동안 수정")
    // The completed progress read was still valid; only page content publication was rejected.
    #expect(gate.requests.count == 2)
    session.cancel()
}

@Test @MainActor
func goalArchiveCacheSessionRereadsDirtyResultAfterRollbackWithoutNotification() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let session = ArchiveQuerySession(context: fixture.context)
    session.apply(fixture.filter, debounceSearch: false)
    await GoalArchiveCacheCompletion(session).wait()
    fixture.stop.occurredAt = fixture.day.addingTimeInterval(4_500)
    session.refreshIfNeeded()
    await GoalArchiveCacheCompletion(session).wait()
    #expect(session.records.first?.activityEntries?.first?.evidence.progressSeconds == 900)
    fixture.context.rollback()
    session.refreshIfNeeded()
    await GoalArchiveCacheCompletion(session).wait()
    #expect(session.records.first?.activityEntries?.first?.evidence.progressSeconds == 600)
    #expect(session.errorMessage == nil && !session.isLoading)
    session.cancel()
}

@Test @MainActor
func goalArchiveCacheSavedLibraryEditReusesIndexButBoardAddInvalidates() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let saved = try SavedTaskLibraryService.create(draft: TemplateTaskDraft(title: "저장 작업", order: 100),
                                                  isFavorite: false, in: fixture.context)
    let probe = GoalArchiveCacheProbe()
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await probe.read(request, in: fixture.container)
    }
    _ = try await service.page(filter: fixture.filter)
    try SavedTaskLibraryService.update(id: saved.id, draft: TemplateTaskDraft(title: "새 저장 제목", order: 100),
                                       isFavorite: true, in: fixture.context)
    let edited = try await service.page(filter: fixture.filter)
    #expect(probe.requests.count == 1)
    #expect(try goalArchiveCacheEntry(edited, taskID: fixture.task.id).title == "첫 작업")
    let added = try SavedTaskLibraryService.add(id: saved.id, on: fixture.day, in: fixture.context)
    _ = try await service.page(filter: fixture.filter)
    #expect(probe.requests.count == 2)
    #expect(added.title == "새 저장 제목")
}

@Test @MainActor
func goalArchiveCacheCompatibilityBoundaryRetainsUnknownDuration() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let probe = GoalArchiveCacheProbe()
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await probe.read(request, in: fixture.container)
    }
    _ = try await service.page(filter: fixture.filter)
    try PersistenceCommandService.perform(in: fixture.context) {
        fixture.stop.supersededAt = fixture.day
        fixture.task.updatedAt = fixture.day.addingTimeInterval(4_500)
        let report = try TaskProgressCompatibilityService.reconcile(tasks: [fixture.task], in: fixture.context)
        #expect(report.insertedBoundaries == 1)
    }
    let page = try await service.page(filter: fixture.filter)
    let entry = try goalArchiveCacheEntry(page, taskID: fixture.task.id)
    #expect(probe.requests.count == 2)
    #expect(entry.evidence.unknownProgress && entry.evidence.progressSeconds == 0)
}

@Test @MainActor
func goalArchiveCacheUpperWideningKeepsCompleteSpanningIntervals() async throws {
    let fixture = try GoalArchiveCacheFixture()
    let longTask = Task(id: goalArchiveCacheID(50), title: "긴 진행", plannedAt: fixture.day, order: 200)
    let start = DayKey.addingDays(-10, to: fixture.day)
    let stop = DayKey.addingDays(10, to: fixture.day)
    fixture.context.insert(longTask)
    fixture.context.insert(TaskProgressEvent(taskId: longTask.id, kind: .started, occurredAt: start))
    fixture.context.insert(TaskProgressEvent(taskId: longTask.id, kind: .stopped, occurredAt: stop))
    try fixture.context.save()
    let probe = GoalArchiveCacheProbe()
    let service = DailyActivityQueryService(context: fixture.context) { request in
        try await probe.read(request, in: fixture.container)
    }
    let first = try await service.page(filter: fixture.filter)
    let expectedSeconds = DayKey.addingDays(1, to: fixture.day).timeIntervalSince(fixture.day)
    #expect(try goalArchiveCacheEntry(first, taskID: longTask.id).evidence.progressSeconds == expectedSeconds)
    let upper = fixture.filter(from: fixture.day, through: DayKey.addingDays(1, to: fixture.day))
    let widened = try await service.page(filter: upper)
    #expect(widened.records.count == 2)
    #expect(probe.requests.count == 1)
    #expect(widened.records.allSatisfy { $0.activityEntries?.contains { $0.id == longTask.id } == true })
}

@Test @MainActor
func goalArchiveCacheCurrentCancellationErrorSettlesSessionAndCanRetry() async throws {
    let fixture = try GoalArchiveCacheFixture()
    var calls = 0
    let service = DailyActivityQueryService(context: fixture.context) { request in
        calls += 1
        if calls == 1 { throw CancellationError() }
        return try await DailyActivityQueryService.readProgressIndex(request, in: fixture.container)
    }
    let session = ArchiveQuerySession(context: fixture.context, dailyService: service)
    session.apply(fixture.filter, debounceSearch: false)
    await GoalArchiveCacheCompletion(session).wait()
    #expect(!session.isLoading && session.records.isEmpty)
    session.retry()
    await GoalArchiveCacheCompletion(session).wait()
    #expect(!session.isLoading && session.errorMessage == nil)
    #expect(session.records.first?.activityEntries?.first?.evidence.progressSeconds == 600)
    #expect(calls == 2)
    session.cancel()
}

@Test @MainActor
func goalArchiveCacheAppendAfterRevisionChangeReloadsEarlierPageValues() async throws {
    let fixture = try GoalArchiveCacheFixture()
    for offset in 1..<35 { try fixture.addEarlierTask(offset: offset, identity: offset + 10) }
    let filter = fixture.filter(from: DayKey.addingDays(-34, to: fixture.day), through: fixture.day)
    let session = ArchiveQuerySession(context: fixture.context)
    session.apply(filter, debounceSearch: false)
    await GoalArchiveCacheCompletion(session).wait()
    #expect(session.records.count == 30 && session.hasMore)
    try PersistenceCommandService.perform(in: fixture.context) {
        fixture.stop.occurredAt = fixture.day.addingTimeInterval(4_500)
    }
    session.loadNextPage()
    await GoalArchiveCacheCompletion(session).wait()
    #expect(session.records.count == 35 && session.loadedPageCount == 2 && !session.hasMore)
    #expect(session.records.first?.activityEntries?.first?.evidence.progressSeconds == 900)
    #expect(session.errorMessage == nil && !session.isLoading)
    session.cancel()
}
