import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

private enum PersistenceCommandTestError: Error {
    case injected
}

@Test
@MainActor
func persistenceCommandCommitsSuccessfulMutation() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext

    let task = try PersistenceCommandService.perform(in: context) {
        let task = Task(title: "저장 경계 확인", plannedAt: Date(), order: 100)
        context.insert(task)
        return task
    }

    let storedTasks = try context.fetch(FetchDescriptor<Task>())
    #expect(storedTasks.map(\.id) == [task.id])
}

@Test
@MainActor
func persistenceCommandRollsBackFailedMutationWithoutLosingPriorSave() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let existingTask = Task(title: "기존 작업", plannedAt: Date(), order: 100)
    context.insert(existingTask)

    #expect(throws: PersistenceCommandTestError.injected) {
        try PersistenceCommandService.perform(in: context) {
            context.insert(Task(title: "롤백 작업", plannedAt: Date(), order: 200))
            throw PersistenceCommandTestError.injected
        }
    }

    let storedTitles = try context.fetch(FetchDescriptor<Task>()).map(\.title)
    #expect(storedTitles == ["기존 작업"])
}

@Test
@MainActor
func releaseSeedPolicyCreatesNoRecords() throws {
    let container = try makeSafetyTestContainer()
    let context = container.mainContext

    SeedService.seedIfNeeded(
        context: context,
        tasks: [],
        events: [],
        templates: [],
        reviews: [],
        policy: .release
    )
    try context.save()

    #expect(try safetyRecordCounts(in: context) == SafetyRecordCounts())
}

@Test
func appStartupSeedPolicyMatchesBuildConfiguration() {
#if DEBUG
    #expect(SeedPolicy.appStartup == .demo)
#else
    #expect(SeedPolicy.appStartup == .release)
#endif
}

@Test
@MainActor
func explicitDemoSeedPolicyRemainsAvailable() throws {
    let container = try makeSafetyTestContainer()
    let context = container.mainContext

    SeedService.seedIfNeeded(
        context: context,
        tasks: [],
        events: [],
        templates: [],
        reviews: [],
        policy: .demo
    )

    let counts = try safetyRecordCounts(in: context)
    #expect(counts.tasks > 0)
    #expect(counts.events > 0)
    #expect(counts.templates > 0)
    #expect(counts.templateItems > 0)
    #expect(counts.reviews > 0)
}

@Test
func attachmentFileNamesRejectUnsafePathsAndExtensions() throws {
    let unsafeFileNames = [
        "../photo.jpg",
        "/tmp/photo.jpg",
        "folder/photo.jpg",
        "folder\\photo.jpg",
        "C:\\photo.jpg",
        ".",
        "..",
        ".hidden.jpg",
        "photo..jpg",
        "%2e%2e%2fphoto.jpg",
        "photo.gif"
    ]

    for fileName in unsafeFileNames {
        var caughtError: (any Error)?
        do {
            try DiaryImageFileStore.validateAttachmentFileName(fileName)
        } catch {
            caughtError = error
        }
        #expect(caughtError is DiaryImageFileStoreError, "Expected rejection for \(fileName)")
    }
}

@Test
func importedAttachmentNamesBecomeUUIDBased() throws {
    let storedFileName = try DiaryImageFileStore.storedFileName(importing: "legacy-photo.JPEG")
    let stem = (storedFileName as NSString).deletingPathExtension

    #expect(UUID(uuidString: stem) != nil)
    #expect((storedFileName as NSString).pathExtension == "jpeg")

    let existingStoredFileName = "\(UUID().uuidString).png"
    #expect(
        try DiaryImageFileStore.storedFileName(importing: existingStoredFileName)
            == existingStoredFileName
    )
}

@Test
@MainActor
func backupValidationPreservesSafeLegacyAttachmentNames() throws {
    let originalName = "legacy-photo.jpg"
    var payload = try makeValidSafetyPayload(attachmentFileName: originalName)
    payload = try BackupCodec.decode(BackupCodec.encode(payload))

    #expect(payload.dailyReviews?.first?.imageFileNames == [originalName])
    #expect(payload.diaryBlocks?.first?.imageFileName == originalName)
}

@Test
func oversizedAttachmentDataIsRejectedBeforeStorage() {
    let oversizedData = Data(
        count: DiaryImageFileStore.maximumImageSizeBytes + 1
    )
    var caughtError: (any Error)?

    do {
        _ = try DiaryImageFileStore.writeImageData(
            oversizedData,
            appSupportFolder: "DataSafetyTests-\(UUID().uuidString)"
        )
    } catch {
        caughtError = error
    }

    guard case .fileTooLarge = caughtError as? DiaryImageFileStoreError else {
        Issue.record("Expected an oversized attachment error")
        return
    }
}

@Test
@MainActor
func malformedBackupLeavesExistingDataUnchanged() throws {
    let validPayload = try makeValidSafetyPayload()
    let encodedPayload = try BackupCodec.encode(validPayload)
    var json = try #require(
        JSONSerialization.jsonObject(with: encodedPayload) as? [String: Any]
    )
    json.removeValue(forKey: "tasks")
    let malformedData = try JSONSerialization.data(withJSONObject: json)

    let container = try makeSafetyTestContainer()
    let context = container.mainContext
    try insertExistingSafetyRecord(in: context)
    let before = try safetySnapshot(in: context)

    var caughtError: (any Error)?
    do {
        let payload = try BackupCodec.decode(malformedData)
        try BackupCodec.replaceAll(with: payload, in: context)
    } catch {
        caughtError = error
    }

    #expect(caughtError != nil)
    #expect(try safetySnapshot(in: context) == before)
}

@Test
@MainActor
func duplicateBackupIDsLeaveExistingDataUnchanged() throws {
    var payload = try makeValidSafetyPayload()
    payload.tasks.append(try #require(payload.tasks.first))

    try assertRejectedRestorePreservesExistingData(payload)
}

@Test
@MainActor
func danglingBackupReferencesLeaveExistingDataUnchanged() throws {
    var payload = try makeValidSafetyPayload()
    payload.tasks[0].eventId = UUID()

    try assertRejectedRestorePreservesExistingData(payload)
}

@Test
@MainActor
func invalidBackupEnumsAndDayKeysLeaveExistingDataUnchanged() throws {
    var invalidEnumPayload = try makeValidSafetyPayload()
    invalidEnumPayload.tasks[0].status = "blocked"
    try assertRejectedRestorePreservesExistingData(invalidEnumPayload)

    var invalidColorPayload = try makeValidSafetyPayload()
    invalidColorPayload.calendarEvents[0].color = "cyan"
    try assertRejectedRestorePreservesExistingData(invalidColorPayload)

    var invalidDayKeyPayload = try makeValidSafetyPayload()
    invalidDayKeyPayload.tasks[0].plannedDayKey = "2026-02-30"
    try assertRejectedRestorePreservesExistingData(invalidDayKeyPayload)

    var reversedEventRangePayload = try makeValidSafetyPayload()
    reversedEventRangePayload.calendarEvents[0].startDayKey = "2026-07-11"
    reversedEventRangePayload.calendarEvents[0].endDayKey = "2026-07-10"
    try assertRejectedRestorePreservesExistingData(reversedEventRangePayload)
}

@Test
@MainActor
func unsafeBackupImageNamesLeaveExistingDataUnchanged() throws {
    var payload = try makeValidSafetyPayload()
    payload.dailyReviews?[0].imageFileNames = ["../photo.jpg"]

    try assertRejectedRestorePreservesExistingData(payload)
}

@Test
@MainActor
func validRestoreIsDurableAfterReopeningStore() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseDataSafety-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let storeURL = directory.appendingPathComponent("Restore.store")
    let exportedPayload = try makeValidSafetyPayload(attachmentFileName: "legacy-photo.jpg")
    let payload = try BackupCodec.decode(BackupCodec.encode(exportedPayload))
    try restoreSafetyPayload(payload, at: storeURL)

    let reopenedContainer = try makeSafetyTestContainer(
        configuration: ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
    )
    let context = reopenedContainer.mainContext
    let counts = try safetyRecordCounts(in: context)

    #expect(counts == SafetyRecordCounts(
        tasks: 1,
        events: 1,
        templates: 1,
        templateItems: 1,
        placements: 1,
        reviews: 1,
        blocks: 1
    ))

    let task = try #require(context.fetch(FetchDescriptor<Task>()).first)
    #expect(task.title == "replacement task")

    let review = try #require(context.fetch(FetchDescriptor<DailyReview>()).first)
    let block = try #require(context.fetch(FetchDescriptor<DiaryBlock>()).first)
    let storedFileName = try #require(review.imageFileNames.first)
    #expect(storedFileName == "legacy-photo.jpg")
    #expect(block.imageFileName == storedFileName)
}

@Test
@MainActor
func deletingPlacedTaskRemovesPlacementMembership() throws {
    let container = try makeSafetyTestContainer()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-10"))
    let placement = TemplatePlacement(
        sourceTemplateId: nil,
        templateName: "placement",
        dayKey: DayKey.key(for: day)
    )
    let task = Task(
        title: "placed task",
        plannedAt: day,
        order: 100,
        templatePlacementId: placement.id
    )
    context.insert(placement)
    context.insert(task)
    try context.save()

    try TaskRules.delete(task, from: context)
    try context.save()

    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 0)
    let payload = try BackupCodec.decode(BackupCodec.encode(BackupCodec.makePayload(context: context)))
    #expect(payload.templatePlacements?.first?.taskIds.isEmpty == true)
}

@Test
@MainActor
func backupExportRepairsLegacyStalePlacementMembership() throws {
    let container = try makeSafetyTestContainer()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-10"))
    let placement = TemplatePlacement(
        sourceTemplateId: nil,
        templateName: "legacy placement",
        dayKey: DayKey.key(for: day),
        taskIds: [UUID()]
    )
    context.insert(placement)
    try context.save()

    let payload = try BackupCodec.makePayload(context: context)
    #expect(payload.templatePlacements?.first?.taskIds.isEmpty == true)
    _ = try BackupCodec.decode(BackupCodec.encode(payload))
}

@Test
@MainActor
func backupDayKeysRemainPortableAcrossDateOffsets() throws {
    var payload = try makeValidSafetyPayload()
    let originalTaskKey = payload.tasks[0].plannedDayKey
    let originalEventStartKey = payload.calendarEvents[0].startDayKey
    let originalEventEndKey = payload.calendarEvents[0].endDayKey
    payload.tasks[0].plannedAt = DayKey.addingDays(-1, to: payload.tasks[0].plannedAt)
    payload.calendarEvents[0].startAt = DayKey.addingDays(-1, to: payload.calendarEvents[0].startAt)
    payload.calendarEvents[0].endAt = DayKey.addingDays(-1, to: payload.calendarEvents[0].endAt)

    let decoded = try BackupCodec.decode(BackupCodec.encode(payload))

    #expect(decoded.tasks[0].plannedDayKey == originalTaskKey)
    #expect(decoded.calendarEvents[0].startDayKey == originalEventStartKey)
    #expect(decoded.calendarEvents[0].endDayKey == originalEventEndKey)
}

@Test
@MainActor
func injectedRestoreFailureRollsBackDurableStore() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlanBaseRollbackSafety-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let storeURL = directory.appendingPathComponent("Rollback.store")
    try createExistingSafetyStore(at: storeURL)
    let replacement = try makeValidSafetyPayload()
    try attemptInjectedRestoreFailure(replacement, at: storeURL)

    let reopened = try makeSafetyTestContainer(
        configuration: ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
    )
    let tasks = try reopened.mainContext.fetch(FetchDescriptor<Task>())
    #expect(tasks.count == 1)
    #expect(tasks.first?.title == "existing task")
}

private enum InjectedRestoreFailure: Error {
    case beforeFinalSave
}

private struct SafetyRecordCounts: Equatable {
    var tasks = 0
    var events = 0
    var templates = 0
    var templateItems = 0
    var placements = 0
    var reviews = 0
    var blocks = 0
}

@MainActor
private func makeSafetyTestContainer(
    configuration: ModelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
) throws -> ModelContainer {
    try ModelContainer(
        for: Task.self,
        CalendarEvent.self,
        TaskTemplate.self,
        TaskTemplateItem.self,
        TemplatePlacement.self,
        DailyReview.self,
        DiaryBlock.self,
        configurations: configuration
    )
}

@MainActor
private func safetyRecordCounts(in context: ModelContext) throws -> SafetyRecordCounts {
    SafetyRecordCounts(
        tasks: try context.fetchCount(FetchDescriptor<Task>()),
        events: try context.fetchCount(FetchDescriptor<CalendarEvent>()),
        templates: try context.fetchCount(FetchDescriptor<TaskTemplate>()),
        templateItems: try context.fetchCount(FetchDescriptor<TaskTemplateItem>()),
        placements: try context.fetchCount(FetchDescriptor<TemplatePlacement>()),
        reviews: try context.fetchCount(FetchDescriptor<DailyReview>()),
        blocks: try context.fetchCount(FetchDescriptor<DiaryBlock>())
    )
}

@MainActor
private func makeValidSafetyPayload(
    attachmentFileName: String = "\(UUID().uuidString).jpg"
) throws -> BackupPayload {
    let container = try makeSafetyTestContainer()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-10"))
    let event = CalendarEvent(title: "replacement event", startAt: day, endAt: day)
    let template = TaskTemplate(name: "replacement template")
    let item = TaskTemplateItem(
        templateId: template.id,
        title: "replacement item",
        priority: TaskPriority.medium.rawValue,
        order: 100
    )
    let placement = TemplatePlacement(
        sourceTemplateId: template.id,
        templateName: template.name,
        dayKey: DayKey.key(for: day)
    )
    let task = Task(
        title: "replacement task",
        plannedAt: day,
        order: 100,
        eventId: event.id,
        templatePlacementId: placement.id,
        priority: .high
    )
    placement.taskIds = [task.id]
    let review = DailyReview(
        dayKey: DayKey.key(for: day),
        content: "replacement review",
        imageFileNames: [attachmentFileName]
    )
    let block = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .image,
        imageFileName: attachmentFileName,
        order: 100
    )

    context.insert(event)
    context.insert(template)
    context.insert(item)
    context.insert(placement)
    context.insert(task)
    context.insert(review)
    context.insert(block)
    try context.save()
    return try BackupCodec.makePayload(context: context)
}

@MainActor
private func insertExistingSafetyRecord(in context: ModelContext) throws {
    let day = try #require(DayKey.date(from: "2026-07-09"))
    context.insert(Task(title: "existing task", plannedAt: day, order: 100))
    try context.save()
}

@MainActor
private func safetySnapshot(in context: ModelContext) throws -> Data {
    var payload = try BackupCodec.makePayload(context: context)
    payload.exportedAt = Date(timeIntervalSince1970: 0)
    return try BackupCodec.encode(payload)
}

@MainActor
private func assertRejectedRestorePreservesExistingData(_ payload: BackupPayload) throws {
    let container = try makeSafetyTestContainer()
    let context = container.mainContext
    try insertExistingSafetyRecord(in: context)
    let before = try safetySnapshot(in: context)
    var caughtError: (any Error)?

    do {
        try BackupCodec.replaceAll(with: payload, in: context)
    } catch {
        caughtError = error
    }

    #expect(caughtError != nil)
    #expect(try safetySnapshot(in: context) == before)
}

@MainActor
private func restoreSafetyPayload(_ payload: BackupPayload, at storeURL: URL) throws {
    let container = try makeSafetyTestContainer(
        configuration: ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
    )
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-08"))
    context.insert(Task(title: "record to replace", plannedAt: day, order: 100))
    try context.save()

    try BackupCodec.replaceAll(with: payload, in: context)
    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 1)
    #expect(try context.fetch(FetchDescriptor<Task>()).first?.title == "replacement task")
}

@MainActor
private func createExistingSafetyStore(at storeURL: URL) throws {
    let container = try makeSafetyTestContainer(
        configuration: ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
    )
    try insertExistingSafetyRecord(in: container.mainContext)
}

@MainActor
private func attemptInjectedRestoreFailure(
    _ payload: BackupPayload,
    at storeURL: URL
) throws {
    let container = try makeSafetyTestContainer(
        configuration: ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
    )
    let context = container.mainContext
    var caughtError: (any Error)?

    do {
        try BackupCodec.replaceAll(
            with: payload,
            in: context,
            beforeFinalSave: { throw InjectedRestoreFailure.beforeFinalSave }
        )
    } catch {
        caughtError = error
    }

    #expect(caughtError is InjectedRestoreFailure)
    let tasks = try context.fetch(FetchDescriptor<Task>())
    #expect(tasks.count == 1)
    #expect(tasks.first?.title == "existing task")
}
