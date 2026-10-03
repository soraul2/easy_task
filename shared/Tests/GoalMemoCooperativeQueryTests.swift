import Foundation
import Observation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test(arguments: ["", " \n", "CAFE", "감사", "체크 전용", "없는 검색어"]) @MainActor
func goalMemoCooperativePagesEqualSynchronousOracle(query: String) async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 650, pins: 117, longBody: true)
    fixture.context.insert(MemoChecklistItem(memoId: fixture.memos[649].id,
                                            title: "체크 전용", order: 100))
    try fixture.context.save()
    var cursor: MemoQueryCursor?
    var count = 0
    repeat {
        let expected = try MemoService.page(in: fixture.context, query: query, cursor: cursor)
        let actual = try await MemoService.cooperativePage(in: fixture.context, query: query, cursor: cursor,
            checkpoint: MemoReadCheckpoint { await Swift.Task.yield(); try Swift.Task.checkCancellation() })
        #expect(goalMemoCooperativeRows(actual.memos, actual.summaries)
                == goalMemoCooperativeRows(expected.memos, expected.summaries))
        #expect(actual.nextCursor == expected.nextCursor)
        #expect(actual.hasMore == expected.hasMore)
        #expect(zip(actual.memos, expected.memos).allSatisfy { $0.0 === $0.1 })
        cursor = actual.nextCursor
        count += 1
        #expect(count < 30)
    } while cursor != nil && count < 30
}

@Test @MainActor
func goalMemoCooperativeABADiscardsCancelledRowsAndLateErrors() async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 190)
    let probe = GoalMemoCooperativeProbe()
    let gates = (1...3).map { _ in GoalMemoCooperativeGate() }
    for index in gates.indices { probe.gates[index + 1] = gates[index] }
    probe.failAfterGate.insert(1)
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    session.apply(query: "항목", debounce: false)
    try await gates[0].waitReached()
    session.apply(query: "없는 검색어", debounce: false)
    try await gates[1].waitReached()
    session.apply(query: "항목", debounce: false)
    try await gates[2].waitReached()
    gates[2].release()
    await goalMemoCooperativeWait(session)
    try goalMemoCooperativeExpect(session, context: fixture.context, query: "항목", depth: 1)
    let current = goalMemoCooperativeRows(session.memos, session.summaries)
    gates[1].release()
    await probe.waitFinished(2)
    gates[0].release()
    await probe.waitFinished(1)
    #expect(goalMemoCooperativeRows(session.memos, session.summaries) == current)
    #expect(session.errorMessage == nil && !session.isLoading)
}

@Test @MainActor
func goalMemoCooperativeClearAndPendingSearchRefreshUseLatestRawQuery() async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 190, longBody: true)
    let probe = GoalMemoCooperativeProbe()
    let gate = GoalMemoCooperativeGate()
    probe.gates[1] = gate
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    session.apply(query: "없는 검색어", debounce: false)
    try await gate.waitReached()
    session.apply(query: " \n", debounce: true)
    session.refresh() // Consumes the pending raw query without waiting for a timer.
    await goalMemoCooperativeWait(session)
    try goalMemoCooperativeExpect(session, context: fixture.context, query: " \n", depth: 1)
    gate.release()
    await probe.waitFinished(1)
    #expect(session.errorMessage == nil && !session.isLoading)
    session.apply(query: " ＣＡＦＥ ", debounce: true)
    session.refresh()
    await goalMemoCooperativeWait(session)
    try goalMemoCooperativeExpect(session, context: fixture.context, query: " ＣＡＦＥ ", depth: 1)
}

@Test @MainActor
func goalMemoCooperativeDetectsSecondUnsavedValueOnSamePendingID() async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 190)
    let target = fixture.memos[3]
    target.content = "첫 미저장 값"
    let originalUpdatedAt = target.updatedAt
    let originalPendingIDs = Set(fixture.context.changedModelsArray.map(\.persistentModelID))
    let probe = GoalMemoCooperativeProbe()
    let gate = GoalMemoCooperativeGate()
    probe.gates[1] = gate
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    session.apply(query: "두번째", debounce: false)
    try await gate.waitReached()
    target.content = "두번째 미저장 값"
    #expect(target.updatedAt == originalUpdatedAt)
    #expect(Set(fixture.context.changedModelsArray.map(\.persistentModelID)) == originalPendingIDs)
    gate.release()
    await goalMemoCooperativeWait(session)
    #expect(probe.calls >= 2)
    try goalMemoCooperativeExpect(session, context: fixture.context, query: "두번째", depth: 1)
    #expect(session.memos.first === target)
    #expect(fixture.context.hasChanges) // Reads neither save nor flush the pending edit.
}

@Test(arguments: ["sort", "child", "child-insert", "child-delete", "drawing", "insert", "delete"]) @MainActor
func goalMemoCooperativeRestartsForRawParentAndChildChanges(kind: String) async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 210)
    fixture.memos[160].content = "needle 기존 일치"
    let item = MemoChecklistItem(memoId: fixture.memos[3].id,
                                title: kind == "child-delete" ? "needle 삭제할 자식" : "기존 자식", order: 100)
    let drawing = MemoDrawing(memoId: fixture.memos[160].id, drawingData: Data([1, 2, 3]),
                              createdAt: fixture.reference, updatedAt: fixture.reference)
    fixture.context.insert(item)
    fixture.context.insert(drawing)
    try fixture.context.save()
    let probe = GoalMemoCooperativeProbe()
    let gate = GoalMemoCooperativeGate()
    probe.gates[1] = gate
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    session.apply(query: "needle", debounce: false)
    try await gate.waitReached()
    switch kind {
    case "sort":
        fixture.memos[160].isPinned = true
        fixture.memos[160].updatedAt = fixture.reference.addingTimeInterval(20)
    case "child":
        item.title = "needle 자식만 일치"
        item.order = 200
        item.isCompleted = true
    case "child-insert":
        fixture.context.insert(MemoChecklistItem(memoId: fixture.memos[4].id,
                                                title: "needle 새 자식", order: 100))
    case "child-delete":
        fixture.context.delete(item)
    case "drawing":
        drawing.memoId = fixture.memos[3].id
        drawing.updatedAt = fixture.reference.addingTimeInterval(30)
    case "insert":
        fixture.context.insert(Memo(content: "needle 새 고정", isPinned: true,
                                    createdAt: fixture.reference, updatedAt: fixture.reference))
    default:
        fixture.context.delete(fixture.memos[160])
    }
    gate.release()
    await goalMemoCooperativeWait(session)
    #expect(probe.calls >= 2)
    try goalMemoCooperativeExpect(session, context: fixture.context, query: "needle", depth: 1)
    #expect(fixture.context.hasChanges)
}

@Test(arguments: ["command", "direct-save", "unknown-import-proxy"]) @MainActor
func goalMemoCooperativeObservesSavedAndUnknownRevisionSignals(kind: String) async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 190)
    let probe = GoalMemoCooperativeProbe()
    let gate = GoalMemoCooperativeGate()
    probe.gates[1] = gate
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    session.apply(query: "수정 일치", debounce: false)
    try await gate.waitReached()
    switch kind {
    case "command":
        try PersistenceCommandService.perform(in: fixture.context) {
            fixture.memos[3].content = "수정 일치 command"
        }
    case "direct-save":
        fixture.memos[3].content = "수정 일치 didSave"
        try fixture.context.save()
    default:
        // Unknown-domain import/legacy invalidation, without a fabricated CloudKit Event.
        NotificationCenter.default.post(name: PersistenceCommandService.dataChangedNotification,
                                         object: fixture.context)
    }
    gate.release()
    await goalMemoCooperativeWait(session)
    #expect(probe.calls >= 2)
    try goalMemoCooperativeExpect(session, context: fixture.context, query: "수정 일치", depth: 1)
}

@Test(arguments: [true, false]) @MainActor
func goalMemoCooperativeAdditionalImportRevisionRestartsOnlyWhenChanged(successful: Bool) async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 190)
    let probe = GoalMemoCooperativeProbe()
    let signal = GoalMemoCooperativeSignal()
    let gate = GoalMemoCooperativeGate()
    probe.gates[1] = gate
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load,
                                  additionalRevision: { signal.value })
    session.apply(query: "없는 검색어", debounce: false)
    try await gate.waitReached()
    // A controllable validity-provider seam models successful vs unchanged import tokens.
    // It is not a CloudKit event parser or a real account/import test.
    if successful { signal.value += 1 }
    gate.release()
    await goalMemoCooperativeWait(session)
    #expect(probe.calls == (successful ? 2 : 1))
    try goalMemoCooperativeExpect(session, context: fixture.context, query: "없는 검색어", depth: 1)
}

@Test @MainActor
func goalMemoCooperativeAppendRebuildsEntireDepthAfterSave() async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 245)
    let probe = GoalMemoCooperativeProbe()
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    session.apply(query: "", debounce: false)
    await goalMemoCooperativeWait(session)
    for _ in 0..<2 { session.loadNextPage(); await goalMemoCooperativeWait(session) }
    #expect(probe.calls == 3) // Stable-version append reads only the next page.
    let oldRows = goalMemoCooperativeRows(session.memos, session.summaries)
    let gate = GoalMemoCooperativeGate()
    probe.gates[4] = gate
    session.loadNextPage()
    try await gate.waitReached()
    #expect(goalMemoCooperativeRows(session.memos, session.summaries) == oldRows)
    fixture.memos[244].updatedAt = fixture.reference.addingTimeInterval(30)
    try fixture.context.save()
    gate.release()
    await goalMemoCooperativeWait(session)
    #expect(probe.cursors[3] != nil && probe.cursors[4] == nil)
    try goalMemoCooperativeExpect(session, context: fixture.context, query: "", depth: 4)
    #expect(Set(session.memos.map(\.instanceID)).count == 160)
}

@Test @MainActor
func goalMemoCooperativeRefreshErrorRetryKeepsDepthSelectionAndFailedDraft() async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 245)
    let probe = GoalMemoCooperativeProbe()
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    session.apply(query: "", debounce: false)
    await goalMemoCooperativeWait(session)
    for _ in 0..<4 { session.loadNextPage(); await goalMemoCooperativeWait(session) }
    let oldRows = goalMemoCooperativeRows(session.memos, session.summaries)
    let selected = try #require(session.memos.first)
    let editor = MemoEditorSession(memo: selected, context: fixture.context,
        saveComposite: { _, _, _, _, _, _ in throw CocoaError(.fileWriteUnknown) })
    editor.updateContent("보존할 편집 초안")
    #expect(!editor.flush())
    probe.failBeforeRead.insert(8) // Third page of the five-page refresh.
    session.refresh()
    await goalMemoCooperativeWait(session)
    #expect(session.errorMessage != nil)
    #expect(goalMemoCooperativeRows(session.memos, session.summaries) == oldRows)
    #expect(session.readPosition.depth == 5)
    editor.refreshFromStore()
    #expect(editor.memo === selected && editor.content == "보존할 편집 초안")
    #expect(editor.hasUnsavedChanges)
    if case .failed = editor.saveState {} else { Issue.record("Refresh changed failed draft state") }
    session.retry()
    await goalMemoCooperativeWait(session)
    try goalMemoCooperativeExpect(session, context: fixture.context, query: "", depth: 5)
    #expect(editor.memo === selected && editor.content == "보존할 편집 초안")
    #expect(editor.hasUnsavedChanges)
}

@Test @MainActor
func goalMemoCooperativeOverlappingRefreshCancelAndReturnKeepAppendDepth() async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 245)
    let probe = GoalMemoCooperativeProbe()
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    session.apply(query: "", debounce: false)
    await goalMemoCooperativeWait(session)
    for _ in 0..<2 { session.loadNextPage(); await goalMemoCooperativeWait(session) }
    let gate = GoalMemoCooperativeGate()
    probe.gates[4] = gate
    session.loadNextPage()
    try await gate.waitReached()
    fixture.memos[244].isPinned = true
    try PersistenceCommandService.perform(in: fixture.context) {}
    session.refresh()
    session.refresh() // Latest request coalesces before its work begins.
    session.cancel() // Hide while four-page target is outstanding.
    #expect(!session.isLoading && session.readPosition.depth == 3)
    session.refresh() // Return with the same four-page target.
    await goalMemoCooperativeWait(session)
    try goalMemoCooperativeExpect(session, context: fixture.context, query: "", depth: 4)
    gate.release()
    await probe.waitFinished(4)
    try goalMemoCooperativeExpect(session, context: fixture.context, query: "", depth: 4)
}

@Test @MainActor
func goalMemoCooperativeInitialAndAppendErrorsRetryWithoutLosingRows() async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 90)
    let probe = GoalMemoCooperativeProbe()
    probe.failBeforeRead = [1, 3]
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    session.apply(query: "", debounce: false)
    await goalMemoCooperativeWait(session)
    #expect(session.errorMessage != nil && session.memos.isEmpty)
    session.retry()
    await goalMemoCooperativeWait(session)
    let oldRows = goalMemoCooperativeRows(session.memos, session.summaries)
    session.loadNextPage()
    await goalMemoCooperativeWait(session)
    #expect(session.errorMessage != nil)
    #expect(goalMemoCooperativeRows(session.memos, session.summaries) == oldRows)
    session.retry()
    await goalMemoCooperativeWait(session)
    try goalMemoCooperativeExpect(session, context: fixture.context, query: "", depth: 2)
}

@Test @MainActor
func goalMemoCooperativePendingTaskDoesNotRetainSession() async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 190)
    let probe = GoalMemoCooperativeProbe()
    let gate = GoalMemoCooperativeGate()
    probe.gates[1] = gate
    var session: MemoQuerySession? = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    weak var weakSession = session
    session?.apply(query: "없는 검색어", debounce: false)
    try await gate.waitReached()
    session = nil
    #expect(weakSession == nil)
    gate.release()
    await probe.waitFinished(1)
    #expect(weakSession == nil)
}

@Test @MainActor
func goalMemoCooperativeGateFailsWhenReaderEndsBeforeItsCheckpoint() async throws {
    let fixture = try GoalMemoCooperativeFixture(count: 1)
    let probe = GoalMemoCooperativeProbe()
    let gate = GoalMemoCooperativeGate()
    probe.gates[1] = gate
    probe.failBeforeRead.insert(1)
    let session = MemoQuerySession(context: fixture.context, cooperativeLoader: probe.load)
    session.apply(query: "", debounce: false)
    do {
        try await gate.waitReached()
        Issue.record("A reader that failed before its checkpoint must not report a reached gate")
    } catch GoalMemoCooperativeGateFailure.readerFinishedBeforeCheckpoint {
        // An actual loader termination settles the harness, without a timeout
        // being used to infer product correctness or a fixed number of yields.
    }
    await goalMemoCooperativeWait(session)
    #expect(probe.calls == 1)
    #expect(session.errorMessage != nil && !session.isLoading)
    #expect(session.memos.isEmpty)
}

@MainActor
private struct GoalMemoCooperativeFixture {
    let container: ModelContainer
    let context: ModelContext
    let memos: [Memo]
    let reference = Date(timeIntervalSince1970: 1_790_899_200)

    init(count: Int, pins: Int = 0, longBody: Bool = false) throws {
        let reference = Date(timeIntervalSince1970: 1_790_899_200)
        container = try PlanBaseContainerFactory.makeInMemory()
        context = container.mainContext
        context.autosaveEnabled = false
        let body = longBody ? String(repeating: "감사 👨‍👩‍👧‍👦 감사\n", count: 100) : "공통 본문"
        memos = (0..<count).map { index in
            let suffix = String(format: "%012x", index)
            return Memo(id: UUID(uuidString: "00000001-0000-4000-8000-\(suffix)")!,
                instanceID: UUID(uuidString: "00000002-0000-4000-8000-\(suffix)")!,
                content: "항목 \(index)\n\(body)" + (index % 23 == 0 ? "\n끝의 Ｃａｆｅ\u{301}" : ""),
                isPinned: index < pins, createdAt: reference.addingTimeInterval(-Double(index)),
                updatedAt: reference.addingTimeInterval(-Double(index)))
        }
        for memo in memos.reversed() { context.insert(memo) }
        try context.save()
    }
}

@MainActor
private final class GoalMemoCooperativeSignal { var value = 0 }

private enum GoalMemoCooperativeGateFailure: Error {
    case readerFinishedBeforeCheckpoint
}

@MainActor
private final class GoalMemoCooperativeGate {
    private var reached = false
    private var released = false
    private var readerFinished = false
    private var blocked: CheckedContinuation<Void, Never>?
    private var reachWaiters: [CheckedContinuation<Void, Error>] = []

    func pause() async {
        reached = true
        let waiting = reachWaiters
        reachWaiters = []
        waiting.forEach { $0.resume() }
        guard !released else { return }
        await withCheckedContinuation { blocked = $0 }
    }
    func waitReached() async throws {
        guard !reached else { return }
        guard !readerFinished else { throw GoalMemoCooperativeGateFailure.readerFinishedBeforeCheckpoint }
        try await withCheckedThrowingContinuation { reachWaiters.append($0) }
    }
    func finishReader() {
        readerFinished = true
        guard !reached else { return }
        let waiting = reachWaiters
        reachWaiters = []
        waiting.forEach { $0.resume(throwing: GoalMemoCooperativeGateFailure.readerFinishedBeforeCheckpoint) }
    }
    func release() {
        released = true
        let waiting = blocked
        blocked = nil
        waiting?.resume()
    }
}

@MainActor
private final class GoalMemoCooperativeProbe {
    var calls = 0
    var cursors: [MemoQueryCursor?] = []
    var gates: [Int: GoalMemoCooperativeGate] = [:]
    var failBeforeRead: Set<Int> = []
    var failAfterGate: Set<Int> = []
    private var finished: Set<Int> = []
    private var finishWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func load(_ context: ModelContext, _ query: String, _ cursor: MemoQueryCursor?,
              _ checkpoint: MemoReadCheckpoint) async throws -> MemoQueryPage {
        calls += 1
        let call = calls
        cursors.append(cursor)
        defer {
            gates[call]?.finishReader()
            finished.insert(call)
            finishWaiters.removeValue(forKey: call)?.forEach { $0.resume() }
        }
        if failBeforeRead.contains(call) { throw CocoaError(.fileReadUnknown) }
        var didPause = false
        let instrumented = MemoReadCheckpoint {
            try await checkpoint()
            // Every actual reader has a first checkpoint; an append may finish
            // in fewer steps than an initial page. Do not tie the gate to a
            // scanner implementation's fourth chunk/checkpoint count.
            if !didPause, let gate = self.gates[call] {
                didPause = true
                await gate.pause()
                if self.failAfterGate.contains(call) { throw CocoaError(.fileReadUnknown) }
                try await checkpoint()
            }
        }
        return try await MemoService.cooperativePage(in: context, query: query, cursor: cursor,
                                                     checkpoint: instrumented)
    }
    func waitFinished(_ call: Int) async {
        guard !finished.contains(call) else { return }
        await withCheckedContinuation { finishWaiters[call, default: []].append($0) }
    }
}

@MainActor
private final class GoalMemoCooperativeCompletion {
    let session: MemoQuerySession
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ session: MemoQuerySession) { self.session = session }
    func wait() async {
        guard session.isLoading else { return }
        await withCheckedContinuation { continuation = $0; observe() }
    }
    private func observe() {
        guard session.isLoading else {
            let waiting = continuation
            continuation = nil
            waiting?.resume()
            return
        }
        withObservationTracking { _ = session.isLoading } onChange: { [weak self] in
            Swift.Task { @MainActor [weak self] in self?.observe() }
        }
    }
}

@MainActor
private func goalMemoCooperativeWait(_ session: MemoQuerySession) async {
    await GoalMemoCooperativeCompletion(session).wait()
}

private struct GoalMemoCooperativeRow: Equatable {
    let id: UUID
    let content: String
    let title: String?
    let preview: String?
    let mode: MemoEditorMode?
    let composite: Bool?
    let drawingRevision: Date?
}

@MainActor
private func goalMemoCooperativeRows(_ memos: [Memo], _ summaries: [UUID: MemoListSummary]) -> [GoalMemoCooperativeRow] {
    memos.map { memo in
        let summary = summaries[memo.instanceID]
        return GoalMemoCooperativeRow(id: memo.instanceID, content: memo.content,
            title: summary?.title, preview: summary?.preview, mode: summary?.mode,
            composite: summary?.isComposite, drawingRevision: summary?.drawingUpdatedAt)
    }
}

@MainActor
private func goalMemoCooperativeExpect(_ session: MemoQuerySession, context: ModelContext,
                                       query: String, depth: Int) throws {
    var expected: [Memo] = []
    var summaries: [UUID: MemoListSummary] = [:]
    var cursor: MemoQueryCursor?
    var more = false
    var pages = 0
    for _ in 0..<depth {
        let page = try MemoService.page(in: context, query: query, cursor: cursor)
        expected += page.memos
        summaries.merge(page.summaries) { _, new in new }
        cursor = page.nextCursor
        more = page.hasMore
        pages += 1
        if !more { break }
    }
    #expect(session.errorMessage == nil && !session.isLoading)
    #expect(goalMemoCooperativeRows(session.memos, session.summaries) == goalMemoCooperativeRows(expected, summaries))
    #expect(Set(session.summaries.keys) == Set(summaries.keys))
    #expect(session.hasMore == more && session.readPosition.cursor == cursor)
    #expect(session.readPosition.depth == pages)
    #expect(zip(session.memos, expected).allSatisfy { $0.0 === $0.1 })
}
