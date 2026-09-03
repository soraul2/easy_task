import Foundation
import SwiftData

public struct FocusDaySummary: Equatable, Sendable {
    public var sessionCount: Int
    public var completedCount: Int
    public var focusedDurationSeconds: Int

    public init(
        sessionCount: Int = 0,
        completedCount: Int = 0,
        focusedDurationSeconds: Int = 0
    ) {
        self.sessionCount = sessionCount
        self.completedCount = completedCount
        self.focusedDurationSeconds = focusedDurationSeconds
    }
}

public enum FocusSessionQueryService {
    public static func dayDescriptor(
        dayKey: String
    ) -> FetchDescriptor<FocusSession> {
        let start = DayKey.date(from: dayKey) ?? .distantPast
        let end = DayKey.addingDays(1, to: start)
        return FetchDescriptor(
            predicate: #Predicate<FocusSession> { session in
                session.supersededAt == nil &&
                    session.endedAt >= start &&
                    session.endedAt < end
            },
            sortBy: [
                SortDescriptor(\FocusSession.endedAt, order: .reverse),
                SortDescriptor(\FocusSession.updatedAt, order: .reverse),
                SortDescriptor(\FocusSession.instanceID, order: .reverse)
            ]
        )
    }

    @MainActor
    public static func summary(
        dayKey: String = DayKey.today,
        in context: ModelContext
    ) throws -> FocusDaySummary {
        let rows = try context.fetch(dayDescriptor(dayKey: dayKey))
        let representatives = Dictionary(grouping: rows, by: \FocusSession.id)
            .values
            .compactMap { candidates in
                candidates.max { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt {
                        return lhs.updatedAt < rhs.updatedAt
                    }
                    return lhs.instanceID.uuidString < rhs.instanceID.uuidString
                }
            }

        return FocusDaySummary(
            sessionCount: representatives.count,
            completedCount: representatives.reduce(into: 0) { result, session in
                if session.outcomeRawValue == FocusSessionOutcome.completed.rawValue {
                    result += 1
                }
            },
            focusedDurationSeconds: representatives.reduce(into: 0) { result, session in
                result += max(0, session.focusedDurationSeconds)
            }
        )
    }
}
