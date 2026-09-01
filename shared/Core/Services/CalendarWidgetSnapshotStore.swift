import Foundation

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

        var shouldRemoveUnreadablePayload = false
        do {
            if let existing = try read(
                directoryURL: directoryURL,
                fileManager: fileManager
            ),
               !forceWrite,
               existing.hasSameContent(as: snapshot) {
                return false
            }
        } catch StoreError.unsupportedSchemaVersion(let version) {
            throw StoreError.unsupportedSchemaVersion(version)
        } catch {
            // Malformed or otherwise unreadable payloads are recoverable because
            // this writer owns the cache. App Group resolution already succeeded.
            shouldRemoveUnreadablePayload = true
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let fileURL = directoryURL.appendingPathComponent(
            CalendarWidgetConstants.snapshotFileName
        )
        if shouldRemoveUnreadablePayload,
           fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
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
