import Foundation
import Testing
@testable import EasyTaskCore

@Test
func boardDeepLinksRoundTripTodayAndExplicitDates() throws {
    let todayURL = try #require(PlanBaseDeepLink.boardTodayURL())
    let datedURL = try #require(PlanBaseDeepLink.boardURL(dayKey: "2026-07-16"))

    #expect(todayURL.absoluteString == "planbase://board?scope=today")
    #expect(PlanBaseDeepLink.boardRoute(from: todayURL) == .today)
    #expect(PlanBaseDeepLink.boardRoute(from: datedURL) == .day("2026-07-16"))
    #expect(
        PlanBaseDeepLink.boardRoute(
            from: URL(string: "easytask://board?scope=today")!
        ) == .today
    )
    #expect(
        PlanBaseDeepLink.boardRoute(
            from: URL(string: "easytask://board?date=2026-07-16")!
        ) == .day("2026-07-16")
    )
}

@Test
func boardDeepLinksRejectAmbiguousAndInvalidRoutes() {
    #expect(PlanBaseDeepLink.boardURL(dayKey: "2026-02-31") == nil)
    #expect(PlanBaseDeepLink.boardRoute(
        from: URL(string: "planbase://board?scope=today&date=2026-07-16")!
    ) == nil)
    #expect(PlanBaseDeepLink.boardRoute(
        from: URL(string: "planbase://board?scope=tomorrow")!
    ) == nil)
    #expect(PlanBaseDeepLink.boardRoute(
        from: URL(string: "planbase://board?date=2026-02-31")!
    ) == nil)
    #expect(PlanBaseDeepLink.boardRoute(
        from: URL(string: "https://example.com/board?scope=today")!
    ) == nil)
}

@Test
func boardTodayRouteResolvesAtHandlingTime() {
    let route = PlanBaseBoardRoute.today

    #expect(route.resolvedDayKey(todayDayKey: "2026-07-16") == "2026-07-16")
    #expect(route.resolvedDayKey(todayDayKey: "2026-07-17") == "2026-07-17")
    #expect(
        PlanBaseBoardRoute.day("2026-07-10")
            .resolvedDayKey(todayDayKey: "2026-07-17") == "2026-07-10"
    )
}
