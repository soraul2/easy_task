import Foundation
import Observation
import SwiftData

/// A receipt identifies an entry into the inbox, independently of CloudKit's physical rows.
@available(watchOS 11, *)
public struct CarryoverEntryKey: Codable, Hashable, Sendable {
    public var taskID: UUID
    public var plannedDayKey: String

    public init(taskID: UUID, plannedDayKey: String) {
        self.taskID = taskID
        self.plannedDayKey = plannedDayKey
    }

    @MainActor public init(_ task: Task) {
        self.init(taskID: task.id, plannedDayKey: task.plannedDayKey)
    }
}

@available(watchOS 11, *)
public struct CarryoverInboxReceipt: Codable, Equatable, Sendable {
    public var version = 1
    public var seen: Set<CarryoverEntryKey> = []
    public var announced: Set<CarryoverEntryKey> = []
    public var lastAnnouncementDayKey: String?

    public init(seen: Set<CarryoverEntryKey> = []) { self.seen = seen }
}

@available(watchOS 11, *)
public enum CarryoverInboxRules {
    @MainActor
    public static func tasks(from rows: [Task], todayKey: String) -> [Task] {
        let representatives = Dictionary(grouping: rows, by: \.id).values.compactMap {
            BoundedQueryService.representativeTask(from: $0)
        }
        return ordered(TaskRules.carryoverTasks(representatives, before: todayKey))
    }

    @MainActor
    static func ordered(_ tasks: [Task]) -> [Task] {
        tasks.sorted {
            if $0.plannedDayKey != $1.plannedDayKey { return $0.plannedDayKey < $1.plannedDayKey }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    @MainActor
    public static func fetch(in context: ModelContext, todayKey: String) throws -> [Task] {
        let candidates = try context.fetch(BoundedQueryService.carryoverTasksDescriptor(before: todayKey))
        return try currentTasks(withIDs: candidates.map(\.id), in: context, todayKey: todayKey)
    }

    @MainActor
    public static func currentTasks(
        withIDs taskIDs: [UUID], in context: ModelContext, todayKey: String = DayKey.today
    ) throws -> [Task] {
        let ids = Array(Set(taskIDs))
        var rows: [Task] = []
        // Include newer completed/moved representatives before deciding eligibility.
        for offset in stride(from: 0, to: ids.count, by: 128) {
            let batch = Array(ids[offset..<min(offset + 128, ids.count)])
            rows += try context.fetch(FetchDescriptor<Task>(predicate: #Predicate {
                $0.supersededAt == nil && batch.contains($0.id)
            }))
        }
        return tasks(from: rows, todayKey: todayKey)
    }
}

/// Preferences used by app previews and UI tests must never acknowledge production inbox entries.
@available(watchOS 11, *)
public enum PlanBaseLocalPreferences {
    public static var current: UserDefaults {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") {
            let prefix = "--ui-testing-memo-store="
            let identifier = arguments.first(where: { $0.hasPrefix(prefix) })
                .map { String($0.dropFirst(prefix.count)) } ?? "process-\(ProcessInfo.processInfo.processIdentifier)"
            return UserDefaults(suiteName: "PlanBaseLocalPreferences.UITests.\(identifier)")!
        }
#endif
        return .standard
    }
}

@MainActor
@Observable
@available(watchOS 11, *)
public final class CarryoverInboxSession {
    public private(set) var tasks: [Task] = []
    public private(set) var newKeys: Set<CarryoverEntryKey> = []
    public private(set) var presentedNewKeys: Set<CarryoverEntryKey> = []
    public private(set) var bannerKeys: Set<CarryoverEntryKey> = []
    public private(set) var todayKey = ""
    public private(set) var errorMessage: String?
    public private(set) var hasLoaded = false
    public private(set) var snapshotRevision = 0
    public private(set) var isPresenting = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let receiptKey = "PlanBaseCarryoverInboxReceipt.v1"
    @ObservationIgnored private let fetch: (String) throws -> [Task]
    @ObservationIgnored private let fetchChanged: (([UUID], String) throws -> [Task])?
    @ObservationIgnored private var receipt: CarryoverInboxReceipt?
    // Keep IDs separately: a committed deletion can detach the cached model,
    // and removing it must not read any of its persisted properties.
    @ObservationIgnored private var cachedTasksByID: [UUID: Task] = [:]
    @ObservationIgnored private var cachedLogicalIDByIdentifier: [PersistentIdentifier: UUID] = [:]
    @ObservationIgnored private var pendingTaskIDs: Set<UUID> = []
    @ObservationIgnored private var requiresFullRefresh = true
    @ObservationIgnored private var observers: [CarryoverNotificationObserver] = []

    public init(context: ModelContext, defaults: UserDefaults = PlanBaseLocalPreferences.current) {
        self.defaults = defaults
        fetch = { try CarryoverInboxRules.fetch(in: context, todayKey: $0) }
        fetchChanged = { try CarryoverInboxRules.currentTasks(withIDs: $0, in: context, todayKey: $1) }
        receipt = Self.readReceipt(defaults: defaults, key: receiptKey)
        observe(PersistenceCommandService.dataChangedNotification, object: context) { [weak self] notification in
            self?.recordChanges(PersistenceCommandService.changes(in: notification))
        }
        observe(ModelContext.didSave, object: context) { [weak self] notification in
            guard !PersistenceCommandService.isPerformingCommand(in: context),
                  PersistenceViewRevision.affects(.tasks, inSaveNotification: notification) else { return }
            self?.requestFullRefresh()
        }
        observe(CloudKitSyncService.eventChangedNotification) { [weak self] notification in
            guard let event = CloudKitSyncService.summary(from: notification),
                  event.kind == .import, event.isCompleted, event.succeeded else { return }
            self?.requestFullRefresh()
        }
        observe(.NSSystemTimeZoneDidChange) { [weak self] _ in self?.requestFullRefresh() }
    }

    init(defaults: UserDefaults, fetch: @escaping (String) throws -> [Task]) {
        self.defaults = defaults
        self.fetch = fetch
        fetchChanged = nil
        receipt = Self.readReceipt(defaults: defaults, key: receiptKey)
    }

    init(defaults: UserDefaults, fetchChanged: @escaping ([UUID], String) throws -> [Task],
         fetch: @escaping (String) throws -> [Task]) {
        self.defaults = defaults
        self.fetch = fetch
        self.fetchChanged = fetchChanged
        receipt = Self.readReceipt(defaults: defaults, key: receiptKey)
    }

    public var count: Int { tasks.count }
    public var newCount: Int { newKeys.count }
    public var displayedNewCount: Int {
        Set(tasks.map(CarryoverEntryKey.init)).intersection(presentedNewKeys).count
    }
    public var accessibilityLabel: String {
        if let errorMessage { return "이월함, \(errorMessage)" }
        guard hasLoaded else { return "이월함, 불러오는 중" }
        return "이월함, 전체 \(count)개, 새 작업 \(newCount)개"
    }
    public var displayedTasks: [Task] {
        tasks.filter { presentedNewKeys.contains(CarryoverEntryKey($0)) }
            + tasks.filter { !presentedNewKeys.contains(CarryoverEntryKey($0)) }
    }

    public func refresh(todayKey: String = DayKey.today) {
        do {
            let fetched = try fetch(todayKey)
            apply(fetched, todayKey: todayKey)
        } catch {
            requiresFullRefresh = true
            errorMessage = "이월함을 불러오지 못했어요. 다시 시도해 주세요."
        }
    }

    /// Local commands identify changed Task rows. Refresh those logical IDs,
    /// choosing current representatives again before deciding inbox eligibility.
    public func refreshPendingChanges(todayKey: String = DayKey.today) {
        guard hasLoaded, self.todayKey == todayKey, !requiresFullRefresh,
              errorMessage == nil, let fetchChanged else {
            refresh(todayKey: todayKey)
            return
        }
        guard !pendingTaskIDs.isEmpty else { return }
        do {
            let replacements = try fetchChanged(Array(pendingTaskIDs), todayKey)
            guard !replacements.isEmpty || pendingTaskIDs.contains(where: { cachedTasksByID[$0] != nil }) else {
                // A task added or removed outside the inbox does not require
                // rebuilding the existing rows, receipts, or presentation.
                pendingTaskIDs = []
                return
            }
            var merged = cachedTasksByID
            for id in pendingTaskIDs { merged.removeValue(forKey: id) }
            for task in replacements { merged[task.id] = task }
            // The cache and replacements already contain eligible canonical
            // rows; do not regroup and filter the entire inbox for one ID.
            apply(CarryoverInboxRules.ordered(Array(merged.values)), todayKey: todayKey)
        } catch {
            requiresFullRefresh = true
            errorMessage = "이월함을 불러오지 못했어요. 다시 시도해 주세요."
        }
    }

    public func requestFullRefresh() {
        requiresFullRefresh = true
        pendingTaskIDs = []
    }

    func recordChanges(_ changes: PersistenceChangeSummary) {
        guard changes.domains.contains(.tasks) else { return }
        guard let taskIDs = changes.taskIDs, let taskIdentifiers = changes.taskIdentifiers else {
            requestFullRefresh()
            return
        }
        guard !requiresFullRefresh else { return }
        pendingTaskIDs.formUnion(taskIDs)
        // Logical IDs are editable through the public command API. Resolve the
        // changed physical value identities against the last completed snapshot
        // instead of scanning live properties on every cached task.
        for identifier in taskIdentifiers {
            if let oldID = cachedLogicalIDByIdentifier[identifier] {
                pendingTaskIDs.insert(oldID)
            }
        }
        // Hidden tabs can accumulate arbitrarily many local edits. Fall back
        // to the full inbox query instead of retaining an unbounded ID list.
        if pendingTaskIDs.count > 256 { requestFullRefresh() }
    }

    private func apply(_ fetched: [Task], todayKey: String) {
        let keys = Set(fetched.map(CarryoverEntryKey.init))
        // Establish the baseline only after a successful fetch, including a genuine empty inbox.
        if receipt == nil {
            receipt = CarryoverInboxReceipt(seen: keys)
            saveReceipt()
        }
        if self.todayKey != todayKey { bannerKeys = [] }
        self.todayKey = todayKey
        tasks = fetched
        cachedTasksByID = [:]
        cachedLogicalIDByIdentifier = [:]
        for task in fetched {
            cachedTasksByID[task.id] = task
            cachedLogicalIDByIdentifier[task.persistentModelID] = task.id
        }
        pendingTaskIDs = []
        requiresFullRefresh = false
        hasLoaded = true
        errorMessage = nil
        newKeys = keys.subtracting(receipt!.seen)
        bannerKeys.formIntersection(newKeys)
        if isPresenting {
            presentedNewKeys.formUnion(newKeys)
            presentedNewKeys.formIntersection(keys)
        } else if receipt!.lastAnnouncementDayKey != todayKey {
            bannerKeys = newKeys.subtracting(receipt!.announced)
        }
        snapshotRevision += 1
    }

    private func observe(_ name: Notification.Name, object: AnyObject? = nil,
                         receive: @escaping @MainActor (Notification) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { notification in
            nonisolated(unsafe) let mainNotification = notification
            MainActor.assumeIsolated { receive(mainNotification) }
        }
        observers.append(CarryoverNotificationObserver(token))
    }

    /// Called by the successfully rendered sheet, never by its opening button.
    public func didDisplayInbox() {
        if !isPresenting {
            isPresenting = true
            presentedNewKeys = newKeys
        }
        guard hasLoaded, errorMessage == nil, receipt != nil else { return }
        presentedNewKeys.formUnion(newKeys)
        receipt!.seen.formUnion(tasks.map(CarryoverEntryKey.init))
        saveReceipt()
        newKeys = []
        bannerKeys = []
    }

    public func endPresentation() {
        isPresenting = false
        presentedNewKeys = []
    }

    public func didDisplayBanner() {
        guard !bannerKeys.isEmpty, receipt != nil else { return }
        receipt!.lastAnnouncementDayKey = todayKey
        receipt!.announced.formUnion(bannerKeys)
        saveReceipt()
    }

    public func dismissBanner() {
        didDisplayBanner()
        bannerKeys = []
    }

    private func saveReceipt() {
        if let receipt, let data = try? JSONEncoder().encode(receipt) {
            defaults.set(data, forKey: receiptKey)
        }
    }

    private static func readReceipt(defaults: UserDefaults, key: String) -> CarryoverInboxReceipt? {
        guard let data = defaults.data(forKey: key),
              let receipt = try? JSONDecoder().decode(CarryoverInboxReceipt.self, from: data),
              receipt.version == 1 else { return nil }
        return receipt
    }
}

private final class CarryoverNotificationObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
