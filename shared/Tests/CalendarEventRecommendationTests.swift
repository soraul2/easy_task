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
    let oldID = try #require(session.recommendations.first?.id)
    session.moveSelection(by: 1)
    session.update(title: "병원", debounce: .milliseconds(30))
    #expect(session.recommendations.isEmpty)
    #expect(session.selectedID == nil)
    #expect(session.apply(id: oldID, to: recommendationDraft()) == nil)
    try await waitForRecommendations(session)
    #expect(session.recommendations.map(\.title) == ["병원 방문"])
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
    for _ in 0..<100 where continuations.count < 3 { try await Swift.Task.sleep(for: .milliseconds(5)) }
    session.dismissRecommendations()
    if continuations.count == 3 { continuations[2].resume(returning: [recommendationEvent()]) }
    try await Swift.Task.sleep(for: .milliseconds(10))
    #expect(session.state == .dismissed)
    #expect(session.recommendations.isEmpty)
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
