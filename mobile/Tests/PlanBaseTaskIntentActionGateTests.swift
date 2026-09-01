import XCTest
@testable import PlanBase

final class PlanBaseTaskIntentActionGateTests: XCTestCase {
    func testSecondLockScreenActionDuringTransitionIsRejected() {
        let firstTap = Date(timeIntervalSinceReferenceDate: 1_000)
        var gate = PlanBaseTaskIntentActionGate(minimumInterval: 1)

        XCTAssertTrue(gate.canAccept(at: firstTap))
        gate.recordAccepted(at: firstTap)

        XCTAssertFalse(gate.canAccept(at: firstTap.addingTimeInterval(0.25)))
    }

    func testActionIsAcceptedAfterTransitionInterval() {
        let firstTap = Date(timeIntervalSinceReferenceDate: 1_000)
        var gate = PlanBaseTaskIntentActionGate(minimumInterval: 1)

        gate.recordAccepted(at: firstTap)

        XCTAssertTrue(gate.canAccept(at: firstTap.addingTimeInterval(1)))
    }

    func testFailedActionDoesNotCloseGateUntilItIsRecorded() {
        let firstAttempt = Date(timeIntervalSinceReferenceDate: 1_000)
        let retry = firstAttempt.addingTimeInterval(0.1)
        var gate = PlanBaseTaskIntentActionGate(minimumInterval: 1)

        XCTAssertTrue(gate.canAccept(at: firstAttempt))
        XCTAssertTrue(gate.canAccept(at: retry))
    }
}
