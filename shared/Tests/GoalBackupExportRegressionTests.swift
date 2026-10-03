import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func goalBackupPublicPayloadRepairsAndGroupsPlacementMembership() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let date = goalBackupExportDate
    let first = TemplatePlacement(sourceTemplateId: nil, templateName: "첫 배치", dayKey: DayKey.key(for: date), taskIds: [UUID()])
    let second = TemplatePlacement(sourceTemplateId: nil, templateName: "다른 배치", dayKey: DayKey.key(for: date))
    let empty = TemplatePlacement(sourceTemplateId: nil, templateName: "빈 배치", dayKey: DayKey.key(for: date), taskIds: [UUID()])
    context.insert(first)
    context.insert(second)
    context.insert(empty)
    let descriptions: [(Int, Double, UUID?, Bool)] = [
        (22, 100, first.id, false), (11, 100, first.id, false), (33, 50, first.id, false),
        (44, 100, second.id, false), (55, 100, nil, false), (66, 0, first.id, true),
    ]
    for (identity, order, placementID, superseded) in descriptions {
        context.insert(Task(id: goalBackupExportID(identity), title: "작업 \(identity)",
            plannedAt: date, order: order, templatePlacementId: placementID,
            createdAt: date, updatedAt: date, supersededAt: superseded ? date : nil))
    }
    #expect(context.hasChanges)
    // Public JSON export must remain independently safe for an unreconciled context.
    let payload = try BackupCodec.makePayload(context: context)
    let memberships = Dictionary(uniqueKeysWithValues: (payload.templatePlacements ?? []).map { ($0.id, $0.taskIds) })
    #expect(memberships[first.id] == [33, 11, 22].map(goalBackupExportID))
    #expect(memberships[second.id] == [goalBackupExportID(44)])
    #expect(memberships[empty.id] == [])
    #expect(payload.tasks.count == 5)
    #expect(first.taskIds.isEmpty)
    #expect(empty.taskIds.isEmpty)
    #expect(!context.hasChanges) // The actual stale-membership repair saved the context.
    #expect(try DataIntegrityService.reconcile(context: context) == .noChanges)
    let again = try BackupCodec.makePayload(context: context)
    #expect(again.templatePlacements?.first { $0.id == first.id }?.taskIds == memberships[first.id])
}

@Test @MainActor
func goalBackupLegacyIndexKeepsOccurrencesAndRetryRebuildsInvocationState() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let review = DailyReview(dayKey: "2026-10-02", content: "중복 파일", imageFileNames: ["same.jpg", "same.jpg"])
    let other = DailyReview(dayKey: "2026-10-01", content: "다른 회고")
    context.insert(review)
    context.insert(other)
    let names = ["same.jpg", "same.jpg", "same.jpg", "other.png"]
    var blocks: [DiaryBlock] = []
    for (index, name) in names.enumerated() {
        let block = DiaryBlock(reviewId: review.id, dayKey: review.dayKey, type: .image,
                               imageFileName: name, order: Double(index * 100))
        blocks.append(block)
        context.insert(block)
    }
    let ignoredText = DiaryBlock(reviewId: review.id, dayKey: review.dayKey, type: .text,
                                 text: "본문", imageFileName: "ignored.jpg", order: 400)
    blocks.append(ignoredText)
    context.insert(ignoredText)
    let retiredBlock = DiaryBlock(reviewId: review.id, dayKey: review.dayKey, type: .image,
                                  imageFileName: "retired.jpg", order: 500, supersededAt: goalBackupExportDate)
    blocks.append(retiredBlock)
    context.insert(retiredBlock)
    let resolved = try goalBackupExportAttachment(
        id: goalBackupFrozenLegacyID(review.id, "same.jpg", 0), reviewID: review.id, order: 100
    )
    let retired = try goalBackupExportAttachment(
        id: goalBackupFrozenLegacyID(review.id, "same.jpg", 1), reviewID: review.id,
        order: 200, supersededAt: goalBackupExportDate
    )
    let otherAttachment = try goalBackupExportAttachment(
        id: goalBackupFrozenLegacyID(other.id, "same.jpg", 1), reviewID: other.id, order: 100
    )
    for attachment in [resolved, retired, otherAttachment] { context.insert(attachment) }
    try context.save()
    let attachments = [resolved, retired, otherAttachment]
    let oldResult = DiaryAttachmentService.unresolvedLegacyImageFileNames(
        for: review, blocks: blocks, attachments: attachments
    )
    let index = DiaryAttachmentIndex(attachments: attachments, blocks: blocks)
    #expect(oldResult == ["same.jpg", "same.jpg", "other.png"])
    #expect(index.unresolvedLegacyImageFileNames(for: review) == oldResult)
    #expect(throws: BackupPackageError.unresolvedLegacyAttachments(3)) {
        try BackupPackageCodec.makeContents(context: context, exportedAt: goalBackupExportDate)
    }

    // Failed export must not retain the old invocation's grouped children.
    for (filename, occurrence) in [("same.jpg", 1), ("same.jpg", 2), ("other.png", 0)] {
        context.insert(try goalBackupExportAttachment(
            id: goalBackupFrozenLegacyID(review.id, filename, occurrence), reviewID: review.id, order: 300
        ))
    }
    let completed = try BackupPackageCodec.makeContents(context: context, exportedAt: goalBackupExportDate)
    #expect(completed.records.attachments.count == 5)
    #expect(completed.records.payload.dailyReviews?.allSatisfy { ($0.imageFileNames ?? []).isEmpty } == true)
    #expect(completed.records.payload.diaryBlocks?.allSatisfy { $0.type != DiaryBlockType.image.rawValue } == true)
    #expect(completed.attachmentData.values.allSatisfy { $0 == goalBackupExportPNG })
    try BackupPackageCodec.validate(completed)
}

@Test @MainActor
func goalBackupExportCountsAttachmentsAfterReviewConvergence() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let first = DailyReview(dayKey: "2026-10-02", content: "첫 회고")
    let second = DailyReview(dayKey: "2026-10-02", content: "두 번째 회고")
    context.insert(first)
    context.insert(second)
    for index in 0..<11 {
        context.insert(try goalBackupExportAttachment(
            id: goalBackupExportID(1_000 + index), reviewID: index < 6 ? first.id : second.id,
            order: Double(index * 100)
        ))
    }
    try context.save()
    #expect(throws: BackupPackageError.tooManyAttachments(actual: 11, maximum: 10)) {
        try BackupPackageCodec.makeContents(context: context)
    }
    let activeReviews = try context.fetch(FetchDescriptor<DailyReview>()).filter { $0.supersededAt == nil }
    let activeAttachments = try context.fetch(FetchDescriptor<DiaryAttachment>()).filter { $0.supersededAt == nil }
    #expect(activeReviews.count == 1)
    #expect(activeAttachments.count == 11)
    #expect(Set(activeAttachments.map(\.reviewId)) == Set(activeReviews.map(\.id)))
    // Export already saved its initial repair before count validation, as before.
    #expect(!context.hasChanges)
}

@Test @MainActor
func goalBackupExportIncludesPendingValuesWithoutAddingASaveBoundary() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    context.autosaveEnabled = false
    let task = Task(title: "저장된 작업", note: "원래", plannedAt: goalBackupExportDate, order: 100,
                    createdAt: goalBackupExportDate, updatedAt: goalBackupExportDate)
    context.insert(task)
    try context.save()
    _ = try DataIntegrityService.reconcile(context: context)
    task.note = "아직 저장하지 않은 메모"
    #expect(context.hasChanges)
    let contents = try BackupPackageCodec.makeContents(context: context, exportedAt: goalBackupExportDate)
    #expect(contents.records.payload.tasks.first?.note == "아직 저장하지 않은 메모")
    #expect(context.hasChanges) // No repair means reconcile does not introduce a save.
    let payload = try BackupCodec.makePayload(context: context)
    #expect(payload.tasks.first?.note == "아직 저장하지 않은 메모")
    #expect(context.hasChanges)
    context.rollback()
    #expect(task.note == "원래")
}

@Test(arguments: Array(2...10)) @MainActor
func goalBackupGroupedExportPreservesPackageVersionCompatibility(version: Int) throws {
    let source = try PlanBaseContainerFactory.makeInMemory()
    let context = source.mainContext
    let template = TaskTemplate(name: "저장한 작업", createdAt: goalBackupExportDate, updatedAt: goalBackupExportDate)
    template.quickEntryAlias = "routine"
    let placement = TemplatePlacement(sourceTemplateId: template.id, templateName: template.name,
        dayKey: DayKey.key(for: goalBackupExportDate), createdAt: goalBackupExportDate, updatedAt: goalBackupExportDate)
    let task = Task(title: "버전 호환", plannedAt: goalBackupExportDate, order: 100,
        templatePlacementId: placement.id, createdAt: goalBackupExportDate, updatedAt: goalBackupExportDate)
    let review = DailyReview(dayKey: "2026-10-02", content: "이미지", createdAt: goalBackupExportDate, updatedAt: goalBackupExportDate)
    let attachment = try goalBackupExportAttachment(id: goalBackupExportID(2_000), reviewID: review.id, order: 0)
    context.insert(template)
    context.insert(placement)
    context.insert(task)
    context.insert(review)
    context.insert(attachment)
    try context.save()
    var contents = try BackupPackageCodec.makeContents(context: context, exportedAt: goalBackupExportDate)
    contents.manifest.formatVersion = version
    contents.records.formatVersion = version
    if version < 6 { contents.records.payload.taskCompletionActivities = nil }
    if version < 7 { contents.records.payload.taskProgressEvents = nil }
    if version < 9 { contents.records.payload.focusSessions = nil }
    if version < 10 { contents.records.payload.taskTemplates[0].quickEntryAlias = nil }
    try goalBackupRefreshMetadata(&contents)
    try BackupPackageCodec.validate(contents)

    let destination = try PlanBaseContainerFactory.makeInMemory()
    _ = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    let again = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    #expect(again.insertedRecords == 0)
    let exported = try BackupPackageCodec.makeContents(context: destination.mainContext, exportedAt: goalBackupExportDate)
    #expect(exported.records.payload.templatePlacements?.first?.taskIds == [task.id])
    #expect(exported.records.payload.tasks.first?.templatePlacementId == placement.id)
    #expect(exported.attachmentData[attachment.id] == goalBackupExportPNG)
    // Current exports explicitly encode an absent alias as ""; older nil input is accepted.
    #expect(exported.records.payload.taskTemplates.first?.quickEntryAlias == (version < 10 ? "" : "routine"))

    let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    if version >= 6 {
        var missing = contents
        missing.records.payload.taskCompletionActivities = nil
        try goalBackupRefreshMetadata(&missing)
        #expect(throws: BackupPackageError.invalidRecordMetadata(recordType: "TaskCompletionActivity", id: zero)) {
            try BackupPackageCodec.validate(missing)
        }
    }
    if version >= 7 {
        var missing = contents
        missing.records.payload.taskProgressEvents = nil
        try goalBackupRefreshMetadata(&missing)
        #expect(throws: BackupPackageError.invalidRecordMetadata(recordType: "TaskProgressEvent", id: zero)) {
            try BackupPackageCodec.validate(missing)
        }
    }
    if version >= 9 {
        var missing = contents
        missing.records.payload.focusSessions = nil
        try goalBackupRefreshMetadata(&missing)
        #expect(throws: BackupPackageError.invalidRecordMetadata(recordType: "FocusSession", id: zero)) {
            try BackupPackageCodec.validate(missing)
        }
    }
}

@Test(arguments: [1, 2]) @MainActor
func goalBackupGroupedJSONKeepsLegacyImageReferences(version: Int) throws {
    let source = try PlanBaseContainerFactory.makeInMemory()
    let context = source.mainContext
    let placement = TemplatePlacement(sourceTemplateId: nil, templateName: "JSON 배치", dayKey: "2026-10-02", taskIds: [UUID()])
    let task = Task(title: "JSON 작업", plannedAt: goalBackupExportDate, order: 100, templatePlacementId: placement.id)
    let review = DailyReview(dayKey: "2026-10-02", content: "레거시", imageFileNames: ["legacy.jpg"])
    let block = DiaryBlock(reviewId: review.id, dayKey: review.dayKey, type: .image, imageFileName: "legacy.jpg", order: 100)
    context.insert(placement)
    context.insert(task)
    context.insert(review)
    context.insert(block)
    var payload = try BackupCodec.makePayload(context: context)
    payload.backupVersion = version
    if version == 1 { payload.taskCompletionActivities = nil }
    let decoded = try BackupCodec.decode(BackupCodec.encode(payload))
    #expect(decoded.templatePlacements?.first?.taskIds == [task.id])
    #expect(decoded.dailyReviews?.first?.imageFileNames == ["legacy.jpg"])
    #expect(decoded.diaryBlocks?.first?.imageFileName == "legacy.jpg")
    let destination = try PlanBaseContainerFactory.makeInMemory()
    try BackupCodec.replaceAll(with: decoded, in: destination.mainContext)
    let restored = try BackupCodec.makePayload(context: destination.mainContext)
    #expect(restored.templatePlacements?.first?.taskIds == [task.id])
    #expect(restored.dailyReviews?.first?.imageFileNames == ["legacy.jpg"])
    #expect(throws: BackupPackageError.unresolvedLegacyAttachments(1)) {
        try BackupPackageCodec.makeContents(context: destination.mainContext)
    }
}

private let goalBackupExportDate = Date(timeIntervalSince1970: 1_790_899_200)
private let goalBackupExportPNG = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

private func goalBackupExportID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "10000000-0000-4000-8000-%012llx", Int64(value)))!
}

@MainActor
private func goalBackupExportAttachment(id: UUID, reviewID: UUID, order: Double,
                                        supersededAt: Date? = nil) throws -> DiaryAttachment {
    let metadata = try DiaryAttachmentService.inspect(goalBackupExportPNG)
    return DiaryAttachment(id: id, reviewId: reviewID, order: order, originalFileName: "synthetic.png",
        mimeType: metadata.mediaType.rawValue, byteCount: metadata.byteCount, sha256: metadata.sha256,
        data: goalBackupExportPNG, createdAt: goalBackupExportDate, updatedAt: goalBackupExportDate,
        supersededAt: supersededAt)
}

/// Frozen legacy identity contract, independent of the service's index/filter path.
private func goalBackupFrozenLegacyID(_ reviewID: UUID, _ filename: String, _ occurrence: Int) -> UUID {
    let digest = SHA256.hash(data: Data("DiaryAttachment|\(reviewID.uuidString)|\(filename)|\(occurrence)".utf8))
    var bytes = Array(digest.prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                       bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
}

private func goalBackupRefreshMetadata(_ contents: inout BackupPackageContents) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(contents.records)
    contents.manifest.recordsByteCount = data.count
    contents.manifest.recordsSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
