import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test
@MainActor
func boundedBoardFetchReturnsOneDayFromTenThousandTasks() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let firstDate = try #require(DayKey.date(from: "2026-01-01"))
    let targetDayKey = "2026-02-10"

    for index in 0..<10_000 {
        let date = DayKey.addingDays(index % 100, to: firstDate)
        context.insert(Task(
            title: "작업 \(index)",
            plannedAt: date,
            order: Double(index)
        ))
    }
    try context.save()

    let clock = ContinuousClock()
    let startedAt = clock.now
    let rows = try context.fetch(BoundedQueryService.boardTasksDescriptor(
        selectedDayKey: targetDayKey
    ))
    let elapsed = startedAt.duration(to: clock.now)

    #expect(try context.fetchCount(FetchDescriptor<Task>()) == 10_000)
    #expect(rows.count == 100)
    #expect(rows.allSatisfy { $0.plannedDayKey == targetDayKey })
    #expect(elapsed < .seconds(5))
}

@Test
@MainActor
func boundedBoardAndCarryoverDescriptorsPreserveVisibilityRules() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let today = try #require(DayKey.date(from: "2026-07-12"))
    let yesterday = try #require(DayKey.date(from: "2026-07-11"))
    let tomorrow = try #require(DayKey.date(from: "2026-07-13"))

    let todayTask = Task(title: "오늘", plannedAt: today, order: 100)
    let carryover = Task(title: "이월", plannedAt: yesterday, order: 100)
    let future = Task(title: "미래", plannedAt: tomorrow, order: 100)
    let completed = Task(title: "완료", status: .done, plannedAt: today, order: 100)
    completed.completedDayKey = "2026-07-12"
    let superseded = Task(title: "대체됨", plannedAt: yesterday, order: 200)
    superseded.supersededAt = Date()
    [todayTask, carryover, future, completed, superseded].forEach(context.insert)
    try context.save()

    let boardRows = try context.fetch(BoundedQueryService.boardTasksDescriptor(
        selectedDayKey: "2026-07-12"
    ))
    let carryoverRows = try context.fetch(BoundedQueryService.carryoverTasksDescriptor(
        before: "2026-07-12"
    ))

    #expect(Set(boardRows.map(\.title)) == Set(["오늘", "완료"]))
    #expect(carryoverRows.map(\.title) == ["이월"])
}

@Test
@MainActor
func boundedCalendarDescriptorsFetchOnlyOverlappingRange() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let june = try #require(DayKey.date(from: "2026-06-20"))
    let julyStart = try #require(DayKey.date(from: "2026-07-02"))
    let julyEnd = try #require(DayKey.date(from: "2026-07-15"))
    let august = try #require(DayKey.date(from: "2026-08-01"))

    let before = CalendarEvent(title: "이전", startAt: june, endAt: june)
    let overlapping = CalendarEvent(title: "겹침", startAt: julyStart, endAt: julyEnd)
    let after = CalendarEvent(title: "이후", startAt: august, endAt: august)
    let placement = TemplatePlacement(
        sourceTemplateId: nil,
        templateName: "7월 배치",
        dayKey: "2026-07-10"
    )
    let outsidePlacement = TemplatePlacement(
        sourceTemplateId: nil,
        templateName: "8월 배치",
        dayKey: "2026-08-10"
    )
    [before, overlapping, after].forEach(context.insert)
    [placement, outsidePlacement].forEach(context.insert)
    try context.save()

    let events = try context.fetch(BoundedQueryService.eventsDescriptor(
        overlappingStartDayKey: "2026-07-01",
        endDayKey: "2026-07-31"
    ))
    let placements = try context.fetch(BoundedQueryService.templatePlacementsDescriptor(
        from: "2026-07-01",
        through: "2026-07-31"
    ))

    #expect(events.map(\.title) == ["겹침"])
    #expect(placements.map(\.templateName) == ["7월 배치"])
}

@Test
@MainActor
func boundedNextOrderAndEventLinksAvoidWholeTaskArray() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let date = try #require(DayKey.date(from: "2026-07-12"))
    let eventID = UUID()
    let first = Task(title: "첫 작업", plannedAt: date, order: 100, eventId: eventID)
    let second = Task(title: "둘째 작업", plannedAt: date, order: 350, eventId: eventID)
    let other = Task(
        title: "다른 상태",
        status: .doing,
        plannedAt: date,
        order: 900
    )
    [first, second, other].forEach(context.insert)
    try context.save()

    #expect(try BoundedQueryService.nextOrder(
        in: context,
        dayKey: "2026-07-12",
        status: .todo
    ) == 450)
    #expect(Set(try BoundedQueryService.tasksLinked(
        toEventID: eventID,
        in: context
    ).map(\.id)) == Set([first.id, second.id]))
}

@Test
@MainActor
func archivePagesKeepCompleteDaysAndDoNotDuplicateAcrossCursors() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let referenceDate = try #require(DayKey.date(from: "2026-07-12"))

    for offset in 0..<40 {
        let date = DayKey.addingDays(-offset, to: referenceDate)
        let taskCount = offset == 29 ? 31 : 1
        for index in 0..<taskCount {
            let task = Task(
                title: "완료 \(offset)-\(index)",
                status: .done,
                plannedAt: date,
                order: Double(index * 100)
            )
            task.completedAt = date
            task.completedDayKey = DayKey.key(for: date)
            context.insert(task)
        }
    }

    let imageDayKey = DayKey.key(for: DayKey.addingDays(-2, to: referenceDate))
    let imageOnlyReview = DailyReview(dayKey: imageDayKey, content: "")
    context.insert(imageOnlyReview)
    context.insert(DiaryAttachment(
        reviewId: imageOnlyReview.id,
        order: 100,
        mimeType: "image/jpeg",
        byteCount: 3,
        sha256: "archive-page-test",
        data: Data([1, 2, 3])
    ))
    try context.save()

    let firstPage = try BoundedQueryService.archivePage(
        in: context,
        filter: ArchiveFilter(),
        referenceDate: referenceDate
    )
    let secondPage = try BoundedQueryService.archivePage(
        in: context,
        filter: ArchiveFilter(),
        beforeDayKey: firstPage.nextBeforeDayKey,
        referenceDate: referenceDate
    )

    #expect(firstPage.records.count == 30)
    #expect(firstPage.records.last?.tasks.count == 31)
    #expect(firstPage.records.first { $0.dayKey == imageDayKey }?.review?.id == imageOnlyReview.id)
    #expect(firstPage.attachments.count == 1)
    #expect(firstPage.hasMore)
    #expect(secondPage.records.count == 10)
    #expect(!secondPage.hasMore)
    #expect(Set(firstPage.records.map(\.dayKey)).isDisjoint(
        with: Set(secondPage.records.map(\.dayKey))
    ))
}

@Test
@MainActor
func archiveSearchScansBoundedWindowsUntilSparseMatch() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let referenceDate = try #require(DayKey.date(from: "2026-07-12"))

    for offset in 0..<95 {
        let date = DayKey.addingDays(-offset, to: referenceDate)
        let task = Task(
            title: offset == 94 ? "needle 작업" : "일반 작업 \(offset)",
            status: .done,
            plannedAt: date,
            order: 100
        )
        task.completedAt = date
        task.completedDayKey = DayKey.key(for: date)
        context.insert(task)
    }
    try context.save()

    var filter = ArchiveFilter()
    filter.searchText = "needle"
    let page = try BoundedQueryService.archivePage(
        in: context,
        filter: filter,
        referenceDate: referenceDate
    )

    #expect(page.records.count == 1)
    #expect(page.records.first?.tasks.map(\.title) == ["needle 작업"])
    #expect(!page.hasMore)
}

@Test
@MainActor
func archivePageSearchIncludesChecklistMatches() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let referenceDate = try #require(DayKey.date(from: "2026-07-12"))
    let task = Task(
        title: "장보기",
        status: .done,
        plannedAt: referenceDate,
        order: 100
    )
    task.completedAt = referenceDate
    task.completedDayKey = "2026-07-12"
    let checklistItem = TaskChecklistItem(
        taskId: task.id,
        title: "오트밀",
        order: 100
    )
    context.insert(task)
    context.insert(checklistItem)
    try context.save()

    var filter = ArchiveFilter()
    filter.searchText = "오트밀"
    filter.scope = .tasks
    let page = try BoundedQueryService.archivePage(
        in: context,
        filter: filter,
        referenceDate: referenceDate
    )

    let record = try #require(page.records.first)
    #expect(record.tasks.map(\.id) == [task.id])
    #expect(record.matchedTaskIDs == [task.id])
    #expect(record.matchedChecklistItemIDs == [checklistItem.id])
}

@Test
@MainActor
func boundedReviewMediaAndArchiveCandidateDescriptorsUseExactOwners() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let today = try #require(DayKey.date(from: "2026-07-12"))
    let yesterday = try #require(DayKey.date(from: "2026-07-11"))

    let review = DailyReview(dayKey: "2026-07-12", content: "오늘 회고")
    let otherReview = DailyReview(dayKey: "2026-07-11", content: "이전 회고")
    let attachment = DiaryAttachment(
        reviewId: review.id,
        order: 100,
        mimeType: "image/png",
        byteCount: 1,
        sha256: "review-owner",
        data: Data([1])
    )
    let otherAttachment = DiaryAttachment(
        reviewId: otherReview.id,
        order: 100,
        mimeType: "image/png",
        byteCount: 1,
        sha256: "other-owner",
        data: Data([2])
    )
    let block = DiaryBlock(
        reviewId: review.id,
        dayKey: review.dayKey,
        type: .text,
        text: "본문",
        order: 100
    )
    let archivedCandidate = Task(
        title: "어제 완료",
        status: .done,
        plannedAt: yesterday,
        order: 100
    )
    archivedCandidate.completedAt = yesterday
    archivedCandidate.completedDayKey = "2026-07-11"
    let todayDone = Task(
        title: "오늘 완료",
        status: .done,
        plannedAt: today,
        order: 100
    )
    todayDone.completedAt = today
    todayDone.completedDayKey = "2026-07-12"
    [review, otherReview].forEach(context.insert)
    [attachment, otherAttachment].forEach(context.insert)
    context.insert(block)
    [archivedCandidate, todayDone].forEach(context.insert)
    try context.save()

    #expect(try context.fetch(
        BoundedQueryService.dailyReviewsDescriptor(dayKey: "2026-07-12")
    ).map(\.id) == [review.id])
    #expect(try context.fetch(
        BoundedQueryService.diaryAttachmentsDescriptor(reviewID: review.id)
    ).map(\.id) == [attachment.id])
    #expect(try context.fetch(
        BoundedQueryService.diaryBlocksDescriptor(reviewID: review.id)
    ).map(\.id) == [block.id])
    #expect(try context.fetch(
        BoundedQueryService.tasksNeedingArchiveDescriptor(before: "2026-07-12")
    ).map(\.id) == [archivedCandidate.id])
}
