import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func cloudKitProbeConfigurationAcceptsFocusKind() throws {
    let token = UUID()
    let configuration = try #require(CloudKitConvergenceProbe.configuration(arguments: [
        "PlanBase",
        "--cloudkit-probe-kind", "focus",
        "--cloudkit-probe-role", "writer",
        "--cloudkit-probe-token", token.uuidString
    ]))

    #expect(configuration.kind == .focus)
    #expect(configuration.token == token)
}

@Test
@MainActor
func cloudKitFocusProbeWritesReadsAndCleansOnlyItsToken() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let token = UUID()
    let commonArguments = [
        "PlanBase",
        "--cloudkit-probe-kind", "focus",
        "--cloudkit-probe-token", token.uuidString
    ]

    let write = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: commonArguments + ["--cloudkit-probe-role", "writer"],
        context: context
    ))
    let writeSnapshot = try #require(write.focusSnapshot)
    #expect(write.passed)
    #expect(writeSnapshot.matchingSessionCount == 1)
    #expect(writeSnapshot.outcomeRawValue == FocusSessionOutcome.completed.rawValue)
    #expect(writeSnapshot.focusedDurationSeconds == 300)

    let read = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: commonArguments + [
            "--cloudkit-probe-role", "reader",
            "--cloudkit-probe-timeout", "1"
        ],
        context: context
    ))
    #expect(read.passed)
    #expect(read.focusSnapshot?.activeSessionCount == 1)

    let unrelated = FocusSession(
        taskId: UUID(),
        startedAt: Date(),
        endedAt: Date().addingTimeInterval(60),
        plannedDurationSeconds: 300,
        focusedDurationSeconds: 60,
        outcome: .stopped
    )
    context.insert(unrelated)
    try context.save()

    let cleanup = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: commonArguments + ["--cloudkit-probe-role", "cleanup"],
        context: context
    ))
    #expect(cleanup.passed)
    #expect(cleanup.focusSnapshot?.totalSessionCount == 0)
    let remaining = try context.fetch(FetchDescriptor<FocusSession>())
    #expect(remaining.map(\.instanceID) == [unrelated.instanceID])
}
