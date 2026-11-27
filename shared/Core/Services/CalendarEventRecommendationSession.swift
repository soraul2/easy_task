import Foundation
import Observation
import SwiftData

@available(watchOS 11, *)
public enum CalendarEventRecommendationState: Equatable, Sendable {
    case idle, loading, results, empty, failed, dismissed, applied
}

@MainActor
@Observable
@available(watchOS 11, *)
public final class CalendarEventRecommendationSession {
    public private(set) var recommendations: [CalendarEventRecommendation] = []
    /// Layout-only previous values while searching. They can never be applied.
    public private(set) var loadingRecommendations: [CalendarEventRecommendation] = []
    public private(set) var state: CalendarEventRecommendationState = .idle
    public private(set) var selectedID: UUID?
    public private(set) var lastApplication: CalendarEventRecommendationApplication?
    public private(set) var notice: String?

    public var isLoading: Bool { state == .loading }
    public var isPresented: Bool {
        switch state {
        case .loading, .results, .empty, .failed: true
        default: false
        }
    }
    public var feedback: String? { lastApplication?.feedback ?? notice }
    public var selectedRecommendation: CalendarEventRecommendation? {
        recommendations.first { $0.id == selectedID }
    }

    @ObservationIgnored private let fetchEvents: @MainActor () async throws -> [CalendarEvent]
    @ObservationIgnored private var pendingQuery: Swift.Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inputTitle = ""
    @ObservationIgnored private var resultQuery: String?
    @ObservationIgnored private var excludedEventID: UUID?
    @ObservationIgnored private var candidateSnapshot: [CalendarEventRecommendationCandidate]?
    @ObservationIgnored private var activeQuery: QueryKey?
    @ObservationIgnored private var revision: PersistenceViewRevision?

    private struct QueryKey: Equatable {
        var title: String
        var excludedEventID: UUID?
    }

    public init(context: ModelContext) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        var failOnce = arguments.contains("--ui-testing") &&
            arguments.contains("--ui-testing-event-recommendation-failure-once")
        fetchEvents = {
            if failOnce {
                failOnce = false
                throw RecommendationFixtureFailure.unavailable
            }
            return try context.fetch(BoundedQueryService.recentCalendarEventsDescriptor())
        }
        #else
        fetchEvents = { try context.fetch(BoundedQueryService.recentCalendarEventsDescriptor()) }
        #endif
        revision = PersistenceViewRevision(context: context, domains: .calendar) { [weak self] in
            self?.invalidateCandidates()
        }
    }

    // Injection keeps failure and late-result tests independent of user storage.
    init(fetchEvents: @escaping @MainActor () async throws -> [CalendarEvent]) {
        self.fetchEvents = fetchEvents
    }

    deinit { pendingQuery?.cancel() }

    /// Call for user title edits or initial loading, never for applying/restoring a draft.
    public func update(
        title: String,
        excludingEventID: UUID? = nil,
        debounce: Duration = .milliseconds(200)
    ) {
        let query = CalendarEventReuseRules.normalizedTitle(title)
        let key = QueryKey(title: query, excludedEventID: excludingEventID)
        inputTitle = title
        excludedEventID = excludingEventID
        if activeQuery == key, state == .loading || state == .results || state == .empty {
            return
        }
        let previous = state == .results ? recommendations : loadingRecommendations
        invalidateQuery()
        lastApplication = nil
        notice = nil
        guard !query.isEmpty else { state = .idle; return }
        loadingRecommendations = previous
        activeQuery = key
        state = .loading
        let request = generation
        pendingQuery = Swift.Task { [weak self] in
            do {
                try await Swift.Task.sleep(for: debounce)
                guard !Swift.Task.isCancelled, let self else { return }
                let candidates: [CalendarEventRecommendationCandidate]
                if let candidateSnapshot {
                    candidates = candidateSnapshot
                } else {
                    let events = try await fetchEvents()
                    // A late fetch must not populate even the private cache.
                    guard !Swift.Task.isCancelled, generation == request else { return }
                    candidates = CalendarEventReuseRules.recommendationCandidates(from: events)
                    candidateSnapshot = candidates
                }
                recommendations = CalendarEventReuseRules.recommendations(
                    forNormalizedTitle: query, fromCandidates: candidates, excludingEventID: excludingEventID
                )
                loadingRecommendations = []
                resultQuery = query
                state = recommendations.isEmpty ? .empty : .results
            } catch is CancellationError {
                // A new edit, dismissal or application owns the visible state.
            } catch {
                guard !Swift.Task.isCancelled, let self, generation == request else { return }
                loadingRecommendations = []
                state = .failed
            }
        }
    }

    public func retry() {
        guard state == .failed else { return }
        candidateSnapshot = nil
        update(title: inputTitle, excludingEventID: excludedEventID)
    }

    /// Calendar saves/imports and day/time-zone changes expire prepared values.
    /// A closed panel stays closed; applying a snapshot never changes the source.
    func invalidateCandidates() {
        candidateSnapshot = nil
        activeQuery = nil
        if state == .loading || state == .results || state == .empty {
            update(title: inputTitle, excludingEventID: excludedEventID)
        } else {
            invalidateQuery()
        }
    }

    public func dismissRecommendations() {
        invalidateQuery()
        state = .dismissed
    }

    @discardableResult
    public func moveSelection(by offset: Int) -> Bool {
        guard state == .results, !recommendations.isEmpty else { return false }
        let index = recommendations.firstIndex { $0.id == selectedID }
        let next = index.map { min(max($0 + offset, 0), recommendations.count - 1) }
            ?? (offset > 0 ? 0 : recommendations.count - 1)
        selectedID = recommendations[next].id
        return true
    }

    public func apply(id: UUID, to draft: CalendarEventReuseDraft) -> CalendarEventReuseDraft? {
        guard state == .results,
              resultQuery == CalendarEventReuseRules.normalizedTitle(draft.title),
              let recommendation = recommendations.first(where: { $0.id == id }) else { return nil }
        let application = CalendarEventRecommendationApplication(recommendation: recommendation, draft: draft)
        invalidateQuery()
        lastApplication = application
        notice = nil
        state = .applied
        return application.after
    }

    public func replacePreservedNote(in draft: CalendarEventReuseDraft) -> CalendarEventReuseDraft? {
        invalidateApplication(ifEdited: draft)
        guard let application = lastApplication, application.canReplaceNote else { return nil }
        let replacement = application.replacingNote()
        lastApplication = replacement
        return replacement.after
    }

    public func undo(in draft: CalendarEventReuseDraft) -> CalendarEventReuseDraft? {
        invalidateApplication(ifEdited: draft)
        guard let application = lastApplication, application.canUndo else { return nil }
        lastApplication = nil
        notice = "추천 적용을 되돌렸어요"
        state = .dismissed
        return application.before
    }

    /// UI nil/empty/default conversions are not edits. A changed visible value expires
    /// the entire receipt, so undo can never overwrite later manual changes.
    public func invalidateApplication(ifEdited draft: CalendarEventReuseDraft) {
        guard let application = lastApplication,
              !application.after.hasSameEditorValues(as: draft) else { return }
        lastApplication = nil
        notice = nil
        if state == .applied { state = .dismissed }
    }

    private func invalidateQuery() {
        pendingQuery?.cancel()
        generation += 1
        recommendations = []
        loadingRecommendations = []
        selectedID = nil
        resultQuery = nil
        activeQuery = nil
    }
}

#if DEBUG
@available(watchOS 11, *)
private enum RecommendationFixtureFailure: Error { case unavailable }
#endif
