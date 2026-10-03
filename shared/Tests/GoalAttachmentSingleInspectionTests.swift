import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import EasyTaskCore

/// Baseline-compatible public-service contracts for attachment phase ordering.
/// No private normalization helpers, inspection counters, candidate APIs, real
/// files, CloudKit, or implementation-shaped reference algorithm are used.
@Test
@MainActor
func goalAttachmentReconciliationPreservesFullGraphContract() throws {
    let fixture = try goalAttachmentSingleInspectionGraph()
    let before = try goalAttachmentSingleInspectionSnapshot(in: fixture.container)
    try #require(before.reviews.count == 2 && before.attachments.count == 6)
    #expect(before.attachments.map(\.instanceID) == fixture.attachments.map(\.instanceID))
    #expect(before.attachments.map(\.data) == fixture.attachments.map(\.data))
    var expected = before

    // Same-day reviews keep the newer scalar version, earliest creation, and the
    // older physical row. The logical attachment winner is chosen BEFORE any
    // attachment normalization; its superseded physical copy stays unnormalized.
    expected.reviews[0].superseded = goalAttachmentSingleInspectionBits(200)
    expected.reviews[1].created = goalAttachmentSingleInspectionBits(0)
    expected.attachments[0].superseded = goalAttachmentSingleInspectionBits(60)
    expected.attachments[1].reviewID = fixture.reviews[1].id
    expected.attachments[1].created = goalAttachmentSingleInspectionBits(25)
    expected.attachments[1].order = Double(100).bitPattern
    expected.attachments[1].name = "winner.png"
    expected.attachments[1].mime = "image/png"
    expected.attachments[1].byteCount = fixture.attachments[1].data.count
    expected.attachments[1].storedSHA = goalAttachmentSingleInspectionSHA(fixture.attachments[1].data)
    expected.attachments[2].order = Double(0).bitPattern
    expected.attachments[3].superseded = goalAttachmentSingleInspectionBits(60)
    expected.attachments[4].mime = "image/png"
    expected.attachments[4].byteCount = fixture.attachments[4].data.count
    expected.attachments[4].storedSHA = goalAttachmentSingleInspectionSHA(fixture.attachments[4].data)
    expected.attachments[4].superseded = goalAttachmentSingleInspectionBits(60)

    let report = try DataIntegrityService.reconcile(context: fixture.context)
    #expect(report == DataIntegrityService.Report(
        insertedRecords: 0, mergedRecords: 2, normalizedFields: 10,
        rewiredReferences: 1, supersededRecords: 4))
    let after = try goalAttachmentSingleInspectionSnapshot(in: fixture.container)
    #expect(after == expected)
    #expect(after.attachments.map(\.dataSHA) == before.attachments.map(\.dataSHA))
    #expect(after.attachments.map(\.data) == before.attachments.map(\.data))
    #expect(after.attachments.map(\.persistentID) == before.attachments.map(\.persistentID))
    #expect(after.reviews.map(\.persistentID) == before.reviews.map(\.persistentID))
    goalAttachmentSingleInspectionExpectClean(fixture.context)

    let stableDigest = goalAttachmentSingleInspectionDigest(after)
    let secondReport = try DataIntegrityService.reconcile(context: fixture.context)
    #expect(secondReport == .noChanges)
    let repeated = try goalAttachmentSingleInspectionSnapshot(in: fixture.container)
    #expect(repeated == after)
    #expect(goalAttachmentSingleInspectionDigest(repeated) == stableDigest)
    goalAttachmentSingleInspectionExpectClean(fixture.context)
    withExtendedLifetime(fixture.container) {}
}

@Test
@MainActor
func goalAttachmentReconciliationNormalizesNonfiniteTimesBeforeSuperseding() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let review = goalAttachmentSingleInspectionReview(0, content: "timestamp control", created: 0, updated: 100)
    let png = try goalAttachmentSingleInspectionPNG(1)
    let corrupt = Data(png.prefix(8)) // Recognizable PNG signature, no decodable image.
    #expect(throws: DiaryAttachmentServiceError.unsupportedImageFormat) { try DiaryAttachmentService.inspect(corrupt) }
    let valid = goalAttachmentSingleInspectionAttachment(0, logical: 0, reviewID: review.id,
        data: png, order: 0, name: "valid.png", created: 20, updated: 30, validatedMetadata: false)
    let invalid = goalAttachmentSingleInspectionAttachment(1, logical: 1, reviewID: review.id,
        data: corrupt, order: 100, name: "corrupt.png", created: 20, updated: 30, validatedMetadata: true)
    context.insert(review)
    context.insert(valid)
    context.insert(invalid)
    try context.save()
    let before = try goalAttachmentSingleInspectionSnapshot(in: container)
    try #require(before.reviews.count == 1 && before.attachments.count == 2)

    // Persist valid clock values first. Nonfinite clocks are pending edits so the
    // test does not require the store to serialize an invalid NSDate.
    valid.createdAt = Date(timeIntervalSince1970: .nan)
    valid.updatedAt = Date(timeIntervalSince1970: .infinity)
    invalid.createdAt = Date(timeIntervalSince1970: .nan)
    invalid.updatedAt = Date(timeIntervalSince1970: -.infinity)
    var expected = before
    expected.attachments[0].created = goalAttachmentSingleInspectionBits(0)
    expected.attachments[0].updated = goalAttachmentSingleInspectionBits(0)
    expected.attachments[0].mime = "image/png"
    expected.attachments[0].byteCount = png.count
    expected.attachments[0].storedSHA = goalAttachmentSingleInspectionSHA(png)
    expected.attachments[1].created = goalAttachmentSingleInspectionBits(0)
    expected.attachments[1].updated = goalAttachmentSingleInspectionBits(0)
    expected.attachments[1].superseded = goalAttachmentSingleInspectionBits(0)

    let report = try DataIntegrityService.reconcile(context: context)
    #expect(report == DataIntegrityService.Report(
        insertedRecords: 0, mergedRecords: 0, normalizedFields: 7,
        rewiredReferences: 0, supersededRecords: 1))
    let after = try goalAttachmentSingleInspectionSnapshot(in: container)
    #expect(after == expected)
    #expect(after.attachments.map(\.dataSHA) == before.attachments.map(\.dataSHA))
    #expect(after.attachments.map(\.persistentID) == before.attachments.map(\.persistentID))
    goalAttachmentSingleInspectionExpectClean(context)
    withExtendedLifetime(container) {}
}

private enum GoalAttachmentSingleInspectionFailure: Error { case injected }

@Test
@MainActor
func goalAttachmentReconciliationCommandRollbackRestoresSavedFieldsAndBytes() throws {
    let fixture = try goalAttachmentSingleInspectionGraph()
    let before = try goalAttachmentSingleInspectionSnapshot(in: fixture.container)
    let digest = goalAttachmentSingleInspectionDigest(before)
    let originalIDs = fixture.attachments.map(\.persistentModelID)
    #expect(throws: GoalAttachmentSingleInspectionFailure.injected) {
        try PersistenceCommandService.perform(in: fixture.context) {
            let report = try DataIntegrityService.reconcile(context: fixture.context, saveChanges: false)
            #expect(report == DataIntegrityService.Report(
                insertedRecords: 0, mergedRecords: 2, normalizedFields: 10,
                rewiredReferences: 1, supersededRecords: 4))
            #expect(fixture.context.hasChanges)
            throw GoalAttachmentSingleInspectionFailure.injected
        }
    }
    let after = try goalAttachmentSingleInspectionSnapshot(in: fixture.container)
    #expect(after == before)
    #expect(goalAttachmentSingleInspectionDigest(after) == digest)
    #expect(after.attachments.map(\.dataSHA) == before.attachments.map(\.dataSHA))
    #expect(after.attachments.map(\.persistentID) == before.attachments.map(\.persistentID))
    for (index, original) in fixture.attachments.enumerated() {
        #expect(original.persistentModelID == originalIDs[index])
    }
    goalAttachmentSingleInspectionExpectClean(fixture.context)
    withExtendedLifetime(fixture.container) {}
}

private struct GoalAttachmentSingleInspectionFixture {
    let container: ModelContainer
    let context: ModelContext
    let reviews: [DailyReview]
    let attachments: [DiaryAttachment]
}

@MainActor
private func goalAttachmentSingleInspectionGraph() throws -> GoalAttachmentSingleInspectionFixture {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let reviews = [
        goalAttachmentSingleInspectionReview(0, content: "older review", created: 0, updated: 100),
        goalAttachmentSingleInspectionReview(1, content: "newer review", created: 10, updated: 200)
    ]
    let loserPNG = try goalAttachmentSingleInspectionPNG(0)
    let winnerPNG = try goalAttachmentSingleInspectionPNG(1)
    let orderedPNG = try goalAttachmentSingleInspectionPNG(2)
    let orphanPNG = try goalAttachmentSingleInspectionPNG(3)
    let corrupt = Data(winnerPNG.prefix(8))
    #expect(throws: DiaryAttachmentServiceError.unsupportedImageFormat) { try DiaryAttachmentService.inspect(corrupt) }
    let attachments = [
        goalAttachmentSingleInspectionAttachment(0, logical: 0, reviewID: reviews[0].id,
            data: loserPNG, order: 500, name: "  duplicate loser.png  ", created: 25, updated: 30, validatedMetadata: false),
        goalAttachmentSingleInspectionAttachment(1, logical: 0, reviewID: reviews[0].id,
            data: winnerPNG, order: .infinity, name: "  winner.png  ", created: 50, updated: 60, validatedMetadata: false),
        goalAttachmentSingleInspectionAttachment(2, logical: 1, reviewID: reviews[1].id,
            data: orderedPNG, order: -100, name: "ordered.png", created: 50, updated: 60, validatedMetadata: true),
        goalAttachmentSingleInspectionAttachment(3, logical: 2, reviewID: reviews[1].id,
            data: corrupt, order: 200, name: "corrupt.png", created: 50, updated: 60, validatedMetadata: true),
        goalAttachmentSingleInspectionAttachment(4, logical: 3, reviewID: goalAttachmentSingleInspectionID(1, 99),
            data: orphanPNG, order: 300, name: "orphan.png", created: 50, updated: 60, validatedMetadata: false),
        goalAttachmentSingleInspectionAttachment(5, logical: 4, reviewID: reviews[0].id,
            data: corrupt, order: -500, name: "  ignored.png  ", created: 70, updated: 80, validatedMetadata: false,
            superseded: 90)
    ]
    for review in reviews { context.insert(review) }
    for attachment in attachments { context.insert(attachment) }
    try context.save()
    return GoalAttachmentSingleInspectionFixture(container: container, context: context,
        reviews: reviews, attachments: attachments)
}

private func goalAttachmentSingleInspectionReview(_ index: Int, content: String, created: Double, updated: Double) -> DailyReview {
    DailyReview(id: goalAttachmentSingleInspectionID(1, index), instanceID: goalAttachmentSingleInspectionID(2, index),
        dayKey: "2026-09-01", title: "Review \(index)", weather: "weather \(index)", mood: "mood \(index)",
        content: content, createdAt: Date(timeIntervalSince1970: created), updatedAt: Date(timeIntervalSince1970: updated))
}

private func goalAttachmentSingleInspectionAttachment(
    _ index: Int, logical: Int, reviewID: UUID, data: Data, order: Double, name: String,
    created: Double, updated: Double, validatedMetadata: Bool, superseded: Double? = nil
) -> DiaryAttachment {
    DiaryAttachment(id: goalAttachmentSingleInspectionID(3, logical), instanceID: goalAttachmentSingleInspectionID(4, index),
        reviewId: reviewID, order: order, originalFileName: name,
        mimeType: validatedMetadata ? "image/png" : "", byteCount: validatedMetadata ? data.count : 0,
        sha256: validatedMetadata ? goalAttachmentSingleInspectionSHA(data) : "", data: data,
        createdAt: Date(timeIntervalSince1970: created), updatedAt: Date(timeIntervalSince1970: updated),
        supersededAt: superseded.map { Date(timeIntervalSince1970: $0) })
}

private struct GoalAttachmentSingleInspectionReviewValue: Equatable {
    let id: UUID
    let instanceID: UUID
    let persistentID: PersistentIdentifier
    let day: String
    let title: String
    let weather: String
    let mood: String
    let content: String
    let imageFileNames: [String]
    var created: UInt64
    let updated: UInt64
    var superseded: UInt64?
}

private struct GoalAttachmentSingleInspectionAttachmentValue: Equatable {
    let id: UUID
    let instanceID: UUID
    let persistentID: PersistentIdentifier
    var reviewID: UUID
    var order: UInt64
    var name: String?
    var mime: String
    var byteCount: Int
    var storedSHA: String
    let data: Data
    let dataSHA: String
    var created: UInt64
    var updated: UInt64
    var superseded: UInt64?
}

private struct GoalAttachmentSingleInspectionValue: Equatable {
    var reviews: [GoalAttachmentSingleInspectionReviewValue]
    var attachments: [GoalAttachmentSingleInspectionAttachmentValue]
    let otherCounts: [Int]
}

@MainActor
private func goalAttachmentSingleInspectionSnapshot(in container: ModelContainer) throws -> GoalAttachmentSingleInspectionValue {
    let reader = ModelContext(container)
    reader.autosaveEnabled = false
    let reviews = try reader.fetch(FetchDescriptor<DailyReview>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    let attachments = try reader.fetch(FetchDescriptor<DiaryAttachment>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    let reviewValues = reviews.map { review in
        GoalAttachmentSingleInspectionReviewValue(id: review.id, instanceID: review.instanceID,
            persistentID: review.persistentModelID, day: review.dayKey, title: review.title,
            weather: review.weather, mood: review.mood, content: review.content, imageFileNames: review.imageFileNames,
            created: review.createdAt.timeIntervalSinceReferenceDate.bitPattern,
            updated: review.updatedAt.timeIntervalSinceReferenceDate.bitPattern,
            superseded: review.supersededAt?.timeIntervalSinceReferenceDate.bitPattern)
    }
    let attachmentValues = attachments.map { attachment in
        let data = attachment.data
        return GoalAttachmentSingleInspectionAttachmentValue(id: attachment.id, instanceID: attachment.instanceID,
            persistentID: attachment.persistentModelID, reviewID: attachment.reviewId, order: attachment.order.bitPattern,
            name: attachment.originalFileName, mime: attachment.mimeType, byteCount: attachment.byteCount,
            storedSHA: attachment.sha256, data: data, dataSHA: goalAttachmentSingleInspectionSHA(data),
            created: attachment.createdAt.timeIntervalSinceReferenceDate.bitPattern,
            updated: attachment.updatedAt.timeIntervalSinceReferenceDate.bitPattern,
            superseded: attachment.supersededAt?.timeIntervalSinceReferenceDate.bitPattern)
    }
    let otherCounts = try [
        reader.fetchCount(FetchDescriptor<CalendarEvent>()), reader.fetchCount(FetchDescriptor<TaskTemplate>()),
        reader.fetchCount(FetchDescriptor<TaskTemplateItem>()), reader.fetchCount(FetchDescriptor<TemplatePlacement>()),
        reader.fetchCount(FetchDescriptor<Task>()), reader.fetchCount(FetchDescriptor<TaskChecklistItem>()),
        reader.fetchCount(FetchDescriptor<DiaryBlock>()), reader.fetchCount(FetchDescriptor<Memo>()),
        reader.fetchCount(FetchDescriptor<MemoDrawing>()), reader.fetchCount(FetchDescriptor<MemoChecklistItem>()),
        reader.fetchCount(FetchDescriptor<TaskCompletionActivity>()), reader.fetchCount(FetchDescriptor<TaskProgressEvent>()),
        reader.fetchCount(FetchDescriptor<FocusSession>())
    ]
    #expect(otherCounts.allSatisfy { $0 == 0 })
    #expect(Set(attachments.map(\.persistentModelID)).count == attachments.count)
    withExtendedLifetime(container) {}
    return GoalAttachmentSingleInspectionValue(reviews: reviewValues, attachments: attachmentValues, otherCounts: otherCounts)
}

@MainActor
private func goalAttachmentSingleInspectionExpectClean(_ context: ModelContext) {
    #expect(!context.hasChanges)
    #expect(context.insertedModelsArray.isEmpty && context.changedModelsArray.isEmpty && context.deletedModelsArray.isEmpty)
}

private func goalAttachmentSingleInspectionPNG(_ marker: UInt8) throws -> Data {
    let pixels = Data([marker, 0x30, 0x50, 0xFF])
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return output as Data
}

private func goalAttachmentSingleInspectionSHA(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
private func goalAttachmentSingleInspectionBits(_ seconds: Double) -> UInt64 {
    Date(timeIntervalSince1970: seconds).timeIntervalSinceReferenceDate.bitPattern
}
private func goalAttachmentSingleInspectionID(_ namespace: Int, _ index: Int) -> UUID {
    UUID(uuidString: String(format: "40000000-0000-4000-%04X-%012X", namespace, index + 1))!
}
private func goalAttachmentSingleInspectionDigest(_ value: GoalAttachmentSingleInspectionValue) -> String {
    // Typed equality above compares every persisted field/PID AND actual Data.
    // This additional digest covers raw image contents and logical/physical IDs
    // without relying on SDK debug-description formatting of persistent IDs.
    let rows = value.attachments.map {
        "\($0.id.uuidString)|\($0.instanceID.uuidString)|\($0.data.count)|\($0.dataSHA)"
    }.joined(separator: "\n")
    return goalAttachmentSingleInspectionSHA(Data(rows.utf8))
}
