import Foundation
import SwiftData

public enum EasyTaskContainerFactory {
    public static var schema: Schema {
        Schema(versionedSchema: EasyTaskSchemaV2.self)
    }

    public static func makePersistent(storeURL: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(
                "EasyTask",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        }

        return try makeContainer(configuration: configuration)
    }

    public static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try makeContainer(configuration: configuration)
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
