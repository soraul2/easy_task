import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func cloudKitProbeConfigurationAcceptsActivityKind() throws {
    let token = UUID()
    let configuration = try #require(CloudKitConvergenceProbe.configuration(arguments: [
        "PlanBase",
        "--cloudkit-probe-kind", "activity",
        "--cloudkit-probe-role", "writer",
        "--cloudkit-probe-token", token.uuidString
    ]))

    #expect(configuration.kind == .activity)
    #expect(configuration.token == token)
}

@Test
@MainActor
func cloudKitActivityProbeWritesReadsAndCleansOnlyItsToken() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let token = UUID()
    let commonArguments = [
        "PlanBase",
        "--cloudkit-probe-kind", "activity",
        "--cloudkit-probe-token", token.uuidString
    ]

    let write = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: commonArguments + ["--cloudkit-probe-role", "writer"],
        context: context
    ))
    let writeSnapshot = try #require(write.activitySnapshot)
    #expect(write.passed)
    #expect(writeSnapshot.matchingActivityCount == 1)
    #expect(writeSnapshot.activityDayKey == CloudKitConvergenceProbe.activityMarkerDayKey)

    let read = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: commonArguments + [
            "--cloudkit-probe-role", "reader",
            "--cloudkit-probe-timeout", "1"
        ],
        context: context
    ))
    #expect(read.passed)
    #expect(read.activitySnapshot?.activeActivityCount == 1)

    let unrelatedTaskID = UUID()
    let unrelatedDayKey = "2026-08-14"
    let unrelated = TaskCompletionActivity(
        id: TaskActivityRules.logicalID(
            taskID: unrelatedTaskID,
            activityDayKey: unrelatedDayKey
        ),
        taskId: unrelatedTaskID,
        activityDayKey: unrelatedDayKey,
        occurredAt: Date(timeIntervalSince1970: 1_786_752_000)
    )
    context.insert(unrelated)
    try context.save()

    let cleanup = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: commonArguments + ["--cloudkit-probe-role", "cleanup"],
        context: context
    ))
    #expect(cleanup.passed)
    #expect(cleanup.activitySnapshot?.totalActivityCount == 0)
    let remaining = try context.fetch(FetchDescriptor<TaskCompletionActivity>())
    #expect(remaining.map(\.instanceID) == [unrelated.instanceID])
}
