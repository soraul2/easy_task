import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func backupPackageRoundTripIncludesAttachmentBytes() throws {
    let source = try EasyTaskContainerFactory.makeInMemory()
    let png = testPNG(0x11)
    let review = try #require(try DiaryAttachmentService.saveReview(
        review: nil,
        dayKey: "2026-07-11",
        title: "패키지 백업",
        content: "이미지 포함",
        attachments: [DiaryAttachmentDraft(data: png, originalFileName: "source.png")],
        in: source.mainContext
    ))
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let packageURL = temporaryPackageURL()
    defer { try? FileManager.default.removeItem(at: packageURL) }

    try BackupPackageCodec.write(contents, to: packageURL)
    let decoded = try BackupPackageCodec.read(from: packageURL)

    #expect(decoded.manifest.formatVersion == BackupPackageCodec.currentVersion)
    #expect(decoded.records.payload.dailyReviews?.first?.id == review.id)
    #expect(decoded.records.payload.dailyReviews?.first?.imageFileNames == [])
    #expect(decoded.records.attachments.count == 1)
    #expect(decoded.attachmentData.values.first == png)
    #expect(FileManager.default.fileExists(
        atPath: packageURL.appendingPathComponent("manifest.json").path
    ))
}

@Test
@MainActor
func backupPackageReadsV2AndWritesV4() throws {
    let source = try EasyTaskContainerFactory.makeInMemory()
    var legacyContents = try BackupPackageCodec.makeContents(context: source.mainContext)
    legacyContents.manifest.formatVersion = 2
    legacyContents.records.formatVersion = 2
    refreshRecordsMetadata(&legacyContents)

    try BackupPackageCodec.validate(legacyContents)
    let current = try BackupPackageCodec.makeContents(context: source.mainContext)
    #expect(current.manifest.formatVersion == 4)
    #expect(current.records.formatVersion == 4)
}

@Test
@MainActor
func backupPackageRoundTripsTaskReminderAndRejectsIdentityMismatch() throws {
    let source = try EasyTaskContainerFactory.makeInMemory()
    let day = try #require(DayKey.date(from: "2026-07-12"))
    let reminderAt = Date(timeIntervalSinceReferenceDate: 120_000)
    let task = Task(
        title: "백업 알림",
        plannedAt: day,
        order: 100,
        reminderAt: reminderAt
    )
    source.mainContext.insert(task)
    try source.mainContext.save()
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    #expect(contents.records.payload.tasks.first?.reminderAt == reminderAt)

    let destination = try EasyTaskContainerFactory.makeInMemory()
    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    let restored = try #require(destination.mainContext.fetch(FetchDescriptor<Task>()).first)
    #expect(restored.reminderAt == reminderAt)

    var tampered = contents
    tampered.records.payload.tasks[0].reminderAt = reminderAt.addingTimeInterval(60)
    refreshRecordsMetadata(&tampered)
    #expect(throws: BackupPackageError.identityCorruption(
        recordType: "Task",
        instanceID: task.instanceID
    )) {
        try BackupPackageCodec.restoreMerging(tampered, into: destination.mainContext)
    }
}

@Test
@MainActor
func v2PackageMergePreservesExistingTaskReminderWhenFieldIsAbsent() throws {
    let id = UUID()
    let instanceID = UUID()
    let plannedAt = try #require(DayKey.date(from: "2026-07-12"))
    let reminderAt = Date(timeIntervalSince1970: 1_900_000_020)
    let destination = try taskReminderMergeContainer(
        id: id,
        instanceID: instanceID,
        title: "로컬 제목",
        plannedAt: plannedAt,
        reminderAt: reminderAt,
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let source = try taskReminderMergeContainer(
        id: id,
        instanceID: instanceID,
        title: "V2에서 수정된 제목",
        plannedAt: plannedAt,
        reminderAt: nil,
        updatedAt: Date(timeIntervalSince1970: 300)
    )
    var contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    contents.manifest.formatVersion = 2
    contents.records.formatVersion = 2
    refreshRecordsMetadata(&contents)
    let packageURL = temporaryPackageURL()
    defer { try? FileManager.default.removeItem(at: packageURL) }

    try BackupPackageCodec.write(contents, to: packageURL)
    let recordsData = try Data(contentsOf: packageURL.appendingPathComponent("records.json"))
    let recordsJSON = try #require(String(data: recordsData, encoding: .utf8))
    #expect(!recordsJSON.contains("\"reminderAt\""))

    let decoded = try BackupPackageCodec.read(from: packageURL)
    let firstMerge = try BackupPackageCodec.restoreMerging(decoded, into: destination.mainContext)
    let secondMerge = try BackupPackageCodec.restoreMerging(decoded, into: destination.mainContext)
    let restored = try #require(
        destination.mainContext.fetch(FetchDescriptor<Task>()).first {
            $0.instanceID == instanceID
        }
    )
    #expect(firstMerge.updatedRecords == 1)
    #expect(secondMerge.preservedLocalRecords == 1)
    #expect(restored.title == "V2에서 수정된 제목")
    #expect(restored.reminderAt == reminderAt)
}

@Test
@MainActor
func v3PackageMergeTreatsNilTaskReminderAsExplicitClear() throws {
    let id = UUID()
    let instanceID = UUID()
    let plannedAt = try #require(DayKey.date(from: "2026-07-12"))
    let destination = try taskReminderMergeContainer(
        id: id,
        instanceID: instanceID,
        title: "로컬 제목",
        plannedAt: plannedAt,
        reminderAt: Date(timeIntervalSince1970: 1_900_000_020),
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let source = try taskReminderMergeContainer(
        id: id,
        instanceID: instanceID,
        title: "V3에서 수정된 제목",
        plannedAt: plannedAt,
        reminderAt: nil,
        updatedAt: Date(timeIntervalSince1970: 300)
    )
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)

    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    let restored = try #require(
        destination.mainContext.fetch(FetchDescriptor<Task>()).first {
            $0.instanceID == instanceID
        }
    )
    #expect(restored.title == "V3에서 수정된 제목")
    #expect(restored.reminderAt == nil)
}

@Test
@MainActor
func legacyJSONMergePreservesExistingTaskReminder() throws {
    let id = UUID()
    let instanceID = UUID()
    let plannedAt = try #require(DayKey.date(from: "2026-07-12"))
    let reminderAt = Date(timeIntervalSince1970: 1_900_000_020)
    let destination = try taskReminderMergeContainer(
        id: id,
        instanceID: instanceID,
        title: "로컬 제목",
        plannedAt: plannedAt,
        reminderAt: reminderAt,
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let source = try taskReminderMergeContainer(
        id: id,
        instanceID: instanceID,
        title: "레거시에서 수정된 제목",
        plannedAt: plannedAt,
        reminderAt: nil,
        updatedAt: Date(timeIntervalSince1970: 300)
    )
    let payload = try BackupCodec.makePayload(context: source.mainContext)

    _ = try BackupPackageCodec.restoreLegacyJSONMerging(
        payload,
        into: destination.mainContext
    )
    _ = try BackupPackageCodec.restoreLegacyJSONMerging(
        payload,
        into: destination.mainContext
    )
    let restored = try #require(
        destination.mainContext.fetch(FetchDescriptor<Task>()).first {
            $0.instanceID == instanceID
        }
    )
    #expect(restored.title == "레거시에서 수정된 제목")
    #expect(restored.reminderAt == reminderAt)
}

@Test
@MainActor
func tamperedPackageChecksumIsRejectedBeforeRestore() throws {
    let source = try packageSourceContainer(image: testPNG(0x12))
    var contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let attachmentID = try #require(contents.records.attachments.first?.id)
    contents.attachmentData[attachmentID] = testPNG(0x13)

    #expect(throws: BackupPackageError.attachmentChecksumMismatch(attachmentID)) {
        try BackupPackageCodec.validate(contents)
    }

    let destination = try EasyTaskContainerFactory.makeInMemory()
    let local = DailyReview(dayKey: "2026-07-10", content: "로컬 유지")
    destination.mainContext.insert(local)
    try destination.mainContext.save()
    #expect(throws: BackupPackageError.attachmentChecksumMismatch(attachmentID)) {
        try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    }
    let reviews = try destination.mainContext.fetch(FetchDescriptor<DailyReview>())
    #expect(reviews.count == 1)
    #expect(reviews.first?.content == "로컬 유지")
}

@Test
@MainActor
func importingSamePackageTwiceCreatesNoDuplicates() throws {
    let source = try packageSourceContainer(image: testPNG(0x14))
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let destination = try EasyTaskContainerFactory.makeInMemory()

    let first = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    let second = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)

    #expect(first.insertedAttachments == 1)
    #expect(second.insertedAttachments == 0)
    #expect(try destination.mainContext.fetch(FetchDescriptor<DailyReview>()).count == 1)
    #expect(try destination.mainContext.fetch(FetchDescriptor<DiaryAttachment>()).count == 1)
    #expect(try destination.mainContext.fetch(FetchDescriptor<DiaryBlock>()).count == 1)
}

@Test
@MainActor
func repeatedImportRemainsIdempotentAfterReviewReconciliation() throws {
    let lowerInstanceID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let higherInstanceID = UUID(uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")!
    let timestamp = Date(timeIntervalSince1970: 450)
    let source = try reviewContainer(
        id: UUID(),
        instanceID: lowerInstanceID,
        content: "백업 회고",
        updatedAt: timestamp
    )
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let destination = try reviewContainer(
        id: UUID(),
        instanceID: higherInstanceID,
        content: "동일 날짜 로컬 회고",
        updatedAt: timestamp
    )

    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)

    let reviews = try destination.mainContext.fetch(FetchDescriptor<DailyReview>())
    let active = try #require(reviews.first { $0.supersededAt == nil })
    #expect(reviews.count == 2)
    #expect(active.instanceID == higherInstanceID)
    #expect(active.content == "동일 날짜 로컬 회고")

    var tampered = contents
    tampered.records.payload.dailyReviews?[0].content = "변조된 백업 회고"
    refreshRecordsMetadata(&tampered)
    #expect(throws: BackupPackageError.identityCorruption(
        recordType: "DailyReview",
        instanceID: lowerInstanceID
    )) {
        try BackupPackageCodec.restoreMerging(tampered, into: destination.mainContext)
    }
}

@Test
@MainActor
func reconciledDuplicateDoesNotMaskLaterIdentityCorruption() throws {
    let logicalID = UUID()
    let lowerInstanceID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let higherInstanceID = UUID(uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")!
    let timestamp = Date(timeIntervalSince1970: 460)
    let source = try reviewContainer(
        id: logicalID,
        instanceID: lowerInstanceID,
        content: "백업 원본",
        updatedAt: timestamp
    )
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let destination = try EasyTaskContainerFactory.makeInMemory()
    destination.mainContext.insert(DailyReview(
        id: logicalID,
        instanceID: lowerInstanceID,
        dayKey: "2026-07-11",
        content: "낮은 인스턴스",
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: timestamp
    ))
    destination.mainContext.insert(DailyReview(
        id: UUID(),
        instanceID: higherInstanceID,
        dayKey: "2026-07-11",
        content: "정상 승자",
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: timestamp
    ))
    try destination.mainContext.save()
    _ = try DataIntegrityService.reconcile(context: destination.mainContext)
    let active = try #require(destination.mainContext
        .fetch(FetchDescriptor<DailyReview>()).first { $0.supersededAt == nil })
    active.content = "타임스탬프 없는 손상"
    try destination.mainContext.save()

    #expect(throws: BackupPackageError.identityCorruption(
        recordType: "DailyReview",
        instanceID: lowerInstanceID
    )) {
        try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    }
}

@Test
@MainActor
func mergeRollsBackWhenReconciledReviewExceedsAttachmentLimit() throws {
    let firstSource = try packageSourceContainer(
        imageCount: 6,
        markerOffset: 0x20
    )
    let secondSource = try packageSourceContainer(
        imageCount: 6,
        markerOffset: 0x30
    )
    let firstContents = try BackupPackageCodec.makeContents(context: firstSource.mainContext)
    let secondContents = try BackupPackageCodec.makeContents(context: secondSource.mainContext)
    let destination = try EasyTaskContainerFactory.makeInMemory()

    _ = try BackupPackageCodec.restoreMerging(firstContents, into: destination.mainContext)
    #expect(throws: BackupPackageError.tooManyAttachments(actual: 12, maximum: 10)) {
        try BackupPackageCodec.restoreMerging(secondContents, into: destination.mainContext)
    }

    let activeReviews = try destination.mainContext.fetch(FetchDescriptor<DailyReview>())
        .filter { $0.supersededAt == nil }
    let activeAttachments = try destination.mainContext.fetch(FetchDescriptor<DiaryAttachment>())
        .filter { $0.supersededAt == nil }
    #expect(activeReviews.count == 1)
    #expect(activeAttachments.count == 6)
}

@Test
@MainActor
func packageMergePreservesNewerLocalReview() throws {
    let reviewID = UUID()
    let source = try EasyTaskContainerFactory.makeInMemory()
    source.mainContext.insert(DailyReview(
        id: reviewID,
        dayKey: "2026-07-11",
        content: "오래된 백업",
        createdAt: Date(timeIntervalSince1970: 50),
        updatedAt: Date(timeIntervalSince1970: 100)
    ))
    try source.mainContext.save()
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)

    let destination = try EasyTaskContainerFactory.makeInMemory()
    destination.mainContext.insert(DailyReview(
        id: reviewID,
        dayKey: "2026-07-11",
        content: "더 최신 로컬",
        createdAt: Date(timeIntervalSince1970: 50),
        updatedAt: Date(timeIntervalSince1970: 200)
    ))
    try destination.mainContext.save()

    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)

    let restored = try #require(
        destination.mainContext.fetch(FetchDescriptor<DailyReview>())
            .first { $0.supersededAt == nil }
    )
    #expect(restored.content == "더 최신 로컬")
    #expect(restored.updatedAt == Date(timeIntervalSince1970: 200))
}

@Test
@MainActor
func packageMergeFailureRollsBackDatabaseAndAttachment() throws {
    struct InjectedFailure: Error {}

    let source = try packageSourceContainer(image: testPNG(0x15))
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let destination = try EasyTaskContainerFactory.makeInMemory()
    let local = DailyReview(dayKey: "2026-07-09", content: "롤백 기준")
    destination.mainContext.insert(local)
    try destination.mainContext.save()

    #expect(throws: InjectedFailure.self) {
        try BackupPackageCodec.restoreMerging(
            contents,
            into: destination.mainContext,
            beforeFinalSave: { throw InjectedFailure() }
        )
    }

    let reviews = try destination.mainContext.fetch(FetchDescriptor<DailyReview>())
    let attachments = try destination.mainContext.fetch(FetchDescriptor<DiaryAttachment>())
    #expect(reviews.count == 1)
    #expect(reviews.first?.id == local.id)
    #expect(attachments.isEmpty)
}

@Test
@MainActor
func packageReadRejectsTamperedRecordsAndUndeclaredFiles() throws {
    let source = try packageSourceContainer(image: testPNG(0x16))
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let packageURL = temporaryPackageURL()
    defer { try? FileManager.default.removeItem(at: packageURL) }
    try BackupPackageCodec.write(contents, to: packageURL)

    let recordsURL = packageURL.appendingPathComponent(BackupPackageCodec.recordsFileName)
    var recordsData = try Data(contentsOf: recordsURL)
    recordsData[recordsData.startIndex] ^= 0x01
    try recordsData.write(to: recordsURL, options: .atomic)
    #expect(throws: BackupPackageError.recordsChecksumMismatch) {
        try BackupPackageCodec.read(from: packageURL)
    }

    try BackupPackageCodec.write(contents, to: packageURL)
    let undeclaredURL = packageURL
        .appendingPathComponent(BackupPackageCodec.attachmentsDirectoryName, isDirectory: true)
        .appendingPathComponent("undeclared.png")
    try testPNG(0x17).write(to: undeclaredURL)
    #expect(throws: BackupPackageError.unexpectedFile("undeclared.png")) {
        try BackupPackageCodec.read(from: packageURL)
    }
}

@Test
@MainActor
func packageReadRejectsAttachmentTraversalBeforeFileAccess() throws {
    let source = try packageSourceContainer(image: testPNG(0x19))
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let packageURL = temporaryPackageURL()
    defer { try? FileManager.default.removeItem(at: packageURL) }
    try BackupPackageCodec.write(contents, to: packageURL)

    var manifest = contents.manifest
    manifest.attachments[0].fileName = "../outside.png"
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(
        to: packageURL.appendingPathComponent(BackupPackageCodec.manifestFileName),
        options: .atomic
    )

    #expect(throws: BackupPackageError.invalidFileName("../outside.png")) {
        try BackupPackageCodec.read(from: packageURL)
    }
}

@Test
@MainActor
func packageValidationRejectsDuplicateManifestEntries() throws {
    let source = try packageSourceContainer(image: testPNG(0x18))
    var contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let duplicate = try #require(contents.manifest.attachments.first)
    contents.manifest.attachments.append(duplicate)

    #expect(throws: BackupPackageError.duplicateAttachmentID(duplicate.id)) {
        try BackupPackageCodec.validate(contents)
    }
}

@Test
@MainActor
func packageValidationRejectsDuplicateAttachmentInstanceIDs() throws {
    let source = try packageSourceContainer(imageCount: 2, markerOffset: 0x40)
    var contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    contents.records.attachments[1].instanceID = contents.records.attachments[0].instanceID
    refreshRecordsMetadata(&contents)

    #expect(throws: BackupPackageError.duplicateInstanceID(
        recordType: "DiaryAttachment",
        instanceID: contents.records.attachments[0].instanceID
    )) {
        try BackupPackageCodec.validate(contents)
    }
}

@Test
@MainActor
func packageValidationRejectsNonCanonicalAttachmentOrder() throws {
    let source = try packageSourceContainer(imageCount: 2, markerOffset: 0x48)
    var contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let attachmentID = contents.records.attachments[1].id
    contents.records.attachments[1].order = 50
    refreshRecordsMetadata(&contents)

    #expect(throws: BackupPackageError.invalidAttachmentMetadata(attachmentID)) {
        try BackupPackageCodec.validate(contents)
    }
}

@Test
@MainActor
func packageExportRejectsUnresolvedLegacyImageReferences() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    container.mainContext.insert(DailyReview(
        dayKey: "2026-07-11",
        content: "이관 대기",
        imageFileNames: ["legacy.jpg"]
    ))
    try container.mainContext.save()

    #expect(throws: BackupPackageError.unresolvedLegacyAttachments(1)) {
        try BackupPackageCodec.makeContents(context: container.mainContext)
    }
}

@Test
@MainActor
func sameInstanceAndTimestampWithDifferentContentIsRejected() throws {
    let logicalID = UUID()
    let instanceID = UUID()
    let timestamp = Date(timeIntervalSince1970: 300)
    let source = try reviewContainer(
        id: logicalID,
        instanceID: instanceID,
        content: "source",
        updatedAt: timestamp
    )
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let destination = try reviewContainer(
        id: logicalID,
        instanceID: instanceID,
        content: "different local",
        updatedAt: timestamp
    )

    #expect(throws: BackupPackageError.identityCorruption(
        recordType: "DailyReview",
        instanceID: instanceID
    )) {
        try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    }
    let local = try #require(destination.mainContext.fetch(FetchDescriptor<DailyReview>()).first)
    #expect(local.content == "different local")
}

@Test
@MainActor
func sameTaskInstanceRejectsDifferentValidEventRelationship() throws {
    let source = try EasyTaskContainerFactory.makeInMemory()
    let day = try #require(DayKey.date(from: "2026-07-11"))
    let firstEvent = CalendarEvent(title: "첫 이벤트", startAt: day, endAt: day)
    let secondEvent = CalendarEvent(title: "둘째 이벤트", startAt: day, endAt: day)
    let task = Task(
        title: "연결 검증",
        plannedAt: day,
        order: 0,
        eventId: firstEvent.id
    )
    source.mainContext.insert(firstEvent)
    source.mainContext.insert(secondEvent)
    source.mainContext.insert(task)
    try source.mainContext.save()
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let destination = try EasyTaskContainerFactory.makeInMemory()
    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)

    var tampered = contents
    let taskIndex = try #require(tampered.records.payload.tasks.firstIndex {
        $0.id == task.id
    })
    tampered.records.payload.tasks[taskIndex].eventId = secondEvent.id
    refreshRecordsMetadata(&tampered)

    #expect(throws: BackupPackageError.identityCorruption(
        recordType: "Task",
        instanceID: task.instanceID
    )) {
        try BackupPackageCodec.restoreMerging(tampered, into: destination.mainContext)
    }
}

@Test
@MainActor
func repeatedAttachmentImportSurvivesCanonicalReviewRewire() throws {
    let source = try packageSourceContainer(image: testPNG(0x55))
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let sourceReview = try #require(contents.records.payload.dailyReviews?.first)
    let destination = try EasyTaskContainerFactory.makeInMemory()
    let localReview = DailyReview(
        id: UUID(),
        instanceID: UUID(uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")!,
        dayKey: sourceReview.dayKey,
        content: "동일 날짜 로컬 회고",
        createdAt: sourceReview.createdAt,
        updatedAt: sourceReview.updatedAt
    )
    destination.mainContext.insert(localReview)
    try destination.mainContext.save()

    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)

    let activeReviews = try destination.mainContext.fetch(FetchDescriptor<DailyReview>())
        .filter { $0.supersededAt == nil }
    let activeAttachments = try destination.mainContext.fetch(FetchDescriptor<DiaryAttachment>())
        .filter { $0.supersededAt == nil }
    #expect(activeReviews.count == 1)
    #expect(activeReviews.first?.id == localReview.id)
    #expect(activeAttachments.count == 1)
    #expect(activeAttachments.first?.reviewId == localReview.id)
}

@Test
@MainActor
func rewiredAttachmentImportRejectsRelativeOrderTampering() throws {
    let source = try packageSourceContainer(imageCount: 2, markerOffset: 0x58)
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let sourceReview = try #require(contents.records.payload.dailyReviews?.first)
    let destination = try EasyTaskContainerFactory.makeInMemory()
    destination.mainContext.insert(DailyReview(
        id: UUID(),
        instanceID: UUID(uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")!,
        dayKey: sourceReview.dayKey,
        content: "동일 날짜 로컬 회고",
        createdAt: sourceReview.createdAt,
        updatedAt: sourceReview.updatedAt
    ))
    try destination.mainContext.save()
    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)

    var tampered = contents
    let firstInstanceID = tampered.records.attachments[0].instanceID
    let firstOrder = tampered.records.attachments[0].order
    tampered.records.attachments[0].order = tampered.records.attachments[1].order
    tampered.records.attachments[1].order = firstOrder
    refreshRecordsMetadata(&tampered)
    try BackupPackageCodec.validate(tampered)

    #expect(throws: BackupPackageError.identityCorruption(
        recordType: "DiaryAttachment",
        instanceID: firstInstanceID
    )) {
        try BackupPackageCodec.restoreMerging(tampered, into: destination.mainContext)
    }
}

@Test
@MainActor
func rewiredAttachmentImportAcceptsPartiallyOverlappingSnapshot() throws {
    let source = try packageSourceContainer(imageCount: 2, markerOffset: 0x5A)
    let fullContents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let sourceReview = try #require(fullContents.records.payload.dailyReviews?.first)
    var partialContents = fullContents
    let retainedRecord = partialContents.records.attachments[0]
    partialContents.records.attachments = [retainedRecord]
    partialContents.attachmentData = [
        retainedRecord.id: try #require(partialContents.attachmentData[retainedRecord.id])
    ]
    partialContents.manifest.attachments = partialContents.manifest.attachments.filter {
        $0.id == retainedRecord.id
    }
    partialContents.manifest.totalAttachmentBytes = retainedRecord.byteCount
    refreshRecordsMetadata(&partialContents)
    try BackupPackageCodec.validate(partialContents)

    let destination = try EasyTaskContainerFactory.makeInMemory()
    let localReview = DailyReview(
        id: UUID(),
        instanceID: UUID(uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")!,
        dayKey: sourceReview.dayKey,
        content: "동일 날짜 로컬 회고",
        createdAt: sourceReview.createdAt,
        updatedAt: sourceReview.updatedAt
    )
    destination.mainContext.insert(localReview)
    try destination.mainContext.save()

    _ = try BackupPackageCodec.restoreMerging(partialContents, into: destination.mainContext)
    _ = try BackupPackageCodec.restoreMerging(fullContents, into: destination.mainContext)

    let activeAttachments = try destination.mainContext.fetch(FetchDescriptor<DiaryAttachment>())
        .filter { $0.supersededAt == nil }
        .sorted { $0.order < $1.order }
    #expect(activeAttachments.count == 2)
    #expect(activeAttachments.allSatisfy { $0.reviewId == localReview.id })
    #expect(activeAttachments.map(\.instanceID) == fullContents.records.attachments.map(\.instanceID))
}

@Test
@MainActor
func olderSnapshotPreservesNewerLocalAttachmentOrder() throws {
    let source = try packageSourceContainer(imageCount: 2, markerOffset: 0x5C)
    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    let destination = try EasyTaskContainerFactory.makeInMemory()
    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)

    let review = try #require(destination.mainContext
        .fetch(FetchDescriptor<DailyReview>()).first { $0.supersededAt == nil })
    let originalAttachments = DiaryAttachmentService.activeAttachments(
        for: review.id,
        in: try destination.mainContext.fetch(FetchDescriptor<DiaryAttachment>())
    )
    let reversedDrafts = originalAttachments.reversed().map {
        DiaryAttachmentDraft(attachment: $0)
    }
    _ = try DiaryAttachmentService.replaceAttachments(
        for: review,
        with: reversedDrafts,
        in: destination.mainContext,
        now: contents.manifest.exportedAt.addingTimeInterval(3_600)
    )
    try destination.mainContext.save()

    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)

    let restoredOrder = DiaryAttachmentService.activeAttachments(
        for: review.id,
        in: try destination.mainContext.fetch(FetchDescriptor<DiaryAttachment>())
    ).map(\.instanceID)
    #expect(restoredOrder == originalAttachments.reversed().map(\.instanceID))
}

@Test
@MainActor
func equalTimestampCandidatesConvergeRegardlessOfImportOrder() throws {
    let logicalID = UUID()
    let lowerInstanceID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let higherInstanceID = UUID(uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")!
    let timestamp = Date(timeIntervalSince1970: 400)
    let lowerSource = try reviewContainer(
        id: logicalID,
        instanceID: lowerInstanceID,
        content: "lower",
        updatedAt: timestamp
    )
    let higherSource = try reviewContainer(
        id: logicalID,
        instanceID: higherInstanceID,
        content: "higher",
        updatedAt: timestamp
    )
    let lower = try BackupPackageCodec.makeContents(context: lowerSource.mainContext)
    let higher = try BackupPackageCodec.makeContents(context: higherSource.mainContext)
    let firstDestination = try EasyTaskContainerFactory.makeInMemory()
    let secondDestination = try EasyTaskContainerFactory.makeInMemory()

    _ = try BackupPackageCodec.restoreMerging(lower, into: firstDestination.mainContext)
    _ = try BackupPackageCodec.restoreMerging(higher, into: firstDestination.mainContext)
    _ = try BackupPackageCodec.restoreMerging(higher, into: secondDestination.mainContext)
    _ = try BackupPackageCodec.restoreMerging(lower, into: secondDestination.mainContext)

    let firstActive = try #require(firstDestination.mainContext
        .fetch(FetchDescriptor<DailyReview>()).first { $0.supersededAt == nil })
    let secondActive = try #require(secondDestination.mainContext
        .fetch(FetchDescriptor<DailyReview>()).first { $0.supersededAt == nil })
    #expect(firstActive.content == secondActive.content)
    #expect(firstActive.instanceID == secondActive.instanceID)
    #expect(try firstDestination.mainContext.fetch(FetchDescriptor<DailyReview>()).count == 2)
    #expect(try secondDestination.mainContext.fetch(FetchDescriptor<DailyReview>()).count == 2)
}

@Test
@MainActor
func legacyJSONMergeIsIdempotentAndReportsImageReferences() throws {
    let source = try EasyTaskContainerFactory.makeInMemory()
    _ = DailyReviewService.save(
        review: nil,
        dayKey: "2026-07-11",
        content: "V1 회고",
        imageFileNames: ["legacy.jpg"],
        in: source.mainContext
    )
    let template = TaskTemplate(name: "V1 템플릿")
    source.mainContext.insert(template)
    source.mainContext.insert(TaskTemplateItem(
        templateId: template.id,
        title: "V1 항목",
        order: 100
    ))
    try source.mainContext.save()
    var payload = try BackupCodec.makePayload(context: source.mainContext)
    payload.dailyReviews?[0].instanceID = nil
    payload.diaryBlocks?[0].instanceID = nil
    if (payload.diaryBlocks?.count ?? 0) > 1 {
        payload.diaryBlocks?[1].instanceID = nil
    }
    payload.taskTemplates[0].instanceID = nil
    payload.taskTemplateItems[0].instanceID = nil
    payload.taskTemplateItems[0].createdAt = nil
    payload.taskTemplateItems[0].updatedAt = nil
    payload = try BackupCodec.decode(BackupCodec.encode(payload))

    let destination = try EasyTaskContainerFactory.makeInMemory()
    let first = try BackupPackageCodec.restoreLegacyJSONMerging(
        payload,
        into: destination.mainContext
    )
    let countsAfterFirst = (
        try destination.mainContext.fetch(FetchDescriptor<DailyReview>()).count,
        try destination.mainContext.fetch(FetchDescriptor<DiaryBlock>()).count
    )
    let second = try BackupPackageCodec.restoreLegacyJSONMerging(
        payload,
        into: destination.mainContext
    )

    #expect(first.referencedImageFileNames == ["legacy.jpg"])
    #expect(second.merge.insertedRecords == 0)
    #expect(try destination.mainContext.fetch(FetchDescriptor<DailyReview>()).count == countsAfterFirst.0)
    #expect(try destination.mainContext.fetch(FetchDescriptor<DiaryBlock>()).count == countsAfterFirst.1)
    #expect(try destination.mainContext.fetch(FetchDescriptor<TaskTemplateItem>()).count == 1)
}

@Test
@MainActor
func repeatedLegacyJSONImportSurvivesReviewAndBlockReconciliation() throws {
    let timestamp = Date(timeIntervalSince1970: 600)
    let source = try EasyTaskContainerFactory.makeInMemory()
    let sourceReview = DailyReview(
        id: UUID(),
        dayKey: "2026-07-11",
        content: "V1 백업 회고",
        createdAt: timestamp,
        updatedAt: timestamp
    )
    source.mainContext.insert(sourceReview)
    source.mainContext.insert(DiaryBlock(
        reviewId: sourceReview.id,
        dayKey: sourceReview.dayKey,
        type: .text,
        text: sourceReview.content,
        order: 0,
        createdAt: timestamp,
        updatedAt: timestamp
    ))
    try source.mainContext.save()
    var payload = try BackupCodec.makePayload(context: source.mainContext)
    payload.dailyReviews?[0].instanceID = nil
    payload.diaryBlocks?[0].instanceID = nil

    let destination = try EasyTaskContainerFactory.makeInMemory()
    destination.mainContext.insert(DailyReview(
        id: UUID(),
        instanceID: UUID(uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")!,
        dayKey: sourceReview.dayKey,
        content: "동일 날짜 로컬 회고",
        createdAt: timestamp,
        updatedAt: timestamp
    ))
    try destination.mainContext.save()

    _ = try BackupPackageCodec.restoreLegacyJSONMerging(payload, into: destination.mainContext)
    _ = try BackupPackageCodec.restoreLegacyJSONMerging(payload, into: destination.mainContext)

    let reviews = try destination.mainContext.fetch(FetchDescriptor<DailyReview>())
    let blocks = try destination.mainContext.fetch(FetchDescriptor<DiaryBlock>())
        .filter { $0.supersededAt == nil }
    let activeReview = try #require(reviews.first { $0.supersededAt == nil })
    #expect(reviews.count == 2)
    #expect(activeReview.content == "동일 날짜 로컬 회고")
    #expect(blocks.count == 1)
    #expect(blocks.first?.reviewId == activeReview.id)
}

@Test
@MainActor
func legacyReplaceAllDoesNotLeaveV3AttachmentOrphans() throws {
    let source = try EasyTaskContainerFactory.makeInMemory()
    let emptyPayload = try BackupCodec.makePayload(context: source.mainContext)
    let destination = try packageSourceContainer(image: testPNG(0x1A))
    #expect(try destination.mainContext.fetch(FetchDescriptor<DiaryAttachment>()).count == 1)

    try BackupCodec.replaceAll(with: emptyPayload, in: destination.mainContext)

    #expect(try destination.mainContext.fetch(FetchDescriptor<DailyReview>()).isEmpty)
    #expect(try destination.mainContext.fetch(FetchDescriptor<DiaryAttachment>()).isEmpty)
}

@MainActor
private func packageSourceContainer(image: Data) throws -> ModelContainer {
    let container = try EasyTaskContainerFactory.makeInMemory()
    _ = try DiaryAttachmentService.saveReview(
        review: nil,
        dayKey: "2026-07-11",
        title: "백업 원본",
        content: "첨부가 있는 회고",
        attachments: [DiaryAttachmentDraft(data: image)],
        in: container.mainContext
    )
    return container
}

@MainActor
private func packageSourceContainer(
    imageCount: Int,
    markerOffset: UInt8
) throws -> ModelContainer {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let drafts = (0..<imageCount).map { index in
        DiaryAttachmentDraft(data: testPNG(markerOffset &+ UInt8(index)))
    }
    _ = try DiaryAttachmentService.saveReview(
        review: nil,
        dayKey: "2026-07-11",
        title: "병합 제한 테스트",
        content: "첨부 \(imageCount)개",
        attachments: drafts,
        in: container.mainContext,
        now: Date(timeIntervalSince1970: 500)
    )
    return container
}

@MainActor
private func reviewContainer(
    id: UUID,
    instanceID: UUID,
    content: String,
    updatedAt: Date
) throws -> ModelContainer {
    let container = try EasyTaskContainerFactory.makeInMemory()
    container.mainContext.insert(DailyReview(
        id: id,
        instanceID: instanceID,
        dayKey: "2026-07-11",
        content: content,
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: updatedAt
    ))
    try container.mainContext.save()
    return container
}

@MainActor
private func taskReminderMergeContainer(
    id: UUID,
    instanceID: UUID,
    title: String,
    plannedAt: Date,
    reminderAt: Date?,
    updatedAt: Date
) throws -> ModelContainer {
    let container = try EasyTaskContainerFactory.makeInMemory()
    container.mainContext.insert(Task(
        id: id,
        instanceID: instanceID,
        title: title,
        plannedAt: plannedAt,
        order: 100,
        reminderAt: reminderAt,
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: updatedAt
    ))
    try container.mainContext.save()
    return container
}

private func testPNG(_ marker: UInt8) -> Data {
    guard var data = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    ) else {
        preconditionFailure("Invalid embedded PNG fixture")
    }
    data.append(marker)
    return data
}

private func temporaryPackageURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("EasyTaskBackupTests-\(UUID().uuidString)")
        .appendingPathExtension("easytaskbackup")
}

private func refreshRecordsMetadata(_ contents: inout BackupPackageContents) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try! encoder.encode(contents.records)
    contents.manifest.recordsByteCount = data.count
    contents.manifest.recordsSHA256 = SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}
