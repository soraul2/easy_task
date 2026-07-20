import CoreData
import Foundation
import SwiftData

public enum EasyTaskStoreMode: Sendable, Equatable {
    case local
    case cloudKit

    public var usesCloudKit: Bool {
        self == .cloudKit
    }
}

public enum EasyTaskContainerFactory {
    public static let cloudKitContainerIdentifier = "iCloud.com.soraul2.easytask"
    public static let appStoreMode = EasyTaskStoreMode.cloudKit

    public static var schema: Schema {
        Schema(versionedSchema: EasyTaskSchemaV6.self)
    }

    @MainActor
    public static func makeAppPersistent(
        storeURL: URL? = nil,
        mode: EasyTaskStoreMode = appStoreMode
    ) throws -> ModelContainer {
        let resolvedStoreURL = try storeURL ?? defaultStoreURL()
        let migration = try LegacyStoreMigrationService.prepareIfNeeded(
            storeURL: resolvedStoreURL
        )

        let container = try makePersistent(storeURL: resolvedStoreURL, mode: mode)
        guard let migration else { return container }

        do {
            let report = try BackupPackageCodec.restoreLegacyJSONMerging(
                migration.payload,
                into: container.mainContext
            )
            try LegacyStoreMigrationService.finish(migration)
            print(
                "EasyTask legacy store migration completed: "
                    + "inserted=\(report.merge.insertedRecords), "
                    + "updated=\(report.merge.updatedRecords), "
                    + "rejectedImages=\(migration.rejectedImageFileNames.count), "
                    + "backup=\(migration.backupDirectoryURL.path)"
            )
            return container
        } catch {
            // Keep the backup and pending marker. The next launch discards only the
            // incomplete current store and retries from the immutable legacy payload.
            print("EasyTask legacy store migration pending retry: \(error)")
            throw error
        }
    }

    public static func makePersistent(
        storeURL: URL? = nil,
        mode: EasyTaskStoreMode = .local
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
        try FileManager.default.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        return applicationSupportURL.appendingPathComponent("default.store")
    }

    static func makeConfiguration(
        storeURL: URL?,
        mode: EasyTaskStoreMode,
        isStoredInMemoryOnly: Bool
    ) -> ModelConfiguration {
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = mode.usesCloudKit
            ? .private(cloudKitContainerIdentifier)
            : .none

        if let storeURL {
            return ModelConfiguration(
                "EasyTask",
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

    private static func makeContainerWithoutMigrationPlan(
        configuration: ModelConfiguration
    ) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: configuration
        )
    }
}
