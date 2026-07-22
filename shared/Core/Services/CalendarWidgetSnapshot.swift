import Foundation

public enum CalendarWidgetConstants {
    public static let appGroupIdentifier = PlanBaseCompatibility.applicationGroupIdentifier
    public static let snapshotFileName = "calendar-widget-v1.json"
    public static let kind = PlanBaseCompatibility.calendarWidgetKind
    public static let deepLinkScheme = "planbase"
    public static let supportedDeepLinkSchemes = [
        deepLinkScheme,
        PlanBaseCompatibility.legacyDeepLinkScheme
    ]
}

public struct CalendarWidgetEventSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let startDayKey: String
    public let endDayKey: String
    public let colorID: String

    public init(
        id: UUID,
        title: String,
        startDayKey: String,
        endDayKey: String,
        colorID: String
    ) {
        self.id = id
        self.title = title
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.colorID = colorID
    }
}

public struct CalendarWidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generatedAt: Date
    public let themeID: String?
    public let events: [CalendarWidgetEventSnapshot]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generatedAt: Date,
        themeID: String? = nil,
        events: [CalendarWidgetEventSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.themeID = themeID
        self.events = events
    }

    @MainActor
    public static func make(
        events: [CalendarEvent],
        referenceDate: Date = Date(),
        themeID: String = AppThemePreset.defaultID,
        maximumEventCount: Int = 256
    ) -> CalendarWidgetSnapshot {
        let monthStart = DayKey.startOfMonth(for: referenceDate)
        let rangeStartKey = DayKey.key(for: DayKey.addingMonths(-1, to: monthStart))
        let rangeEnd = DayKey.addingDays(-1, to: DayKey.addingMonths(3, to: monthStart))
        let rangeEndKey = DayKey.key(for: rangeEnd)

        let snapshots = events
            .filter { event in
                event.supersededAt == nil
                    && !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && DayKey.date(from: event.startDayKey) != nil
                    && DayKey.date(from: event.endDayKey) != nil
                    && event.startDayKey <= rangeEndKey
                    && event.endDayKey >= rangeStartKey
            }
            .sorted { lhs, rhs in
                if lhs.startDayKey != rhs.startDayKey {
                    return lhs.startDayKey < rhs.startDayKey
                }
                if lhs.endDayKey != rhs.endDayKey {
                    return lhs.endDayKey > rhs.endDayKey
                }
                if lhs.title != rhs.title {
                    return lhs.title < rhs.title
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(max(0, maximumEventCount))
            .map { event in
                CalendarWidgetEventSnapshot(
                    id: event.id,
                    title: event.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    startDayKey: event.startDayKey,
                    endDayKey: event.endDayKey,
                    colorID: CalendarEventColor(rawValue: event.color ?? "")?.rawValue
                        ?? CalendarEventPalette.defaultColor
                )
            }

        return CalendarWidgetSnapshot(
            generatedAt: referenceDate,
            themeID: AppThemePreset.preset(for: themeID).id,
            events: snapshots
        )
    }

    public func events(onDayKey dayKey: String) -> [CalendarWidgetEventSnapshot] {
        events.filter { $0.startDayKey <= dayKey && dayKey <= $0.endDayKey }
    }

    public func hasSameContent(as other: CalendarWidgetSnapshot) -> Bool {
        schemaVersion == other.schemaVersion
            && themeID == other.themeID
            && events == other.events
    }
}

public enum CalendarWidgetSnapshotStore {
    public enum StoreError: Error, Equatable {
        case appGroupContainerUnavailable
    }

    @discardableResult
    public static func writeIfChanged(
        _ snapshot: CalendarWidgetSnapshot,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let directoryURL = try resolvedDirectoryURL(
            directoryURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        if let existing = try read(directoryURL: directoryURL, fileManager: fileManager),
           existing.hasSameContent(as: snapshot) {
            return false
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(
            to: directoryURL.appendingPathComponent(CalendarWidgetConstants.snapshotFileName),
            options: .atomic
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
        return try decoder.decode(
            CalendarWidgetSnapshot.self,
            from: Data(contentsOf: fileURL)
        )
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
}
