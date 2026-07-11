import Foundation
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
