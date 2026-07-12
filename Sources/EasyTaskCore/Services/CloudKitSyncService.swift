import CloudKit
import CoreData
import Foundation
import Observation
import SwiftData

public enum CloudKitSyncEventKind: String, Sendable {
    case setup
    case `import`
    case export
    case unknown
}

public struct CloudKitSyncEventSummary: Equatable, Sendable {
    public let identifier: UUID
    public let kind: CloudKitSyncEventKind
    public let startedAt: Date?
    public let completedAt: Date?
    public let isCompleted: Bool
    public let succeeded: Bool
    public let errorDescription: String?

    public init(
        identifier: UUID = UUID(),
        kind: CloudKitSyncEventKind,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        isCompleted: Bool,
        succeeded: Bool,
        errorDescription: String? = nil
    ) {
        self.identifier = identifier
        self.kind = kind
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.isCompleted = isCompleted
        self.succeeded = succeeded
        self.errorDescription = errorDescription
    }
}

public enum CloudKitAccountAvailability: Equatable, Sendable {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case unavailable(String?)

    public var title: String {
        switch self {
        case .checking:
            "iCloud 확인 중"
        case .available:
            "iCloud 연결됨"
        case .noAccount:
            "iCloud 로그인 필요"
        case .restricted:
            "iCloud 사용 제한됨"
        case .temporarilyUnavailable:
            "iCloud 일시 사용 불가"
        case .unavailable:
            "iCloud 상태 확인 실패"
        }
    }

    public var systemImage: String {
        switch self {
        case .checking:
            "icloud"
        case .available:
            "icloud.fill"
        case .noAccount, .restricted, .temporarilyUnavailable, .unavailable:
            "exclamationmark.icloud"
        }
    }
}

@MainActor
@Observable
public final class CloudKitSyncMonitor {
    public private(set) var accountAvailability: CloudKitAccountAvailability = .checking
    public private(set) var isSyncing = false
    public private(set) var lastSuccessfulSyncAt: Date?
    public private(set) var lastEventKind: CloudKitSyncEventKind?
    public private(set) var syncErrorDescription: String?
    public private(set) var dataIssueDescription: String?

    private let containerIdentifier: String
    private var activeEventIDs: Set<UUID> = []
    private var eventErrorsByID: [UUID: String] = [:]
    private var eventErrorOrder: [UUID] = []
    private var accountStatusErrorDescription: String?

    public init(
        containerIdentifier: String = EasyTaskContainerFactory.cloudKitContainerIdentifier
    ) {
        self.containerIdentifier = containerIdentifier
    }

    public var title: String {
        if isSyncing { return "iCloud 동기화 중" }
        if lastErrorDescription != nil { return "iCloud 동기화 확인 필요" }
        return accountAvailability.title
    }

    public var lastErrorDescription: String? {
        dataIssueDescription ?? syncErrorDescription
    }

    public var systemImage: String {
        if isSyncing { return "arrow.triangle.2.circlepath.icloud" }
        if lastErrorDescription != nil { return "exclamationmark.icloud" }
        return accountAvailability.systemImage
    }

    public func refreshAccountStatus() async {
        accountAvailability = .checking
        do {
            let container = CKContainer(identifier: containerIdentifier)
            accountAvailability = Self.availability(for: try await container.accountStatus())
            accountStatusErrorDescription = nil
            refreshSyncErrorDescription()
        } catch {
            accountAvailability = .unavailable(error.localizedDescription)
            accountStatusErrorDescription = "iCloud 계정 상태 확인 실패: \(error.localizedDescription)"
            refreshSyncErrorDescription()
        }
    }

    public func record(
        _ summary: CloudKitSyncEventSummary,
        at date: Date = Date()
    ) {
        lastEventKind = summary.kind
        guard summary.isCompleted else {
            activeEventIDs.insert(summary.identifier)
            refreshSyncingState()
            return
        }

        activeEventIDs.remove(summary.identifier)
        if summary.succeeded {
            lastSuccessfulSyncAt = date
            eventErrorsByID.removeValue(forKey: summary.identifier)
            eventErrorOrder.removeAll { $0 == summary.identifier }
            if summary.kind == .import,
               dataIssueDescription?.hasPrefix("동기화 후") == true {
                dataIssueDescription = nil
            }
        } else {
            eventErrorsByID[summary.identifier] =
                summary.errorDescription ?? "알 수 없는 동기화 오류"
            eventErrorOrder.removeAll { $0 == summary.identifier }
            eventErrorOrder.append(summary.identifier)
        }
        refreshSyncingState()
        refreshSyncErrorDescription()
    }

    public func recordReconciliationFailure(_ error: any Error) {
        dataIssueDescription = "동기화 후 데이터 정리 실패: \(error.localizedDescription)"
    }

    public func recordStartupFailure(_ error: any Error) {
        dataIssueDescription = "데이터 점검 실패: \(error.localizedDescription)"
    }

    public func recordIssue(_ description: String) {
        dataIssueDescription = description
    }

    public func clearError() {
        accountStatusErrorDescription = nil
        eventErrorsByID = [:]
        eventErrorOrder = []
        refreshSyncErrorDescription()
        dataIssueDescription = nil
    }

    private func refreshSyncingState() {
        isSyncing = !activeEventIDs.isEmpty
    }

    private func refreshSyncErrorDescription() {
        let latestEventError = eventErrorOrder.reversed().lazy.compactMap {
            self.eventErrorsByID[$0]
        }.first
        syncErrorDescription = accountStatusErrorDescription ?? latestEventError
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
            identifier: event.identifier,
            kind: kind(for: event.type),
            startedAt: event.startDate,
            completedAt: event.endDate,
            isCompleted: event.endDate != nil,
            succeeded: event.succeeded,
            errorDescription: event.error?.localizedDescription
        )
    }

    public static func shouldReconcile(after summary: CloudKitSyncEventSummary) -> Bool {
        summary.kind == .import && summary.isCompleted && summary.succeeded
    }

    @MainActor
    public static func reconcileIfNeeded(
        after summary: CloudKitSyncEventSummary,
        context: ModelContext
    ) throws {
        guard shouldReconcile(after: summary) else { return }
        try PersistenceCommandService.perform(in: context) {
            _ = try DataIntegrityService.reconcile(
                context: context,
                saveChanges: false
            )
        }
    }

    @MainActor
    @discardableResult
    public static func handle(
        _ notification: Notification,
        context: ModelContext
    ) throws -> CloudKitSyncEventSummary? {
        guard let summary = summary(from: notification) else { return nil }
        try reconcileIfNeeded(after: summary, context: context)
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

private extension CloudKitSyncMonitor {
    static func availability(for status: CKAccountStatus) -> CloudKitAccountAvailability {
        switch status {
        case .available:
            .available
        case .noAccount:
            .noAccount
        case .restricted:
            .restricted
        case .temporarilyUnavailable:
            .temporarilyUnavailable
        case .couldNotDetermine:
            .unavailable(nil)
        @unknown default:
            .unavailable(nil)
        }
    }
}
