import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func schemaV1ContainsEveryPersistedModel() {
    let modelNames = Set(EasyTaskSchemaV1.models.map { String(reflecting: $0) })
    let expectedNames = Set([
        String(reflecting: EasyTaskSchemaV1.Task.self),
        String(reflecting: EasyTaskSchemaV1.CalendarEvent.self),
        String(reflecting: EasyTaskSchemaV1.TaskTemplate.self),
        String(reflecting: EasyTaskSchemaV1.TaskTemplateItem.self),
        String(reflecting: EasyTaskSchemaV1.TemplatePlacement.self),
        String(reflecting: EasyTaskSchemaV1.DailyReview.self),
        String(reflecting: EasyTaskSchemaV1.DiaryBlock.self)
    ])

    #expect(EasyTaskSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    #expect(modelNames == expectedNames)
}

@Test
func schemaV2ContainsEveryFrozenPersistedModel() {
    let modelNames = Set(EasyTaskSchemaV2.models.map { String(reflecting: $0) })
    let expectedNames = Set([
        String(reflecting: EasyTaskSchemaV2.Task.self),
        String(reflecting: EasyTaskSchemaV2.CalendarEvent.self),
        String(reflecting: EasyTaskSchemaV2.TaskTemplate.self),
        String(reflecting: EasyTaskSchemaV2.TaskTemplateItem.self),
        String(reflecting: EasyTaskSchemaV2.TemplatePlacement.self),
        String(reflecting: EasyTaskSchemaV2.DailyReview.self),
        String(reflecting: EasyTaskSchemaV2.DiaryBlock.self)
    ])

    #expect(EasyTaskSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
    #expect(modelNames == expectedNames)
}

@Test
func schemaV3ContainsEveryFrozenPersistedModel() {
    let modelNames = Set(EasyTaskSchemaV3.models.map { String(reflecting: $0) })
    let expectedNames = Set([
        String(reflecting: EasyTaskSchemaV3.Task.self),
        String(reflecting: EasyTaskSchemaV3.CalendarEvent.self),
        String(reflecting: EasyTaskSchemaV3.TaskTemplate.self),
        String(reflecting: EasyTaskSchemaV3.TaskTemplateItem.self),
        String(reflecting: EasyTaskSchemaV3.TemplatePlacement.self),
        String(reflecting: EasyTaskSchemaV3.DailyReview.self),
        String(reflecting: EasyTaskSchemaV3.DiaryBlock.self),
        String(reflecting: EasyTaskSchemaV3.DiaryAttachment.self)
    ])

    #expect(EasyTaskSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
    #expect(modelNames == expectedNames)
}

@Test
func schemaV4ContainsEveryCurrentPersistedModel() {
    let modelNames = Set(EasyTaskSchemaV4.models.map { String(reflecting: $0) })
    let expectedNames = Set([
        String(reflecting: Task.self),
        String(reflecting: CalendarEvent.self),
        String(reflecting: TaskTemplate.self),
        String(reflecting: TaskTemplateItem.self),
        String(reflecting: TemplatePlacement.self),
        String(reflecting: DailyReview.self),
        String(reflecting: DiaryBlock.self),
        String(reflecting: DiaryAttachment.self)
    ])

    #expect(EasyTaskSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
    #expect(modelNames == expectedNames)
}

@Test
@MainActor
func versionedContainerReopensFileBackedStore() throws {
    try withTemporaryStore { storeURL in
        try writeFixture(
            to: EasyTaskContainerFactory.makePersistent(storeURL: storeURL),
            title: "versioned fixture"
        )

        let reopened = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        try expectFixture(in: reopened, title: "versioned fixture")
    }
}

@Test
@MainActor
func v3AttachmentPersistsInFileBackedStore() throws {
    try withTemporaryStore { storeURL in
        let id = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let instanceID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let reviewID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
        let sha256 = "275f1bcbbb585c71e3b2184304eccfa0e37de92022ca3b6f4e9c10df32318d85"
        let container = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        container.mainContext.insert(DiaryAttachment(
            id: id,
            instanceID: instanceID,
            reviewId: reviewID,
            order: 200,
            originalFileName: "review.png",
            mimeType: "image/png",
            byteCount: data.count,
            sha256: sha256,
            data: data,
            createdAt: createdAt,
            updatedAt: updatedAt
        ))
        try container.mainContext.save()

        let reopened = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        let attachment = try #require(
            reopened.mainContext.fetch(FetchDescriptor<DiaryAttachment>()).first
        )
        #expect(attachment.id == id)
        #expect(attachment.instanceID == instanceID)
        #expect(attachment.reviewId == reviewID)
        #expect(attachment.order == 200)
        #expect(attachment.originalFileName == "review.png")
        #expect(attachment.mimeType == "image/png")
        #expect(attachment.byteCount == data.count)
        #expect(attachment.sha256 == sha256)
        #expect(attachment.data == data)
        #expect(attachment.createdAt == createdAt)
        #expect(attachment.updatedAt == updatedAt)
        #expect(attachment.supersededAt == nil)
    }
}

@Test
@MainActor
func versionedV1StoreMigratesToV2WithoutDataLoss() throws {
    try withTemporaryStore { storeURL in
        let v1Schema = Schema(versionedSchema: EasyTaskSchemaV1.self)
        let configuration = ModelConfiguration(
            "EasyTaskV1",
            schema: v1Schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let v1Container = try ModelContainer(
            for: v1Schema,
            configurations: configuration
        )
        try writeV1Fixture(to: v1Container, title: "v1 fixture")

        let migrated = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        try expectFixture(in: migrated, title: "v1 fixture")
        try expectStableInstanceIdentityBackfill(in: migrated)
    }
}

@Test
@MainActor
func versionedV2StoreMigratesToV3WithoutDataLoss() throws {
    try withTemporaryStore { storeURL in
        let v2Schema = Schema(versionedSchema: EasyTaskSchemaV2.self)
        let configuration = ModelConfiguration(
            "EasyTaskV2",
            schema: v2Schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let v2Container = try ModelContainer(
            for: v2Schema,
            configurations: configuration
        )
        try writeV2Fixture(to: v2Container, title: "v2 fixture")

        let migrated = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        try expectFixture(in: migrated, title: "v2 fixture")
        let review = try #require(migrated.mainContext.fetch(FetchDescriptor<DailyReview>()).first)
        let imageBlock = try #require(
            migrated.mainContext.fetch(FetchDescriptor<DiaryBlock>())
                .first { $0.type == DiaryBlockType.image.rawValue }
        )
        #expect(review.imageFileNames == ["legacy-review.png"])
        #expect(imageBlock.imageFileName == "legacy-block.png")
        #expect(try migrated.mainContext.fetchCount(FetchDescriptor<DiaryAttachment>()) == 0)
    }
}

@Test
@MainActor
func versionedV3StoreMigratesToV4WithStableIdentityAndNoReminder() throws {
    try withTemporaryStore { storeURL in
        let schema = Schema(versionedSchema: EasyTaskSchemaV3.self)
        let configuration = ModelConfiguration(
            "EasyTaskV3",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let id = UUID()
        let instanceID = UUID()
        let day = try #require(DayKey.date(from: "2026-07-12"))
        container.mainContext.insert(EasyTaskSchemaV3.Task(
            id: id,
            instanceID: instanceID,
            title: "V3 알림 이관",
            plannedAt: day,
            order: 100
        ))
        try container.mainContext.save()

        let migrated = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        let task = try #require(migrated.mainContext.fetch(FetchDescriptor<Task>()).first)
        #expect(task.id == id)
        #expect(task.instanceID == instanceID)
        #expect(task.title == "V3 알림 이관")
        #expect(task.reminderAt == nil)
    }
}

@Test
@MainActor
func existingUnversionedStoreOpensWithSchemaV1WithoutDataLoss() throws {
    try withTemporaryStore { storeURL in
        try writeUnversionedV1Fixture(to: storeURL, title: "legacy fixture")

        let migrated = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        try expectFixture(in: migrated, title: "legacy fixture")
        try expectStableInstanceIdentityBackfill(in: migrated)
    }
}

@Test
@MainActor
func initialDesktopStoreBridgesToV3WithBackupAndNoDuplicates() throws {
    try withTemporaryStore { storeURL in
        try writeInitialDesktopFixture(to: storeURL, title: "initial desktop fixture")

        let migrated = try EasyTaskContainerFactory.makeAppPersistent(
            storeURL: storeURL,
            mode: .local
        )
        try expectInitialDesktopFixture(
            in: migrated,
            title: "initial desktop fixture"
        )

        let backupRootURL = storeURL.deletingLastPathComponent().appendingPathComponent(
            LegacyStoreMigrationService.backupRootDirectoryName,
            isDirectory: true
        )
        let backupDirectories = try FileManager.default.contentsOfDirectory(
            at: backupRootURL,
            includingPropertiesForKeys: nil
        )
        #expect(backupDirectories.count == 1)
        let backupDirectoryURL = try #require(backupDirectories.first)
        #expect(FileManager.default.fileExists(
            atPath: backupDirectoryURL.appendingPathComponent(storeURL.lastPathComponent).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: backupDirectoryURL.appendingPathComponent(
                LegacyStoreMigrationService.payloadFileName
            ).path
        ))
        let markerURL = storeURL.deletingLastPathComponent().appendingPathComponent(
            LegacyStoreMigrationService.pendingMarkerFileName
        )
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))

        let reopened = try EasyTaskContainerFactory.makeAppPersistent(
            storeURL: storeURL,
            mode: .local
        )
        try expectInitialDesktopFixture(
            in: reopened,
            title: "initial desktop fixture"
        )
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<Task>()) == 1)
        #expect(try FileManager.default.contentsOfDirectory(
            at: backupRootURL,
            includingPropertiesForKeys: nil
        ).count == 1)
    }
}

@Test
@MainActor
func pendingBridgeWithoutOriginalBackupDoesNotRemoveCurrentStore() throws {
    try withTemporaryStore { storeURL in
        try writeFixture(
            to: EasyTaskContainerFactory.makePersistent(storeURL: storeURL),
            title: "protected current fixture"
        )
        let markerURL = storeURL.deletingLastPathComponent().appendingPathComponent(
            LegacyStoreMigrationService.pendingMarkerFileName
        )
        let markerData = Data(
            #"{"backupDirectoryName":"missing-backup","storeFileName":"default.store"}"#.utf8
        )
        try markerData.write(to: markerURL, options: .atomic)

        do {
            _ = try EasyTaskContainerFactory.makeAppPersistent(
                storeURL: storeURL,
                mode: .local
            )
            Issue.record("원본 백업이 없는 pending migration이 거부되지 않았습니다.")
        } catch {
            #expect(FileManager.default.fileExists(atPath: storeURL.path))
        }

        try FileManager.default.removeItem(at: markerURL)
        let reopened = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        try expectFixture(in: reopened, title: "protected current fixture")
    }
}

@Test
@MainActor
func appFactoryOpensPreviousDefaultV3ConfigurationWithoutBackup() throws {
    try withTemporaryStore { storeURL in
        let schema = Schema(versionedSchema: EasyTaskSchemaV3.self)
        let previousConfiguration = ModelConfiguration(
            "EasyTaskV3",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let previousContainer = try ModelContainer(
            for: schema,
            configurations: previousConfiguration
        )
        let day = try #require(DayKey.date(from: "2026-07-12"))
        previousContainer.mainContext.insert(EasyTaskSchemaV3.Task(
            title: "previous default V3 fixture",
            plannedAt: day,
            order: 100
        ))
        try previousContainer.mainContext.save()

        let reopened = try EasyTaskContainerFactory.makeAppPersistent(
            storeURL: storeURL,
            mode: .local
        )
        let task = try #require(reopened.mainContext.fetch(FetchDescriptor<Task>()).first)
        #expect(task.title == "previous default V3 fixture")
        #expect(task.reminderAt == nil)

        let backupRootURL = storeURL.deletingLastPathComponent().appendingPathComponent(
            LegacyStoreMigrationService.backupRootDirectoryName,
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(atPath: backupRootURL.path))
    }
}

@Test
@MainActor
func migratedDuplicateLogicalIDsConvergeRegardlessOfInsertionOrder() throws {
    let forwardWinner = try migratedDuplicateTaskWinner(reversed: false)
    let reversedWinner = try migratedDuplicateTaskWinner(reversed: true)

    #expect(forwardWinner == reversedWinner)
}

@MainActor
private func migratedDuplicateTaskWinner(reversed: Bool) throws -> String {
    var winnerTitle = ""
    try withTemporaryStore { storeURL in
        let v1Schema = Schema(versionedSchema: EasyTaskSchemaV1.self)
        let configuration = ModelConfiguration(
            "EasyTaskV1Duplicates",
            schema: v1Schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let v1Container = try ModelContainer(for: v1Schema, configurations: configuration)
        let context = v1Container.mainContext
        let day = try #require(DayKey.date(from: "2026-07-10"))
        let logicalID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let timestamp = Date(timeIntervalSince1970: 100)
        let first = EasyTaskSchemaV1.Task(
            id: logicalID,
            title: "alpha",
            plannedAt: day,
            order: 100,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let second = EasyTaskSchemaV1.Task(
            id: logicalID,
            title: "omega",
            plannedAt: day,
            order: 100,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        for task in reversed ? [second, first] : [first, second] {
            context.insert(task)
        }
        try context.save()

        let migrated = try EasyTaskContainerFactory.makePersistent(storeURL: storeURL)
        let migratedTasks = try migrated.mainContext.fetch(FetchDescriptor<Task>())
        #expect(Set(migratedTasks.map(\.instanceID)).count == 2)
        _ = try DataIntegrityService.reconcile(context: migrated.mainContext)
        winnerTitle = try #require(
            migratedTasks.first { $0.supersededAt == nil }
        ).title
    }
    return winnerTitle
}

@MainActor
private func writeUnversionedV1Fixture(to storeURL: URL, title: String) throws {
    let configuration = ModelConfiguration(
        url: storeURL,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(
        for: EasyTaskSchemaV1.Task.self,
        EasyTaskSchemaV1.CalendarEvent.self,
        EasyTaskSchemaV1.TaskTemplate.self,
        EasyTaskSchemaV1.TaskTemplateItem.self,
        EasyTaskSchemaV1.TemplatePlacement.self,
        EasyTaskSchemaV1.DailyReview.self,
        EasyTaskSchemaV1.DiaryBlock.self,
        configurations: configuration
    )
    try writeV1Fixture(to: container, title: title)
}

@MainActor
private func writeInitialDesktopFixture(to storeURL: URL, title: String) throws {
    let schema = Schema(EasyTaskLegacySchema.models)
    let configuration = ModelConfiguration(
        "EasyTaskInitialDesktop",
        schema: schema,
        url: storeURL,
        allowsSave: true,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: configuration)
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-06"))
    let event = EasyTaskLegacySchema.CalendarEvent(
        title: "\(title) event",
        startAt: day,
        endAt: day
    )
    let template = EasyTaskLegacySchema.TaskTemplate(name: "\(title) template")
    let item = EasyTaskLegacySchema.TaskTemplateItem(
        templateId: template.id,
        title: "\(title) template item",
        order: 100
    )
    let task = EasyTaskLegacySchema.Task(
        title: title,
        plannedAt: day,
        order: 100,
        eventId: event.id,
        estimatedMinutes: 50
    )
    let review = EasyTaskLegacySchema.DailyReview(
        dayKey: DayKey.key(for: day),
        title: "\(title) review title",
        content: "\(title) review",
        imageFileNames: ["legacy-review.jpg"]
    )
    let block = EasyTaskLegacySchema.DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .text,
        text: review.content,
        order: 100
    )

    context.insert(event)
    context.insert(template)
    context.insert(item)
    context.insert(task)
    context.insert(review)
    context.insert(block)
    try context.save()
}

@MainActor
private func expectInitialDesktopFixture(
    in container: ModelContainer,
    title: String
) throws {
    let context = container.mainContext
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TaskTemplateItem>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TemplatePlacement>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<DailyReview>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<DiaryBlock>()) == 1)

    let task = try #require(context.fetch(FetchDescriptor<Task>()).first)
    let event = try #require(context.fetch(FetchDescriptor<CalendarEvent>()).first)
    let review = try #require(context.fetch(FetchDescriptor<DailyReview>()).first)
    #expect(task.title == title)
    #expect(task.eventId == event.id)
    #expect(task.templatePlacementId == nil)
    #expect(task.estimatedMinutes == 50)
    #expect(review.title == "\(title) review title")
    #expect(review.content == "\(title) review")
    #expect(review.imageFileNames == ["legacy-review.jpg"])
}

@MainActor
private func writeV1Fixture(to container: ModelContainer, title: String) throws {
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-10"))
    let event = EasyTaskSchemaV1.CalendarEvent(title: "\(title) event", startAt: day, endAt: day)
    let template = EasyTaskSchemaV1.TaskTemplate(name: "\(title) template")
    let templateItem = EasyTaskSchemaV1.TaskTemplateItem(
        templateId: template.id,
        title: "\(title) template item",
        order: 100
    )
    let placement = EasyTaskSchemaV1.TemplatePlacement(
        sourceTemplateId: template.id,
        templateName: template.name,
        dayKey: DayKey.key(for: day)
    )
    let task = EasyTaskSchemaV1.Task(
        title: title,
        plannedAt: day,
        order: 100,
        eventId: event.id
    )
    placement.taskIds = [task.id]
    let review = EasyTaskSchemaV1.DailyReview(
        dayKey: DayKey.key(for: day),
        content: "\(title) review"
    )
    let block = EasyTaskSchemaV1.DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .text,
        text: review.content,
        order: 100
    )

    context.insert(event)
    context.insert(template)
    context.insert(templateItem)
    context.insert(placement)
    context.insert(task)
    context.insert(review)
    context.insert(block)
    try context.save()
}

@MainActor
private func writeV2Fixture(to container: ModelContainer, title: String) throws {
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-10"))
    let event = EasyTaskSchemaV2.CalendarEvent(
        title: "\(title) event",
        startAt: day,
        endAt: day
    )
    let template = EasyTaskSchemaV2.TaskTemplate(name: "\(title) template")
    let templateItem = EasyTaskSchemaV2.TaskTemplateItem(
        templateId: template.id,
        title: "\(title) template item",
        order: 100
    )
    let placement = EasyTaskSchemaV2.TemplatePlacement(
        sourceTemplateId: template.id,
        templateName: template.name,
        dayKey: DayKey.key(for: day)
    )
    let task = EasyTaskSchemaV2.Task(
        title: title,
        plannedAt: day,
        order: 100,
        eventId: event.id,
        templatePlacementId: placement.id
    )
    let review = EasyTaskSchemaV2.DailyReview(
        dayKey: DayKey.key(for: day),
        content: "\(title) review",
        imageFileNames: ["legacy-review.png"]
    )
    let block = EasyTaskSchemaV2.DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .text,
        text: review.content,
        order: 100
    )
    let imageBlock = EasyTaskSchemaV2.DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .image,
        imageFileName: "legacy-block.png",
        order: 200
    )

    context.insert(event)
    context.insert(template)
    context.insert(templateItem)
    context.insert(placement)
    context.insert(task)
    context.insert(review)
    context.insert(block)
    context.insert(imageBlock)
    try context.save()
}

@MainActor
private func writeFixture(to container: ModelContainer, title: String) throws {
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-10"))
    let event = CalendarEvent(title: "\(title) event", startAt: day, endAt: day)
    let template = TaskTemplate(name: "\(title) template")
    let templateItem = TaskTemplateItem(
        templateId: template.id,
        title: "\(title) template item",
        order: 100
    )
    let placement = TemplatePlacement(
        sourceTemplateId: template.id,
        templateName: template.name,
        dayKey: DayKey.key(for: day)
    )
    let task = Task(
        title: title,
        plannedAt: day,
        order: 100,
        eventId: event.id,
        templatePlacementId: placement.id
    )
    placement.taskIds = [task.id]
    let review = DailyReview(dayKey: DayKey.key(for: day), content: "\(title) review")
    let block = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .text,
        text: review.content,
        order: 100
    )

    context.insert(event)
    context.insert(template)
    context.insert(templateItem)
    context.insert(placement)
    context.insert(task)
    context.insert(review)
    context.insert(block)
    try context.save()
}

@MainActor
private func expectFixture(in container: ModelContainer, title: String) throws {
    let context = container.mainContext
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TaskTemplateItem>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<TemplatePlacement>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<DailyReview>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<DiaryBlock>()) >= 1)

    let event = try #require(context.fetch(FetchDescriptor<CalendarEvent>()).first)
    let template = try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first)
    let templateItem = try #require(context.fetch(FetchDescriptor<TaskTemplateItem>()).first)
    let placement = try #require(context.fetch(FetchDescriptor<TemplatePlacement>()).first)
    let task = try #require(context.fetch(FetchDescriptor<Task>()).first)
    let review = try #require(context.fetch(FetchDescriptor<DailyReview>()).first)
    let block = try #require(
        context.fetch(FetchDescriptor<DiaryBlock>())
            .first { $0.type == DiaryBlockType.text.rawValue }
    )
    #expect(event.title == "\(title) event")
    #expect(template.name == "\(title) template")
    #expect(templateItem.title == "\(title) template item")
    #expect(placement.templateName == "\(title) template")
    #expect(task.title == title)
    #expect(task.templatePlacementId == placement.id)
    #expect(review.content == "\(title) review")
    #expect(block.text == "\(title) review")
    #expect(placement.taskIds.isEmpty)
}

@MainActor
private func expectStableInstanceIdentityBackfill(in container: ModelContainer) throws {
    let context = container.mainContext
    let instanceIDs = [
        try #require(context.fetch(FetchDescriptor<CalendarEvent>()).first).instanceID,
        try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first).instanceID,
        try #require(context.fetch(FetchDescriptor<TaskTemplateItem>()).first).instanceID,
        try #require(context.fetch(FetchDescriptor<TemplatePlacement>()).first).instanceID,
        try #require(context.fetch(FetchDescriptor<Task>()).first).instanceID,
        try #require(context.fetch(FetchDescriptor<DailyReview>()).first).instanceID,
        try #require(context.fetch(FetchDescriptor<DiaryBlock>()).first).instanceID
    ]
    #expect(Set(instanceIDs).count == instanceIDs.count)
}

@MainActor
private func withTemporaryStore(
    _ operation: (URL) throws -> Void
) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("EasyTaskSchemaV1-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try operation(directory.appendingPathComponent("default.store"))
}
