import Foundation

public enum CalendarWidgetConstants {
    public static let appGroupIdentifier = PlanBaseCompatibility.applicationGroupIdentifier
    public static let snapshotFileName = "calendar-widget-v1.json"
    public static let kind = PlanBaseCompatibility.calendarWidgetKind
    public static let lockScreenKind = PlanBaseCompatibility.lockScreenWidgetKind
    public static let deepLinkScheme = "planbase"
    public static let supportedDeepLinkSchemes = [
        deepLinkScheme,
        PlanBaseCompatibility.legacyDeepLinkScheme
    ]
}

public struct CalendarWidgetEventSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let renderID: UUID
    public let title: String
    public let startDayKey: String
    public let endDayKey: String
    public let colorID: String

    public init(
        id: UUID,
        renderID: UUID? = nil,
        title: String,
        startDayKey: String,
        endDayKey: String,
        colorID: String
    ) {
        self.id = id
        self.renderID = renderID ?? id
        self.title = title
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.colorID = colorID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case renderID
        case title
        case startDayKey
        case endDayKey
        case colorID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        renderID = try container.decodeIfPresent(UUID.self, forKey: .renderID) ?? id
        title = try container.decode(String.self, forKey: .title)
        startDayKey = try container.decode(String.self, forKey: .startDayKey)
        endDayKey = try container.decode(String.self, forKey: .endDayKey)
        colorID = try container.decode(String.self, forKey: .colorID)
    }
}

public struct CalendarWidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let generatedAt: Date
    public let themeID: String?
    public let coveredStartDayKey: String
    public let coveredEndDayKey: String
    public let eventCountsByDayKey: [String: Int]
    public let events: [CalendarWidgetEventSnapshot]
    public let lockScreenCoveredStartDayKey: String?
    public let lockScreenCoveredEndDayKey: String?
    public let lockScreenDaySummaries: [LockScreenWidgetDaySummary]?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generatedAt: Date,
        themeID: String? = nil,
        coveredStartDayKey: String? = nil,
        coveredEndDayKey: String? = nil,
        eventCountsByDayKey: [String: Int]? = nil,
        events: [CalendarWidgetEventSnapshot],
        lockScreenCoveredStartDayKey: String? = nil,
        lockScreenCoveredEndDayKey: String? = nil,
        lockScreenDaySummaries: [LockScreenWidgetDaySummary]? = nil
    ) {
        let defaultCoverage = Self.defaultCoverage(for: generatedAt)
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.themeID = themeID
        self.coveredStartDayKey = coveredStartDayKey ?? defaultCoverage.startDayKey
        self.coveredEndDayKey = coveredEndDayKey ?? defaultCoverage.endDayKey
        self.eventCountsByDayKey = eventCountsByDayKey ?? Self.eventCounts(
            for: events,
            startDayKey: self.coveredStartDayKey,
            endDayKey: self.coveredEndDayKey
        )
        self.events = events
        self.lockScreenCoveredStartDayKey = lockScreenCoveredStartDayKey
        self.lockScreenCoveredEndDayKey = lockScreenCoveredEndDayKey
        self.lockScreenDaySummaries = lockScreenDaySummaries
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case themeID
        case coveredStartDayKey
        case coveredEndDayKey
        case eventCountsByDayKey
        case events
        case lockScreenCoveredStartDayKey
        case lockScreenCoveredEndDayKey
        case lockScreenDaySummaries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        let defaultCoverage = Self.defaultCoverage(for: generatedAt)
        let coveredStartDayKey = try container.decodeIfPresent(
            String.self,
            forKey: .coveredStartDayKey
        ) ?? defaultCoverage.startDayKey
        let coveredEndDayKey = try container.decodeIfPresent(
            String.self,
            forKey: .coveredEndDayKey
        ) ?? defaultCoverage.endDayKey
        let events = try container.decode(
            [CalendarWidgetEventSnapshot].self,
            forKey: .events
        )

        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.generatedAt = generatedAt
        self.themeID = try container.decodeIfPresent(String.self, forKey: .themeID)
        self.coveredStartDayKey = coveredStartDayKey
        self.coveredEndDayKey = coveredEndDayKey
        self.eventCountsByDayKey = try container.decodeIfPresent(
            [String: Int].self,
            forKey: .eventCountsByDayKey
        ) ?? Self.eventCounts(
            for: events,
            startDayKey: coveredStartDayKey,
            endDayKey: coveredEndDayKey
        )
        self.events = events
        self.lockScreenCoveredStartDayKey = try container.decodeIfPresent(
            String.self,
            forKey: .lockScreenCoveredStartDayKey
        )
        self.lockScreenCoveredEndDayKey = try container.decodeIfPresent(
            String.self,
            forKey: .lockScreenCoveredEndDayKey
        )
        self.lockScreenDaySummaries = try container.decodeIfPresent(
            [LockScreenWidgetDaySummary].self,
            forKey: .lockScreenDaySummaries
        )
    }

    @MainActor
    public static func make(
        events: [CalendarEvent],
        tasks: [Task]? = nil,
        referenceDate: Date = Date(),
        themeID: String = AppThemePreset.defaultID,
        maximumEventCount: Int = 256
    ) -> CalendarWidgetSnapshot {
        let monthStart = DayKey.startOfMonth(for: referenceDate)
        let rangeStartKey = DayKey.key(for: DayKey.addingMonths(-1, to: monthStart))
        let rangeEnd = DayKey.addingDays(-1, to: DayKey.addingMonths(3, to: monthStart))
        let rangeEndKey = DayKey.key(for: rangeEnd)

        let representatives = representativeEvents(
            from: events
            .filter { event in
                event.supersededAt == nil
                    && !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && DayKey.date(from: event.startDayKey) != nil
                    && DayKey.date(from: event.endDayKey) != nil
                    && event.startDayKey <= rangeEndKey
                    && event.endDayKey >= rangeStartKey
            }
        )
        let allSnapshots = representatives
            .map { snapshot(for: $0) }
            .sorted(by: snapshotSort)
        let currentGridKeys = DayKey.adaptiveMonthGridDates(for: monthStart)
            .map(DayKey.key(for:))
        let nextMonth = DayKey.addingMonths(1, to: monthStart)
        let nextGridKeys = DayKey.adaptiveMonthGridDates(for: nextMonth)
            .map(DayKey.key(for:))
        let snapshots = prioritizedSnapshots(
            allSnapshots,
            currentGridKeys: currentGridKeys,
            nextGridKeys: nextGridKeys,
            maximumEventCount: maximumEventCount
        )
        let counts = eventCounts(
            for: allSnapshots,
            startDayKey: rangeStartKey,
            endDayKey: rangeEndKey
        )
        let lockScreenCoverage = tasks.map { _ in
            LockScreenWidgetRules.coverageDayKeys(for: referenceDate)
        }
        let lockScreenDaySummaries = tasks.map {
            LockScreenWidgetRules.makeDaySummaries(
                tasks: $0,
                events: events,
                referenceDate: referenceDate
            )
        }

        return CalendarWidgetSnapshot(
            generatedAt: referenceDate,
            themeID: AppThemePreset.preset(for: themeID).id,
            coveredStartDayKey: rangeStartKey,
            coveredEndDayKey: rangeEndKey,
            eventCountsByDayKey: counts,
            events: snapshots,
            lockScreenCoveredStartDayKey: lockScreenCoverage?.startDayKey,
            lockScreenCoveredEndDayKey: lockScreenCoverage?.endDayKey,
            lockScreenDaySummaries: lockScreenDaySummaries
        )
    }

    public func events(onDayKey dayKey: String) -> [CalendarWidgetEventSnapshot] {
        events.filter { $0.startDayKey <= dayKey && dayKey <= $0.endDayKey }
    }

    public func totalEventCount(onDayKey dayKey: String) -> Int {
        max(eventCountsByDayKey[dayKey] ?? 0, events(onDayKey: dayKey).count)
    }

    public func covers(dayKey: String) -> Bool {
        coveredStartDayKey <= dayKey && dayKey <= coveredEndDayKey
    }

    public func lockScreenSummary(onDayKey dayKey: String) -> LockScreenWidgetDaySummary? {
        guard let lockScreenCoveredStartDayKey,
              let lockScreenCoveredEndDayKey,
              lockScreenCoveredStartDayKey <= dayKey,
              dayKey <= lockScreenCoveredEndDayKey else {
            return nil
        }
        return lockScreenDaySummaries?.first { $0.dayKey == dayKey }
    }

    public func hasLockScreenCoverage(dayKey: String) -> Bool {
        lockScreenSummary(onDayKey: dayKey) != nil
    }

    public func lockScreenTimelineEntryDates(startingAt date: Date) -> [Date] {
        let todayKey = DayKey.key(for: date)
        guard hasLockScreenCoverage(dayKey: todayKey),
              let lockScreenCoveredStartDayKey,
              let lockScreenCoveredEndDayKey,
              let lockScreenDaySummaries else {
            return [date]
        }
        let futureDates = lockScreenDaySummaries.compactMap { summary -> Date? in
            guard summary.dayKey > todayKey,
                  summary.dayKey >= lockScreenCoveredStartDayKey,
                  summary.dayKey <= lockScreenCoveredEndDayKey,
                  let futureDate = DayKey.date(from: summary.dayKey),
                  futureDate > date else {
                return nil
            }
            return futureDate
        }
        return [date] + Array(Set(futureDates)).sorted()
    }

    public static func lockScreenTimelineRefreshDate(after lastEntryDate: Date) -> Date {
        DayKey.addingDays(1, to: DayKey.startOfDay(for: lastEntryDate))
    }

    public static func coverageDayKeys(for referenceDate: Date) -> (
        startDayKey: String,
        endDayKey: String
    ) {
        defaultCoverage(for: referenceDate)
    }

    public func hasSameContent(as other: CalendarWidgetSnapshot) -> Bool {
        schemaVersion == other.schemaVersion
            && themeID == other.themeID
            && coveredStartDayKey == other.coveredStartDayKey
            && coveredEndDayKey == other.coveredEndDayKey
            && eventCountsByDayKey == other.eventCountsByDayKey
            && events == other.events
            && lockScreenCoveredStartDayKey == other.lockScreenCoveredStartDayKey
            && lockScreenCoveredEndDayKey == other.lockScreenCoveredEndDayKey
            && lockScreenDaySummaries == other.lockScreenDaySummaries
    }

    private static func representativeEvents(
        from events: [CalendarEvent]
    ) -> [CalendarEvent] {
        Dictionary(grouping: events, by: \.id).values.compactMap { candidates in
            candidates.max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.instanceID.uuidString < rhs.instanceID.uuidString
            }
        }
    }

    private static func snapshot(for event: CalendarEvent) -> CalendarWidgetEventSnapshot {
        CalendarWidgetEventSnapshot(
            id: event.id,
            renderID: event.instanceID,
            title: event.title.trimmingCharacters(in: .whitespacesAndNewlines),
            startDayKey: event.startDayKey,
            endDayKey: event.endDayKey,
            colorID: CalendarEventColor(rawValue: event.color ?? "")?.rawValue
                ?? CalendarEventPalette.defaultColor
        )
    }

    private static func prioritizedSnapshots(
        _ snapshots: [CalendarWidgetEventSnapshot],
        currentGridKeys: [String],
        nextGridKeys: [String],
        maximumEventCount: Int
    ) -> [CalendarWidgetEventSnapshot] {
        let maximumEventCount = max(0, maximumEventCount)
        guard maximumEventCount > 0 else { return [] }

        var selectedRenderIDs: Set<UUID> = []
        var selected: [CalendarWidgetEventSnapshot] = []

        func append(_ snapshot: CalendarWidgetEventSnapshot) {
            guard selected.count < maximumEventCount,
                  selectedRenderIDs.insert(snapshot.renderID).inserted else {
                return
            }
            selected.append(snapshot)
        }

        for dayKey in currentGridKeys + nextGridKeys {
            for snapshot in snapshots
            where snapshot.startDayKey <= dayKey && dayKey <= snapshot.endDayKey {
                let alreadySelectedForDay = selected.lazy.filter {
                    $0.startDayKey <= dayKey && dayKey <= $0.endDayKey
                }.prefix(3).count
                guard alreadySelectedForDay < 3 else { break }
                append(snapshot)
            }
        }

        guard selected.count < maximumEventCount else {
            return selected.sorted(by: snapshotSort)
        }

        let currentStartKey = currentGridKeys.first ?? ""
        let currentEndKey = currentGridKeys.last ?? ""
        let prioritizedRemainder = snapshots.sorted { lhs, rhs in
            let lhsPriority = coveragePriority(
                lhs,
                currentStartKey: currentStartKey,
                currentEndKey: currentEndKey
            )
            let rhsPriority = coveragePriority(
                rhs,
                currentStartKey: currentStartKey,
                currentEndKey: currentEndKey
            )
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return snapshotSort(lhs, rhs)
        }
        for snapshot in prioritizedRemainder {
            append(snapshot)
            if selected.count == maximumEventCount { break }
        }
        return selected.sorted(by: snapshotSort)
    }

    private static func coveragePriority(
        _ snapshot: CalendarWidgetEventSnapshot,
        currentStartKey: String,
        currentEndKey: String
    ) -> Int {
        if snapshot.startDayKey <= currentEndKey && snapshot.endDayKey >= currentStartKey {
            return 0
        }
        if snapshot.startDayKey > currentEndKey {
            return 1
        }
        return 2
    }

    private static func snapshotSort(
        _ lhs: CalendarWidgetEventSnapshot,
        _ rhs: CalendarWidgetEventSnapshot
    ) -> Bool {
        if lhs.startDayKey != rhs.startDayKey {
            return lhs.startDayKey < rhs.startDayKey
        }
        if lhs.endDayKey != rhs.endDayKey {
            return lhs.endDayKey > rhs.endDayKey
        }
        if lhs.title != rhs.title {
            return lhs.title < rhs.title
        }
        if lhs.id != rhs.id {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.renderID.uuidString < rhs.renderID.uuidString
    }

    private static func defaultCoverage(for generatedAt: Date) -> (
        startDayKey: String,
        endDayKey: String
    ) {
        let monthStart = DayKey.startOfMonth(for: generatedAt)
        let startDayKey = DayKey.key(for: DayKey.addingMonths(-1, to: monthStart))
        let endDayKey = DayKey.key(
            for: DayKey.addingDays(-1, to: DayKey.addingMonths(3, to: monthStart))
        )
        return (startDayKey, endDayKey)
    }

    private static func eventCounts(
        for events: [CalendarWidgetEventSnapshot],
        startDayKey: String,
        endDayKey: String
    ) -> [String: Int] {
        guard let startDate = DayKey.date(from: startDayKey),
              let endDate = DayKey.date(from: endDayKey),
              startDayKey <= endDayKey else {
            return [:]
        }

        var counts: [String: Int] = [:]
        var date = startDate
        while date <= endDate {
            let dayKey = DayKey.key(for: date)
            let count = Set(events.lazy.filter {
                $0.startDayKey <= dayKey && dayKey <= $0.endDayKey
            }.map(\.id)).count
            if count > 0 {
                counts[dayKey] = count
            }
            date = DayKey.addingDays(1, to: date)
        }
        return counts
    }
}

public struct CalendarWidgetMonthSelection: Equatable, Sendable {
    public let month: Date
    public let canMoveBackward: Bool
    public let canMoveForward: Bool

    public init(
        month: Date,
        canMoveBackward: Bool,
        canMoveForward: Bool
    ) {
        self.month = month
        self.canMoveBackward = canMoveBackward
        self.canMoveForward = canMoveForward
    }
}

public enum CalendarWidgetMonthNavigation {
    public static func selection(
        selectedMonthDayKey: String?,
        snapshot: CalendarWidgetSnapshot,
        referenceDate: Date
    ) -> CalendarWidgetMonthSelection {
        let currentMonth = DayKey.startOfMonth(for: referenceDate)
        guard let firstCoveredDate = DayKey.date(from: snapshot.coveredStartDayKey),
              let lastCoveredDate = DayKey.date(from: snapshot.coveredEndDayKey) else {
            return CalendarWidgetMonthSelection(
                month: currentMonth,
                canMoveBackward: false,
                canMoveForward: false
            )
        }

        let firstMonth = DayKey.startOfMonth(for: firstCoveredDate)
        let lastMonth = DayKey.startOfMonth(for: lastCoveredDate)
        let firstMonthKey = DayKey.key(for: firstMonth)
        let lastMonthKey = DayKey.key(for: lastMonth)
        let fallbackMonthKey = DayKey.key(for: currentMonth)
        let fallbackMonth = firstMonthKey <= fallbackMonthKey
            && fallbackMonthKey <= lastMonthKey
            ? currentMonth
            : firstMonth
        let requestedMonth = selectedMonthDayKey
            .flatMap(DayKey.date(from:))
            .map(DayKey.startOfMonth(for:))
        let requestedMonthKey = requestedMonth.map(DayKey.key(for:))
        let month: Date
        if let requestedMonth,
           let requestedMonthKey,
           firstMonthKey <= requestedMonthKey,
           requestedMonthKey <= lastMonthKey {
            month = requestedMonth
        } else {
            month = fallbackMonth
        }
        let monthKey = DayKey.key(for: month)

        return CalendarWidgetMonthSelection(
            month: month,
            canMoveBackward: firstMonthKey < monthKey,
            canMoveForward: monthKey < lastMonthKey
        )
    }

    public static func moving(
        selectedMonthDayKey: String?,
        by monthDelta: Int,
        snapshot: CalendarWidgetSnapshot,
        referenceDate: Date
    ) -> CalendarWidgetMonthSelection {
        let currentSelection = selection(
            selectedMonthDayKey: selectedMonthDayKey,
            snapshot: snapshot,
            referenceDate: referenceDate
        )
        let step = monthDelta < 0 ? -1 : monthDelta > 0 ? 1 : 0
        guard step != 0,
              (step < 0
                  ? currentSelection.canMoveBackward
                  : currentSelection.canMoveForward) else {
            return currentSelection
        }
        let targetMonth = DayKey.addingMonths(step, to: currentSelection.month)
        return selection(
            selectedMonthDayKey: DayKey.key(for: targetMonth),
            snapshot: snapshot,
            referenceDate: referenceDate
        )
    }
}

public enum CalendarWidgetSnapshotStore {
    public enum StoreError: Error, Equatable {
        case appGroupContainerUnavailable
        case unsupportedSchemaVersion(Int)
    }

    public static var snapshotWritingOptions: Data.WritingOptions {
#if os(iOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
#else
        [.atomic]
#endif
    }

    @discardableResult
    public static func writeIfChanged(
        _ snapshot: CalendarWidgetSnapshot,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        forceWrite: Bool = false
    ) throws -> Bool {
        let directoryURL = try resolvedDirectoryURL(
            directoryURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        do {
            if let existing = try read(
                directoryURL: directoryURL,
                fileManager: fileManager
            ),
               !forceWrite,
               existing.hasSameContent(as: snapshot) {
                return false
            }
        } catch let error as StoreError {
            throw error
        } catch is DecodingError {
            // A malformed payload is recoverable because this writer owns the file.
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let fileURL = directoryURL.appendingPathComponent(
            CalendarWidgetConstants.snapshotFileName
        )
        try data.write(
            to: fileURL,
            options: snapshotWritingOptions
        )
        return true
    }

    public static func read(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> CalendarWidgetSnapshot? {
        let directoryURL = try resolvedDirectoryURL(
            directoryURL,
            fileManager: fileManager
        )
        let fileURL = directoryURL.appendingPathComponent(
            CalendarWidgetConstants.snapshotFileName
        )
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(SchemaEnvelope.self, from: data)
        guard envelope.schemaVersion <= CalendarWidgetSnapshot.currentSchemaVersion else {
            throw StoreError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        return try decoder.decode(
            CalendarWidgetSnapshot.self,
            from: data
        )
    }

    private struct SchemaEnvelope: Decodable {
        let schemaVersion: Int
    }

    private static func resolvedDirectoryURL(
        _ directoryURL: URL?,
        fileManager: FileManager
    ) throws -> URL {
        if let directoryURL {
            return directoryURL
        }
        guard let groupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: CalendarWidgetConstants.appGroupIdentifier
        ) else {
            throw StoreError.appGroupContainerUnavailable
        }
        return groupURL.appendingPathComponent("Widget", isDirectory: true)
    }
}

public enum PlanBaseBoardRoute: Equatable, Sendable {
    case today
    case day(String)

    public func resolvedDayKey(todayDayKey: String = DayKey.today) -> String {
        switch self {
        case .today:
            todayDayKey
        case .day(let dayKey):
            dayKey
        }
    }
}

public enum PlanBaseDeepLink {
    public static func calendarURL(dayKey: String) -> URL? {
        guard DayKey.date(from: dayKey) != nil else { return nil }
        var components = URLComponents()
        components.scheme = CalendarWidgetConstants.deepLinkScheme
        components.host = "calendar"
        components.queryItems = [URLQueryItem(name: "date", value: dayKey)]
        return components.url
    }

    public static func calendarDayKey(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              CalendarWidgetConstants.supportedDeepLinkSchemes.contains(scheme),
              url.host?.lowercased() == "calendar",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dayKey = components.queryItems?.first(where: { $0.name == "date" })?.value,
              DayKey.date(from: dayKey) != nil else {
            return nil
        }
        return dayKey
    }

    public static func boardTodayURL() -> URL? {
        var components = URLComponents()
        components.scheme = CalendarWidgetConstants.deepLinkScheme
        components.host = "board"
        components.queryItems = [URLQueryItem(name: "scope", value: "today")]
        return components.url
    }

    public static func boardURL(dayKey: String) -> URL? {
        guard DayKey.date(from: dayKey) != nil else { return nil }
        var components = URLComponents()
        components.scheme = CalendarWidgetConstants.deepLinkScheme
        components.host = "board"
        components.queryItems = [URLQueryItem(name: "date", value: dayKey)]
        return components.url
    }

    public static func boardRoute(from url: URL) -> PlanBaseBoardRoute? {
        guard let scheme = url.scheme?.lowercased(),
              CalendarWidgetConstants.supportedDeepLinkSchemes.contains(scheme),
              url.host?.lowercased() == "board",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let scopes = components.queryItems?.filter { $0.name == "scope" } ?? []
        let dates = components.queryItems?.filter { $0.name == "date" } ?? []
        guard scopes.count <= 1, dates.count <= 1 else { return nil }

        if let scope = scopes.first?.value {
            guard dates.isEmpty, scope == "today" else { return nil }
            return .today
        }
        if let dayKey = dates.first?.value {
            guard scopes.isEmpty, DayKey.date(from: dayKey) != nil else { return nil }
            return .day(dayKey)
        }
        return nil
    }
}
