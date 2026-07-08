import Foundation

public enum CalendarEventTimeline {
    public static func badgeText(for event: CalendarEvent, today: Date = Date()) -> String {
        let currentDay = DayKey.startOfDay(for: today)
        let startDay = DayKey.startOfDay(for: min(event.startAt, event.endAt))
        let endDay = DayKey.startOfDay(for: max(event.startAt, event.endAt))

        if DayKey.calendar.compare(currentDay, to: startDay, toGranularity: .day) == .orderedAscending {
            return "시작 D-\(days(from: currentDay, to: startDay))"
        }

        if DayKey.calendar.compare(currentDay, to: endDay, toGranularity: .day) == .orderedDescending {
            return "종료됨"
        }

        if DayKey.calendar.isDate(startDay, inSameDayAs: endDay) {
            return "오늘"
        }

        let remainingDays = days(from: currentDay, to: endDay)
        return remainingDays == 0 ? "오늘 종료" : "종료 D-\(remainingDays)"
    }

    private static func days(from start: Date, to end: Date) -> Int {
        DayKey.calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
