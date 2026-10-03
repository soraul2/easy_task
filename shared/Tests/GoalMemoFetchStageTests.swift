#if DEBUG && PLANBASE_GOAL_CANDIDATE
import Foundation
import Observation
import SwiftData
import Testing
@testable import EasyTaskCore

// This file is an experimental overlay for M2-separated-fetch-prototype.swift.
// The fixture's first nonempty pinned saved batch has dense checklist-only matches.
// Loader checkpoints 0/1 precede its first step; 2 follows parent fetching,
// 3 follows checklist fetching, and 4 follows matching/final page construction.
// This mapping tests the inspected prototype without inspecting private PageScan.
private enum GoalMemoFetchStage: Int, CaseIterable, Sendable {
    case afterParent = 2
    case afterChecklist = 3
    case afterMatching = 4
}

@Test(arguments: GoalMemoFetchStage.allCases,
      ["raw-parent", "raw-checklist", "signaled-external-save"]) @MainActor
private func goalMemoFetchStagesRestartWholeReadAndPreserveDraft(
    stage: GoalMemoFetchStage, mutation: String
) async throws {
    let fixture = try GoalMemoFetchStageFixture()
    defer { withExtendedLifetime(fixture.container) {} }
    let target = fixture.memos[0]
    let item = fixture.items[0]
    if mutation == "raw-parent" { target.content = "reader pending first value" }
    if mutation == "raw-checklist" { item.title = "stage-needle reader first value" }
    let pendingBefore = goalMemoFetchStagePendingIDs(fixture.context)
    let parentUpdatedAt = target.updatedAt
    let itemUpdatedAt = item.updatedAt
    let draftBefore = goalMemoFetchStageDraft(fixture.draft)
    let gate = GoalMemoFetchStageGate()
    defer { gate.release() }
    let probe = GoalMemoFetchStageProbe(call: 1, stage: stage, gate: gate)
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    defer { session.cancel() }
    session.apply(query: "stage-needle", debounce: false)
    try await gate.waitReached()
    #expect(probe.pausedOrdinal == stage.rawValue)
    #expect(session.isLoading && session.memos.isEmpty)
    switch mutation {
    case "raw-parent":
        // A second scalar value on the same already pending physical row.
        target.content = "stage-needle reader second value 👨‍👩‍👧‍👦"
        target.isPinned = false
        #expect(target.updatedAt == parentUpdatedAt)
        #expect(goalMemoFetchStagePendingIDs(fixture.context) == pendingBefore)
    case "raw-checklist":
        item.title = "reader second value without query match"
        item.memoId = fixture.memos[110].id
        item.order = 900
        #expect(item.updatedAt == itemUpdatedAt)
        #expect(goalMemoFetchStagePendingIDs(fixture.context) == pendingBefore)
    default:
        let writer = ModelContext(fixture.container)
        writer.autosaveEnabled = false
        let targetID = target.id
        let itemID = fixture.items[1].id
        let destinationID = fixture.memos[110].id
        let externalParent = try #require(try writer.fetch(FetchDescriptor<Memo>(
            predicate: #Predicate<Memo> { $0.id == targetID })).first)
        let externalChild = try #require(try writer.fetch(FetchDescriptor<MemoChecklistItem>(
            predicate: #Predicate<MemoChecklistItem> { $0.id == itemID })).first)
        externalParent.content = "stage-needle external saved parent"
        externalParent.isPinned = false
        externalParent.updatedAt = fixture.reference.addingTimeInterval(300)
        externalChild.title = "external saved child without query match"
        externalChild.memoId = destinationID
        externalChild.order = 800
        externalChild.updatedAt = fixture.reference.addingTimeInterval(200)
        try writer.save()
        // A sibling save does not itself notify a source-context revision observer.
        // Exercise the application's unknown-domain import/proxy invalidation contract.
        NotificationCenter.default.post(name: PersistenceCommandService.dataChangedNotification,
                                         object: fixture.context)
        withExtendedLifetime(writer) {}
    }
    gate.release()
    await goalMemoFetchStageWait(session)
    #expect(probe.calls >= 2)
    #expect(probe.invalidatedCalls.contains(1))
    #expect(probe.cursors.allSatisfy { $0 == nil })
    try goalMemoFetchStageExpect(session, context: fixture.context, depth: 1)
    #expect(goalMemoFetchStageDraft(fixture.draft) == draftBefore)
    #expect(fixture.context.hasChanges)
    let registeredDraft: Memo? = fixture.context.registeredModel(for: fixture.draft.persistentModelID)
    #expect(registeredDraft === fixture.draft)
    let draftID = fixture.draft.id
    let savedDraftContent = try goalMemoFetchStageStoredDraftContent(id: draftID, fixture: fixture)
    #expect(savedDraftContent == GoalMemoFetchStageFixture.savedDraftContent)
    if mutation == "raw-parent" {
        #expect(target.content == "stage-needle reader second value 👨‍👩‍👧‍👦")
        #expect(!target.isPinned && target.updatedAt == parentUpdatedAt)
        let registeredTarget: Memo? = fixture.context.registeredModel(for: target.persistentModelID)
        #expect(registeredTarget === target)
        #expect(goalMemoFetchStagePendingIDs(fixture.context) == pendingBefore)
    } else if mutation == "raw-checklist" {
        #expect(item.title == "reader second value without query match")
        #expect(item.memoId == fixture.memos[110].id && item.order == 900)
        #expect(item.updatedAt == itemUpdatedAt)
        let registeredItem: MemoChecklistItem? = fixture.context.registeredModel(for: item.persistentModelID)
        #expect(registeredItem === item)
        #expect(goalMemoFetchStagePendingIDs(fixture.context) == pendingBefore)
    } else {
        // These two saved rows moved outside the first pinned page's predicates.
        // A read must publish the latest matching page, but has no contract to
        // refresh clean registered objects that it did not hydrate. Check the
        // store independently and the published IDs against fixed fixture rows.
        let reader = ModelContext(fixture.container)
        reader.autosaveEnabled = false
        let targetID = target.id
        let itemID = fixture.items[1].id
        let savedParent = try #require(try reader.fetch(FetchDescriptor<Memo>(
            predicate: #Predicate<Memo> { $0.id == targetID })).first)
        let savedChild = try #require(try reader.fetch(FetchDescriptor<MemoChecklistItem>(
            predicate: #Predicate<MemoChecklistItem> { $0.id == itemID })).first)
        #expect(savedParent.content == "stage-needle external saved parent" && !savedParent.isPinned)
        #expect(savedChild.title == "external saved child without query match")
        #expect(savedChild.memoId == fixture.memos[110].id)
        #expect(session.memos.map(\.instanceID) == Array(fixture.memos[2..<42]).map(\.instanceID))
        #expect(!fixture.context.changedModelsArray.contains { $0.persistentModelID == target.persistentModelID })
        withExtendedLifetime(reader) {}
    }
}

@Test(arguments: GoalMemoFetchStage.allCases) @MainActor
private func goalMemoFetchStagesCancelRefreshWithoutPublishingAndRetry(stage: GoalMemoFetchStage) async throws {
    let fixture = try GoalMemoFetchStageFixture()
    defer { withExtendedLifetime(fixture.container) {} }
    let gate = GoalMemoFetchStageGate()
    defer { gate.release() }
    let probe = GoalMemoFetchStageProbe(call: 2, stage: stage, gate: gate)
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    defer { session.cancel() }
    session.apply(query: "stage-needle", debounce: false)
    await goalMemoFetchStageWait(session)
    try goalMemoFetchStageExpect(session, context: fixture.context, depth: 1)
    let published = goalMemoFetchStageRows(session.memos, session.summaries)
    let publishedKeys = Set(session.summaries.keys)
    let position = session.readPosition
    let more = session.hasMore
    let draft = goalMemoFetchStageDraft(fixture.draft)
    session.refresh()
    try await gate.waitReached()
    #expect(probe.pausedOrdinal == stage.rawValue && session.isLoading)
    session.cancel()
    #expect(!session.isLoading && session.errorMessage == nil)
    gate.release()
    await probe.waitFinished(2)
    #expect(probe.cancelledCalls.contains(2) && !probe.returnedCalls.contains(2))
    #expect(goalMemoFetchStageRows(session.memos, session.summaries) == published)
    #expect(Set(session.summaries.keys) == publishedKeys)
    #expect(session.readPosition.depth == position.depth && session.readPosition.cursor == position.cursor)
    #expect(session.hasMore == more && session.errorMessage == nil)
    #expect(goalMemoFetchStageDraft(fixture.draft) == draft && fixture.context.hasChanges)
    session.refresh()
    await goalMemoFetchStageWait(session)
    #expect(probe.calls == 3)
    try goalMemoFetchStageExpect(session, context: fixture.context, depth: 1)
    #expect(goalMemoFetchStageDraft(fixture.draft) == draft)
}

@Test @MainActor
private func goalMemoFetchStageUnreachableGateReportsReaderCompletion() async throws {
    let fixture = try GoalMemoFetchStageFixture()
    defer { withExtendedLifetime(fixture.container) {} }
    let gate = GoalMemoFetchStageGate()
    defer { gate.release() }
    // Deliberately impossible on this dense first page. This protects the harness
    // against a future stage layout change; product correctness never uses timeouts.
    let probe = GoalMemoFetchStageProbe(call: 1, ordinal: 999, gate: gate)
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    defer { session.cancel() }
    session.apply(query: "stage-needle", debounce: false)
    do {
        try await gate.waitReached()
        Issue.record("An unreachable fetch-stage gate must report reader completion")
    } catch GoalMemoFetchStageFailure.readerFinishedBeforeCheckpoint {
        // Actual loader termination settles the gate, with no polling/sleep limit.
    }
    await goalMemoFetchStageWait(session)
    try goalMemoFetchStageExpect(session, context: fixture.context, depth: 1)
}

@MainActor
private struct GoalMemoFetchStageFixture {
    static let savedDraftContent = "saved unrelated draft"
    let container: ModelContainer
    let context: ModelContext
    let memos: [Memo]
    let items: [MemoChecklistItem]
    let draft: Memo
    let reference = Date(timeIntervalSince1970: 1_790_899_200)
    init() throws {
        let date = Date(timeIntervalSince1970: 1_790_899_200)
        container = try PlanBaseContainerFactory.makeInMemory()
        context = container.mainContext
        context.autosaveEnabled = false
        memos = (0..<125).map { index in
            let suffix = String(format: "%012x", index)
            return Memo(id: UUID(uuidString: "f0170001-0000-4000-8000-\(suffix)")!,
                instanceID: UUID(uuidString: "f0170002-0000-4000-8000-\(suffix)")!,
                content: "parent \(index)\n감사 👨‍👩‍👧‍👦", isPinned: true,
                createdAt: date.addingTimeInterval(-Double(index)),
                updatedAt: date.addingTimeInterval(-Double(index)))
        }
        items = memos.enumerated().map { index, memo in
            MemoChecklistItem(memoId: memo.id, title: "stage-needle checklist \(index)", order: 100,
                              createdAt: date, updatedAt: date)
        }
        draft = Memo(content: Self.savedDraftContent, isPinned: false,
                     createdAt: date, updatedAt: date)
        memos.reversed().forEach { context.insert($0) }
        items.forEach { context.insert($0) }
        context.insert(draft)
        try context.save()
        // This draft is outside the initial pinned batch and deliberately unsaved.
        draft.content = "unrelated unsaved draft 👨‍👩‍👧‍👦"
    }
}

private enum GoalMemoFetchStageFailure: Error { case readerFinishedBeforeCheckpoint }

@MainActor
private final class GoalMemoFetchStageGate {
    private var reached = false
    private var released = false
    private var finished = false
    private var blocked: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Error>] = []
    func pause() async {
        reached = true
        let waiting = waiters; waiters = []
        waiting.forEach { $0.resume() }
        guard !released else { return }
        await withCheckedContinuation { blocked = $0 }
    }
    func waitReached() async throws {
        guard !reached else { return }
        guard !finished else { throw GoalMemoFetchStageFailure.readerFinishedBeforeCheckpoint }
        try await withCheckedThrowingContinuation { waiters.append($0) }
    }
    func readerFinished() {
        finished = true
        guard !reached else { return }
        let waiting = waiters; waiters = []
        waiting.forEach { $0.resume(throwing: GoalMemoFetchStageFailure.readerFinishedBeforeCheckpoint) }
    }
    func release() {
        released = true
        let waiting = blocked; blocked = nil
        waiting?.resume()
    }
}

@MainActor
private final class GoalMemoFetchStageProbe {
    let gatedCall: Int
    let ordinal: Int
    let gate: GoalMemoFetchStageGate
    var calls = 0
    var cursors: [MemoQueryCursor?] = []
    var pausedOrdinal: Int?
    var invalidatedCalls: Set<Int> = []
    var cancelledCalls: Set<Int> = []
    var returnedCalls: Set<Int> = []
    private var finishedCalls: Set<Int> = []
    private var finishWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    init(call: Int, stage: GoalMemoFetchStage, gate: GoalMemoFetchStageGate) {
        gatedCall = call; ordinal = stage.rawValue; self.gate = gate
    }
    init(call: Int, ordinal: Int, gate: GoalMemoFetchStageGate) {
        gatedCall = call; self.ordinal = ordinal; self.gate = gate
    }
    func load(_ context: ModelContext, _ query: String, _ cursor: MemoQueryCursor?,
              _ checkpoint: MemoReadCheckpoint) async throws -> MemoQueryPage {
        calls += 1
        let call = calls
        cursors.append(cursor)
        defer {
            if call == gatedCall { gate.readerFinished() }
            finishedCalls.insert(call)
            finishWaiters.removeValue(forKey: call)?.forEach { $0.resume() }
        }
        var index = 0
        let instrumented = MemoReadCheckpoint {
            let current = index
            index += 1
            try await checkpoint()
            if call == self.gatedCall && current == self.ordinal {
                self.pausedOrdinal = current
                await self.gate.pause()
                // Validate/cancel again before allowing the next scanner operation.
                try await checkpoint()
            }
        }
        do {
            let page = try await MemoService.cooperativePage(in: context, query: query, cursor: cursor,
                                                            checkpoint: instrumented)
            returnedCalls.insert(call)
            return page
        } catch is MemoReadInvalidated {
            invalidatedCalls.insert(call)
            throw MemoReadInvalidated.changed
        } catch is CancellationError {
            cancelledCalls.insert(call)
            throw CancellationError()
        }
    }
    func waitFinished(_ call: Int) async {
        guard !finishedCalls.contains(call) else { return }
        await withCheckedContinuation { finishWaiters[call, default: []].append($0) }
    }
}

@MainActor
private final class GoalMemoFetchStageCompletion {
    let session: MemoQuerySession
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ session: MemoQuerySession) { self.session = session }
    func wait() async {
        guard session.isLoading else { return }
        await withCheckedContinuation { continuation = $0; observe() }
    }
    private func observe() {
        guard session.isLoading else {
            let waiting = continuation; continuation = nil
            waiting?.resume()
            return
        }
        withObservationTracking { _ = session.isLoading } onChange: { [weak self] in
            Swift.Task { @MainActor [weak self] in self?.observe() }
        }
    }
}

@MainActor
private func goalMemoFetchStageWait(_ session: MemoQuerySession) async {
    let completion = GoalMemoFetchStageCompletion(session)
    await completion.wait()
    withExtendedLifetime(completion) {}
}

private struct GoalMemoFetchStageRow: Equatable {
    let id: UUID
    let content: String
    let title: String?
    let preview: String?
    let mode: MemoEditorMode?
    let composite: Bool?
    let drawingRevision: Date?
}

@MainActor
private func goalMemoFetchStageRows(_ memos: [Memo], _ summaries: [UUID: MemoListSummary]) -> [GoalMemoFetchStageRow] {
    memos.map { memo in
        let summary = summaries[memo.instanceID]
        return GoalMemoFetchStageRow(id: memo.instanceID, content: memo.content,
            title: summary?.title, preview: summary?.preview, mode: summary?.mode,
            composite: summary?.isComposite, drawingRevision: summary?.drawingUpdatedAt)
    }
}

@MainActor
private func goalMemoFetchStageExpect(_ session: MemoQuerySession, context: ModelContext, depth: Int) throws {
    var expected: [Memo] = []
    var summaries: [UUID: MemoListSummary] = [:]
    var cursor: MemoQueryCursor?
    var more = false
    var pages = 0
    for _ in 0..<depth {
        let page = try MemoService.page(in: context, query: "stage-needle", cursor: cursor)
        expected += page.memos
        summaries.merge(page.summaries) { _, new in new }
        cursor = page.nextCursor; more = page.hasMore; pages += 1
        if !more { break }
    }
    #expect(!session.isLoading && session.errorMessage == nil)
    #expect(goalMemoFetchStageRows(session.memos, session.summaries) == goalMemoFetchStageRows(expected, summaries))
    #expect(Set(session.summaries.keys) == Set(summaries.keys))
    #expect(session.hasMore == more && session.readPosition.cursor == cursor && session.readPosition.depth == pages)
    #expect(zip(session.memos, expected).allSatisfy { $0.0 === $0.1 })
}

private struct GoalMemoFetchStageDraft: Equatable {
    let id: UUID
    let physical: UUID
    let content: String
    let mode: String
    let pinned: Bool
    let created: Date
    let updated: Date
    let superseded: Date?
}

@MainActor
private func goalMemoFetchStageDraft(_ memo: Memo) -> GoalMemoFetchStageDraft {
    GoalMemoFetchStageDraft(id: memo.id, physical: memo.instanceID, content: memo.content,
        mode: memo.preferredModeRawValue, pinned: memo.isPinned, created: memo.createdAt,
        updated: memo.updatedAt, superseded: memo.supersededAt)
}

@MainActor
private func goalMemoFetchStagePendingIDs(_ context: ModelContext) -> Set<PersistentIdentifier> {
    Set((context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray)
        .map(\.persistentModelID))
}

@MainActor
private func goalMemoFetchStageStoredDraftContent(id: UUID, fixture: GoalMemoFetchStageFixture) throws -> String {
    let reader = ModelContext(fixture.container)
    reader.autosaveEnabled = false
    defer { withExtendedLifetime(reader) {} }
    let memo = try #require(try reader.fetch(FetchDescriptor<Memo>(
        predicate: #Predicate<Memo> { $0.id == id })).first)
    return memo.content
}
#endif
