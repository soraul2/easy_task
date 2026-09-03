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
func boardActionDeepLinksRoundTripQuickAddAndCompletionConfirmation() throws {
    let taskID = UUID()
    let quickAddURL = try #require(PlanBaseDeepLink.boardNewTaskTodayURL())
    let confirmationURL = try #require(
        PlanBaseDeepLink.boardConfirmCompletionTodayURL(taskID: taskID)
    )

    #expect(quickAddURL.absoluteString == "planbase://board?scope=today&action=new-task")
    #expect(
        PlanBaseDeepLink.boardNavigationRoute(from: quickAddURL)
            == PlanBaseBoardNavigationRoute(destination: .today, action: .newTask)
    )
    #expect(
        PlanBaseDeepLink.boardNavigationRoute(from: confirmationURL)
            == PlanBaseBoardNavigationRoute(
                destination: .today,
                action: .confirmCompletion(taskID: taskID)
            )
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
    #expect(PlanBaseDeepLink.boardNavigationRoute(
        from: URL(string: "planbase://board?scope=today&action=new-task&task=bad")!
    ) == nil)
    #expect(PlanBaseDeepLink.boardNavigationRoute(
        from: URL(string: "planbase://board?date=2026-07-16&action=new-task")!
    ) == nil)
    #expect(PlanBaseDeepLink.boardNavigationRoute(
        from: URL(string: "planbase://board?scope=today&unknown=value")!
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

@Test
func focusDeepLinksRoundTripAndRejectStaleShapes() throws {
    let sessionID = UUID()
    let launcherURL = try #require(PlanBaseDeepLink.focusURL())
    let sessionURL = try #require(PlanBaseDeepLink.focusURL(sessionID: sessionID))

    #expect(launcherURL.absoluteString == "planbase://focus")
    #expect(PlanBaseDeepLink.focusRoute(from: launcherURL) == PlanBaseFocusRoute())
    #expect(
        PlanBaseDeepLink.focusRoute(from: sessionURL)
            == PlanBaseFocusRoute(sessionID: sessionID)
    )
    #expect(
        PlanBaseDeepLink.focusRoute(
            from: URL(string: "easytask://focus?session=\(sessionID.uuidString)")!
        ) == PlanBaseFocusRoute(sessionID: sessionID)
    )
    #expect(PlanBaseDeepLink.focusRoute(
        from: URL(string: "planbase://focus?session=bad")!
    ) == nil)
    #expect(PlanBaseDeepLink.focusRoute(
        from: URL(string: "planbase://focus?session=\(sessionID)&session=\(sessionID)")!
    ) == nil)
    #expect(PlanBaseDeepLink.focusRoute(
        from: URL(string: "planbase://focus?unknown=value")!
    ) == nil)
}
