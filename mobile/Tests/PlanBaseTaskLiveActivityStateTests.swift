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
}
