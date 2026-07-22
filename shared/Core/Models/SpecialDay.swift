import Foundation

public enum SpecialDayType: String, Codable, Sendable {
    case holiday
    case anniversary
    case seasonal
    case miscellaneous
}

public struct SpecialDay: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(dateKey)-\(name)" }

    public let dateKey: String
    public let name: String
    public let type: SpecialDayType
    public let isPublicHoliday: Bool
}

public struct SpecialDayStore {
    private let daysByDateKey: [String: [SpecialDay]]

    public init(days: [SpecialDay]) {
        daysByDateKey = Dictionary(grouping: days, by: \.dateKey)
            .mapValues { days in
                days.sorted { lhs, rhs in
                    if lhs.isPublicHoliday != rhs.isPublicHoliday {
                        return lhs.isPublicHoliday && !rhs.isPublicHoliday
                    }
                    if lhs.type != rhs.type {
                        return Self.priority(for: lhs.type) < Self.priority(for: rhs.type)
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
    }

    public static func load(bundle: Bundle? = nil) -> SpecialDayStore {
        let url = bundle?.url(forResource: "SpecialDays.kr", withExtension: "json")
            ?? Bundle.main.url(forResource: "SpecialDays.kr", withExtension: "json")

        if let url,
           let data = try? Data(contentsOf: url),
           let days = try? JSONDecoder().decode([SpecialDay].self, from: data) {
            return SpecialDayStore(days: days)
        }

        return SpecialDayStore(days: embeddedDays)
    }

    public func days(on date: Date) -> [SpecialDay] {
        daysByDateKey[DayKey.key(for: date), default: []]
    }

    public func days(on dayKey: String) -> [SpecialDay] {
        daysByDateKey[dayKey, default: []]
    }

    private static func priority(for type: SpecialDayType) -> Int {
        switch type {
        case .holiday: 0
        case .anniversary: 1
        case .seasonal: 2
        case .miscellaneous: 3
        }
    }

    private static let embeddedRows: [(
        dateKey: String,
        name: String,
        type: SpecialDayType,
        isPublicHoliday: Bool
    )] = [
        ("2026-01-01", "신정", .holiday, true),
        ("2026-02-16", "설날 연휴", .holiday, true),
        ("2026-02-17", "설날", .holiday, true),
        ("2026-02-18", "설날 연휴", .holiday, true),
        ("2026-03-01", "삼일절", .holiday, true),
        ("2026-03-02", "대체공휴일", .holiday, true),
        ("2026-04-05", "식목일", .anniversary, false),
        ("2026-04-11", "임시정부수립일", .anniversary, false),
        ("2026-05-01", "근로자의 날", .anniversary, false),
        ("2026-05-05", "어린이날", .holiday, true),
        ("2026-05-08", "어버이날", .anniversary, false),
        ("2026-05-15", "스승의 날", .anniversary, false),
        ("2026-05-24", "부처님오신날", .holiday, true),
        ("2026-05-25", "대체공휴일", .holiday, true),
        ("2026-06-03", "지방선거일", .holiday, true),
        ("2026-06-06", "현충일", .holiday, true),
        ("2026-06-25", "6·25전쟁일", .anniversary, false),
        ("2026-07-17", "제헌절", .anniversary, false),
        ("2026-08-15", "광복절", .holiday, true),
        ("2026-08-17", "대체공휴일", .holiday, true),
        ("2026-09-24", "추석 연휴", .holiday, true),
        ("2026-09-25", "추석", .holiday, true),
        ("2026-09-26", "추석 연휴", .holiday, true),
        ("2026-10-01", "국군의 날", .anniversary, false),
        ("2026-10-03", "개천절", .holiday, true),
        ("2026-10-05", "대체공휴일", .holiday, true),
        ("2026-10-09", "한글날", .holiday, true),
        ("2026-10-25", "독도의 날", .anniversary, false),
        ("2026-11-17", "순국선열의 날", .anniversary, false),
        ("2026-12-25", "성탄절", .holiday, true),
        ("2027-01-01", "신정", .holiday, true),
        ("2027-02-06", "설날 연휴", .holiday, true),
        ("2027-02-07", "설날", .holiday, true),
        ("2027-02-08", "설날 연휴", .holiday, true),
        ("2027-02-09", "대체공휴일", .holiday, true),
        ("2027-03-01", "삼일절", .holiday, true),
        ("2027-04-05", "식목일", .anniversary, false),
        ("2027-04-11", "임시정부수립일", .anniversary, false),
        ("2027-05-01", "근로자의 날", .anniversary, false),
        ("2027-05-05", "어린이날", .holiday, true),
        ("2027-05-08", "어버이날", .anniversary, false),
        ("2027-05-13", "부처님오신날", .holiday, true),
        ("2027-05-15", "스승의 날", .anniversary, false),
        ("2027-06-06", "현충일", .holiday, true),
        ("2027-06-25", "6·25전쟁일", .anniversary, false),
        ("2027-07-17", "제헌절", .anniversary, false),
        ("2027-08-15", "광복절", .holiday, true),
        ("2027-08-16", "대체공휴일", .holiday, true),
        ("2027-09-14", "추석 연휴", .holiday, true),
        ("2027-09-15", "추석", .holiday, true),
        ("2027-09-16", "추석 연휴", .holiday, true),
        ("2027-10-01", "국군의 날", .anniversary, false),
        ("2027-10-03", "개천절", .holiday, true),
        ("2027-10-04", "대체공휴일", .holiday, true),
        ("2027-10-09", "한글날", .holiday, true),
        ("2027-10-11", "대체공휴일", .holiday, true),
        ("2027-10-25", "독도의 날", .anniversary, false),
        ("2027-11-17", "순국선열의 날", .anniversary, false),
        ("2027-12-25", "성탄절", .holiday, true),
        ("2027-12-27", "대체공휴일", .holiday, true),
        ("2028-01-01", "신정", .holiday, true),
        ("2028-01-26", "설날 연휴", .holiday, true),
        ("2028-01-27", "설날", .holiday, true),
        ("2028-01-28", "설날 연휴", .holiday, true),
        ("2028-03-01", "삼일절", .holiday, true),
        ("2028-04-05", "식목일", .anniversary, false),
        ("2028-04-11", "임시정부수립일", .anniversary, false),
        ("2028-04-12", "국회의원 선거일", .holiday, true),
        ("2028-05-01", "근로자의 날", .anniversary, false),
        ("2028-05-02", "부처님오신날", .holiday, true),
        ("2028-05-05", "어린이날", .holiday, true),
        ("2028-05-08", "어버이날", .anniversary, false),
        ("2028-05-15", "스승의 날", .anniversary, false),
        ("2028-06-06", "현충일", .holiday, true),
        ("2028-06-25", "6·25전쟁일", .anniversary, false),
        ("2028-07-17", "제헌절", .anniversary, false),
        ("2028-08-15", "광복절", .holiday, true),
        ("2028-10-01", "국군의 날", .anniversary, false),
        ("2028-10-02", "추석 연휴", .holiday, true),
        ("2028-10-03", "개천절", .holiday, true),
        ("2028-10-03", "추석", .holiday, true),
        ("2028-10-04", "추석 연휴", .holiday, true),
        ("2028-10-05", "대체공휴일", .holiday, true),
        ("2028-10-09", "한글날", .holiday, true),
        ("2028-10-25", "독도의 날", .anniversary, false),
        ("2028-11-17", "순국선열의 날", .anniversary, false),
        ("2028-12-25", "성탄절", .holiday, true),
    ]

    private static let embeddedDays = embeddedRows.map { row in
        SpecialDay(
            dateKey: row.dateKey,
            name: row.name,
            type: row.type,
            isPublicHoliday: row.isPublicHoliday
        )
    }
}
