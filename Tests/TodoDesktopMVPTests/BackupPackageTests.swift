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

    #expect(decoded.manifest.formatVersion == 2)
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
    try source.mainContext.save()
    var payload = try BackupCodec.makePayload(context: source.mainContext)
    payload.dailyReviews?[0].instanceID = nil
    payload.diaryBlocks?[0].instanceID = nil
    if (payload.diaryBlocks?.count ?? 0) > 1 {
        payload.diaryBlocks?[1].instanceID = nil
    }

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

private func testPNG(_ marker: UInt8) -> Data {
    Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, marker])
}

private func temporaryPackageURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("EasyTaskBackupTests-\(UUID().uuidString)")
        .appendingPathExtension("easytaskbackup")
}
