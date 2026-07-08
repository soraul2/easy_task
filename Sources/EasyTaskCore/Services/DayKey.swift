import Foundation

public enum DayKey {
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = .current
        return calendar
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func key(for date: Date) -> String {
        formatter.string(from: date)
    }

    public static func date(from key: String) -> Date? {
        formatter.date(from: key).map(startOfDay(for:))
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
