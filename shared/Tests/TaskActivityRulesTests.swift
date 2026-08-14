import Foundation
import Testing
@testable import EasyTaskCore

@Test
func taskActivityLogicalIDUsesStableUUIDV8Encoding() throws {
    let taskID = try #require(UUID(
        uuidString: "00000000-0000-0000-0000-000000000001"
    ))
    let expected = try #require(UUID(
        uuidString: "5D1A849F-FD16-8314-9C19-BF2C11B2192C"
    ))

    let logicalID = TaskActivityRules.logicalID(
        taskID: taskID,
        activityDayKey: "2026-08-14"
    )

    #expect(logicalID == expected)
    #expect(logicalID.uuidString.split(separator: "-")[2].first == "8")
    #expect(["8", "9", "A", "B"].contains(
        String(logicalID.uuidString.split(separator: "-")[3].first ?? "0")
    ))
}

@Test
func legacyActivityDayKeyUsesUTCAndCompletionToleranceIsBounded() {
    let date = Date(timeIntervalSince1970: 1_786_751_400)

    #expect(TaskActivityRules.legacyDayKey(for: date) == "2026-08-14")
    #expect(TaskActivityRules.representsSameCompletion(
        date,
        date.addingTimeInterval(1)
    ))
    #expect(!TaskActivityRules.representsSameCompletion(
        date,
        date.addingTimeInterval(1.001)
    ))
}
