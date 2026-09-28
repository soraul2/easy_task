import Foundation
import Observation
import SwiftData

/// A lightweight invalidation token. It keeps observing while a screen is hidden,
/// without fetching models or rebuilding a fingerprint of the store.
@MainActor
@Observable
public final class PersistenceViewRevision {
    public private(set) var value = 0
    @ObservationIgnored private var observers: [ViewNotificationObserver] = []
    @ObservationIgnored private let onChange: (@MainActor () -> Void)?

    public init(
        context: ModelContext,
        domains: PersistenceChangeDomains,
        onChange: (@MainActor () -> Void)? = nil
    ) {
        self.onChange = onChange
        observe(PersistenceCommandService.dataChangedNotification, object: context) { notification in
            PersistenceCommandService.affects(domains, in: notification)
        }
        // Covers direct saves/autosaves as well as command-based mutations.
        observe(ModelContext.didSave, object: context) { notification in
            Self.affects(domains, inSaveNotification: notification)
        }
        observe(CloudKitSyncService.eventChangedNotification) { notification in
            guard let event = CloudKitSyncService.summary(from: notification) else { return false }
            return event.kind == .import && event.isCompleted && event.succeeded
        }
        observe(.NSCalendarDayChanged)
        observe(.NSSystemTimeZoneDidChange)
    }

    private func observe(
        _ name: Notification.Name,
        object: AnyObject? = nil,
        accepts: @escaping @MainActor (Notification) -> Bool = { _ in true }
    ) {
        let token = NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) {
            [weak self] notification in
            // NotificationCenter delivers this observer on OperationQueue.main.
            // Notification itself is not Sendable; it never leaves this callback's thread.
            nonisolated(unsafe) let mainThreadNotification = notification
            MainActor.assumeIsolated {
                guard accepts(mainThreadNotification), let self else { return }
                self.value &+= 1
                self.onChange?()
            }
        }
        observers.append(ViewNotificationObserver(token))
    }

    public static func affects(_ domains: PersistenceChangeDomains, inSaveNotification notification: Notification) -> Bool {
        !savedDomains(in: notification).intersection(domains).isEmpty
    }

    private static func savedDomains(in notification: Notification) -> PersistenceChangeDomains {
        guard let info = notification.userInfo else { return .all }
        func value(_ key: ModelContext.NotificationKey) -> Any? {
            info[key] ?? info[key.rawValue]
        }
        if let invalidated = value(.invalidatedAllIdentifiers) {
            if let all = invalidated as? Bool {
                if all { return .all }
            } else {
                // Reset/invalidation payloads need a conservative refresh even
                // when a platform supplies identifiers instead of a Boolean.
                return .all
            }
        }
        var identifiers: [PersistentIdentifier] = []
        var hasMetadata = false
        for key in [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers] {
            if let ids = value(key) as? [PersistentIdentifier] {
                identifiers += ids
                hasMetadata = true
            } else if let ids = value(key) as? Set<PersistentIdentifier> {
                identifiers += ids
                hasMetadata = true
            }
        }
        guard hasMetadata else { return .all }
        var result: PersistenceChangeDomains = []
        for id in identifiers {
            switch id.entityName.split(separator: ".").last.map(String.init) {
            case "Task", "TaskChecklistItem", "TaskProgressEvent", "TaskCompletionActivity", "FocusSession", "TemplatePlacement":
                result.insert(.tasks)
            case "CalendarEvent": result.insert(.calendar)
            case "TaskTemplate", "TaskTemplateItem": result.insert(.templates)
            case "Memo", "MemoDrawing", "MemoChecklistItem": result.insert(.memos)
            case "DailyReview", "DiaryBlock", "DiaryAttachment": result.insert(.reviews)
            default: return .all
            }
        }
        return result
    }
}

private final class ViewNotificationObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
