import Foundation
import PlanBaseCore
import Testing

@Test
@MainActor
func cloudKitImportRevalidatesChangedImageWithStaleMetadata() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let review = DailyReview(dayKey: "2026-07-12", content: "Attachment validation fixture")
    let valid = try #require(Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    ))
    let metadata = try DiaryAttachmentService.inspect(valid)
    let attachment = DiaryAttachment(
        reviewId: review.id,
        order: 0,
        mimeType: metadata.mediaType.rawValue,
        byteCount: metadata.byteCount,
        sha256: metadata.sha256,
        data: valid
    )
    context.insert(review)
    context.insert(attachment)
    try context.save()

    let importEvent = CloudKitSyncEventSummary(kind: .import, isCompleted: true, succeeded: true)
    try CloudKitSyncService.reconcileIfNeeded(after: importEvent, context: context)
    #expect(attachment.supersededAt == nil)

    // A PNG signature and the same size, but without a decodable image payload.
    let malformed = Data(valid.prefix(8)) + Data(repeating: 0, count: valid.count - 8)
    attachment.data = malformed
    try context.save()
    #expect(attachment.sha256 == metadata.sha256)
    #expect(attachment.mimeType == metadata.mediaType.rawValue)
    #expect(attachment.byteCount == malformed.count)

    try CloudKitSyncService.reconcileIfNeeded(after: importEvent, context: context)

    #expect(attachment.supersededAt != nil)
}
