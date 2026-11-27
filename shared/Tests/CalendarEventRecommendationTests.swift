import Foundation
import Testing
import SwiftData
@testable import EasyTaskCore

@MainActor
private func recommendationEvent(_ title: String = "공장 점검", note: String? = "준비물", color: String? = "blue",
                                 updated: Double = 100) -> CalendarEvent {
    let day = DayKey.date(from: "2026-10-30")!
    return CalendarEvent(title: title, startAt: day, endAt: DayKey.addingDays(2, to: day),
                         note: note, color: color, updatedAt: Date(timeIntervalSince1970: updated))
}

@MainActor
private final class RecommendationEventSource {
    var events: [CalendarEvent]

    init(events: [CalendarEvent]) {
        self.events = events
    }
}

private func recommendationDraft(note: String? = nil) -> CalendarEventReuseDraft {
    let day = DayKey.date(from: "2026-12-31")!
    return CalendarEventReuseDraft(title: "공", startAt: day, endAt: day, note: note, color: "red")
}

@MainActor
private func loadedSession(events: [CalendarEvent]) async throws -> CalendarEventRecommendationSession {
    let session = CalendarEventRecommendationSession(fetchEvents: { events })
    session.update(title: "공", debounce: .zero)
    try await waitForRecommendations(session)
    return session
}

@MainActor
private func waitForRecommendations(_ session: CalendarEventRecommendationSession) async throws {
    for _ in 0..<100 where session.isLoading {
        try await Swift.Task.sleep(for: .milliseconds(10))
    }
    #expect(!session.isLoading)
}

@Test @MainActor
func recommendationApplicationFillsTitleAndCrossYearDurationProtectingNote() throws {
    let recommendation = try #require(CalendarEventReuseRules.recommendations(for: "공", from: [recommendationEvent()]).first)
    let original = recommendationDraft(note: "  작성 중인 메모\n")
    let applied = CalendarEventRecommendationApplication(recommendation: recommendation, draft: original)
    #expect(applied.after.title == "공장 점검")
    #expect(applied.after.startAt == original.startAt)
    #expect(DayKey.key(for: applied.after.endAt) == "2027-01-02")
    #expect(applied.after.note == original.note)
    #expect(applied.preservedExistingNote)
    #expect(applied.canReplaceNote)
    #expect(applied.canUndo)
    #expect(applied.before == original)
    let replaced = applied.replacingNote()
    #expect(replaced.after.note == "준비물")
    #expect(!replaced.canReplaceNote)
    #expect(replaced.before == original)
    // Run this test with TZ=America/Los_Angeles as well as the normal test zone:
    // the spring/fall intervals span 47/49 hours but must remain three calendar days.
    for (start, end) in [("2026-03-07", "2026-03-09"), ("2026-10-31", "2026-11-02")] {
        let day = try #require(DayKey.date(from: start))
        let draft = CalendarEventReuseDraft(title: "공", startAt: day, endAt: day)
        let applied = CalendarEventReuseRules.applying(recommendation, to: draft)
        #expect(applied.startAt == day)
        #expect(DayKey.key(for: applied.endAt) == end)
        #expect(applied.includedDayCount == 3)
    }
}

@Test @MainActor
func recommendationMemoPolicyHandlesEmptyMissingEqualAndOriginalWhitespace() throws {
    let recommendation = try #require(CalendarEventReuseRules.recommendations(for: "공", from: [recommendationEvent()]).first)
    #expect(CalendarEventReuseRules.applying(recommendation, to: recommendationDraft(note: " \n")).note == "준비물")
    let equal = CalendarEventRecommendationApplication(recommendation: recommendation, draft: recommendationDraft(note: " 준비물\n"))
    #expect(equal.after.note == " 준비물\n")
    #expect(!equal.canReplaceNote)
    #expect(!equal.preservedExistingNote)
    var noNote = recommendation
    noNote.note = nil
    let preserved = CalendarEventRecommendationApplication(recommendation: noNote, draft: recommendationDraft(note: "내 메모"))
    #expect(preserved.after.note == "내 메모")
    #expect(preserved.preservedExistingNote)
    #expect(!preserved.canReplaceNote)
    #expect(CalendarEventReuseRules.applying(noNote, to: recommendationDraft(note: " \n")).note == " \n")
}

@Test @MainActor
func recommendationNoChangeUsesVisibleValuesWithoutOfferingUndo() throws {
    let recommendation = try #require(CalendarEventReuseRules.recommendations(for: "공", from: [recommendationEvent(note: nil, color: nil)]).first)
    let draft = CalendarEventReuseDraft(title: recommendation.title, startAt: DayKey.date(from: "2026-10-30")!,
                                      endAt: DayKey.date(from: "2026-11-01")!, note: "", color: nil)
    let application = CalendarEventRecommendationApplication(recommendation: recommendation, draft: draft)
    #expect(!application.canUndo)
    #expect(application.feedback == "이미 같은 내용이 입력되어 있어요")
}

@Test @MainActor
func recommendationSearchRanksExactPrefixContainsAndNormalizesEffectiveColor() {
    let events = [recommendationEvent("점검", updated: 1), recommendationEvent("점검 준비", updated: 2),
                  recommendationEvent("공장 점검", updated: 300), recommendationEvent("공장 점검", color: nil, updated: 200),
                  recommendationEvent("공장 점검", note: "다른 메모", updated: 250)]
    let results = CalendarEventReuseRules.recommendations(for: " 점검 ", from: events)
    #expect(results.map(\.title) == ["점검", "점검 준비", "공장 점검", "공장 점검"])
    #expect(results[2].note != results[3].note)
    #expect(results.allSatisfy { $0.color == "blue" })
    #expect(CalendarEventReuseRules.recommendations(for: "검", from: events).isEmpty)
    #expect(CalendarEventReuseRules.recommendations(for: "점", from: events).count == 2)
}

@Test @MainActor
func recommendationPreparedOrderingKeepsPhysicalIDTiesAndLogicalWinners() {
    let lower = recommendationEvent("공장 이전 버전")
    lower.instanceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let middle = recommendationEvent("공장 별도 일정")
    middle.instanceID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let higher = recommendationEvent("공장 최신 버전")
    higher.id = lower.id
    higher.instanceID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    for events in [[lower, middle, higher], [higher, middle, lower]] {
        let results = CalendarEventReuseRules.recommendations(for: "공", from: events)
        #expect(results.map(\.instanceID) == [higher.instanceID, middle.instanceID])
    }
}

@Test @MainActor
func recommendationPreparedCandidatesConvergeBeforeMatchingRenamedTitles() {
    let older = recommendationEvent("Factory audit", updated: 100)
    let latest = recommendationEvent("병원 방문", updated: 200)
    latest.id = older.id
    let independent = recommendationEvent("ＦＡＣＴＯＲＹ review", updated: 150)
    let results = CalendarEventReuseRules.recommendations(for: " factory ", from: [older, independent, latest])
    #expect(results.map(\.eventID) == [independent.id])
    #expect(results.map(\.title) == ["ＦＡＣＴＯＲＹ review"])
}

@Test @MainActor
func recommendationSessionApplyReplaceUndoStaysClosedAndRestoresOriginal() async throws {
    let session = try await loadedSession(events: [recommendationEvent()])
    let original = recommendationDraft(note: "내 메모")
    #expect(session.moveSelection(by: 1))
    let selected = try #require(session.selectedRecommendation)
    var draft = try #require(session.apply(id: selected.id, to: original))
    #expect(session.state == .applied)
    #expect(session.recommendations.isEmpty)
    #expect(session.selectedID == nil)
    session.invalidateApplication(ifEdited: draft)
    #expect(session.lastApplication?.canUndo == true)
    draft = try #require(session.replacePreservedNote(in: draft))
    #expect(draft.note == "준비물")
    #expect(try #require(session.undo(in: draft)) == original)
    #expect(session.state == .dismissed)
    #expect(session.feedback == "추천 적용을 되돌렸어요")
    #expect(session.undo(in: original) == nil)
}

@Test @MainActor
func recommendationManualChangesExpireUndoAndReplacementForEveryField() async throws {
    for field in 0..<5 {
        let session = try await loadedSession(events: [recommendationEvent()])
        let id = try #require(session.recommendations.first?.id)
        var draft = try #require(session.apply(id: id, to: recommendationDraft(note: "내 메모")))
        switch field {
        case 0: draft.title += " 수정"
        case 1: draft.startAt = DayKey.addingDays(1, to: draft.startAt)
        case 2: draft.endAt = DayKey.addingDays(1, to: draft.endAt)
        case 3: draft.note = "추가 입력"
        default: draft.color = "green"
        }
        #expect(session.undo(in: draft) == nil)
        #expect(session.replacePreservedNote(in: draft) == nil)
        #expect(session.lastApplication == nil)
    }
}

@Test @MainActor
func recommendationNewInputImmediatelyRemovesOldCandidatesAndSelection() async throws {
    let session = try await loadedSession(events: [recommendationEvent(), recommendationEvent("병원 방문")])
    let previous = session.recommendations
    let oldID = try #require(session.recommendations.first?.id)
    session.moveSelection(by: 1)
    session.update(title: "병원", debounce: .milliseconds(30))
    #expect(session.recommendations.isEmpty)
    #expect(session.loadingRecommendations == previous)
    #expect(session.selectedID == nil)
    #expect(!session.moveSelection(by: 1))
    #expect(session.apply(id: oldID, to: recommendationDraft()) == nil)
    try await waitForRecommendations(session)
    #expect(session.recommendations.map(\.title) == ["병원 방문"])
    #expect(session.loadingRecommendations.isEmpty)
    #expect(session.apply(id: try #require(session.recommendations.first?.id), to: recommendationDraft()) == nil)
    session.dismissRecommendations()
    #expect(!session.isPresented)
    #expect(session.state == .dismissed)
}

@Test @MainActor
func recommendationLateFetchCannotReopenDismissedOrNewerResults() async throws {
    var continuations: [CheckedContinuation<[CalendarEvent], Error>] = []
    let session = CalendarEventRecommendationSession(fetchEvents: {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    })
    session.update(title: "공", debounce: .zero)
    for _ in 0..<100 where continuations.count < 1 { try await Swift.Task.sleep(for: .milliseconds(5)) }
    #expect(continuations.count == 1)
    session.update(title: "병원", debounce: .zero)
    for _ in 0..<100 where continuations.count < 2 { try await Swift.Task.sleep(for: .milliseconds(5)) }
    #expect(continuations.count == 2)
    guard continuations.count == 2 else { return }
    continuations[1].resume(returning: [recommendationEvent("병원 방문")])
    try await waitForRecommendations(session)
    continuations[0].resume(returning: [recommendationEvent()])
    try await Swift.Task.sleep(for: .milliseconds(10))
    #expect(session.recommendations.map(\.title) == ["병원 방문"])
    session.update(title: "공", debounce: .zero)
    try await waitForRecommendations(session)
    // The newer pool contains only the hospital event. A late older fetch must
    // not replace that pool, even when its query is requested again.
    #expect(session.state == .empty)
    #expect(continuations.count == 2)
    session.invalidateCandidates()
    for _ in 0..<100 where continuations.count < 3 { try await Swift.Task.sleep(for: .milliseconds(5)) }
    #expect(continuations.count == 3)
    session.dismissRecommendations()
    if continuations.count == 3 { continuations[2].resume(returning: [recommendationEvent()]) }
    try await Swift.Task.sleep(for: .milliseconds(10))
    #expect(session.state == .dismissed)
    #expect(session.recommendations.isEmpty)
    #expect(session.loadingRecommendations.isEmpty)
    session.update(title: "병원", debounce: .zero)
    for _ in 0..<100 where continuations.count < 4 { try await Swift.Task.sleep(for: .milliseconds(5)) }
    #expect(continuations.count == 4)
    if continuations.count == 4 { continuations[3].resume(returning: [recommendationEvent("병원 재조회")]) }
    try await waitForRecommendations(session)
    #expect(session.recommendations.map(\.title) == ["병원 재조회"])
}

@Test @MainActor
func recommendationFailureRetryAndEmptyInputHaveSeparateStates() async throws {
    enum Failure: Error { case fixture }
    var attempts = 0
    let session = CalendarEventRecommendationSession(fetchEvents: {
        attempts += 1
        if attempts == 1 { throw Failure.fixture }
        return [recommendationEvent()]
    })
    session.update(title: "공", debounce: .zero)
    try await waitForRecommendations(session)
    #expect(session.state == .failed)
    #expect(session.isPresented)
    session.retry()
    try await waitForRecommendations(session)
    #expect(session.state == .results)
    session.update(title: "없는 일정", debounce: .zero)
    try await waitForRecommendations(session)
    #expect(session.state == .empty)
    session.update(title: " \n")
    #expect(session.state == .idle)
    #expect(!session.isPresented)
}

@Test @MainActor
func recommendationSessionReusesPoolAcrossQueriesAndEquivalentResults() async throws {
    let events = [recommendationEvent("Factory audit"), recommendationEvent("병원 방문")]
    var fetches = 0
    let session = CalendarEventRecommendationSession(fetchEvents: {
        fetches += 1
        return events
    })
    session.update(title: "Factory", debounce: .zero)
    try await waitForRecommendations(session)
    #expect(fetches == 1)
    session.moveSelection(by: 1)
    let selectedID = session.selectedID
    let results = session.recommendations

    session.update(title: " ＦＡＣＴＯＲＹ ", debounce: .zero)
    #expect(session.state == .results)
    #expect(session.recommendations == results)
    #expect(session.selectedID == selectedID)
    #expect(fetches == 1)

    session.update(title: "병원", debounce: .zero)
    try await waitForRecommendations(session)
    #expect(session.recommendations.map(\.title) == ["병원 방문"])
    #expect(fetches == 1)
    session.update(title: "없는 일정", debounce: .zero)
    try await waitForRecommendations(session)
    #expect(session.state == .empty)
    session.update(title: " 없는 일정 ", debounce: .zero)
    #expect(session.state == .empty)
    #expect(fetches == 1)
}

@Test @MainActor
func recommendationEquivalentInputDoesNotRestartAnInFlightFetch() async throws {
    var continuations: [CheckedContinuation<[CalendarEvent], Error>] = []
    let session = CalendarEventRecommendationSession(fetchEvents: {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    })
    session.update(title: "Factory", debounce: .zero)
    for _ in 0..<100 where continuations.isEmpty { try await Swift.Task.sleep(for: .milliseconds(5)) }
    #expect(continuations.count == 1)
    #expect(session.state == .loading)
    session.update(title: " factory ", debounce: .zero)
    try await Swift.Task.sleep(for: .milliseconds(10))
    #expect(continuations.count == 1)
    guard continuations.count == 1 else {
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
        return
    }
    continuations[0].resume(returning: [recommendationEvent("Factory audit")])
    try await waitForRecommendations(session)
    #expect(session.recommendations.map(\.title) == ["Factory audit"])
}

@Test @MainActor
func recommendationExclusionChangesReusePoolButRecomputeCandidates() async throws {
    let first = recommendationEvent("공장 첫 일정", updated: 1)
    let second = recommendationEvent("공장 다른 일정", updated: 2)
    var fetches = 0
    let session = CalendarEventRecommendationSession(fetchEvents: {
        fetches += 1
        return [first, second]
    })
    session.update(title: "공", excludingEventID: first.id, debounce: .zero)
    try await waitForRecommendations(session)
    #expect(session.recommendations.map(\.eventID) == [second.id])
    session.update(title: "공", excludingEventID: second.id, debounce: .zero)
    try await waitForRecommendations(session)
    #expect(session.recommendations.map(\.eventID) == [first.id])
    session.update(title: "공", debounce: .zero)
    try await waitForRecommendations(session)
    #expect(Set(session.recommendations.map(\.eventID)) == Set([first.id, second.id]))
    #expect(fetches == 1)
}

@Test @MainActor
func recommendationInvalidationRefreshesModifiedAndDeletedCandidates() async throws {
    let event = recommendationEvent("공장 원래 일정")
    let source = RecommendationEventSource(events: [event])
    var fetches = 0
    let session = CalendarEventRecommendationSession(fetchEvents: {
        fetches += 1
        return source.events
    })
    session.update(title: "공", debounce: .zero)
    try await waitForRecommendations(session)
    event.title = "병원 변경 일정"
    session.update(title: "병원", debounce: .zero)
    try await waitForRecommendations(session)
    // The cached pool must be values, not live SwiftData model references.
    #expect(session.state == .empty)
    #expect(fetches == 1)
    session.invalidateCandidates()
    try await waitForRecommendations(session)
    #expect(session.recommendations.map(\.title) == ["병원 변경 일정"])
    #expect(fetches == 2)

    let oldID = try #require(session.recommendations.first?.id)
    source.events = []
    session.invalidateCandidates()
    #expect(session.state == .loading)
    #expect(session.recommendations.isEmpty)
    var draft = recommendationDraft()
    draft.title = "병원"
    #expect(session.apply(id: oldID, to: draft) == nil)
    try await waitForRecommendations(session)
    #expect(session.state == .empty)
    #expect(session.loadingRecommendations.isEmpty)
    #expect(fetches == 3)
}

@Test(arguments: [false, true]) @MainActor
func recommendationRetryAfterInvalidationFailureFetchesFreshPool(usingRetry: Bool) async throws {
    enum Failure: Error { case unavailable }
    var fetches = 0
    let session = CalendarEventRecommendationSession(fetchEvents: {
        fetches += 1
        if fetches == 2 { throw Failure.unavailable }
        return [recommendationEvent(fetches == 1 ? "공장 이전 일정" : "공장 최신 일정")]
    })
    session.update(title: "공", debounce: .zero)
    try await waitForRecommendations(session)
    session.invalidateCandidates()
    try await waitForRecommendations(session)
    #expect(session.state == .failed)
    #expect(session.recommendations.isEmpty)
    #expect(session.loadingRecommendations.isEmpty)
    if usingRetry { session.retry() }
    else { session.update(title: "공", debounce: .zero) }
    try await waitForRecommendations(session)
    #expect(fetches == 3)
    #expect(session.recommendations.map(\.title) == ["공장 최신 일정"])
}

@Test(arguments: [false, true], [false, true]) @MainActor
func recommendationInvalidationKeepsDismissedOrAppliedPanelClosed(applied: Bool, invalidating: Bool) async throws {
    var fetches = 0
    let session = CalendarEventRecommendationSession(fetchEvents: {
        fetches += 1
        return [recommendationEvent()]
    })
    session.update(title: "공", debounce: .zero)
    try await waitForRecommendations(session)
    if applied {
        let id = try #require(session.recommendations.first?.id)
        _ = try #require(session.apply(id: id, to: recommendationDraft()))
    } else {
        session.dismissRecommendations()
    }
    if invalidating { session.invalidateCandidates() }
    #expect(session.state == (applied ? .applied : .dismissed))
    #expect(!session.isPresented)
    #expect(session.recommendations.isEmpty)
    #expect(session.loadingRecommendations.isEmpty)
    #expect(fetches == 1)
    if applied { #expect(session.lastApplication?.canUndo == true) }

    session.update(title: "공", debounce: .zero)
    try await waitForRecommendations(session)
    #expect(session.state == .results)
    #expect(fetches == (invalidating ? 2 : 1))
}

@Test @MainActor
func recommendationContextRefreshesAfterCalendarSaveAndDelete() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let event = recommendationEvent("공장 이전 일정")
    try PersistenceCommandService.perform(in: context) { context.insert(event) }
    let session = CalendarEventRecommendationSession(context: context)
    session.update(title: "공", debounce: .zero)
    try await waitForRecommendations(session)
    #expect(session.recommendations.map(\.title) == ["공장 이전 일정"])

    try PersistenceCommandService.perform(in: context) {
        event.title = "공장 최신 일정"
        event.updatedAt = event.updatedAt.addingTimeInterval(1)
    }
    try await waitForRecommendations(session)
    #expect(session.recommendations.map(\.title) == ["공장 최신 일정"])
    try PersistenceCommandService.perform(in: context) { context.delete(event) }
    try await waitForRecommendations(session)
    #expect(session.state == .empty)
    #expect(session.recommendations.isEmpty)
}

@Test @MainActor
func recommendationContextKeepsPoolForMemoSaveAndRefreshesSuccessfulImport() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    try PersistenceCommandService.perform(in: context) {
        context.insert(recommendationEvent())
    }
    let session = CalendarEventRecommendationSession(context: context)
    session.update(title: "공", debounce: .zero)
    try await waitForRecommendations(session)

    // A separate local context models imported data without opening CloudKit.
    let importingContext = ModelContext(container)
    importingContext.insert(recommendationEvent("병원 가져온 일정"))
    try importingContext.save()
    _ = try MemoService.save(memo: nil, content: "추천과 무관한 메모", in: context)
    session.update(title: "병원", debounce: .zero)
    try await waitForRecommendations(session)
    #expect(session.state == .empty)

    try CloudKitSyncService.reconcileIfNeeded(
        after: CloudKitSyncEventSummary(kind: .export, isCompleted: true, succeeded: true), context: context)
    #expect(session.state == .empty)
    try CloudKitSyncService.reconcileIfNeeded(
        after: CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: true), context: context)
    try await waitForRecommendations(session)
    #expect(session.recommendations.map(\.title) == ["병원 가져온 일정"])
}
