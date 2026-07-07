import Foundation

enum SpecialDayType: String, Codable {
    case holiday
    case anniversary
    case seasonal
    case miscellaneous
}

struct SpecialDay: Codable, Identifiable, Equatable {
    var id: String { "\(dateKey)-\(name)" }

    let dateKey: String
    let name: String
    let type: SpecialDayType
    let isPublicHoliday: Bool
}

struct SpecialDayStore {
    private let daysByDateKey: [String: [SpecialDay]]

    init(days: [SpecialDay]) {
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

    static func load(bundle: Bundle? = nil) -> SpecialDayStore {
        let url = bundle?.url(forResource: "SpecialDays.kr", withExtension: "json")
            ?? Bundle.main.url(forResource: "SpecialDays.kr", withExtension: "json")
            ?? Bundle.module.url(forResource: "SpecialDays.kr", withExtension: "json")

        guard let url,
              let data = try? Data(contentsOf: url),
              let days = try? JSONDecoder().decode([SpecialDay].self, from: data) else {
            return SpecialDayStore(days: [])
        }

        return SpecialDayStore(days: days)
    }

    func days(on date: Date) -> [SpecialDay] {
        daysByDateKey[DayKey.key(for: date), default: []]
    }

    func days(on dayKey: String) -> [SpecialDay] {
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
}
