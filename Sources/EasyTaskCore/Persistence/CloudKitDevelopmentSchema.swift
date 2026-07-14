#if DEBUG
import CoreData
import Foundation
import SwiftData

public extension EasyTaskContainerFactory {
    static let cloudKitSchemaInitializationArgument = "--initialize-cloudkit-schema"

    @discardableResult
    static func initializeDevelopmentCloudKitSchemaIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) throws -> Bool {
        guard arguments.contains(cloudKitSchemaInitializationArgument) else {
            return false
        }

        let temporaryStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTask-CloudKit-Schema-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: temporaryStoreURL.path + suffix)
                )
            }
        }

        try autoreleasepool {
            let storeDescription = NSPersistentStoreDescription(url: temporaryStoreURL)
            storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerIdentifier
            )
            storeDescription.shouldAddStoreAsynchronously = false

            guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(
                for: EasyTaskSchemaV5.models
            ) else {
                throw CloudKitDevelopmentSchemaError.unavailableManagedObjectModel
            }

            let container = NSPersistentCloudKitContainer(
                name: "EasyTask",
                managedObjectModel: managedObjectModel
            )
            container.persistentStoreDescriptions = [storeDescription]

            var loadingError: (any Error)?
            container.loadPersistentStores { _, error in
                loadingError = error
            }
            if let loadingError {
                throw loadingError
            }

            try container.initializeCloudKitSchema()
            if let store = container.persistentStoreCoordinator.persistentStores.first {
                try container.persistentStoreCoordinator.remove(store)
            }
        }

        return true
    }
}

public enum CloudKitDevelopmentSchemaError: LocalizedError {
    case unavailableManagedObjectModel

    public var errorDescription: String? {
        switch self {
        case .unavailableManagedObjectModel:
            "CloudKit 개발 스키마용 Core Data 모델을 만들 수 없습니다."
        }
    }
}
#endif
