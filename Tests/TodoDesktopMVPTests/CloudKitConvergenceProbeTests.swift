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
func cloudKitProbeParsesConflictKindAndVariant() throws {
    let token = UUID()
    let configuration = try #require(CloudKitConvergenceProbe.configuration(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-kind", "conflict",
            "--cloudkit-probe-role", "writer",
            "--cloudkit-probe-token", token.uuidString,
            "--cloudkit-probe-variant", "newer",
            "--cloudkit-probe-wait-for-export"
        ]
    ))

    #expect(configuration == CloudKitProbeConfiguration(
        kind: .conflict,
        role: .writer,
        token: token,
        conflictVariant: .newer,
        waitsForExport: true
    ))
}

@Test
func cloudKitProbeRejectsMalformedExplicitArgumentsWithoutOpeningNormalApp() {
    let arguments = [
        "EasyTask",
        "--cloudkit-probe-kind", "unsupported",
        "--cloudkit-probe-role", "reader",
        "--cloudkit-probe-token", UUID().uuidString
    ]

    #expect(CloudKitConvergenceProbe.isProbeInvocation(arguments: arguments))
    #expect(CloudKitConvergenceProbe.configuration(arguments: arguments) == nil)
    #expect(!CloudKitConvergenceProbe.isProbeInvocation(arguments: ["EasyTask"]))
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

@Test
@MainActor
func cloudKitMediaProbeVerifiesImageBytesAndCleansGraph() async throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let token = UUID()

    let writeResult = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-kind", "media",
            "--cloudkit-probe-role", "writer",
            "--cloudkit-probe-token", token.uuidString
        ],
        context: context,
        sourceBundleIdentifier: "probe.media.writer"
    ))
    let writeSnapshot = try #require(writeResult.mediaSnapshot)
    #expect(writeResult.passed)
    #expect(writeSnapshot.sourceBundleIdentifier == "probe.media.writer")
    #expect(writeSnapshot.matchingReviewCount == 1)
    #expect(writeSnapshot.matchingAttachmentCount == 1)
    #expect(writeSnapshot.conflictingDayReviewCount == 0)
    #expect(writeSnapshot.attachmentByteCount == 68)
    #expect(writeSnapshot.attachmentSHA256 ==
        "431ced6916a2a21a156e38701afe55bbd7f88969fbbfc56d7fe099d47f265460")
    #expect(writeSnapshot.attachmentOrder == 0)
    #expect(writeSnapshot.dataMatchesExpected)

    let attachment = try #require(context.fetch(
        FetchDescriptor<DiaryAttachment>()
    ).first)
    let inspected = try DiaryAttachmentService.inspect(attachment.data)
    #expect(inspected.sha256 == writeSnapshot.attachmentSHA256)
    #expect(inspected.byteCount == writeSnapshot.attachmentByteCount)

    let readResult = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-kind", "media",
            "--cloudkit-probe-role", "reader",
            "--cloudkit-probe-token", token.uuidString,
            "--cloudkit-probe-timeout", "1"
        ],
        context: context
    ))
    #expect(readResult.passed)

    let cleanupResult = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-kind", "media",
            "--cloudkit-probe-role", "cleanup",
            "--cloudkit-probe-token", token.uuidString
        ],
        context: context
    ))
    #expect(cleanupResult.passed)
    #expect(try context.fetch(FetchDescriptor<DailyReview>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<DiaryAttachment>()).isEmpty)
}

@Test
@MainActor
func cloudKitMediaProbeRefusesOccupiedDayWithoutMutation() async throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let existing = DailyReview(
        dayKey: CloudKitConvergenceProbe.mediaMarkerDayKey,
        content: "사용자 회고"
    )
    context.insert(existing)
    try context.save()

    let result = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-kind", "media",
            "--cloudkit-probe-role", "writer",
            "--cloudkit-probe-token", UUID().uuidString
        ],
        context: context
    ))

    #expect(!result.passed)
    #expect(result.error == "Media probe day is occupied")
    #expect(try context.fetch(FetchDescriptor<DailyReview>()).map(\.content) == ["사용자 회고"])
    #expect(try context.fetch(FetchDescriptor<DiaryAttachment>()).isEmpty)
}

@Test
@MainActor
func cloudKitMediaCleanupPreservesAttachmentWithWrongOwner() async throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let token = UUID()
    let data = try #require(Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    ))
    let metadata = try DiaryAttachmentService.inspect(data)
    let attachment = DiaryAttachment(
        id: token,
        reviewId: UUID(),
        order: 0,
        originalFileName: "easytask-cloudkit-probe-\(token.uuidString.lowercased()).png",
        mimeType: metadata.mediaType.rawValue,
        byteCount: metadata.byteCount,
        sha256: metadata.sha256,
        data: data
    )
    context.insert(attachment)
    try context.save()

    let result = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-kind", "media",
            "--cloudkit-probe-role", "cleanup",
            "--cloudkit-probe-token", token.uuidString
        ],
        context: context
    ))

    #expect(!result.passed)
    #expect(try context.fetch(FetchDescriptor<DiaryAttachment>()).count == 1)
}

@Test
@MainActor
func cloudKitConflictProbeConvergesOnDeterministicNewerVariant() async throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let token = UUID()

    for (variant, source) in [
        (CloudKitConflictVariant.older, "probe.macos"),
        (.newer, "probe.ios")
    ] {
        let result = try #require(await CloudKitConvergenceProbe.runIfRequested(
            arguments: [
                "EasyTask",
                "--cloudkit-probe-kind", "conflict",
                "--cloudkit-probe-role", "writer",
                "--cloudkit-probe-token", token.uuidString,
                "--cloudkit-probe-variant", variant.rawValue
            ],
            context: context,
            sourceBundleIdentifier: source
        ))
        #expect(result.passed)
    }

    let readResult = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-kind", "conflict",
            "--cloudkit-probe-role", "reader",
            "--cloudkit-probe-token", token.uuidString,
            "--cloudkit-probe-timeout", "1"
        ],
        context: context
    ))
    let snapshot = try #require(readResult.conflictSnapshot)
    #expect(readResult.passed)
    #expect(Set(snapshot.observedVariants) == Set(CloudKitConflictVariant.allCases))
    #expect(snapshot.winningVariant == .newer)
    #expect(snapshot.sourceBundleIdentifier == "probe.ios")
    #expect(snapshot.totalMarkerCount == 2)
    #expect(snapshot.activeMarkerCount == 1)

    let records = try context.fetch(FetchDescriptor<CalendarEvent>())
    #expect(records.count == 2)
    #expect(records.filter { $0.supersededAt == nil }.count == 1)

    let cleanupResult = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-kind", "conflict",
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
func cloudKitConflictReaderRejectsCollisionBeforeReconciliation() async throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let token = UUID()
    let markerDate = try #require(DayKey.date(from: "2099-12-29"))
    let baseTimestamp = Date(timeIntervalSince1970: 4_102_444_800)
    context.insert(CalendarEvent(
        id: token,
        title: CloudKitConvergenceProbe.conflictMarkerTitle,
        startAt: markerDate,
        endAt: markerDate,
        note: "\(token.uuidString)|older|probe.macos",
        createdAt: baseTimestamp,
        updatedAt: baseTimestamp.addingTimeInterval(10)
    ))
    context.insert(CalendarEvent(
        id: token,
        title: "사용자 일정",
        startAt: markerDate,
        endAt: markerDate,
        createdAt: baseTimestamp,
        updatedAt: baseTimestamp.addingTimeInterval(30)
    ))
    try context.save()

    let result = try #require(await CloudKitConvergenceProbe.runIfRequested(
        arguments: [
            "EasyTask",
            "--cloudkit-probe-kind", "conflict",
            "--cloudkit-probe-role", "reader",
            "--cloudkit-probe-token", token.uuidString,
            "--cloudkit-probe-timeout", "1"
        ],
        context: context
    ))

    #expect(!result.passed)
    #expect(result.error == "Conflict probe token collides with a user event")
    let records = try context.fetch(FetchDescriptor<CalendarEvent>())
    #expect(records.count == 2)
    #expect(records.allSatisfy { $0.supersededAt == nil })
}

@Test
@MainActor
func extendedProbeCleanupPreservesNonMarkerCollisions() async throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let mediaToken = UUID()
    let conflictToken = UUID()
    context.insert(DailyReview(
        id: mediaToken,
        dayKey: "2026-07-12",
        content: "사용자 회고"
    ))
    let date = try #require(DayKey.date(from: "2026-07-12"))
    context.insert(CalendarEvent(
        id: conflictToken,
        title: "사용자 일정",
        startAt: date,
        endAt: date
    ))
    try context.save()

    for (kind, token) in [
        (CloudKitProbeKind.media, mediaToken),
        (.conflict, conflictToken)
    ] {
        let result = try #require(await CloudKitConvergenceProbe.runIfRequested(
            arguments: [
                "EasyTask",
                "--cloudkit-probe-kind", kind.rawValue,
                "--cloudkit-probe-role", "cleanup",
                "--cloudkit-probe-token", token.uuidString
            ],
            context: context
        ))
        #expect(!result.passed)
    }

    #expect(try context.fetch(FetchDescriptor<DailyReview>()).map(\.content) == ["사용자 회고"])
    #expect(try context.fetch(FetchDescriptor<CalendarEvent>()).map(\.title) == ["사용자 일정"])
}
