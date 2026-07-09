import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

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
        .appendingPathComponent("EasyTaskDataSafety-\(UUID().uuidString)", isDirectory: true)
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
    let stem = (storedFileName as NSString).deletingPathExtension
    #expect(UUID(uuidString: stem) != nil)
    #expect(block.imageFileName == storedFileName)
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
