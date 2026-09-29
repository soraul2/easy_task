import XCTest
@testable import PlanBase

final class PlanBaseTaskLiveActivityStateTests: XCTestCase {
    func testLegacyPayloadStillDecodesAsDoingWithOriginalTimerWireKey() throws {
        let id = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "taskSessionID": "legacy", "taskID": id.uuidString,
            "title": "이전 진행 작업", "completedCount": 1, "totalCount": 3,
            "hasNextTask": true, "requiresCompletionConfirmation": false,
            "updatedAt": 12345.0
        ])
        let state = try JSONDecoder().decode(PlanBaseTaskActivityAttributes.ContentState.self, from: data)
        XCTAssertFalse(state.isTodo)
        XCTAssertFalse(state.isFocusSession)
        XCTAssertEqual(state.elapsedTimerStartedAt, Date(timeIntervalSinceReferenceDate: 12345))
        XCTAssertEqual(state.taskID, id)
    }

    func testTodoPayloadRoundTripsAndKeepsUpdatedAtWireCompatibility() throws {
        let state = PlanBaseTaskActivityAttributes.ContentState(
            taskSessionID: "selection:revision", taskID: UUID(), title: "할 일",
            completedCount: 2, totalCount: 3, hasNextTask: false,
            requiresCompletionConfirmation: false,
            elapsedTimerStartedAt: Date(timeIntervalSinceReferenceDate: 54321), taskStatusRawValue: "todo")
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PlanBaseTaskActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, state)
        XCTAssertTrue(decoded.isTodo)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["updatedAt"])
        XCTAssertNil(json["elapsedTimerStartedAt"])
    }

    func testFocusHasPriorityOverOrdinaryTaskStatus() {
        let state = PlanBaseTaskActivityAttributes.ContentState(
            taskSessionID: "focus", taskID: UUID(), title: "집중", completedCount: 0, totalCount: 0,
            hasNextTask: false, requiresCompletionConfirmation: false, elapsedTimerStartedAt: Date(),
            taskStatusRawValue: "todo", focusSessionID: UUID(), focusRevision: 1)
        XCTAssertTrue(state.isFocusSession)
        XCTAssertFalse(state.isTodo)
    }

    func testLegacyAttributesDecodeWithoutCreationDate() throws {
        let data = try JSONSerialization.data(withJSONObject: ["activityID": UUID().uuidString, "dayKey": "2026-09-17"])
        let attributes = try JSONDecoder().decode(PlanBaseTaskActivityAttributes.self, from: data)
        XCTAssertNil(attributes.createdAt)
        XCTAssertEqual(attributes.dayKey, "2026-09-17")
    }
    private func timerState(focus: Bool = false, overrides: [String: Any] = [:]) throws -> PlanBaseTaskActivityAttributes.ContentState {
        var json: [String: Any] = [
            "taskSessionID": "task-session", "taskID": "00000000-0000-4000-8000-000000000001",
            "title": "테스트", "completedCount": 0, "totalCount": 2,
            "hasNextTask": true, "requiresCompletionConfirmation": false, "updatedAt": 1000.0,
            "taskStatusRawValue": "doing"
        ]
        if focus {
            json.merge([
                "focusSessionID": "00000000-0000-4000-8000-000000000002", "focusRevision": 1,
                "focusPhaseRawValue": "focus", "focusRunStateRawValue": "running", "focusDeadline": 1300.0
            ]) { _, new in new }
        }
        json.merge(overrides) { _, new in new }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return try decoder.decode(PlanBaseTaskActivityAttributes.ContentState.self,
                                  from: JSONSerialization.data(withJSONObject: json))
    }

    func testOrdinaryTimerUsesUnboundedStartIncludingLongAccumulatedTime() throws {
        for start in [1000.0, -3600, -36000, -360000] {
            let state = try timerState(overrides: ["updatedAt": start])
            XCTAssertEqual(state.timerPresentation, .elapsed(startedAt: Date(timeIntervalSinceReferenceDate: start)))
        }
        XCTAssertEqual(try timerState(overrides: ["taskStatusRawValue": "todo"]).timerPresentation, .todo)
        XCTAssertEqual(try timerState(overrides: ["taskStatusRawValue": NSNull()]).timerPresentation,
                       .elapsed(startedAt: Date(timeIntervalSinceReferenceDate: 1000)))
    }

    func testFocusUsesFixedPhaseIntervalEvenWhenDeadlineIsInThePast() throws {
        for phase in ["focus", "breakTime"] {
            let state = try timerState(focus: true, overrides: ["focusPhaseRawValue": phase, "taskStatusRawValue": "todo"])
            XCTAssertEqual(state.timerPresentation,
                           .countdown(interval: Date(timeIntervalSinceReferenceDate: 1000)...Date(timeIntervalSinceReferenceDate: 1300)))
            // No Date.now is involved: a late render keeps the original upper bound (native Text clamps to zero).
        }
    }

    func testPauseAndResumeChangeIdentityAndPreserveOriginalPhaseStart() throws {
        let running = try timerState(focus: true)
        let paused = try timerState(focus: true, overrides: [
            "focusRevision": 2, "focusRunStateRawValue": "paused", "focusDeadline": NSNull(),
            "focusRemainingSecondsAtPause": 123.25
        ])
        let resumed = try timerState(focus: true, overrides: ["focusRevision": 3, "focusDeadline": 1400.0])
        XCTAssertEqual(paused.timerPresentation, .paused(remainingSeconds: 123.25))
        XCTAssertEqual(resumed.elapsedTimerStartedAt, running.elapsedTimerStartedAt)
        XCTAssertNotEqual(running.timerIdentity, paused.timerIdentity)
        XCTAssertNotEqual(paused.timerIdentity, resumed.timerIdentity)
        XCTAssertEqual(resumed.timerPresentation,
                       .countdown(interval: running.elapsedTimerStartedAt...Date(timeIntervalSinceReferenceDate: 1400)))
    }

    func testZeroRemainderAndZeroLengthCountdownAreValid() throws {
        XCTAssertEqual(try timerState(focus: true, overrides: ["focusDeadline": 1000.0]).timerPresentation,
                       .countdown(interval: Date(timeIntervalSinceReferenceDate: 1000)...Date(timeIntervalSinceReferenceDate: 1000)))
        XCTAssertEqual(try timerState(focus: true, overrides: [
            "focusRunStateRawValue": "paused", "focusDeadline": NSNull(), "focusRemainingSecondsAtPause": 0.0
        ]).timerPresentation, .paused(remainingSeconds: 0))
    }

    func testInvalidFocusPayloadNeverFallsBackToPausedZeroOrOrdinaryTimer() throws {
        let invalid: [[String: Any]] = [
            ["focusSessionID": NSNull()], ["focusRevision": NSNull()], ["focusRevision": 0],
            ["focusPhaseRawValue": "unknown"], ["focusRunStateRawValue": "stopped"],
            ["focusRunStateRawValue": NSNull()], ["focusDeadline": NSNull()], ["focusDeadline": 999.0],
            ["focusRemainingSecondsAtPause": 10.0],
            ["focusRunStateRawValue": "paused", "focusDeadline": NSNull()],
            ["focusRunStateRawValue": "paused", "focusRemainingSecondsAtPause": 10.0],
            ["focusRunStateRawValue": "paused", "focusDeadline": NSNull(), "focusRemainingSecondsAtPause": Double.greatestFiniteMagnitude],
            ["focusRunStateRawValue": "paused", "focusDeadline": NSNull(), "focusRemainingSecondsAtPause": -1.0]
        ]
        for overrides in invalid {
            guard case .invalid = try timerState(focus: true, overrides: overrides).timerPresentation else {
                return XCTFail("Accepted invalid payload: \(overrides)")
            }
        }
        guard case .invalid = try timerState(overrides: ["focusDeadline": 1300.0]).timerPresentation else {
            return XCTFail("Partial Focus became an ordinary timer")
        }
    }

    func testTimerIdentityIgnoresNonTimerUpdatesButTracksTaskAndRevision() throws {
        let ordinary = try timerState()
        XCTAssertEqual(ordinary.timerIdentity, try timerState(overrides: ["title": "다른 제목", "completedCount": 1, "themeID": "other"]).timerIdentity)
        XCTAssertNotEqual(ordinary.timerIdentity, try timerState(overrides: ["taskSessionID": "next-selection"]).timerIdentity)
        XCTAssertNotEqual(ordinary.timerIdentity, try timerState(overrides: ["taskID": UUID().uuidString]).timerIdentity)
        XCTAssertNotEqual(ordinary.timerIdentity, try timerState(overrides: ["updatedAt": 900.0]).timerIdentity)
        XCTAssertNotEqual(try timerState(focus: true).timerIdentity,
                          try timerState(focus: true, overrides: ["focusRevision": 2]).timerIdentity)
    }

    func testNonfiniteTimesAreInvalid() throws {
        for value in ["Infinity", "-Infinity", "NaN"] {
            for overrides: [String: Any] in [
                ["updatedAt": value], ["focusDeadline": value],
                ["focusRunStateRawValue": "paused", "focusDeadline": NSNull(), "focusRemainingSecondsAtPause": value]
            ] {
                guard case .invalid = try timerState(focus: true, overrides: overrides).timerPresentation else {
                    return XCTFail("Accepted nonfinite time")
                }
            }
        }
    }

    func testPresentationDoesNotAddWireKeys() throws {
        let state = try timerState(focus: true)
        _ = state.timerPresentation
        _ = state.timerIdentity
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        XCTAssertNil(json["timerPresentation"])
        XCTAssertNil(json["timerIdentity"])
        XCTAssertNil(json["elapsedTimerStartedAt"])
        XCTAssertEqual(json["updatedAt"] as? Double, 1000)
    }

}
