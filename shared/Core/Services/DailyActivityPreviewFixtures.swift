#if DEBUG
import Foundation
import SwiftData

/// Deterministic, in-memory-only UI preview data. Callers must opt in via the UI testing launch flag.
public enum DailyActivityPreviewFixtures {
    @MainActor
    public static func seed(in context: ModelContext, referenceDate: Date = Date()) throws {
        let marker = "기획서 초안 마무리"
        var descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.title == marker })
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        let today = DayKey.startOfDay(for: referenceDate)
        func time(_ offset: Int, _ hour: Int) -> Date {
            DayKey.addingDays(offset, to: today).addingTimeInterval(Double(hour * 3600))
        }
        func task(_ title: String, day: Int) -> Task {
            let result = Task(title: title, plannedAt: DayKey.addingDays(day, to: today), order: 100, createdAt: time(day, 8))
            context.insert(result)
            return result
        }
        func progress(_ task: Task, start: Date, minutes: Int) {
            context.insert(TaskProgressEvent(taskId: task.id, kind: .started, occurredAt: start))
            context.insert(
                TaskProgressEvent(
                    taskId: task.id, kind: .stopped,
                    occurredAt: start.addingTimeInterval(Double(minutes * 60))))
        }
        func focus(_ taskID: UUID, start: Date, minutes: Int) {
            context.insert(
                FocusSession(
                    taskId: taskID, startedAt: start,
                    endedAt: start.addingTimeInterval(Double(minutes * 60)),
                    plannedDurationSeconds: minutes * 60, focusedDurationSeconds: minutes * 60,
                    outcome: .completed))
        }
        let proposal = task(marker, day: -2)
        proposal.status = TaskStatus.done.rawValue
        proposal.completedAt = time(0, 10)
        proposal.completedDayKey = DayKey.key(for: today)
        try TaskActivityService.recordCapturedCompletion(
            taskID: proposal.id, occurredAt: time(0, 10), in: context)
        progress(proposal, start: time(0, 9), minutes: 40)
        let english = task("영어 공부", day: 0)
        english.note = "듣기 연습과 새 표현 정리"
        progress(english, start: time(0, 10), minutes: 30)
        focus(english.id, start: time(0, 10), minutes: 25)
        let interview = task("고객 인터뷰 메모 정리", day: 0)
        progress(interview, start: time(0, 11), minutes: 20)
        let book = task("책 읽기", day: 0)
        focus(book.id, start: time(0, 12), minutes: 15)

        let yesterdayFocus = task("집중해서 책 읽기", day: -1)
        focus(yesterdayFocus.id, start: time(-1, 20), minutes: 25)
        let design = task("모바일 화면의 접근성과 긴 제목 줄바꿈을 확인하며 디자인 초안 다듬기", day: -2)
        progress(design, start: time(-2, 10), minutes: 45)
        let review = DailyReview(dayKey: DayKey.key(for: time(-3, 0)), content: "")
        review.title = "아이디어를 정리한 날"
        review.content = "떠오른 생각을 천천히 정리했다. 다음 주에는 작은 기능 하나부터 마무리해 보자."
        context.insert(review)
        focus(UUID(), start: time(-4, 9), minutes: 15)
    }
}
#endif
