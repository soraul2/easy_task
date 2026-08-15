import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func cloudKitProbeConfigurationAcceptsProgressKind() throws {
    let token = UUID()
    let configuration = try #require(CloudKitConvergenceProbe.configuration(arguments: [
        "PlanBase",
        "--cloudkit-probe-kind", "progress",
        "--cloudkit-probe-role", "writer",
        "--cloudkit-probe-token", token.uuidString
    ]))

    #expect(configuration.kind == .progress)
    #expect(configuration.token == token)
}

@Test
@MainActor
func cloudKitProgressProbeWritesReadsAndCleansOnlyItsToken() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let token = UUID()
    let commonArguments = [
        "PlanBase",
        "--cloudkit-probe-kind", "progress",
        "--cloudkit-probe-token", token.uuidString
    ]

    let write = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: commonArguments + ["--cloudkit-probe-role", "writer"],
        context: context
    ))
    let writeSnapshot = try #require(write.progressSnapshot)
    #expect(write.passed)
    #expect(writeSnapshot.matchingEventCount == 1)
    #expect(writeSnapshot.kindRawValue == TaskProgressEventKind.started.rawValue)

    let read = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: commonArguments + [
            "--cloudkit-probe-role", "reader",
            "--cloudkit-probe-timeout", "1"
        ],
        context: context
    ))
    #expect(read.passed)
    #expect(read.progressSnapshot?.activeEventCount == 1)

    let unrelated = TaskProgressEvent(
        taskId: UUID(),
        kind: .started,
        occurredAt: Date()
    )
    context.insert(unrelated)
    try context.save()

    let cleanup = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: commonArguments + ["--cloudkit-probe-role", "cleanup"],
        context: context
    ))
    #expect(cleanup.passed)
    #expect(cleanup.progressSnapshot?.totalEventCount == 0)
    let remaining = try context.fetch(FetchDescriptor<TaskProgressEvent>())
    #expect(remaining.map(\.instanceID) == [unrelated.instanceID])
}
