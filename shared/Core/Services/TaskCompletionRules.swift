import Foundation

/// A board completion normally records the action day. Backdating is an explicit
/// choice offered only for an unfinished task on its selected past planned day.
public enum TaskCompletionRules {
    public static func backdatedDayKey(
        selectedDayKey: String,
        plannedDayKey: String,
        status: TaskStatus,
        todayKey: String = DayKey.today
    ) -> String? {
        guard status != .done,
              selectedDayKey == plannedDayKey,
              selectedDayKey < todayKey,
              DayKey.date(from: selectedDayKey) != nil else { return nil }
        return selectedDayKey
    }

    public static func defaultActionTitle(
        selectedDayKey: String,
        todayKey: String = DayKey.today
    ) -> String {
        selectedDayKey < todayKey ? "오늘 완료" : "완료"
    }

    public static func backdatedActionTitle(
        dayKey: String,
        todayKey: String = DayKey.today
    ) -> String {
        "\(dateTitle(dayKey, todayKey: todayKey)) 완료로 기록"
    }

    public static func completionNotice(
        dayKey: String,
        todayKey: String = DayKey.today
    ) -> String {
        "\(dateTitle(dayKey, todayKey: todayKey)) 완료로 기록했어요"
    }

    private static func dateTitle(_ dayKey: String, todayKey: String) -> String {
        guard let date = DayKey.date(from: dayKey) else { return dayKey }
        let components = DayKey.calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return dayKey
        }
        let yearPrefix = dayKey.prefix(4) == todayKey.prefix(4) ? "" : "\(year)년 "
        return "\(yearPrefix)\(month)월 \(day)일"
    }
}
