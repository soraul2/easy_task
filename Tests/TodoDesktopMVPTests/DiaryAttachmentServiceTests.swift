import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
func attachmentInspectionDetectsSupportedFormatsFromBytes() throws {
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
    let heic = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])

    #expect(try DiaryAttachmentService.inspect(jpeg).mediaType == .jpeg)
    #expect(try DiaryAttachmentService.inspect(png).mediaType == .png)
    #expect(try DiaryAttachmentService.inspect(heic).mediaType == .heic)
    #expect(try DiaryAttachmentService.inspect(png).sha256.count == 64)
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
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])

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
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
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
func legacyFileMigrationIsIdempotent() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let folder = "EasyTaskTests-\(UUID().uuidString)"
    let directory = DiaryImageFileStore.directoryURL(appSupportFolder: folder)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x02])
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

    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x03])
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

    let report = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
        context: context,
        appSupportFolder: folder
    )

    let attachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
    #expect(report.importedCount == 1)
    #expect(attachments.first?.reviewId == review.id)
    #expect(attachments.first?.data == png)
    #expect(block.supersededAt != nil)
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
    let pngA = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x04])
    let pngB = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x05])
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
