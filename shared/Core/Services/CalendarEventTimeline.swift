import Foundation

public enum CalendarEventTimeline {
    public static func dateRangeText(for event: CalendarEvent) -> String {
        dateRangeText(startAt: event.startAt, endAt: event.endAt)
    }

    public static func dateRangeText(startAt: Date, endAt: Date) -> String {
        let start = DayKey.startOfDay(for: min(startAt, endAt))
        let end = DayKey.startOfDay(for: max(startAt, endAt))
        let calendar = DayKey.calendar
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        let startMonth = calendar.component(.month, from: start)
        let endMonth = calendar.component(.month, from: end)
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)

        if start == end {
            return "\(startMonth)월 \(startDay)일"
        }
        if startYear == endYear, startMonth == endMonth {
            return "\(startMonth)월 \(startDay)일–\(endDay)일"
        }
        if startYear == endYear {
            return "\(startMonth)월 \(startDay)일–\(endMonth)월 \(endDay)일"
        }
        return "\(startYear)년 \(startMonth)월 \(startDay)일–\(endYear)년 \(endMonth)월 \(endDay)일"
    }

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
