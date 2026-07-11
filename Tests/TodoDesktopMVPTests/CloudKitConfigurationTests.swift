import Foundation
import Testing
@testable import EasyTaskCore

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
