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
    public let focusSessionID: UUID?
    public let focusPhaseRawValue: String?
    public let focusRunStateRawValue: String?
    public let focusDeadline: Date?
    public let focusRemainingSecondsAtPause: TimeInterval?
    public let focusPlannedSeconds: Int?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generatedAt: Date,
        dayKey: String,
        todoCount: Int,
        doingCount: Int,
        doneCount: Int,
        eventCount: Int,
        focusTitle: String? = nil,
        focusKind: LockScreenWidgetFocusKind? = nil,
        activeFocus: FocusActiveSessionSnapshot? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.dayKey = dayKey
        self.todoCount = max(0, todoCount)
        self.doingCount = max(0, doingCount)
        self.doneCount = max(0, doneCount)
        self.eventCount = max(0, eventCount)

        let validActiveFocus = activeFocus.flatMap {
            FocusTimerRules.isValid($0) ? $0 : nil
        }
        let activeTitle = validActiveFocus?.taskTitleSnapshot
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = activeTitle?.isEmpty == false
            ? activeTitle
            : focusTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKind = validActiveFocus == nil ? focusKind : .doingTask
        if let normalizedTitle, !normalizedTitle.isEmpty, let normalizedKind {
            self.focusTitle = normalizedTitle
            self.focusKind = normalizedKind
        } else {
            self.focusTitle = nil
            self.focusKind = nil
        }
        focusSessionID = validActiveFocus?.sessionID
        focusPhaseRawValue = validActiveFocus?.phaseRawValue
        focusRunStateRawValue = validActiveFocus?.runStateRawValue
        focusDeadline = validActiveFocus?.deadline
        focusRemainingSecondsAtPause = validActiveFocus?.remainingSecondsAtPause
        focusPlannedSeconds = validActiveFocus.map {
            $0.phase == .focus ? $0.plannedFocusSeconds : $0.plannedBreakSeconds
        }
    }

    public var remainingTaskCount: Int {
        todoCount + doingCount
    }

    public var totalTaskCount: Int {
        remainingTaskCount + doneCount
    }

    public var hasContent: Bool {
        hasActiveFocusTimer || totalTaskCount > 0 || eventCount > 0
    }

    public var hasActiveFocusTimer: Bool {
        focusSessionID != nil && focusPhase != nil && focusRunState != nil
    }

    public var focusPhase: FocusTimerPhase? {
        focusPhaseRawValue.flatMap(FocusTimerPhase.init(rawValue:))
    }

    public var focusRunState: FocusTimerRunState? {
        focusRunStateRawValue.flatMap(FocusTimerRunState.init(rawValue:))
    }

    public func focusRemainingSeconds(at date: Date) -> TimeInterval? {
        guard hasActiveFocusTimer, let planned = focusPlannedSeconds else { return nil }
        switch focusRunState {
        case .running:
            guard let focusDeadline else { return nil }
            return min(TimeInterval(planned), max(0, focusDeadline.timeIntervalSince(date)))
        case .paused:
            return min(
                TimeInterval(planned),
                max(0, focusRemainingSecondsAtPause ?? 0)
            )
        case nil:
            return nil
        }
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
            && focusSessionID == other.focusSessionID
            && focusPhaseRawValue == other.focusPhaseRawValue
            && focusRunStateRawValue == other.focusRunStateRawValue
            && focusDeadline == other.focusDeadline
            && focusRemainingSecondsAtPause == other.focusRemainingSecondsAtPause
            && focusPlannedSeconds == other.focusPlannedSeconds
    }

    @MainActor
    public static func make(
        tasks: [Task],
        events: [CalendarEvent],
        referenceDate: Date = Date(),
        activeFocus: FocusActiveSessionSnapshot? = nil
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
            focusKind: summary?.focusKind,
            activeFocus: activeFocus
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
