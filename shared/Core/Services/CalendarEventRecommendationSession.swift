import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class CalendarEventRecommendationSession {
    public private(set) var recommendations: [CalendarEventRecommendation] = []
    public private(set) var isLoading = false

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var pendingQuery: Swift.Task<Void, Never>?

    public init(context: ModelContext) {
        self.context = context
    }

    deinit {
        pendingQuery?.cancel()
    }

    public func update(
        title: String,
        excludingEventID: UUID? = nil,
        debounce: Duration = .milliseconds(200)
    ) {
        pendingQuery?.cancel()
        guard !CalendarEventReuseRules.normalizedTitle(title).isEmpty else {
            recommendations = []
            isLoading = false
            return
        }
        isLoading = true
        pendingQuery = Swift.Task { [weak self] in
            do {
                try await Swift.Task.sleep(for: debounce)
                guard !Swift.Task.isCancelled, let self else { return }
                let events = try context.fetch(
                    BoundedQueryService.recentCalendarEventsDescriptor()
                )
                guard !Swift.Task.isCancelled else { return }
                recommendations = CalendarEventReuseRules.recommendations(
                    for: title,
                    from: events,
                    excludingEventID: excludingEventID
                )
                isLoading = false
            } catch is CancellationError {
                // The newest title owns the visible suggestions.
            } catch {
                guard !Swift.Task.isCancelled else { return }
                self?.recommendations = []
                self?.isLoading = false
            }
        }
    }

    public func dismissRecommendations() {
        pendingQuery?.cancel()
        recommendations = []
        isLoading = false
    }
}
