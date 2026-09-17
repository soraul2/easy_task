import Foundation

public struct TaskLiveActivityLifetimeReceipt: Codable, Equatable, Sendable {
    public var activityID: String?
    public var startedAt: Date?
    public var dayKey: String
    public var suppressedDayKey: String?
    public var observedExpiration = false
}

/// ActivityKit does not report who dismissed a card. Only an observed lifetime expiry
/// is automatically recoverable; ambiguous disappearance respects the person's dismissal.
@MainActor
public final class TaskLiveActivityLifetimeStore {
    public static let maximumActivityAge: TimeInterval = 8 * 60 * 60
    private let defaults: UserDefaults
    private let key = "PlanBaseTaskLiveActivityLifetime.v1"

    public init(defaults: UserDefaults = PlanBaseLocalPreferences.current) { self.defaults = defaults }

    public var receipt: TaskLiveActivityLifetimeReceipt? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(TaskLiveActivityLifetimeReceipt.self, from: $0) }
    }

    public func recordStarted(id: String, dayKey: String, at date: Date) {
        save(TaskLiveActivityLifetimeReceipt(activityID: id, startedAt: date, dayKey: dayKey))
    }

    public func observeEnded(id: String, now: Date) {
        guard var value = receipt, value.activityID == id else { return }
        if let start = value.startedAt, now.timeIntervalSince(start) >= Self.maximumActivityAge {
            value.observedExpiration = true
        } else {
            value.suppressedDayKey = DayKey.key(for: now)
        }
        save(value)
    }

    public func observeDismissed(id: String, now: Date) {
        guard var value = receipt, value.activityID == id else { return }
        if !value.observedExpiration { value.suppressedDayKey = DayKey.key(for: now) }
        save(value)
    }

    /// Record the app's own ending before awaiting ActivityKit, so the observer cannot
    /// mistake completion, date rollover or duplicate cleanup for a user dismissal.
    public func recordAppEnding(id: String) {
        guard var value = receipt, value.activityID == id else { return }
        value.activityID = nil
        value.startedAt = nil
        save(value)
    }

    public func permitsStarting(dayKey: String, activityIsMissing: Bool, explicitStart: Bool = false) -> Bool {
        guard let value = receipt else { return true }
        if explicitStart { return true }
        if value.suppressedDayKey == dayKey { return false }
        if value.dayKey != dayKey { return true }
        if activityIsMissing, value.activityID != nil, !value.observedExpiration { return false }
        return true
    }

    private func save(_ receipt: TaskLiveActivityLifetimeReceipt) {
        if let data = try? JSONEncoder().encode(receipt) { defaults.set(data, forKey: key) }
    }
}
