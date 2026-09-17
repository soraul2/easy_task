import Foundation
import Testing
@testable import EasyTaskCore

@Test @MainActor
func taskLiveActivityLifetimeExpiryUsesCardCreationNotTaskElapsedTime() throws {
    let suite = "LiveLifetimeTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TaskLiveActivityLifetimeStore(defaults: defaults)
    let now = try #require(DayKey.date(from: "2026-09-17"))
    store.recordStarted(id: "card", dayKey: "2026-09-17", at: now)
    store.observeEnded(id: "card", now: now.addingTimeInterval(8 * 3600))
    #expect(store.receipt?.observedExpiration == true)
    store.observeDismissed(id: "card", now: now.addingTimeInterval(12 * 3600))
    #expect(store.permitsStarting(dayKey: "2026-09-17", activityIsMissing: true))
}

@Test @MainActor
func taskLiveActivityLifetimeDismissalStaysSuppressedAcrossRelaunchAndCanBeExplicitlyRestarted() throws {
    let suite = "LiveLifetimeTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TaskLiveActivityLifetimeStore(defaults: defaults)
    let now = try #require(DayKey.date(from: "2026-09-17"))
    store.recordStarted(id: "card", dayKey: "2026-09-17", at: now)
    store.observeDismissed(id: "card", now: now.addingTimeInterval(60))
    let reopened = TaskLiveActivityLifetimeStore(defaults: defaults)
    #expect(!reopened.permitsStarting(dayKey: "2026-09-17", activityIsMissing: true))
    // Passing the eight-hour point does not turn an observed dismissal into an expiry.
    reopened.observeEnded(id: "card", now: now.addingTimeInterval(9 * 3600))
    #expect(!reopened.permitsStarting(dayKey: "2026-09-17", activityIsMissing: true))
    #expect(reopened.permitsStarting(dayKey: "2026-09-17", activityIsMissing: true, explicitStart: true))
    #expect(reopened.permitsStarting(dayKey: "2026-09-18", activityIsMissing: true))
    reopened.recordStarted(id: "new", dayKey: "2026-09-17", at: now.addingTimeInterval(10 * 3600))
    #expect(reopened.receipt?.suppressedDayKey == nil)
}

@Test @MainActor
func taskLiveActivityLifetimeAppCompletionAndRequestFailureRemainRetryable() throws {
    let suite = "LiveLifetimeTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TaskLiveActivityLifetimeStore(defaults: defaults)
    let now = try #require(DayKey.date(from: "2026-09-17"))
    #expect(store.permitsStarting(dayKey: "2026-09-17", activityIsMissing: true))
    // A failed Activity.request does not write a receipt.
    #expect(store.permitsStarting(dayKey: "2026-09-17", activityIsMissing: true))
    store.recordStarted(id: "card", dayKey: "2026-09-17", at: now)
    store.recordAppEnding(id: "card")
    store.observeDismissed(id: "card", now: now.addingTimeInterval(5))
    #expect(store.permitsStarting(dayKey: "2026-09-17", activityIsMissing: true))
}

@Test @MainActor
func taskLiveActivityLifetimeAmbiguousDisappearanceDoesNotRecreateADismissedCard() throws {
    let suite = "LiveLifetimeTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = TaskLiveActivityLifetimeStore(defaults: defaults)
    store.recordStarted(id: "unknown", dayKey: "2026-09-17", at: Date())
    #expect(!store.permitsStarting(dayKey: "2026-09-17", activityIsMissing: true))
    #expect(store.permitsStarting(dayKey: "2026-09-17", activityIsMissing: false))
}
