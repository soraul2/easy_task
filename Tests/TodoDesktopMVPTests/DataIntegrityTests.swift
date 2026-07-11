import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func duplicateReviewUsesInstanceIDToBreakEqualTimestampTie() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let createdAt = testTimestamp(10)
    let updatedAt = testTimestamp(30)
    let canonicalID = testUUID(10)
    let winnerID = testUUID(20)
    let canonical = DailyReview(
        id: canonicalID,
        instanceID: testUUID(1),
        dayKey: "2026-07-10",
        content: "older instance",
        createdAt: createdAt,
        updatedAt: updatedAt
    )
    let winner = DailyReview(
        id: winnerID,
        instanceID: testUUID(2),
        dayKey: "2026-07-10",
        content: "higher instance",
        createdAt: testTimestamp(20),
        updatedAt: updatedAt
    )
    let block = DiaryBlock(
        reviewId: winnerID,
        dayKey: winner.dayKey,
        type: .text,
        text: "kept block",
        order: 100,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
    context.insert(canonical)
    context.insert(winner)
    context.insert(block)
    try context.save()

    let report = try DataIntegrityService.reconcile(context: context)
    let reviews = try context.fetch(FetchDescriptor<DailyReview>())
    let activeReview = try #require(reviews.first { $0.supersededAt == nil })

    #expect(report.mergedRecords == 1)
    #expect(activeReview.id == winnerID)
    #expect(activeReview.instanceID == testUUID(2))
    #expect(activeReview.content == "higher instance")
    #expect(activeReview.createdAt == createdAt)
    #expect(canonical.supersededAt == updatedAt)
    #expect(winner.supersededAt == nil)
    #expect(block.reviewId == winnerID)
    #expect(block.dayKey == activeReview.dayKey)
}

@Test
@MainActor
func seededTemplateMergeRewiresItemsAndPlacements() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let canonicalTemplateID = testUUID(100)
    let winnerTemplateID = testUUID(200)
    let canonicalTemplate = TaskTemplate(
        id: canonicalTemplateID,
        instanceID: testUUID(11),
        seedKey: "morning-routine",
        name: "Old routine",
        createdAt: testTimestamp(10),
        updatedAt: testTimestamp(20)
    )
    let winnerTemplate = TaskTemplate(
        id: winnerTemplateID,
        instanceID: testUUID(12),
        seedKey: "morning-routine",
        name: "Current routine",
        isFavorite: true,
        createdAt: testTimestamp(15),
        updatedAt: testTimestamp(30)
    )
    let canonicalItem = TaskTemplateItem(
        id: testUUID(300),
        instanceID: testUUID(21),
        seedKey: "morning-routine.0",
        templateId: canonicalTemplateID,
        title: "Old item",
        order: 100,
        createdAt: testTimestamp(10),
        updatedAt: testTimestamp(20)
    )
    let winnerItem = TaskTemplateItem(
        id: testUUID(400),
        instanceID: testUUID(22),
        seedKey: "morning-routine.0",
        templateId: winnerTemplateID,
        title: "Current item",
        order: 200,
        createdAt: testTimestamp(15),
        updatedAt: testTimestamp(40)
    )
    let placement = TemplatePlacement(
        sourceTemplateId: winnerTemplateID,
        templateName: "Current routine",
        dayKey: "2026-07-10",
        taskIds: [testUUID(999)],
        createdAt: testTimestamp(20),
        updatedAt: testTimestamp(20)
    )
    let unrelatedTask = Task(
        title: "Must remain unplaced",
        plannedAt: try #require(DayKey.date(from: "2026-07-10")),
        order: 100
    )
    context.insert(canonicalTemplate)
    context.insert(winnerTemplate)
    context.insert(canonicalItem)
    context.insert(winnerItem)
    context.insert(placement)
    context.insert(unrelatedTask)
    try context.save()

    _ = try DataIntegrityService.reconcile(context: context)

    #expect(canonicalTemplate.supersededAt == winnerTemplate.updatedAt)
    #expect(canonicalTemplate.name == "Old routine")
    #expect(winnerTemplate.supersededAt == nil)
    #expect(winnerTemplate.name == "Current routine")
    #expect(winnerTemplate.isFavorite)
    #expect(canonicalItem.supersededAt == winnerItem.updatedAt)
    #expect(canonicalItem.title == "Old item")
    #expect(winnerItem.supersededAt == nil)
    #expect(winnerItem.templateId == winnerTemplateID)
    #expect(winnerItem.title == "Current item")
    #expect(placement.sourceTemplateId == winnerTemplateID)
    #expect(placement.taskIds.isEmpty)
    #expect(unrelatedTask.templatePlacementId == nil)
}

@Test
@MainActor
func invalidScalarsAndReferencesAreRepairedWithoutDeletingChildren() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let july10 = try #require(DayKey.date(from: "2026-07-10"))
    let july11 = try #require(DayKey.date(from: "2026-07-11"))
    let template = TaskTemplate(name: "Valid template")
    let review = DailyReview(dayKey: "2026-07-10", content: "Valid review")
    let placement = TemplatePlacement(
        sourceTemplateId: testUUID(900),
        templateName: "Detached source",
        dayKey: "not-a-day",
        taskIds: [testUUID(901)],
        createdAt: testTimestamp(10),
        updatedAt: testTimestamp(10)
    )
    let event = CalendarEvent(
        title: "Reversed event",
        startAt: july11,
        endAt: july10,
        color: "ultraviolet",
        createdAt: testTimestamp(30),
        updatedAt: testTimestamp(20)
    )
    event.startDayKey = "2026-07-11"
    event.endDayKey = "2026-07-10"

    let task = Task(
        title: "Repair me",
        plannedAt: july11,
        order: 100,
        eventId: testUUID(910),
        templatePlacementId: testUUID(911),
        createdAt: testTimestamp(30),
        updatedAt: testTimestamp(20)
    )
    task.status = "blocked"
    task.plannedDayKey = "2026-07-10"
    task.priority = "urgent"
    task.tags = [" focus ", "", "focus", "home"]
    task.estimatedMinutes = -15
    task.order = -.infinity
    task.completedAt = testTimestamp(25)
    task.completedDayKey = "bad-completion-key"
    task.archivedAt = testTimestamp(26)
    task.archivedDayKey = "bad-archive-key"

    let repairableItem = TaskTemplateItem(
        templateId: template.id,
        title: "Repair item",
        priority: "critical",
        tags: [" work ", "work", ""],
        estimatedMinutes: -1,
        order: .infinity
    )
    let danglingItem = TaskTemplateItem(
        templateId: testUUID(920),
        title: "Dangling item",
        order: 100,
        updatedAt: testTimestamp(40)
    )
    let blankItem = TaskTemplateItem(
        templateId: template.id,
        title: "  \n ",
        order: 200,
        updatedAt: testTimestamp(41)
    )
    let danglingBlock = DiaryBlock(
        reviewId: testUUID(930),
        dayKey: "2026-07-10",
        type: .text,
        text: "Dangling block",
        order: 100,
        updatedAt: testTimestamp(42)
    )
    let blankBlock = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .text,
        text: " \n ",
        order: 200,
        updatedAt: testTimestamp(43)
    )

    context.insert(template)
    context.insert(review)
    context.insert(placement)
    context.insert(event)
    context.insert(task)
    context.insert(repairableItem)
    context.insert(danglingItem)
    context.insert(blankItem)
    context.insert(danglingBlock)
    context.insert(blankBlock)
    try context.save()

    let report = try DataIntegrityService.reconcile(context: context)

    #expect(report.hasChanges)
    #expect(event.startAt == july10)
    #expect(event.endAt == july11)
    #expect(event.startDayKey == "2026-07-10")
    #expect(event.endDayKey == "2026-07-11")
    #expect(event.color == nil)
    #expect(event.createdAt == event.updatedAt)
    #expect(task.status == TaskStatus.done.rawValue)
    #expect(task.plannedDayKey == "2026-07-10")
    #expect(task.plannedAt == july10)
    #expect(task.priority == nil)
    #expect(task.tags == ["focus", "home"])
    #expect(task.estimatedMinutes == nil)
    #expect(task.order == 0)
    #expect(task.eventId == nil)
    #expect(task.templatePlacementId == nil)
    #expect(task.completedAt != nil)
    #expect(task.completedDayKey.map(validIntegrityTestDayKey) == true)
    #expect(task.archivedAt != nil)
    #expect(task.archivedDayKey.map(validIntegrityTestDayKey) == true)
    #expect(task.createdAt == task.updatedAt)
    #expect(repairableItem.priority == nil)
    #expect(repairableItem.tags == ["work"])
    #expect(repairableItem.estimatedMinutes == nil)
    #expect(repairableItem.order == 0)
    #expect(placement.sourceTemplateId == nil)
    #expect(validIntegrityTestDayKey(placement.dayKey))
    #expect(placement.taskIds.isEmpty)
    #expect(danglingItem.supersededAt == danglingItem.updatedAt)
    #expect(blankItem.supersededAt == blankItem.updatedAt)
    #expect(danglingBlock.supersededAt == danglingBlock.updatedAt)
    #expect(blankBlock.supersededAt == blankBlock.updatedAt)
    #expect(try context.fetchCount(FetchDescriptor<TaskTemplateItem>()) == 3)
    #expect(try context.fetchCount(FetchDescriptor<DiaryBlock>()) == 2)
}

@Test
@MainActor
func duplicateLogicalIDsMergeForEveryPersistedModel() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-10"))
    let oldTimestamp = testTimestamp(10)
    let newTimestamp = testTimestamp(20)

    let eventID = testUUID(1_000)
    let eventA = CalendarEvent(
        id: eventID,
        instanceID: testUUID(101),
        title: "Old event",
        startAt: day,
        endAt: day,
        createdAt: oldTimestamp,
        updatedAt: oldTimestamp
    )
    let eventB = CalendarEvent(
        id: eventID,
        instanceID: testUUID(102),
        title: "New event",
        startAt: day,
        endAt: day,
        createdAt: newTimestamp,
        updatedAt: newTimestamp
    )

    let templateID = testUUID(2_000)
    let templateA = TaskTemplate(
        id: templateID,
        instanceID: testUUID(201),
        name: "Old template",
        createdAt: oldTimestamp,
        updatedAt: oldTimestamp
    )
    let templateB = TaskTemplate(
        id: templateID,
        instanceID: testUUID(202),
        name: "New template",
        createdAt: newTimestamp,
        updatedAt: newTimestamp
    )

    let itemID = testUUID(3_000)
    let itemA = TaskTemplateItem(
        id: itemID,
        instanceID: testUUID(301),
        templateId: templateID,
        title: "Old item",
        order: 100,
        createdAt: oldTimestamp,
        updatedAt: oldTimestamp
    )
    let itemB = TaskTemplateItem(
        id: itemID,
        instanceID: testUUID(302),
        templateId: templateID,
        title: "New item",
        order: 200,
        createdAt: newTimestamp,
        updatedAt: newTimestamp
    )

    let placementID = testUUID(4_000)
    let placementA = TemplatePlacement(
        id: placementID,
        instanceID: testUUID(401),
        sourceTemplateId: templateID,
        templateName: "Old placement",
        dayKey: "2026-07-10",
        createdAt: oldTimestamp,
        updatedAt: oldTimestamp
    )
    let placementB = TemplatePlacement(
        id: placementID,
        instanceID: testUUID(402),
        sourceTemplateId: templateID,
        templateName: "New placement",
        dayKey: "2026-07-10",
        createdAt: newTimestamp,
        updatedAt: newTimestamp
    )

    let taskID = testUUID(5_000)
    let taskA = Task(
        id: taskID,
        instanceID: testUUID(501),
        title: "Old task",
        plannedAt: day,
        order: 100,
        eventId: eventID,
        templatePlacementId: placementID,
        createdAt: oldTimestamp,
        updatedAt: oldTimestamp
    )
    let taskB = Task(
        id: taskID,
        instanceID: testUUID(502),
        title: "New task",
        plannedAt: day,
        order: 200,
        eventId: eventID,
        templatePlacementId: placementID,
        createdAt: newTimestamp,
        updatedAt: newTimestamp
    )

    let reviewID = testUUID(6_000)
    let reviewA = DailyReview(
        id: reviewID,
        instanceID: testUUID(601),
        dayKey: "2026-07-10",
        content: "Old review",
        createdAt: oldTimestamp,
        updatedAt: oldTimestamp
    )
    let reviewB = DailyReview(
        id: reviewID,
        instanceID: testUUID(602),
        dayKey: "2026-07-10",
        content: "New review",
        createdAt: newTimestamp,
        updatedAt: newTimestamp
    )

    let blockID = testUUID(7_000)
    let blockA = DiaryBlock(
        id: blockID,
        instanceID: testUUID(701),
        reviewId: reviewID,
        dayKey: "2026-07-10",
        type: .text,
        text: "Old block",
        order: 100,
        createdAt: oldTimestamp,
        updatedAt: oldTimestamp
    )
    let blockB = DiaryBlock(
        id: blockID,
        instanceID: testUUID(702),
        reviewId: reviewID,
        dayKey: "2026-07-10",
        type: .text,
        text: "New block",
        order: 200,
        createdAt: newTimestamp,
        updatedAt: newTimestamp
    )

    for event in [eventA, eventB] { context.insert(event) }
    for template in [templateA, templateB] { context.insert(template) }
    for item in [itemA, itemB] { context.insert(item) }
    for placement in [placementA, placementB] { context.insert(placement) }
    for task in [taskA, taskB] { context.insert(task) }
    for review in [reviewA, reviewB] { context.insert(review) }
    for block in [blockA, blockB] { context.insert(block) }
    try context.save()

    let report = try DataIntegrityService.reconcile(context: context)

    #expect(report.mergedRecords == 7)
    #expect(report.supersededRecords == 7)
    #expect([eventA, eventB].filter { $0.supersededAt == nil }.count == 1)
    #expect([templateA, templateB].filter { $0.supersededAt == nil }.count == 1)
    #expect([itemA, itemB].filter { $0.supersededAt == nil }.count == 1)
    #expect([placementA, placementB].filter { $0.supersededAt == nil }.count == 1)
    #expect([taskA, taskB].filter { $0.supersededAt == nil }.count == 1)
    #expect([reviewA, reviewB].filter { $0.supersededAt == nil }.count == 1)
    #expect([blockA, blockB].filter { $0.supersededAt == nil }.count == 1)
    #expect(eventA.title == "Old event")
    #expect(templateA.name == "Old template")
    #expect(itemA.title == "Old item")
    #expect(placementA.templateName == "Old placement")
    #expect(taskA.title == "Old task")
    #expect(reviewA.content == "Old review")
    #expect(blockA.text == "Old block")
    #expect(eventA.supersededAt == newTimestamp)
    #expect(eventB.createdAt == oldTimestamp)
    #expect(eventB.supersededAt == nil)
    #expect(templateB.supersededAt == nil)
    #expect(itemB.supersededAt == nil)
    #expect(placementB.supersededAt == nil)
    #expect(taskB.supersededAt == nil)
    #expect(reviewB.supersededAt == nil)
    #expect(blockB.supersededAt == nil)
}

@Test
@MainActor
func secondReconciliationIsIdempotent() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let first = DailyReview(
        instanceID: testUUID(801),
        dayKey: "2026-07-10",
        content: "First",
        updatedAt: testTimestamp(10)
    )
    let second = DailyReview(
        instanceID: testUUID(802),
        dayKey: "2026-07-10",
        content: "Second",
        updatedAt: testTimestamp(20)
    )
    context.insert(first)
    context.insert(second)
    try context.save()

    let firstReport = try DataIntegrityService.reconcile(context: context)
    let secondReport = try DataIntegrityService.reconcile(context: context)

    #expect(firstReport.hasChanges)
    #expect(secondReport == .noChanges)
}

@Test
@MainActor
func zeroMinuteEstimatesRemainValid() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
    let context = container.mainContext
    let day = try #require(DayKey.date(from: "2026-07-10"))
    let template = TaskTemplate(name: "Zero estimate")
    let item = TaskTemplateItem(
        templateId: template.id,
        title: "Zero-minute item",
        estimatedMinutes: 0,
        order: 100
    )
    let task = Task(
        title: "Zero-minute task",
        plannedAt: day,
        order: 100,
        estimatedMinutes: 0
    )
    context.insert(template)
    context.insert(item)
    context.insert(task)
    try context.save()

    _ = try DataIntegrityService.reconcile(context: context)

    #expect(item.estimatedMinutes == 0)
    #expect(task.estimatedMinutes == 0)
}

private func testUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llX", value))!
}

private func testTimestamp(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

private func validIntegrityTestDayKey(_ value: String) -> Bool {
    guard let date = DayKey.date(from: value) else { return false }
    return DayKey.key(for: date) == value
}
