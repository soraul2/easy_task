import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func backupMergeStagesJoinNewAndPreservedParentsBeforeFinalSave() throws {
    let fixture = try makeBackupMergeStageFixture()
    let destination = try PlanBaseContainerFactory.makeInMemory()
    let context = destination.mainContext
    _ = try BackupPackageCodec.restoreMerging(fixture.initial, into: context)
    var inspectedBeforeSave = false

    _ = try BackupPackageCodec.restoreMerging(fixture.complete, into: context, beforeFinalSave: {
        inspectedBeforeSave = true
        // New parents and children have reached the same transaction before its
        // final save. Preserved children must still resolve their original parents.
        #expect(context.hasChanges)
        try expectBackupStageJoins(fixture.groups, in: context)
    })
    #expect(inspectedBeforeSave)
    try expectBackupStageJoins(fixture.groups, in: context)
    let afterMerge = try backupStageSnapshot(in: context)
    _ = try BackupPackageCodec.restoreMerging(fixture.complete, into: context)
    #expect(try backupStageSnapshot(in: context) == afterMerge)
    #expect(!context.hasChanges)
}

@Test @MainActor
func backupMergeStagesRollbackKeepsPendingEditsAndRetryRebuildsLookups() throws {
    struct InjectedFailure: Error {}
    let fixture = try makeBackupMergeStageFixture()
    let destination = try PlanBaseContainerFactory.makeInMemory()
    let context = destination.mainContext
    _ = try BackupPackageCodec.restoreMerging(fixture.initial, into: context)
    let preservedID = fixture.groups[0].taskID
    let local = try #require(context.fetch(FetchDescriptor<Task>()).first { $0.id == preservedID })
    local.note = "가져오기 전 저장 대기 중이던 편집"
    local.updatedAt = fixture.complete.manifest.exportedAt.addingTimeInterval(3_600)
    #expect(context.hasChanges)
    // Direct value snapshots do not reconcile or save the pending local edit.
    let pendingBaseline = try backupStageSnapshot(in: context)
    var reachedFinalSave = false

    #expect(throws: InjectedFailure.self) {
        try BackupPackageCodec.restoreMerging(fixture.complete, into: context, beforeFinalSave: {
            reachedFinalSave = true
            try expectBackupStageJoins(fixture.groups, in: context)
            throw InjectedFailure()
        })
    }
    #expect(reachedFinalSave)
    #expect(try backupStageSnapshot(in: context) == pendingBaseline)
    #expect(!context.hasChanges)
    try expectBackupStageJoins([fixture.groups[0]], in: context)

    // A retry must see new parent records again; a retained pre-rollback lookup
    // would contain invalid objects or miss the newly reinserted parent rows.
    _ = try BackupPackageCodec.restoreMerging(fixture.complete, into: context)
    try expectBackupStageJoins(fixture.groups, in: context)
    let reloaded = try #require(context.fetch(FetchDescriptor<Task>()).first { $0.id == preservedID })
    #expect(reloaded.note == "가져오기 전 저장 대기 중이던 편집")
    let afterRetry = try backupStageSnapshot(in: context)
    _ = try BackupPackageCodec.restoreMerging(fixture.complete, into: context)
    #expect(try backupStageSnapshot(in: context) == afterRetry)
}

private struct BackupStageGroup {
    let eventID: UUID
    let templateID: UUID
    let templateItemID: UUID
    let placementID: UUID
    let taskID: UUID
    let checklistID: UUID
    let reviewID: UUID
    let blockID: UUID
    let attachmentID: UUID
    let dayKey: String
    let image: Data
}

private struct BackupStageFixture {
    let initial: BackupPackageContents
    let complete: BackupPackageContents
    let groups: [BackupStageGroup]
}

@MainActor
private func makeBackupMergeStageFixture() throws -> BackupStageFixture {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let date = try #require(DayKey.date(from: "2026-09-22"))
    let first = try insertBackupStageGroup(index: 0, date: date, in: context)
    let initial = try BackupPackageCodec.makeContents(context: context, exportedAt: date)
    let second = try insertBackupStageGroup(index: 1, date: DayKey.addingDays(1, to: date), in: context)
    let complete = try BackupPackageCodec.makeContents(context: context, exportedAt: date.addingTimeInterval(100))
    return .init(initial: initial, complete: complete, groups: [first, second])
}

@MainActor
private func insertBackupStageGroup(index: Int, date: Date, in context: ModelContext) throws -> BackupStageGroup {
    let dayKey = DayKey.key(for: date)
    let event = CalendarEvent(title: "연결 일정 \(index)", startAt: date, endAt: date.addingTimeInterval(3_600),
                              createdAt: date, updatedAt: date)
    let template = TaskTemplate(name: "연결 루틴 \(index)", createdAt: date, updatedAt: date)
    let item = TaskTemplateItem(templateId: template.id, title: "루틴 항목 \(index)", order: 100,
                                createdAt: date, updatedAt: date)
    let placement = TemplatePlacement(sourceTemplateId: template.id, templateName: template.name, dayKey: dayKey,
                                       createdAt: date, updatedAt: date)
    let task = Task(title: "연결 작업 \(index)", plannedAt: date, order: 100, eventId: event.id,
                    templatePlacementId: placement.id, createdAt: date, updatedAt: date)
    let checklist = TaskChecklistItem(taskId: task.id, title: "체크 항목 \(index)", order: 100,
                                      createdAt: date, updatedAt: date)
    let review = DailyReview(dayKey: dayKey, content: "회고 내용 \(index)", createdAt: date, updatedAt: date)
    let block = DiaryBlock(reviewId: review.id, dayKey: dayKey, type: .text, text: review.content,
                           order: 100, createdAt: date, updatedAt: date)
    var image = try #require(Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
    image.append(UInt8(index))
    let metadata = try DiaryAttachmentService.inspect(image)
    let attachment = DiaryAttachment(reviewId: review.id, order: 100, originalFileName: "stage-\(index).png",
        mimeType: metadata.mediaType.rawValue, byteCount: metadata.byteCount, sha256: metadata.sha256,
        data: image, createdAt: date, updatedAt: date)
    context.insert(event)
    context.insert(template)
    context.insert(item)
    context.insert(placement)
    context.insert(task)
    context.insert(checklist)
    context.insert(review)
    context.insert(block)
    context.insert(attachment)
    return .init(eventID: event.id, templateID: template.id, templateItemID: item.id,
                 placementID: placement.id, taskID: task.id, checklistID: checklist.id,
                 reviewID: review.id, blockID: block.id, attachmentID: attachment.id,
                 dayKey: dayKey, image: image)
}

@MainActor
private func expectBackupStageJoins(_ groups: [BackupStageGroup], in context: ModelContext) throws {
    let events = try context.fetch(FetchDescriptor<CalendarEvent>())
    let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
    let items = try context.fetch(FetchDescriptor<TaskTemplateItem>())
    let placements = try context.fetch(FetchDescriptor<TemplatePlacement>())
    let tasks = try context.fetch(FetchDescriptor<Task>())
    let checks = try context.fetch(FetchDescriptor<TaskChecklistItem>())
    let reviews = try context.fetch(FetchDescriptor<DailyReview>())
    let blocks = try context.fetch(FetchDescriptor<DiaryBlock>())
    let attachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
    for group in groups {
        #expect(events.contains { $0.id == group.eventID && $0.supersededAt == nil })
        #expect(templates.contains { $0.id == group.templateID && $0.supersededAt == nil })
        let item = try #require(items.first { $0.id == group.templateItemID && $0.supersededAt == nil })
        #expect(item.templateId == group.templateID)
        let placement = try #require(placements.first { $0.id == group.placementID && $0.supersededAt == nil })
        #expect(placement.sourceTemplateId == group.templateID && placement.dayKey == group.dayKey)
        let task = try #require(tasks.first { $0.id == group.taskID && $0.supersededAt == nil })
        #expect(task.eventId == group.eventID && task.templatePlacementId == group.placementID)
        #expect(task.plannedDayKey == group.dayKey)
        let check = try #require(checks.first { $0.id == group.checklistID && $0.supersededAt == nil })
        #expect(check.taskId == group.taskID)
        let review = try #require(reviews.first { $0.id == group.reviewID && $0.supersededAt == nil })
        #expect(review.dayKey == group.dayKey)
        let block = try #require(blocks.first { $0.id == group.blockID && $0.supersededAt == nil })
        #expect(block.reviewId == group.reviewID && block.dayKey == group.dayKey)
        let attachment = try #require(attachments.first { $0.id == group.attachmentID && $0.supersededAt == nil })
        #expect(attachment.reviewId == group.reviewID && attachment.data == group.image)
    }
}

private struct BackupStageSnapshot: Equatable {
    let records: [Data]
    let attachmentBytes: [UUID: Data]
}

@MainActor
private func backupStageSnapshot(in context: ModelContext) throws -> BackupStageSnapshot {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var records: [Data] = []
    let tasks = try context.fetch(FetchDescriptor<Task>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    records.append(try encoder.encode(tasks.map(TaskDTO.init)))
    let events = try context.fetch(FetchDescriptor<CalendarEvent>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    records.append(try encoder.encode(events.map(CalendarEventDTO.init)))
    let templates = try context.fetch(FetchDescriptor<TaskTemplate>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    records.append(try encoder.encode(templates.map(TaskTemplateDTO.init)))
    let items = try context.fetch(FetchDescriptor<TaskTemplateItem>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    records.append(try encoder.encode(items.map(TaskTemplateItemDTO.init)))
    let placements = try context.fetch(FetchDescriptor<TemplatePlacement>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    records.append(try encoder.encode(placements.map(TemplatePlacementDTO.init)))
    let checks = try context.fetch(FetchDescriptor<TaskChecklistItem>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    records.append(try encoder.encode(checks.map(TaskChecklistItemDTO.init)))
    let reviews = try context.fetch(FetchDescriptor<DailyReview>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    records.append(try encoder.encode(reviews.map(DailyReviewDTO.init)))
    let blocks = try context.fetch(FetchDescriptor<DiaryBlock>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    records.append(try encoder.encode(blocks.map(DiaryBlockDTO.init)))
    let attachments = try context.fetch(FetchDescriptor<DiaryAttachment>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    let metadata = attachments.map { attachment in
        BackupPackageAttachmentRecord(id: attachment.id, instanceID: attachment.instanceID,
            reviewId: attachment.reviewId, order: attachment.order, originalFileName: attachment.originalFileName,
            mimeType: attachment.mimeType, byteCount: attachment.byteCount, sha256: attachment.sha256,
            createdAt: attachment.createdAt, updatedAt: attachment.updatedAt)
    }
    records.append(try encoder.encode(metadata))
    return .init(records: records, attachmentBytes: Dictionary(uniqueKeysWithValues: attachments.map { ($0.instanceID, $0.data) }))
}
