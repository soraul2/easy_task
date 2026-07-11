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
        Schema(versionedSchema: EasyTaskSchemaV3.self)
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
}
