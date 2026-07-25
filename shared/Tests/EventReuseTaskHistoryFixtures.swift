import Foundation
import Testing
@testable import EasyTaskCore

enum EventReuseTaskHistoryFixtures {
    static let thursdayKey = "2026-07-23"
    static let fridayKey = "2026-07-24"
    static let saturdayKey = "2026-07-25"

    static func thursdayPlannedSaturdayCompleted() throws -> Task {
        let thursday = try #require(DayKey.date(from: thursdayKey))
        let saturdayEvening = try #require(
            DayKey.calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 25,
                hour: 19
            ))
        )
        let task = Task(
            title: "목요일 계획·토요일 완료",
            plannedAt: thursday,
            order: 100
        )
        TaskRules.applyStatus(
            .done,
            to: task,
            now: saturdayEvening,
            completionDayKey: saturdayKey
        )
        return task
    }

    static func sameDayCompleted() throws -> Task {
        let saturday = try #require(DayKey.date(from: saturdayKey))
        let task = Task(
            title: "같은 날 계획·완료",
            plannedAt: saturday,
            order: 200
        )
        TaskRules.applyStatus(
            .done,
            to: task,
            now: saturday,
            completionDayKey: saturdayKey
        )
        return task
    }

    static func archivedOnlyLegacyTask() throws -> Task {
        let thursday = try #require(DayKey.date(from: thursdayKey))
        let saturday = try #require(DayKey.date(from: saturdayKey))
        let task = Task(
            title: "보관일만 남은 레거시 완료",
            status: .done,
            plannedAt: thursday,
            order: 300
        )
        task.completedAt = nil
        task.completedDayKey = nil
        task.archivedAt = saturday
        task.archivedDayKey = saturdayKey
        return task
    }

    static func completedAtOnlyLegacyTask() throws -> Task {
        let thursday = try #require(DayKey.date(from: thursdayKey))
        let completionTime = try #require(
            DayKey.calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 25,
                hour: 1,
                minute: 30
            ))
        )
        let task = Task(
            title: "완료 처리 시각만 남은 레거시 완료",
            status: .done,
            plannedAt: thursday,
            order: 400
        )
        task.completedAt = completionTime
        task.completedDayKey = nil
        task.archivedAt = nil
        task.archivedDayKey = nil
        return task
    }

    static func rescheduledToFriday() throws -> Task {
        let thursday = try #require(DayKey.date(from: thursdayKey))
        let friday = try #require(DayKey.date(from: fridayKey))
        let task = Task(
            title: "목요일에서 금요일로 재계획",
            plannedAt: thursday,
            order: 500
        )
        TaskRules.move(task, to: friday)
        return task
    }

    static func recentEvents() throws -> [CalendarEvent] {
        let olderStart = try #require(DayKey.date(from: "2026-06-01"))
        let newerStart = try #require(DayKey.date(from: "2026-07-20"))
        return [
            CalendarEvent(
                title: "공장",
                startAt: olderStart,
                endAt: DayKey.addingDays(1, to: olderStart),
                note: "이전 메모",
                color: CalendarEventColor.blue.rawValue,
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            CalendarEvent(
                title: "공장",
                startAt: newerStart,
                endAt: DayKey.addingDays(2, to: newerStart),
                note: "최근 메모",
                color: CalendarEventColor.red.rawValue,
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        ]
    }

    static func transientDuplicateEvents() throws -> [CalendarEvent] {
        let logicalID = UUID()
        let day = try #require(DayKey.date(from: "2026-07-20"))
        return [
            CalendarEvent(
                id: logicalID,
                instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                title: "공장 이전 중복",
                startAt: day,
                endAt: day,
                note: "이전",
                color: CalendarEventColor.blue.rawValue,
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            CalendarEvent(
                id: logicalID,
                instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                title: "공장 최신 중복",
                startAt: day,
                endAt: DayKey.addingDays(1, to: day),
                note: "최신",
                color: CalendarEventColor.red.rawValue,
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        ]
    }
}

@Test
func eventReuseTaskHistoryFixturesCaptureCurrentDataMeaning() throws {
    let delayed = try EventReuseTaskHistoryFixtures.thursdayPlannedSaturdayCompleted()
    let sameDay = try EventReuseTaskHistoryFixtures.sameDayCompleted()
    let archivedOnly = try EventReuseTaskHistoryFixtures.archivedOnlyLegacyTask()
    let completedAtOnly = try EventReuseTaskHistoryFixtures.completedAtOnlyLegacyTask()
    let rescheduled = try EventReuseTaskHistoryFixtures.rescheduledToFriday()
    let recentEvents = try EventReuseTaskHistoryFixtures.recentEvents()
    let duplicates = try EventReuseTaskHistoryFixtures.transientDuplicateEvents()

    #expect(delayed.plannedDayKey == EventReuseTaskHistoryFixtures.thursdayKey)
    #expect(delayed.completedDayKey == EventReuseTaskHistoryFixtures.saturdayKey)
    #expect(sameDay.plannedDayKey == sameDay.completedDayKey)
    #expect(archivedOnly.completedDayKey == nil)
    #expect(archivedOnly.archivedDayKey == EventReuseTaskHistoryFixtures.saturdayKey)
    #expect(completedAtOnly.completedDayKey == nil)
    #expect(completedAtOnly.completedAt != nil)
    #expect(rescheduled.plannedDayKey == EventReuseTaskHistoryFixtures.fridayKey)
    #expect(recentEvents.map(\.title) == ["공장", "공장"])
    #expect(Set(recentEvents.map(\.color)).count == 2)
    #expect(Set(recentEvents.map(\.note)).count == 2)
    #expect(duplicates.map(\.id).allSatisfy { $0 == duplicates[0].id })
    #expect(Set(duplicates.map(\.instanceID)).count == 2)
}
