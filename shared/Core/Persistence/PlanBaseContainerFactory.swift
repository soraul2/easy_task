import CoreData
import Foundation
import SwiftData
#if os(macOS)
import Security
#endif

public enum PlanBaseStoreMode: Sendable, Equatable {
    case local
    case cloudKit

    public var usesCloudKit: Bool {
        self == .cloudKit
    }
}

public enum PlanBaseContainerFactory {
    public static let cloudKitContainerIdentifier =
        PlanBaseCompatibility.cloudKitContainerIdentifier
    public static let applicationGroupIdentifier =
        PlanBaseCompatibility.applicationGroupIdentifier
    public static let appStoreMode = PlanBaseStoreMode.cloudKit
    static let applicationSupportDirectoryName = "PlanBase"

    /// Uses CloudKit only when the current executable was signed with the
    /// capabilities required by the platform. This prevents Core Data's
    /// asynchronous CloudKit setup from terminating a malformed build.
    public static var runtimeAppStoreMode: PlanBaseStoreMode {
#if os(iOS)
        let hasRequiredEntitlements = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: applicationGroupIdentifier
        ) != nil
        return resolvedAppStoreMode(hasRequiredRuntimeEntitlements: hasRequiredEntitlements)
#elseif os(macOS)
        return resolvedAppStoreMode(
            hasRequiredRuntimeEntitlements: currentProcessHasCloudKitEntitlements()
        )
#else
        return appStoreMode
#endif
    }

    public static var schema: Schema {
        Schema(versionedSchema: EasyTaskSchemaV6.self)
    }

    @MainActor
    public static func makeAppPersistent(
        storeURL: URL? = nil,
        mode: PlanBaseStoreMode? = nil
    ) throws -> ModelContainer {
        let resolvedMode = mode ?? runtimeAppStoreMode
        if mode == nil, resolvedMode == .local, appStoreMode == .cloudKit {
            print("PlanBase CloudKit entitlements unavailable; opening the local store.")
        }
        let resolvedStoreURL = try storeURL ?? defaultStoreURL()
        let migration = try LegacyStoreMigrationService.prepareIfNeeded(
            storeURL: resolvedStoreURL
        )

        let container = try makePersistent(storeURL: resolvedStoreURL, mode: resolvedMode)
        guard let migration else { return container }

        do {
            let report = try BackupPackageCodec.restoreLegacyJSONMerging(
                migration.payload,
                into: container.mainContext
            )
            try LegacyStoreMigrationService.finish(migration)
            print(
                "PlanBase legacy store migration completed: "
                    + "inserted=\(report.merge.insertedRecords), "
                    + "updated=\(report.merge.updatedRecords), "
                    + "rejectedImages=\(migration.rejectedImageFileNames.count), "
                    + "backup=\(migration.backupDirectoryURL.path)"
            )
            return container
        } catch {
            // Keep the backup and pending marker. The next launch discards only the
            // incomplete current store and retries from the immutable legacy payload.
            print("PlanBase legacy store migration pending retry: \(error)")
            throw error
        }
    }

    public static func makePersistent(
        storeURL: URL? = nil,
        mode: PlanBaseStoreMode = .local
    ) throws -> ModelContainer {
        let configuration = makeConfiguration(
            storeURL: storeURL,
            mode: mode,
            isStoredInMemoryOnly: false
        )

        if let storeURL,
           FileManager.default.fileExists(atPath: storeURL.path),
           isStoreCompatibleWithCurrentSchema(at: storeURL) {
            // A store can have the exact current Core Data model hashes while its
            // staged-migration checksum was produced by another SwiftData runtime.
            // It needs no migration, and opening it directly avoids error 134504.
            return try makeContainerWithoutMigrationPlan(configuration: configuration)
        }

        return try makeContainer(configuration: configuration)
    }

    public static func makeInMemory() throws -> ModelContainer {
        let configuration = makeConfiguration(
            storeURL: nil,
            mode: .local,
            isStoredInMemoryOnly: true
        )
        return try makeContainer(configuration: configuration)
    }

    static func defaultStoreURL() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try prepareDefaultStoreLocation(applicationSupportURL: applicationSupportURL)
    }

    static func prepareDefaultStoreLocation(applicationSupportURL: URL) throws -> URL {
        let storeDirectoryURL = applicationSupportURL.appendingPathComponent(
            applicationSupportDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: storeDirectoryURL,
            withIntermediateDirectories: true
        )

        let storeURL = storeDirectoryURL.appendingPathComponent("default.store")
        let previousStoreURL = applicationSupportURL.appendingPathComponent("default.store")
        _ = try copyRecognizedStoreIfNeeded(from: previousStoreURL, to: storeURL)
        return storeURL
    }

    @discardableResult
    static func copyRecognizedStoreIfNeeded(
        from sourceStoreURL: URL,
        to destinationStoreURL: URL
    ) throws -> Bool {
        guard !FileManager.default.fileExists(atPath: destinationStoreURL.path),
              FileManager.default.fileExists(atPath: sourceStoreURL.path),
              isRecognizedPlanBaseStore(at: sourceStoreURL) else {
            return false
        }

        let sourceURLs = storeFamilyURLs(for: sourceStoreURL)
        let destinationURLs = storeFamilyURLs(for: destinationStoreURL)
        var copiedURLs: [URL] = []

        do {
            for destinationURL in destinationURLs
            where FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            for (sourceURL, destinationURL) in zip(sourceURLs, destinationURLs)
            where FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                copiedURLs.append(destinationURL)
            }
        } catch {
            for copiedURL in copiedURLs {
                try? FileManager.default.removeItem(at: copiedURL)
            }
            throw error
        }

        return true
    }

    static func makeConfiguration(
        storeURL: URL?,
        mode: PlanBaseStoreMode,
        isStoredInMemoryOnly: Bool
    ) -> ModelConfiguration {
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = mode.usesCloudKit
            ? .private(cloudKitContainerIdentifier)
            : .none

        if let storeURL {
            return ModelConfiguration(
                PlanBaseCompatibility.modelConfigurationName,
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: cloudKitDatabase
            )
        }

        return ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: cloudKitDatabase
        )
    }

    static func resolvedAppStoreMode(
        hasRequiredRuntimeEntitlements: Bool
    ) -> PlanBaseStoreMode {
        guard appStoreMode.usesCloudKit, hasRequiredRuntimeEntitlements else {
            return .local
        }
        return .cloudKit
    }

#if os(macOS)
    private static func currentProcessHasCloudKitEntitlements() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let containers = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) as? [String],
              containers.contains(cloudKitContainerIdentifier),
              let services = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-services" as CFString,
                nil
              ) as? [String] else {
            return false
        }
        return services.contains("CloudKit") || services.contains("*")
    }
#endif

    public static func makeContainer(
        configuration: ModelConfiguration
    ) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: EasyTaskMigrationPlan.self,
            configurations: configuration
        )
    }

    static func isStoreCompatibleWithCurrentSchema(at storeURL: URL) -> Bool {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(
            for: EasyTaskSchemaV6.models
        ),
        let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: [NSReadOnlyPersistentStoreOption: true]
        ) else {
            return false
        }

        return model.isConfiguration(
            withName: nil,
            compatibleWithStoreMetadata: metadata
        )
    }

    static func isRecognizedPlanBaseStore(at storeURL: URL) -> Bool {
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: [NSReadOnlyPersistentStoreOption: true]
        ) else {
            return false
        }

        let modelCollections: [[any PersistentModel.Type]] = [
            EasyTaskLegacySchema.models,
            EasyTaskSchemaV1.models,
            EasyTaskSchemaV2.models,
            EasyTaskSchemaV3.models,
            EasyTaskSchemaV4.models,
            EasyTaskSchemaV5.models,
            EasyTaskSchemaV6.models
        ]
        return modelCollections.contains { models in
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: models) else {
                return false
            }
            return model.isConfiguration(
                withName: nil,
                compatibleWithStoreMetadata: metadata
            )
        }
    }

    private static func storeFamilyURLs(for storeURL: URL) -> [URL] {
        let parentURL = storeURL.deletingLastPathComponent()
        let storeName = storeURL.lastPathComponent
        return [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal"),
            parentURL.appendingPathComponent(".\(storeName)_SUPPORT", isDirectory: true)
        ]
    }

    private static func makeContainerWithoutMigrationPlan(
        configuration: ModelConfiguration
    ) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: configuration
        )
    }
}
