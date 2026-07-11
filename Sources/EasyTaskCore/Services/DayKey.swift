import Foundation

public enum DayKey {
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = .current
        return calendar
    }

    public static func key(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        let calendar = calendar
        guard let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )) else {
            return nil
        }
        let normalized = calendar.startOfDay(for: date)
        return self.key(for: normalized) == key ? normalized : nil
    }

    public static var today: String {
        key(for: Date())
    }

    public static func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public static func addingMonths(_ months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    public static func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? startOfDay(for: date)
    }

    public static func monthGridDates(for date: Date) -> [Date] {
        let monthStart = startOfMonth(for: date)
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = weekday - calendar.firstWeekday
        let normalizedLeadingDays = leadingDays >= 0 ? leadingDays : leadingDays + 7
        let gridStart = addingDays(-normalizedLeadingDays, to: monthStart)
        return (0..<42).map { addingDays($0, to: gridStart) }
    }

    public static func isSameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, equalTo: rhs, toGranularity: .month)
    }

    public static func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    public static func display(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy.MM.dd E"
        return formatter.string(from: date)
    }

    public static func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: date)
    }

    public static func dayNumber(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    public static func weekdaySymbols() -> [String] {
        ["일", "월", "화", "수", "목", "금", "토"]
    }
}
