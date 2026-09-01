import Foundation

public enum PlanBaseBoardRoute: Equatable, Sendable {
    case today
    case day(String)

    public func resolvedDayKey(todayDayKey: String = DayKey.today) -> String {
        switch self {
        case .today:
            todayDayKey
        case .day(let dayKey):
            dayKey
        }
    }
}

public enum PlanBaseBoardAction: Equatable, Sendable {
    case newTask
    case confirmCompletion(taskID: UUID)
}

public struct PlanBaseBoardNavigationRoute: Equatable, Sendable {
    public let destination: PlanBaseBoardRoute
    public let action: PlanBaseBoardAction?

    public init(destination: PlanBaseBoardRoute, action: PlanBaseBoardAction? = nil) {
        self.destination = destination
        self.action = action
    }
}

public enum PlanBaseCalendarRoute: Equatable, Sendable {
    case today
    case day(String)

    public func resolvedDayKey(todayDayKey: String = DayKey.today) -> String {
        switch self {
        case .today:
            todayDayKey
        case .day(let dayKey):
            dayKey
        }
    }
}

public enum PlanBaseDeepLink {
    public static func calendarURL(dayKey: String) -> URL? {
        guard DayKey.date(from: dayKey) != nil else { return nil }
        var components = URLComponents()
        components.scheme = CalendarWidgetConstants.deepLinkScheme
        components.host = "calendar"
        components.queryItems = [URLQueryItem(name: "date", value: dayKey)]
        return components.url
    }

    public static func calendarDayKey(from url: URL) -> String? {
        guard case .day(let dayKey) = calendarRoute(from: url) else { return nil }
        return dayKey
    }

    public static func calendarTodayURL() -> URL? {
        var components = URLComponents()
        components.scheme = CalendarWidgetConstants.deepLinkScheme
        components.host = "calendar"
        components.queryItems = [URLQueryItem(name: "scope", value: "today")]
        return components.url
    }

    public static func calendarRoute(from url: URL) -> PlanBaseCalendarRoute? {
        guard let scheme = url.scheme?.lowercased(),
              CalendarWidgetConstants.supportedDeepLinkSchemes.contains(scheme),
              url.host?.lowercased() == "calendar",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []
        guard items.allSatisfy({ $0.name == "date" || $0.name == "scope" }) else {
            return nil
        }
        let dates = components.queryItems?.filter { $0.name == "date" } ?? []
        let scopes = components.queryItems?.filter { $0.name == "scope" } ?? []
        guard dates.count <= 1, scopes.count <= 1 else { return nil }
        if let scope = scopes.first?.value {
            guard dates.isEmpty, scope == "today" else { return nil }
            return .today
        }
        if let dayKey = dates.first?.value {
            guard scopes.isEmpty, DayKey.date(from: dayKey) != nil else { return nil }
            return .day(dayKey)
        }
        return nil
    }

    public static func boardTodayURL() -> URL? {
        var components = URLComponents()
        components.scheme = CalendarWidgetConstants.deepLinkScheme
        components.host = "board"
        components.queryItems = [URLQueryItem(name: "scope", value: "today")]
        return components.url
    }

    public static func boardURL(dayKey: String) -> URL? {
        guard DayKey.date(from: dayKey) != nil else { return nil }
        var components = URLComponents()
        components.scheme = CalendarWidgetConstants.deepLinkScheme
        components.host = "board"
        components.queryItems = [URLQueryItem(name: "date", value: dayKey)]
        return components.url
    }

    public static func boardNewTaskTodayURL() -> URL? {
        boardTodayActionURL(action: "new-task")
    }

    public static func boardConfirmCompletionTodayURL(taskID: UUID) -> URL? {
        boardTodayActionURL(
            action: "confirm-completion",
            additionalItems: [URLQueryItem(name: "task", value: taskID.uuidString)]
        )
    }

    public static func boardRoute(from url: URL) -> PlanBaseBoardRoute? {
        boardNavigationRoute(from: url)?.destination
    }

    public static func boardNavigationRoute(from url: URL) -> PlanBaseBoardNavigationRoute? {
        guard let scheme = url.scheme?.lowercased(),
              CalendarWidgetConstants.supportedDeepLinkSchemes.contains(scheme),
              url.host?.lowercased() == "board",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []
        guard items.allSatisfy({
            $0.name == "scope" || $0.name == "date"
                || $0.name == "action" || $0.name == "task"
        }) else { return nil }
        let scopes = items.filter { $0.name == "scope" }
        let dates = items.filter { $0.name == "date" }
        let actions = items.filter { $0.name == "action" }
        let taskIDs = items.filter { $0.name == "task" }
        guard scopes.count <= 1, dates.count <= 1,
              actions.count <= 1, taskIDs.count <= 1 else { return nil }

        let destination: PlanBaseBoardRoute

        if let scope = scopes.first?.value {
            guard dates.isEmpty, scope == "today" else { return nil }
            destination = .today
        } else if let dayKey = dates.first?.value {
            guard scopes.isEmpty, DayKey.date(from: dayKey) != nil else { return nil }
            destination = .day(dayKey)
        } else {
            return nil
        }

        let action: PlanBaseBoardAction?
        if let actionValue = actions.first?.value {
            guard destination == .today else { return nil }
            switch actionValue {
            case "new-task":
                guard taskIDs.isEmpty else { return nil }
                action = .newTask
            case "confirm-completion":
                guard taskIDs.count == 1,
                      let rawTaskID = taskIDs.first?.value,
                      let taskID = UUID(uuidString: rawTaskID) else { return nil }
                action = .confirmCompletion(taskID: taskID)
            default:
                return nil
            }
        } else {
            guard taskIDs.isEmpty else { return nil }
            action = nil
        }
        return PlanBaseBoardNavigationRoute(destination: destination, action: action)
    }

    private static func boardTodayActionURL(
        action: String,
        additionalItems: [URLQueryItem] = []
    ) -> URL? {
        var components = URLComponents()
        components.scheme = CalendarWidgetConstants.deepLinkScheme
        components.host = "board"
        components.queryItems = [
            URLQueryItem(name: "scope", value: "today"),
            URLQueryItem(name: "action", value: action)
        ] + additionalItems
        return components.url
    }
}
