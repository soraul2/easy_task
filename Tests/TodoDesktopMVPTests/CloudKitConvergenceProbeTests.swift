import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func cloudKitProbeParsesExplicitArguments() throws {
    let token = UUID()
    let configuration = try #require(CloudKitConvergenceProbe.configuration(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-role", "reader",
            "--cloudkit-probe-token", token.uuidString,
            "--cloudkit-probe-expect", "absent",
            "--cloudkit-probe-timeout", "45",
            "--cloudkit-probe-exit"
        ]
    ))

    #expect(configuration == CloudKitProbeConfiguration(
        role: .reader,
        token: token,
        expectation: .absent,
        timeoutSeconds: 45,
        exitsWhenFinished: true
    ))
    #expect(CloudKitConvergenceProbe.configuration(arguments: ["EasyTask"]) == nil)
}

@Test
@MainActor
func cloudKitProbeWriterReaderAndCleanupLifecycle() async throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let token = UUID()

    let writeResult = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-role", "writer",
            "--cloudkit-probe-token", token.uuidString
        ],
        context: context,
        sourceBundleIdentifier: "probe.writer"
    ))
    #expect(writeResult.passed)
    #expect(writeResult.snapshot?.sourceBundleIdentifier == "probe.writer")

    let readResult = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-role", "reader",
            "--cloudkit-probe-token", token.uuidString,
            "--cloudkit-probe-expect", "present",
            "--cloudkit-probe-timeout", "1"
        ],
        context: context
    ))
    #expect(readResult.passed)

    let cleanupResult = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-role", "cleanup",
            "--cloudkit-probe-token", token.uuidString
        ],
        context: context
    ))
    #expect(cleanupResult.passed)
    #expect(try context.fetch(FetchDescriptor<CalendarEvent>()).isEmpty)
}

@Test
@MainActor
func cloudKitProbeCleanupNeverDeletesNonMarkerCollision() async throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let token = UUID()
    let date = try #require(DayKey.date(from: "2099-12-31"))
    let userEvent = CalendarEvent(
        id: token,
        title: "사용자 일정",
        startAt: date,
        endAt: date
    )
    context.insert(userEvent)
    try context.save()

    let result = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-role", "cleanup",
            "--cloudkit-probe-token", token.uuidString
        ],
        context: context
    ))

    #expect(!result.passed)
    #expect(try context.fetch(FetchDescriptor<CalendarEvent>()).map(\.title) == ["사용자 일정"])
}
