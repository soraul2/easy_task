import Foundation
import Testing
@testable import EasyTaskCore

@Test
func dailyReviewWritingPromptStartsAnEmptyReview() {
    let result = DailyReviewWritingRules.appending(.didWell, to: " \n ")

    #expect(result == "잘한 점\n")
}

@Test
func dailyReviewWritingPromptAppendsAfterExistingContent() {
    let result = DailyReviewWritingRules.appending(
        .nextStep,
        to: "오늘은 산책을 했다.\n"
    )

    #expect(result == "오늘은 산책을 했다.\n\n내일의 한 걸음\n")
}

@Test
func dailyReviewWritingPromptDoesNotDuplicateAnExistingHeading() {
    let content = "잘한 점\n중요한 일을 끝냈다."

    #expect(DailyReviewWritingRules.contains(.didWell, in: content))
    #expect(DailyReviewWritingRules.appending(.didWell, to: content) == content)
}

@Test
func archiveRecordSummaryCountsLoadedContent() {
    let firstReview = DailyReview(dayKey: "2026-07-24", content: "기록")
    let firstTask = Task(title: "첫 번째", plannedAt: Date(), order: 100)
    let secondTask = Task(title: "두 번째", plannedAt: Date(), order: 200)
    let records = [
        ArchiveDayRecord(
            dayKey: "2026-07-24",
            tasks: [firstTask, secondTask],
            review: firstReview
        ),
        ArchiveDayRecord(
            dayKey: "2026-07-23",
            tasks: [],
            review: nil
        )
    ]

    #expect(
        ArchiveRecordSummary(records: records) ==
            ArchiveRecordSummary(
                dayCount: 2,
                reviewCount: 1,
                completedTaskCount: 2
            )
    )
}
