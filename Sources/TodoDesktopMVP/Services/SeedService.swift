import Foundation
import SwiftData

enum SeedService {
    @MainActor
    static func seedIfNeeded(
        context: ModelContext,
        tasks: [Task],
        events: [CalendarEvent],
        templates: [TaskTemplate],
        reviews: [DailyReview]
    ) {
        ensureRoutineTemplates(context: context, templates: templates)
        ensureArchiveSearchSamples(context: context, tasks: tasks, reviews: reviews)
        guard tasks.isEmpty, events.isEmpty else { return }

        let today = DayKey.startOfDay(for: Date())
        let yesterday = DayKey.addingDays(-1, to: today)
        let tomorrow = DayKey.addingDays(1, to: today)
        let afterTomorrow = DayKey.addingDays(2, to: today)

        let planningEvent = CalendarEvent(
            title: "TodoApp MVP 설계",
            startAt: today,
            endAt: afterTomorrow,
            note: "칸반, 캘린더, 보관함 흐름 확인",
            color: "blue"
        )
        context.insert(planningEvent)

        context.insert(Task(
            title: "오늘 처리할 작업 빠르게 추가해보기",
            status: .todo,
            plannedAt: today,
            order: 100,
            eventId: planningEvent.id,
            priority: .medium,
            estimatedMinutes: 30
        ))

        context.insert(Task(
            title: "카드 상태 컨트롤 확인",
            status: .doing,
            plannedAt: today,
            order: 100,
            priority: .high,
            estimatedMinutes: 45
        ))

        context.insert(Task(
            title: "어제 미완료되어 오늘 보드에 표시되는 작업",
            status: .todo,
            plannedAt: yesterday,
            order: 200,
            estimatedMinutes: 20
        ))

        let doneTask = Task(
            title: "완료 영역 접힘 확인",
            status: .done,
            plannedAt: today,
            order: 100,
            estimatedMinutes: 15
        )
        TaskRules.applyStatus(.done, to: doneTask)
        context.insert(doneTask)

        context.insert(CalendarEvent(
            title: "다음 릴리즈 아이디어 정리",
            startAt: tomorrow,
            endAt: afterTomorrow,
            note: "기간 이벤트가 캘린더에 띠처럼 보이는지 확인",
            color: "green"
        ))
    }

    private static func ensureArchiveSearchSamples(
        context: ModelContext,
        tasks: [Task],
        reviews: [DailyReview]
    ) {
        let samplePrefix = "샘플:"
        let today = DayKey.startOfDay(for: Date())
        let threeDaysAgo = DayKey.addingDays(-3, to: today)
        let twoDaysAgo = DayKey.addingDays(-2, to: today)
        let yesterday = DayKey.addingDays(-1, to: today)

        migrateLegacySampleReviews(reviews)

        if !tasks.contains(where: { $0.title.hasPrefix(samplePrefix) }) {
            insertArchivedSampleTask(
                title: "샘플: 고객 미팅 준비 자료 정리",
                note: "검색 키워드: 고객사, 회의록, 요구사항",
                day: threeDaysAgo,
                order: 100,
                estimatedMinutes: 60,
                context: context
            )
            insertArchivedSampleTask(
                title: "샘플: 결제 오류 재현 로그 확인",
                note: "검색 키워드: payment webhook, 특수 이슈",
                day: threeDaysAgo,
                order: 200,
                estimatedMinutes: 45,
                context: context
            )
            insertArchivedSampleTask(
                title: "샘플: 캘린더 띠 이벤트 색상 조정",
                note: "기간 이벤트가 이어진 막대로 보이는지 확인",
                day: twoDaysAgo,
                order: 100,
                estimatedMinutes: 30,
                context: context
            )
            insertArchivedSampleTask(
                title: "샘플: 운동 기록 정리",
                note: "하체 루틴, 유산소, 스트레칭 기록",
                day: yesterday,
                order: 100,
                estimatedMinutes: 50,
                context: context
            )
        }

        applySampleEstimatedMinutes(to: tasks)

        ensureSampleReview(
            day: threeDaysAgo,
            title: "샘플: 고객 미팅 정리",
            weather: "맑음",
            mood: "차분함",
            content: "고객 미팅 자료와 결제 오류 로그를 정리했다. 나중에 고객사 또는 payment 키워드로 찾을 수 있어야 한다.",
            existingReviews: reviews,
            context: context
        )
        ensureSampleReview(
            day: twoDaysAgo,
            title: "샘플: 캘린더 UI 점검",
            weather: "흐림",
            mood: "집중",
            content: "캘린더 띠 이벤트 색상과 기간 표시를 확인했다. UI 조화와 가독성을 추가로 점검했다.",
            existingReviews: reviews,
            context: context
        )
        ensureSampleReview(
            day: yesterday,
            title: "샘플: 운동 기록 정리",
            weather: "비",
            mood: "개운함",
            content: "운동 기록을 정리하고 다음 루틴 템플릿에 반영할 항목을 확인했다.",
            existingReviews: reviews,
            context: context
        )
    }

    private static func migrateLegacySampleReviews(_ reviews: [DailyReview]) {
        for review in reviews where review.content.hasPrefix("샘플 회고:") {
            let migratedContent = review.content
                .replacingOccurrences(of: "샘플 회고: ", with: "")
                .replacingOccurrences(of: "샘플 회고:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if review.title.isEmpty {
                if migratedContent.contains("고객 미팅") {
                    review.title = "샘플: 고객 미팅 정리"
                    review.weather = review.weather.isEmpty ? "맑음" : review.weather
                    review.mood = review.mood.isEmpty ? "차분함" : review.mood
                } else if migratedContent.contains("캘린더") {
                    review.title = "샘플: 캘린더 UI 점검"
                    review.weather = review.weather.isEmpty ? "흐림" : review.weather
                    review.mood = review.mood.isEmpty ? "집중" : review.mood
                } else if migratedContent.contains("운동") {
                    review.title = "샘플: 운동 기록 정리"
                    review.weather = review.weather.isEmpty ? "비" : review.weather
                    review.mood = review.mood.isEmpty ? "개운함" : review.mood
                } else {
                    review.title = "샘플: 일기"
                }
            }

            review.content = migratedContent
            review.updatedAt = Date()
        }
    }

    private static func insertArchivedSampleTask(
        title: String,
        note: String,
        day: Date,
        order: Double,
        estimatedMinutes: Int,
        context: ModelContext
    ) {
        let now = Date()
        let task = Task(
            title: title,
            note: note,
            status: .done,
            plannedAt: day,
            order: order,
            estimatedMinutes: estimatedMinutes,
            createdAt: day,
            updatedAt: now
        )
        task.completedAt = day
        task.completedDayKey = DayKey.key(for: day)
        task.archivedAt = now
        task.archivedDayKey = DayKey.today
        context.insert(task)
    }

    private static func applySampleEstimatedMinutes(to tasks: [Task]) {
        let estimatesByTitle = [
            "샘플: 고객 미팅 준비 자료 정리": 60,
            "샘플: 결제 오류 재현 로그 확인": 45,
            "샘플: 캘린더 띠 이벤트 색상 조정": 30,
            "샘플: 운동 기록 정리": 50
        ]

        for task in tasks {
            guard task.estimatedMinutes == nil,
                  let estimatedMinutes = estimatesByTitle[task.title] else { continue }

            task.estimatedMinutes = estimatedMinutes
            task.updatedAt = Date()
        }
    }

    private static func ensureSampleReview(
        day: Date,
        title: String,
        weather: String,
        mood: String,
        content: String,
        existingReviews: [DailyReview],
        context: ModelContext
    ) {
        let dayKey = DayKey.key(for: day)
        guard !existingReviews.contains(where: {
            $0.dayKey == dayKey &&
                ($0.title.hasPrefix("샘플:") || $0.content.hasPrefix("샘플 회고:") || $0.content.hasPrefix("샘플 일기:"))
        }) else { return }

        context.insert(DailyReview(
            dayKey: dayKey,
            title: title,
            weather: weather,
            mood: mood,
            content: content,
            createdAt: day,
            updatedAt: day
        ))
    }

    private static func ensureRoutineTemplates(
        context: ModelContext,
        templates: [TaskTemplate]
    ) {
        ensureTemplate(
            named: "아침 루틴",
            items: [
                "메일 확인",
                "오늘 일정 훑기",
                "우선 작업 1개 정하기"
            ],
            existingTemplates: templates,
            context: context
        )

        ensureTemplate(
            named: "운동 루틴",
            items: [
                "스트레칭 10분",
                "근력 운동 30분",
                "유산소 20분",
                "운동 기록 남기기"
            ],
            existingTemplates: templates,
            context: context
        )

        ensureTemplate(
            named: "업무 정리 루틴",
            items: [
                "오늘 처리할 업무 나열",
                "진행 중 작업 상태 업데이트",
                "막힌 이슈 정리",
                "내일 첫 작업 정하기"
            ],
            existingTemplates: templates,
            context: context
        )

        ensureTemplate(
            named: "주간 회고 루틴",
            items: [
                "이번 주 완료 작업 확인",
                "다음 주 일정 훑기",
                "반복 작업 템플릿 보정"
            ],
            existingTemplates: templates,
            context: context
        )
    }

    private static func ensureTemplate(
        named name: String,
        items: [String],
        existingTemplates: [TaskTemplate],
        context: ModelContext
    ) {
        guard !existingTemplates.contains(where: { $0.name == name }) else { return }

        let template = TaskTemplate(name: name)
        context.insert(template)

        for (index, title) in items.enumerated() {
            context.insert(TaskTemplateItem(
                templateId: template.id,
                title: title,
                order: Double(index + 1) * 100
            ))
        }
    }
}
