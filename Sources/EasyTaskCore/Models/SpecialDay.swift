import Foundation

public enum SpecialDayType: String, Codable {
    case holiday
    case anniversary
    case seasonal
    case miscellaneous
}

public struct SpecialDay: Codable, Identifiable, Equatable {
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
            ?? packageResourceURL()

        guard let url,
              let data = try? Data(contentsOf: url),
              let days = try? JSONDecoder().decode([SpecialDay].self, from: data) else {
            return SpecialDayStore(days: [])
        }

        return SpecialDayStore(days: days)
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

    private static func packageResourceURL() -> URL? {
        #if SWIFT_PACKAGE
        Bundle.module.url(forResource: "SpecialDays.kr", withExtension: "json")
        #else
        nil
        #endif
    }
}
