import Foundation
import Observation

/// Owned by the app root so navigating to a board does not discard the archive session.
@MainActor
@Observable
public final class ArchiveScreenState {
    public var filter = ArchiveFilter(contentMode: .dailyActivity)
    public var querySession: ArchiveQuerySession?
    public var activitySession: ActivityOverviewSession?
    public var selectedActivityDayKey: String?
    public var expandedTaskDays: Set<String> = []
    public var expandedReviewDays: Set<String> = []
    public var scrollDayKey: String?

    public init() {}
}

public struct ArchiveDaySelection: Identifiable {
    public let date: Date
    public var id: String { DayKey.key(for: date) }

    public init(date: Date) { self.date = date }
}
