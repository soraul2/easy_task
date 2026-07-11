import CoreData
import Foundation
import SwiftData

enum LegacyStoreMigrationError: LocalizedError {
    case unavailableManagedObjectModel

    var errorDescription: String? {
        switch self {
        case .unavailableManagedObjectModel:
            "기존 EasyTask 저장소의 Core Data 모델을 만들 수 없습니다."
        }
    }
}

enum LegacyStoreMigrationService {
    struct PreparedMigration {
        let storeURL: URL
        let backupDirectoryURL: URL
        let payload: BackupPayload
        let rejectedImageFileNames: [String]
    }

    private struct PendingMarker: Codable {
        let backupDirectoryName: String
        let storeFileName: String
    }

    struct LegacySnapshot {
        let payload: BackupPayload
        let rejectedImageFileNames: [String]
    }

    static let backupRootDirectoryName = "EasyTaskLegacyBackups"
    static let pendingMarkerFileName = ".EasyTaskLegacyMigration.pending.json"
    static let payloadFileName = "legacy-payload.json"
    static let rejectedImageNamesFileName = "rejected-image-file-names.json"

    @MainActor
    static func prepareIfNeeded(storeURL: URL) throws -> PreparedMigration? {
        let markerURL = pendingMarkerURL(for: storeURL)
        if FileManager.default.fileExists(atPath: markerURL.path) {
            return try resumePendingMigration(storeURL: storeURL, markerURL: markerURL)
        }

        guard FileManager.default.fileExists(atPath: storeURL.path),
              try isLegacyStore(at: storeURL) else {
            return nil
        }

        let snapshot = try readLegacySnapshot(from: storeURL)
        try BackupCodec.validate(snapshot.payload)

        let backupDirectoryURL = try makeBackupDirectory(for: storeURL)
        var didStartRemovingOriginal = false
        do {
            try copyStoreFamily(from: storeURL, to: backupDirectoryURL)
            try BackupCodec.encode(snapshot.payload).write(
                to: backupDirectoryURL.appendingPathComponent(payloadFileName),
                options: .atomic
            )
            try JSONEncoder().encode(snapshot.rejectedImageFileNames).write(
                to: backupDirectoryURL.appendingPathComponent(rejectedImageNamesFileName),
                options: .atomic
            )
            let marker = PendingMarker(
                backupDirectoryName: backupDirectoryURL.lastPathComponent,
                storeFileName: storeURL.lastPathComponent
            )
            try JSONEncoder().encode(marker).write(to: markerURL, options: .atomic)
            didStartRemovingOriginal = true
            try removeStoreFamily(at: storeURL)
        } catch {
            if didStartRemovingOriginal {
                try? restoreStoreFamily(
                    storeURL: storeURL,
                    backupDirectoryURL: backupDirectoryURL
                )
            } else {
                try? FileManager.default.removeItem(at: backupDirectoryURL)
            }
            try? FileManager.default.removeItem(at: markerURL)
            throw error
        }

        return PreparedMigration(
            storeURL: storeURL,
            backupDirectoryURL: backupDirectoryURL,
            payload: snapshot.payload,
            rejectedImageFileNames: snapshot.rejectedImageFileNames
        )
    }

    static func finish(_ migration: PreparedMigration) throws {
        let markerURL = pendingMarkerURL(for: migration.storeURL)
        if FileManager.default.fileExists(atPath: markerURL.path) {
            try FileManager.default.removeItem(at: markerURL)
        }
    }

}

private extension LegacyStoreMigrationService {
    static func isLegacyStore(at storeURL: URL) throws -> Bool {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: [NSReadOnlyPersistentStoreOption: true]
        )
        guard let model = NSManagedObjectModel.makeManagedObjectModel(
            for: EasyTaskLegacySchema.models
        ) else {
            throw LegacyStoreMigrationError.unavailableManagedObjectModel
        }
        return model.isConfiguration(
            withName: nil,
            compatibleWithStoreMetadata: metadata
        )
    }

    @MainActor
    static func readLegacySnapshot(from storeURL: URL) throws -> LegacySnapshot {
        try autoreleasepool {
            let schema = Schema(EasyTaskLegacySchema.models)
            let configuration = ModelConfiguration(
                "EasyTaskLegacy",
                schema: schema,
                url: storeURL,
                allowsSave: false,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                configurations: configuration
            )
            return try makeSnapshot(context: container.mainContext)
        }
    }

    @MainActor
    static func makeSnapshot(context: ModelContext) throws -> LegacySnapshot {
        let events = try context.fetch(FetchDescriptor<EasyTaskLegacySchema.CalendarEvent>())
        let templates = try context.fetch(FetchDescriptor<EasyTaskLegacySchema.TaskTemplate>())
        let templateItems = try context.fetch(
            FetchDescriptor<EasyTaskLegacySchema.TaskTemplateItem>()
        )
        let tasks = try context.fetch(FetchDescriptor<EasyTaskLegacySchema.Task>())
        let reviews = try context.fetch(FetchDescriptor<EasyTaskLegacySchema.DailyReview>())
        let blocks = try context.fetch(FetchDescriptor<EasyTaskLegacySchema.DiaryBlock>())

        let eventIDs = Set(events.map(\.id))
        let templateIDs = Set(templates.map(\.id))
        let reviewIDs = Set(reviews.map(\.id))
        var rejectedImageFileNames: Set<String> = []

        let payload = BackupPayload(
            backupVersion: BackupCodec.currentVersion,
            exportedAt: Date(),
            tasks: tasks.map { task in
                TaskDTO(
                    id: task.id,
                    title: task.title,
                    note: task.note,
                    status: TaskStatus(rawValue: task.status)?.rawValue
                        ?? TaskStatus.todo.rawValue,
                    plannedAt: task.plannedAt,
                    plannedDayKey: DayKey.key(for: task.plannedAt),
                    order: task.order,
                    eventId: task.eventId.flatMap { eventIDs.contains($0) ? $0 : nil },
                    templatePlacementId: nil,
                    priority: task.priority.flatMap(TaskPriority.init(rawValue:))?.rawValue,
                    tags: task.tags,
                    estimatedMinutes: task.estimatedMinutes,
                    createdAt: task.createdAt,
                    updatedAt: task.updatedAt,
                    completedAt: task.completedAt,
                    completedDayKey: task.completedAt.map(DayKey.key(for:)),
                    archivedAt: task.archivedAt,
                    archivedDayKey: task.archivedAt.map(DayKey.key(for:))
                )
            },
            calendarEvents: events.map { event in
                CalendarEventDTO(
                    id: event.id,
                    title: event.title,
                    startAt: event.startAt,
                    endAt: event.endAt,
                    startDayKey: DayKey.key(for: event.startAt),
                    endDayKey: DayKey.key(for: event.endAt),
                    note: event.note,
                    color: event.color,
                    createdAt: event.createdAt,
                    updatedAt: event.updatedAt
                )
            },
            taskTemplates: templates.map { template in
                TaskTemplateDTO(
                    id: template.id,
                    name: template.name,
                    isFavorite: template.isFavorite,
                    createdAt: template.createdAt,
                    updatedAt: template.updatedAt
                )
            },
            taskTemplateItems: templateItems.compactMap { item in
                guard templateIDs.contains(item.templateId) else { return nil }
                return TaskTemplateItemDTO(
                    id: item.id,
                    templateId: item.templateId,
                    title: item.title,
                    note: item.note,
                    priority: item.priority.flatMap(TaskPriority.init(rawValue:))?.rawValue,
                    tags: item.tags,
                    estimatedMinutes: item.estimatedMinutes,
                    order: item.order
                )
            },
            templatePlacements: [],
            dailyReviews: reviews.map { review in
                let safeFileNames = review.imageFileNames.filter { fileName in
                    guard (try? DiaryImageFileStore.validateAttachmentFileName(fileName)) != nil
                    else {
                        rejectedImageFileNames.insert(fileName)
                        return false
                    }
                    return true
                }
                return DailyReviewDTO(
                    id: review.id,
                    dayKey: normalizedDayKey(review.dayKey, fallback: review.createdAt),
                    title: review.title,
                    weather: review.weather,
                    mood: review.mood,
                    content: review.content,
                    imageFileNames: safeFileNames,
                    createdAt: review.createdAt,
                    updatedAt: review.updatedAt
                )
            },
            diaryBlocks: blocks.compactMap { block in
                guard reviewIDs.contains(block.reviewId) else { return nil }
                let fileName: String?
                if let candidate = block.imageFileName,
                   (try? DiaryImageFileStore.validateAttachmentFileName(candidate)) != nil {
                    fileName = candidate
                } else {
                    if let candidate = block.imageFileName {
                        rejectedImageFileNames.insert(candidate)
                    }
                    fileName = nil
                }
                return DiaryBlockDTO(
                    id: block.id,
                    reviewId: block.reviewId,
                    dayKey: normalizedDayKey(block.dayKey, fallback: block.createdAt),
                    type: DiaryBlockType(rawValue: block.type)?.rawValue
                        ?? DiaryBlockType.text.rawValue,
                    text: block.text,
                    imageFileName: fileName,
                    order: block.order,
                    createdAt: block.createdAt,
                    updatedAt: block.updatedAt
                )
            }
        )
        return LegacySnapshot(
            payload: payload,
            rejectedImageFileNames: rejectedImageFileNames.sorted()
        )
    }

    static func normalizedDayKey(_ dayKey: String, fallback: Date) -> String {
        guard let date = DayKey.date(from: dayKey), DayKey.key(for: date) == dayKey else {
            return DayKey.key(for: fallback)
        }
        return dayKey
    }

    static func makeBackupDirectory(for storeURL: URL) throws -> URL {
        let rootURL = backupRootURL(for: storeURL)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let directoryURL = rootURL.appendingPathComponent(
            "legacy-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        return directoryURL
    }

    static func backupRootURL(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent(
            backupRootDirectoryName,
            isDirectory: true
        )
    }

    static func pendingMarkerURL(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent(
            pendingMarkerFileName
        )
    }

    static func storeFamilyURLs(for storeURL: URL) -> [URL] {
        let parentURL = storeURL.deletingLastPathComponent()
        let storeName = storeURL.lastPathComponent
        return [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal"),
            parentURL.appendingPathComponent(".\(storeName)_SUPPORT", isDirectory: true)
        ]
    }

    static func copyStoreFamily(from storeURL: URL, to directoryURL: URL) throws {
        for sourceURL in storeFamilyURLs(for: storeURL)
        where FileManager.default.fileExists(atPath: sourceURL.path) {
            try FileManager.default.copyItem(
                at: sourceURL,
                to: directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
            )
        }
    }

    static func removeStoreFamily(at storeURL: URL) throws {
        for itemURL in storeFamilyURLs(for: storeURL)
        where FileManager.default.fileExists(atPath: itemURL.path) {
            try FileManager.default.removeItem(at: itemURL)
        }
    }

    static func restoreStoreFamily(
        storeURL: URL,
        backupDirectoryURL: URL
    ) throws {
        try removeStoreFamily(at: storeURL)
        let parentURL = storeURL.deletingLastPathComponent()
        for expectedURL in storeFamilyURLs(for: storeURL) {
            let sourceURL = backupDirectoryURL.appendingPathComponent(
                expectedURL.lastPathComponent
            )
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            try FileManager.default.copyItem(
                at: sourceURL,
                to: parentURL.appendingPathComponent(sourceURL.lastPathComponent)
            )
        }
    }

    static func resumePendingMigration(
        storeURL: URL,
        markerURL: URL
    ) throws -> PreparedMigration {
        let marker = try JSONDecoder().decode(
            PendingMarker.self,
            from: Data(contentsOf: markerURL)
        )
        guard marker.storeFileName == storeURL.lastPathComponent,
              !marker.backupDirectoryName.contains("/"),
              !marker.backupDirectoryName.contains("\\") else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let rootURL = backupRootURL(for: storeURL).standardizedFileURL
        let backupDirectoryURL = rootURL.appendingPathComponent(
            marker.backupDirectoryName,
            isDirectory: true
        ).standardizedFileURL
        guard backupDirectoryURL.deletingLastPathComponent() == rootURL else {
            throw CocoaError(.fileReadNoPermission)
        }

        let backupStoreURL = backupDirectoryURL.appendingPathComponent(
            marker.storeFileName
        )
        guard FileManager.default.fileExists(atPath: backupStoreURL.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let payload = try BackupCodec.decode(Data(
            contentsOf: backupDirectoryURL.appendingPathComponent(payloadFileName)
        ))
        let rejectedURL = backupDirectoryURL.appendingPathComponent(
            rejectedImageNamesFileName
        )
        let rejectedImageFileNames: [String] = if FileManager.default.fileExists(
            atPath: rejectedURL.path
        ) {
            try JSONDecoder().decode([String].self, from: Data(contentsOf: rejectedURL))
        } else {
            []
        }
        try removeStoreFamily(at: storeURL)
        return PreparedMigration(
            storeURL: storeURL,
            backupDirectoryURL: backupDirectoryURL,
            payload: payload,
            rejectedImageFileNames: rejectedImageFileNames
        )
    }
}
