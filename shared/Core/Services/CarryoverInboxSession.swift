import Foundation
import Observation
import SwiftData

/// A receipt identifies an entry into the inbox, independently of CloudKit's physical rows.
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

public struct CarryoverInboxReceipt: Codable, Equatable, Sendable {
    public var version = 1
    public var seen: Set<CarryoverEntryKey> = []
    public var announced: Set<CarryoverEntryKey> = []
    public var lastAnnouncementDayKey: String?

    public init(seen: Set<CarryoverEntryKey> = []) { self.seen = seen }
}

public enum CarryoverInboxRules {
    @MainActor
    public static func tasks(from rows: [Task], todayKey: String) -> [Task] {
        let representatives = Dictionary(grouping: rows, by: \.id).values.compactMap {
            BoundedQueryService.representativeTask(from: $0)
        }
        return TaskRules.carryoverTasks(representatives, before: todayKey).sorted {
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
    @ObservationIgnored private var receipt: CarryoverInboxReceipt?

    public init(context: ModelContext, defaults: UserDefaults = PlanBaseLocalPreferences.current) {
        self.defaults = defaults
        fetch = { try CarryoverInboxRules.fetch(in: context, todayKey: $0) }
        receipt = Self.readReceipt(defaults: defaults, key: receiptKey)
    }

    init(defaults: UserDefaults, fetch: @escaping (String) throws -> [Task]) {
        self.defaults = defaults
        self.fetch = fetch
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
            let keys = Set(fetched.map(CarryoverEntryKey.init))
            // Establish the baseline only after a successful fetch, including a genuine empty inbox.
            if receipt == nil {
                receipt = CarryoverInboxReceipt(seen: keys)
                saveReceipt()
            }
            if self.todayKey != todayKey { bannerKeys = [] }
            self.todayKey = todayKey
            tasks = fetched
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
        } catch {
            errorMessage = "이월함을 불러오지 못했어요. 다시 시도해 주세요."
        }
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
