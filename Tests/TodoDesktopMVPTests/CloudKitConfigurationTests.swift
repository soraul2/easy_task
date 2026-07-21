import CloudKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func cloudKitSyncMonitorTracksProgressSuccessAndFailure() {
    let monitor = CloudKitSyncMonitor()
    let successDate = Date(timeIntervalSince1970: 1234)
    let importID = UUID()

    monitor.record(CloudKitSyncEventSummary(
        identifier: importID,
        kind: .import,
        isCompleted: false,
        succeeded: false
    ))
    #expect(monitor.isSyncing)

    monitor.record(CloudKitSyncEventSummary(
        identifier: importID,
        kind: .import,
        isCompleted: true,
        succeeded: true
    ), at: successDate)
    #expect(!monitor.isSyncing)
    #expect(monitor.lastSuccessfulSyncAt == successDate)
    #expect(monitor.lastErrorDescription == nil)

    monitor.record(CloudKitSyncEventSummary(
        kind: .export,
        isCompleted: true,
        succeeded: false,
        errorDescription: "네트워크 오류"
    ))
    #expect(monitor.lastSuccessfulSyncAt == successDate)
    #expect(monitor.lastErrorDescription == "네트워크 오류")
}

@Test
@MainActor
func cloudKitSyncMonitorKeepsConcurrentOperationsAndErrorsIndependent() {
    let monitor = CloudKitSyncMonitor()
    let importID = UUID()
    let exportID = UUID()

    monitor.record(CloudKitSyncEventSummary(
        identifier: importID,
        kind: .import,
        isCompleted: false,
        succeeded: false
    ))
    monitor.record(CloudKitSyncEventSummary(
        identifier: exportID,
        kind: .export,
        isCompleted: false,
        succeeded: false
    ))

    monitor.record(CloudKitSyncEventSummary(
        identifier: importID,
        kind: .import,
        isCompleted: true,
        succeeded: true
    ))
    #expect(monitor.isSyncing)

    monitor.record(CloudKitSyncEventSummary(
        identifier: exportID,
        kind: .export,
        isCompleted: true,
        succeeded: false,
        errorDescription: "내보내기 실패"
    ))
    #expect(!monitor.isSyncing)
    #expect(monitor.syncErrorDescription == "내보내기 실패")

    monitor.record(CloudKitSyncEventSummary(
        kind: .setup,
        isCompleted: true,
        succeeded: true
    ))
    #expect(monitor.syncErrorDescription == "내보내기 실패")
}

@Test
@MainActor
func cloudKitSyncSuccessDoesNotHideUnrelatedDataIssue() {
    let monitor = CloudKitSyncMonitor()
    monitor.recordIssue("이전 회고 이미지 정리가 필요합니다")

    monitor.record(CloudKitSyncEventSummary(
        kind: .export,
        isCompleted: true,
        succeeded: true
    ))

    #expect(monitor.lastErrorDescription == "이전 회고 이미지 정리가 필요합니다")
}

@Test
func cloudKitPartialFailureSurfacesQuotaExceededCause() {
    let quotaError = NSError(
        domain: CKErrorDomain,
        code: CKError.Code.quotaExceeded.rawValue
    )
    let partialError = NSError(
        domain: CKErrorDomain,
        code: CKError.Code.partialFailure.rawValue,
        userInfo: [
            CKPartialErrorsByItemIDKey: [AnyHashable("record"): quotaError]
        ]
    )

    #expect(
        CloudKitErrorDescription.userFacingDescription(for: partialError)
            == CloudKitErrorDescription.quotaExceeded
    )
}

@Test
func cloudKitErrorDescriptionPreservesUnknownErrors() {
    let error = NSError(
        domain: "EasyTaskTests",
        code: 42,
        userInfo: [NSLocalizedDescriptionKey: "알 수 없는 원본 오류"]
    )

    #expect(
        CloudKitErrorDescription.userFacingDescription(for: error)
            == "알 수 없는 원본 오류"
    )
}

@Test
@MainActor
func syncFailureStatusDoesNotDiscardLocalRecords() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let task = Task(title: "로컬에 남아야 하는 작업", plannedAt: Date(), order: 100)
    context.insert(task)
    try context.save()

    let monitor = CloudKitSyncMonitor()
    monitor.record(CloudKitSyncEventSummary(
        kind: .export,
        isCompleted: true,
        succeeded: false,
        errorDescription: CloudKitErrorDescription.quotaExceeded
    ))

    let tasks = try context.fetch(FetchDescriptor<Task>())
    #expect(tasks.contains { $0.id == task.id })
    #expect(monitor.lastErrorDescription == CloudKitErrorDescription.quotaExceeded)
}

@Test
func cloudKitConfigurationUsesExplicitSharedContainer() {
    let configuration = EasyTaskContainerFactory.makeConfiguration(
        storeURL: nil,
        mode: .cloudKit,
        isStoredInMemoryOnly: false
    )

    #expect(configuration.cloudKitContainerIdentifier == "iCloud.com.soraul2.easytask")
    #expect(EasyTaskStoreMode.cloudKit.usesCloudKit)
    #expect(EasyTaskContainerFactory.appStoreMode == .cloudKit)
}

@Test
func localConfigurationKeepsCloudKitDisabled() {
    let configuration = EasyTaskContainerFactory.makeConfiguration(
        storeURL: nil,
        mode: .local,
        isStoredInMemoryOnly: false
    )

    #expect(configuration.cloudKitContainerIdentifier == nil)
    #expect(!EasyTaskStoreMode.local.usesCloudKit)
}

@Test
func cloudKitStartupNeverCreatesDemoRecords() {
    #expect(SeedPolicy.appStartup(cloudKitEnabled: true) == .release)
    #expect(SeedPolicy.appStartup(cloudKitEnabled: false) == .appStartup)
}

@Test(arguments: [
    CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: true),
    CloudKitSyncEventSummary(kind: .import, isCompleted: false, succeeded: true),
    CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: false),
    CloudKitSyncEventSummary(kind: .export, isCompleted: true, succeeded: true),
    CloudKitSyncEventSummary(kind: .setup, isCompleted: true, succeeded: true)
])
func onlySuccessfulCompletedImportsTriggerReconciliation(
    summary: CloudKitSyncEventSummary
) {
    let expected = summary.kind == .import && summary.isCompleted && summary.succeeded
    #expect(CloudKitSyncService.shouldReconcile(after: summary) == expected)
}

@Test
@MainActor
func successfulCloudKitImportPersistsReconciliationRepairs() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-12"))
    let olderReview = DailyReview(
        id: UUID(),
        instanceID: UUID(),
        dayKey: "2026-07-12",
        content: "older",
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 20)
    )
    let newerReview = DailyReview(
        id: UUID(),
        instanceID: UUID(),
        dayKey: "2026-07-12",
        content: "newer",
        createdAt: Date(timeIntervalSince1970: 11),
        updatedAt: Date(timeIntervalSince1970: 30)
    )
    let image = try #require(Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    ))
    let metadata = try DiaryAttachmentService.inspect(image)
    let attachment = DiaryAttachment(
        reviewId: olderReview.id,
        order: 100,
        mimeType: metadata.mediaType.rawValue,
        byteCount: metadata.byteCount,
        sha256: metadata.sha256,
        data: image,
        updatedAt: Date(timeIntervalSince1970: 25)
    )
    let danglingTask = Task(
        title: "원격 이벤트가 먼저 삭제된 작업",
        plannedAt: day,
        order: 100,
        eventId: UUID()
    )
    context.insert(olderReview)
    context.insert(newerReview)
    context.insert(attachment)
    context.insert(danglingTask)
    try context.save()

    try CloudKitSyncService.reconcileIfNeeded(
        after: CloudKitSyncEventSummary(
            kind: .import,
            isCompleted: true,
            succeeded: true
        ),
        context: context
    )

    let reviews = try context.fetch(FetchDescriptor<DailyReview>())
    let activeReview = try #require(reviews.first { $0.supersededAt == nil })
    let reopenedAttachments = try context.fetch(FetchDescriptor<DiaryAttachment>())

    #expect(reviews.filter { $0.supersededAt == nil }.count == 1)
    #expect(activeReview.id == newerReview.id)
    #expect(activeReview.content == "newer")
    #expect(reopenedAttachments.first?.reviewId == newerReview.id)
    #expect(danglingTask.eventId == nil)
}

#if DEBUG
@Test
func cloudKitSchemaInitializationRequiresExplicitLaunchArgument() throws {
    #expect(
        try EasyTaskContainerFactory.initializeDevelopmentCloudKitSchemaIfRequested(
            arguments: ["EasyTask"]
        ) == false
    )
}
#endif
