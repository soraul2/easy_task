import Foundation

public enum FocusModeConstants {
    public static let appGroupIdentifier = PlanBaseCompatibility.applicationGroupIdentifier
    public static let directoryName = "Focus"
    public static let activeSnapshotFileName = "focus-active-v1.json"
}

public enum FocusActiveSessionStoreError: LocalizedError, Equatable {
    case appGroupContainerUnavailable
    case unsupportedFormatVersion(Int)
    case invalidSnapshot

    public var errorDescription: String? {
        switch self {
        case .appGroupContainerUnavailable:
            "집중 타이머 공유 저장소를 열 수 없습니다. 앱 권한을 확인해 주세요."
        case .unsupportedFormatVersion(let version):
            "이 앱에서 지원하지 않는 집중 타이머 형식입니다. version=\(version)"
        case .invalidSnapshot:
            "저장된 집중 타이머 상태가 손상되었습니다."
        }
    }
}

public enum FocusActiveSessionStore {
    public static let didChangeNotification = Notification.Name(
        "PlanBaseFocusActiveSessionChanged"
    )

    public static var snapshotWritingOptions: Data.WritingOptions {
#if os(iOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
#else
        [.atomic]
#endif
    }

    public static func read(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> FocusActiveSessionSnapshot? {
        let directoryURL = try resolvedDirectoryURL(directoryURL, fileManager: fileManager)
        let fileURL = directoryURL.appendingPathComponent(
            FocusModeConstants.activeSnapshotFileName
        )
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(FormatEnvelope.self, from: data)
        guard envelope.formatVersion <= FocusActiveSessionSnapshot.currentFormatVersion else {
            throw FocusActiveSessionStoreError.unsupportedFormatVersion(
                envelope.formatVersion
            )
        }
        let snapshot = try decoder.decode(FocusActiveSessionSnapshot.self, from: data)
        guard FocusTimerRules.isValid(snapshot) else {
            throw FocusActiveSessionStoreError.invalidSnapshot
        }
        return snapshot
    }

    public static func write(
        _ snapshot: FocusActiveSessionSnapshot,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        guard FocusTimerRules.isValid(snapshot) else {
            throw FocusActiveSessionStoreError.invalidSnapshot
        }
        let directoryURL = try resolvedDirectoryURL(directoryURL, fileManager: fileManager)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(
            to: directoryURL.appendingPathComponent(
                FocusModeConstants.activeSnapshotFileName
            ),
            options: snapshotWritingOptions
        )
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    public static func clear(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let directoryURL = try resolvedDirectoryURL(directoryURL, fileManager: fileManager)
        let fileURL = directoryURL.appendingPathComponent(
            FocusModeConstants.activeSnapshotFileName
        )
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

private extension FocusActiveSessionStore {
    struct FormatEnvelope: Decodable {
        let formatVersion: Int
    }

    static func resolvedDirectoryURL(
        _ directoryURL: URL?,
        fileManager: FileManager
    ) throws -> URL {
        if let directoryURL { return directoryURL }
        guard let groupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: FocusModeConstants.appGroupIdentifier
        ) else {
            throw FocusActiveSessionStoreError.appGroupContainerUnavailable
        }
        return groupURL.appendingPathComponent(
            FocusModeConstants.directoryName,
            isDirectory: true
        )
    }
}
