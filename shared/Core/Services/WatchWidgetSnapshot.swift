import Foundation

public enum WatchWidgetConstants {
    public static let appGroupIdentifier = PlanBaseCompatibility.applicationGroupIdentifier
    public static let snapshotFileName = "watch-widget-v1.json"
    public static let kind = PlanBaseCompatibility.watchWidgetKind
}

public struct WatchWidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let dayKey: String
    public let todoCount: Int
    public let doingCount: Int
    public let doneCount: Int
    public let eventCount: Int
    public let focusTitle: String?
    public let focusKind: LockScreenWidgetFocusKind?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generatedAt: Date,
        dayKey: String,
        todoCount: Int,
        doingCount: Int,
        doneCount: Int,
        eventCount: Int,
        focusTitle: String? = nil,
        focusKind: LockScreenWidgetFocusKind? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.dayKey = dayKey
        self.todoCount = max(0, todoCount)
        self.doingCount = max(0, doingCount)
        self.doneCount = max(0, doneCount)
        self.eventCount = max(0, eventCount)

        let normalizedTitle = focusTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedTitle, !normalizedTitle.isEmpty, let focusKind {
            self.focusTitle = normalizedTitle
            self.focusKind = focusKind
        } else {
            self.focusTitle = nil
            self.focusKind = nil
        }
    }

    public var remainingTaskCount: Int {
        todoCount + doingCount
    }

    public var totalTaskCount: Int {
        remainingTaskCount + doneCount
    }

    public var hasContent: Bool {
        totalTaskCount > 0 || eventCount > 0
    }

    public func hasSameContent(as other: WatchWidgetSnapshot) -> Bool {
        schemaVersion == other.schemaVersion
            && dayKey == other.dayKey
            && todoCount == other.todoCount
            && doingCount == other.doingCount
            && doneCount == other.doneCount
            && eventCount == other.eventCount
            && focusTitle == other.focusTitle
            && focusKind == other.focusKind
    }

    @MainActor
    public static func make(
        tasks: [Task],
        events: [CalendarEvent],
        referenceDate: Date = Date()
    ) -> WatchWidgetSnapshot {
        let dayKey = DayKey.key(for: referenceDate)
        let summary = LockScreenWidgetRules.makeDaySummaries(
            tasks: tasks,
            events: events,
            referenceDate: referenceDate
        ).first

        return WatchWidgetSnapshot(
            generatedAt: referenceDate,
            dayKey: dayKey,
            todoCount: summary?.todoCount ?? 0,
            doingCount: summary?.doingCount ?? 0,
            doneCount: summary?.doneCount ?? 0,
            eventCount: summary?.eventCount ?? 0,
            focusTitle: summary?.focusTitle,
            focusKind: summary?.focusKind
        )
    }
}

public enum WatchWidgetSnapshotStore {
    public enum StoreError: Error, Equatable {
        case appGroupContainerUnavailable
        case unsupportedSchemaVersion(Int)
    }

    @discardableResult
    public static func writeIfChanged(
        _ snapshot: WatchWidgetSnapshot,
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

        var shouldRemoveUnreadablePayload = false
        do {
            if !forceWrite,
               let existing = try read(
                directoryURL: directoryURL,
                fileManager: fileManager
               ),
               existing.hasSameContent(as: snapshot) {
                return false
            }
        } catch StoreError.unsupportedSchemaVersion(let version) {
            throw StoreError.unsupportedSchemaVersion(version)
        } catch {
            shouldRemoveUnreadablePayload = true
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let fileURL = directoryURL.appendingPathComponent(
            WatchWidgetConstants.snapshotFileName
        )
        if shouldRemoveUnreadablePayload,
           fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        try data.write(to: fileURL, options: [.atomic])
        return true
    }

    public static func read(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> WatchWidgetSnapshot? {
        let directoryURL = try resolvedDirectoryURL(
            directoryURL,
            fileManager: fileManager
        )
        let fileURL = directoryURL.appendingPathComponent(
            WatchWidgetConstants.snapshotFileName
        )
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(SchemaEnvelope.self, from: data)
        guard envelope.schemaVersion <= WatchWidgetSnapshot.currentSchemaVersion else {
            throw StoreError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        return try decoder.decode(WatchWidgetSnapshot.self, from: data)
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
            forSecurityApplicationGroupIdentifier: WatchWidgetConstants.appGroupIdentifier
        ) else {
            throw StoreError.appGroupContainerUnavailable
        }
        return groupURL.appendingPathComponent("WatchWidget", isDirectory: true)
    }
}
