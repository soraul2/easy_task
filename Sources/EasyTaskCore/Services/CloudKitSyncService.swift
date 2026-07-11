import CoreData
import Foundation
import SwiftData

public enum CloudKitSyncEventKind: String, Sendable {
    case setup
    case `import`
    case export
    case unknown
}

public struct CloudKitSyncEventSummary: Equatable, Sendable {
    public let kind: CloudKitSyncEventKind
    public let isCompleted: Bool
    public let succeeded: Bool
    public let errorDescription: String?

    public init(
        kind: CloudKitSyncEventKind,
        isCompleted: Bool,
        succeeded: Bool,
        errorDescription: String? = nil
    ) {
        self.kind = kind
        self.isCompleted = isCompleted
        self.succeeded = succeeded
        self.errorDescription = errorDescription
    }
}

public enum CloudKitSyncService {
    public static var eventChangedNotification: Notification.Name {
        NSPersistentCloudKitContainer.eventChangedNotification
    }

    public static func summary(from notification: Notification) -> CloudKitSyncEventSummary? {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else {
            return nil
        }

        return CloudKitSyncEventSummary(
            kind: kind(for: event.type),
            isCompleted: event.endDate != nil,
            succeeded: event.succeeded,
            errorDescription: event.error?.localizedDescription
        )
    }

    public static func shouldReconcile(after summary: CloudKitSyncEventSummary) -> Bool {
        summary.kind == .import && summary.isCompleted && summary.succeeded
    }

    @MainActor
    @discardableResult
    public static func handle(
        _ notification: Notification,
        context: ModelContext
    ) throws -> CloudKitSyncEventSummary? {
        guard let summary = summary(from: notification) else { return nil }
        if shouldReconcile(after: summary) {
            _ = try DataIntegrityService.reconcile(context: context)
        }
        return summary
    }
}

private extension CloudKitSyncService {
    static func kind(
        for eventType: NSPersistentCloudKitContainer.EventType
    ) -> CloudKitSyncEventKind {
        switch eventType {
        case .setup:
            .setup
        case .import:
            .import
        case .export:
            .export
        @unknown default:
            .unknown
        }
    }
}
