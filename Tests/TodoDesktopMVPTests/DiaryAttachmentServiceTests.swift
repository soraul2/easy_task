import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import EasyTaskCore

@Test
func attachmentInspectionDetectsSupportedFormatsFromBytes() throws {
    let jpeg = try #require(encodedTestImage(type: .jpeg))
    let png = try #require(encodedTestImage(type: .png))
    let heic = try #require(encodedTestImage(type: .heic))

    #expect(try DiaryAttachmentService.inspect(jpeg).mediaType == .jpeg)
    #expect(try DiaryAttachmentService.inspect(png).mediaType == .png)
    #expect(try DiaryAttachmentService.inspect(heic).mediaType == .heic)
    #expect(try DiaryAttachmentService.inspect(png).sha256.count == 64)
}

@Test
func attachmentInspectionAvoidsDegenerateImageIOThumbnailSize() {
    #expect(DiaryAttachmentService.validationThumbnailMaxPixelSize >= 8)
}

@Test
func attachmentInspectionRejectsUnknownAndOversizedData() {
    #expect(throws: DiaryAttachmentServiceError.unsupportedImageFormat) {
        try DiaryAttachmentService.inspect(Data("not an image".utf8))
    }

    let oversized = Data(
        repeating: 0,
        count: DiaryAttachmentService.maximumImageSizeBytes + 1
    )
    #expect(throws: DiaryAttachmentServiceError.fileTooLarge(
        actualBytes: oversized.count,
        maximumBytes: DiaryAttachmentService.maximumImageSizeBytes
    )) {
        try DiaryAttachmentService.inspect(oversized)
    }
}

@Test
@MainActor
func savingReviewAndAttachmentsCommitsOneConsistentGraph() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let png = try #require(encodedTestImage(type: .png, marker: 0x01))

    let review = try #require(try DiaryAttachmentService.saveReview(
        review: nil,
        dayKey: "2026-07-11",
        title: "첨부 테스트",
        content: "이미지와 함께 저장",
        attachments: [DiaryAttachmentDraft(data: png, originalFileName: "photo.png")],
        in: context
    ))

    let attachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
    #expect(attachments.count == 1)
    #expect(attachments[0].reviewId == review.id)
    #expect(attachments[0].mimeType == DiaryAttachmentMediaType.png.rawValue)
    #expect(attachments[0].byteCount == png.count)
    #expect(attachments[0].data == png)
    #expect(review.imageFileNames.isEmpty)
}

@Test
@MainActor
func invalidReplacementLeavesExistingAttachmentUntouched() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let png = try #require(encodedTestImage(type: .png, marker: 0x01))
    let review = try #require(try DiaryAttachmentService.saveReview(
        review: nil,
        dayKey: "2026-07-11",
        content: "기존 첨부",
        attachments: [DiaryAttachmentDraft(data: png)],
        in: context
    ))
    let originalID = try #require(context.fetch(FetchDescriptor<DiaryAttachment>()).first?.id)

    #expect(throws: DiaryAttachmentServiceError.unsupportedImageFormat) {
        try DiaryAttachmentService.replaceAttachments(
            for: review,
            with: [DiaryAttachmentDraft(data: Data("invalid".utf8))],
            in: context
        )
    }

    let remaining = try context.fetch(FetchDescriptor<DiaryAttachment>())
    #expect(remaining.count == 1)
    #expect(remaining[0].id == originalID)
    #expect(remaining[0].data == png)
}

@Test
@MainActor
func textOnlyReviewSavePreservesAttachmentIdentity() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let png = try #require(encodedTestImage(type: .png, marker: 0x07))
    let firstDate = Date(timeIntervalSince1970: 100)
    let secondDate = Date(timeIntervalSince1970: 200)
    let review = try #require(try DiaryAttachmentService.saveReview(
        review: nil,
        dayKey: "2026-07-11",
        content: "첫 본문",
        attachments: [DiaryAttachmentDraft(data: png)],
        in: context,
        now: firstDate
    ))
    let original = try #require(context.fetch(FetchDescriptor<DiaryAttachment>()).first)
    let originalID = original.id
    let originalInstanceID = original.instanceID
    let originalUpdatedAt = original.updatedAt

    _ = try DiaryAttachmentService.saveReview(
        review: review,
        dayKey: review.dayKey,
        content: "수정한 본문",
        attachments: [DiaryAttachmentDraft(attachment: original)],
        in: context,
        now: secondDate
    )

    let attachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
    #expect(attachments.count == 1)
    #expect(attachments[0].id == originalID)
    #expect(attachments[0].instanceID == originalInstanceID)
    #expect(attachments[0].updatedAt == originalUpdatedAt)
    #expect(review.content == "수정한 본문")
    #expect(review.updatedAt == secondDate)
}

@Test
@MainActor
func legacyFileMigrationIsIdempotent() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let folder = "EasyTaskTests-\(UUID().uuidString)"
    let directory = DiaryImageFileStore.directoryURL(appSupportFolder: folder)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let png = try #require(encodedTestImage(type: .png, marker: 0x02))
    let fileName = try DiaryImageFileStore.writeImageData(
        png,
        preferredExtension: "png",
        appSupportFolder: folder
    )
    let review = DailyReview(
        dayKey: "2026-07-11",
        content: "기존 회고",
        imageFileNames: [fileName]
    )
    context.insert(review)
    try context.save()

    let first = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
        context: context,
        appSupportFolder: folder
    )
    let second = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
        context: context,
        appSupportFolder: folder
    )

    #expect(first.importedCount == 1)
    #expect(second.importedCount == 0)
    #expect(try context.fetch(FetchDescriptor<DiaryAttachment>()).count == 1)
    #expect(review.imageFileNames.isEmpty)
}

@Test
@MainActor
func legacyMigrationRecoversBlockOnlyImages() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let folder = "EasyTaskTests-\(UUID().uuidString)"
    let directory = DiaryImageFileStore.directoryURL(appSupportFolder: folder)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let png = try #require(encodedTestImage(type: .png, marker: 0x03))
    let fileName = try DiaryImageFileStore.writeImageData(
        png,
        preferredExtension: "png",
        appSupportFolder: folder
    )
    let review = DailyReview(dayKey: "2026-07-10", content: "블록 이미지")
    context.insert(review)
    let block = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .image,
        imageFileName: fileName,
        order: 100
    )
    context.insert(block)
    try context.save()

    #expect(DiaryAttachmentService.unresolvedLegacyImageFileNames(
        for: review,
        blocks: [block],
        attachments: []
    ) == [fileName])

    let report = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
        context: context,
        appSupportFolder: folder
    )

    let attachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
    #expect(report.importedCount == 1)
    #expect(attachments.first?.reviewId == review.id)
    #expect(attachments.first?.data == png)
    #expect(block.supersededAt != nil)
    #expect(DiaryAttachmentService.unresolvedLegacyImageFileNames(
        for: review,
        blocks: [block],
        attachments: attachments
    ).isEmpty)
}

@Test
@MainActor
func legacyMigrationRetainsReferencesUntilMissingFilesCanRetry() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let folder = "EasyTaskTests-\(UUID().uuidString)"
    let directory = DiaryImageFileStore.directoryURL(appSupportFolder: folder)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let png = try #require(encodedTestImage(type: .png, marker: 0x06))
    let existingFileName = try DiaryImageFileStore.writeImageData(
        png,
        preferredExtension: "png",
        appSupportFolder: folder
    )
    let missingFileName = "\(UUID().uuidString).png"
    let review = DailyReview(
        dayKey: "2026-07-11",
        content: "부분 이관",
        imageFileNames: [existingFileName, missingFileName, existingFileName]
    )
    context.insert(review)
    try context.save()

    let first = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
        context: context,
        appSupportFolder: folder
    )
    let second = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
        context: context,
        appSupportFolder: folder
    )
    #expect(first.importedCount == 2)
    #expect(first.missingFileNames == [missingFileName])
    #expect(second.importedCount == 0)
    #expect(review.imageFileNames.count == 3)
    #expect(try context.fetch(FetchDescriptor<DiaryAttachment>()).count == 2)

    let missingURL = try DiaryImageFileStore.validatedImageURL(
        for: missingFileName,
        appSupportFolder: folder
    )
    try png.write(to: missingURL, options: .atomic)
    let third = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
        context: context,
        appSupportFolder: folder
    )
    let attachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
        .sorted { $0.order < $1.order }

    #expect(third.importedCount == 1)
    #expect(review.imageFileNames.isEmpty)
    #expect(attachments.count == 3)
    #expect(attachments.map(\.order) == [0, 100, 200])
    #expect(Set(attachments.map(\.id)).count == 3)
}

@Test
@MainActor
func legacyMigrationDefersImagesBeyondAttachmentLimitWithoutLosingReferences() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let folder = "EasyTaskTests-\(UUID().uuidString)"
    let directory = DiaryImageFileStore.directoryURL(appSupportFolder: folder)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let fileNames = try (0..<12).map { index in
        let png = try #require(encodedTestImage(type: .png, marker: UInt8(index)))
        return try DiaryImageFileStore.writeImageData(
            png,
            preferredExtension: "png",
            appSupportFolder: folder
        )
    }
    let review = DailyReview(
        dayKey: "2026-07-11",
        content: "기존 이미지 12개",
        imageFileNames: fileNames
    )
    context.insert(review)
    try context.save()

    let first = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
        context: context,
        appSupportFolder: folder
    )
    let second = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
        context: context,
        appSupportFolder: folder
    )

    let activeAttachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
        .filter { $0.supersededAt == nil }
    #expect(first.importedCount == 10)
    #expect(first.deferredFileNames.count == 2)
    #expect(second.importedCount == 0)
    #expect(second.deferredFileNames.count == 2)
    #expect(activeAttachments.count == 10)
    #expect(review.imageFileNames == fileNames)

    let unresolved = DiaryAttachmentService.unresolvedLegacyImageFileNames(
        for: review,
        blocks: [],
        attachments: activeAttachments
    )
    #expect(unresolved.count == 2)
    #expect(throws: BackupPackageError.unresolvedLegacyAttachments(2)) {
        try BackupPackageCodec.makeContents(context: context)
    }

    review.imageFileNames = []
    try context.save()
    let backup = try BackupPackageCodec.makeContents(context: context)
    #expect(backup.records.attachments.count == 10)
}

@Test
@MainActor
func integrityReconciliationRewiresAttachmentsWithoutLosingImages() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let older = DailyReview(
        dayKey: "2026-07-11",
        content: "older",
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    let newer = DailyReview(
        dayKey: "2026-07-11",
        content: "newer",
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    context.insert(older)
    context.insert(newer)
    let pngA = try #require(encodedTestImage(type: .png, marker: 0x04))
    let pngB = try #require(encodedTestImage(type: .png, marker: 0x05))
    context.insert(DiaryAttachment(
        reviewId: older.id,
        order: 100,
        mimeType: "",
        byteCount: 0,
        sha256: "",
        data: pngA
    ))
    context.insert(DiaryAttachment(
        reviewId: newer.id,
        order: 100,
        mimeType: "",
        byteCount: 0,
        sha256: "",
        data: pngB
    ))
    try context.save()

    _ = try DataIntegrityService.reconcile(context: context)

    let activeReviews = try context.fetch(FetchDescriptor<DailyReview>())
        .filter { $0.supersededAt == nil }
    let activeAttachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
        .filter { $0.supersededAt == nil }
    #expect(activeReviews.count == 1)
    #expect(activeAttachments.count == 2)
    #expect(Set(activeAttachments.map(\.reviewId)) == Set([activeReviews[0].id]))
    #expect(Set(activeAttachments.map(\.data)) == Set([pngA, pngB]))
    #expect(activeAttachments.map(\.order).sorted() == [0, 100])
}

@Test
@MainActor
func diaryAttachmentIndexGroupsAndSortsRecordsPerReview() {
    let firstReview = DailyReview(
        dayKey: "2026-07-10",
        content: "",
        imageFileNames: ["first-legacy.jpg"]
    )
    let secondReview = DailyReview(dayKey: "2026-07-11", content: "")
    let later = DiaryAttachment(
        reviewId: firstReview.id,
        order: 200,
        mimeType: "image/jpeg",
        byteCount: 1,
        sha256: "later",
        data: Data([0x01])
    )
    let earlier = DiaryAttachment(
        reviewId: firstReview.id,
        order: 100,
        mimeType: "image/jpeg",
        byteCount: 1,
        sha256: "earlier",
        data: Data([0x02])
    )
    let other = DiaryAttachment(
        reviewId: secondReview.id,
        order: 0,
        mimeType: "image/jpeg",
        byteCount: 1,
        sha256: "other",
        data: Data([0x03])
    )
    let superseded = DiaryAttachment(
        reviewId: firstReview.id,
        order: 0,
        mimeType: "image/jpeg",
        byteCount: 1,
        sha256: "superseded",
        data: Data([0x04]),
        supersededAt: Date()
    )
    let otherReviewBlock = DiaryBlock(
        reviewId: secondReview.id,
        dayKey: secondReview.dayKey,
        type: .image,
        imageFileName: "second-legacy.jpg",
        order: 0
    )

    let index = DiaryAttachmentIndex(
        attachments: [later, other, superseded, earlier],
        blocks: [otherReviewBlock]
    )

    #expect(index.activeAttachments(for: firstReview.id).map { $0.id } == [earlier.id, later.id])
    #expect(index.activeAttachments(for: secondReview.id).map { $0.id } == [other.id])
    #expect(index.unresolvedLegacyImageFileNames(for: firstReview) == ["first-legacy.jpg"])
    #expect(index.unresolvedLegacyImageFileNames(for: secondReview) == ["second-legacy.jpg"])
}

private func encodedTestImage(type: UTType, marker: UInt8? = nil) -> Data? {
    let pixel = Data([0xF0, 0x30, 0x50, 0xFF])
    guard let provider = CGDataProvider(data: pixel as CFData),
          let image = CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
        return nil
    }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        output,
        type.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    var data = output as Data
    if let marker { data.append(marker) }
    return data
}
