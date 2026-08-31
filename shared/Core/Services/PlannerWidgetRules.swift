import Foundation

public enum PlannerWidgetTaskStatus: String, Codable, Equatable, Sendable {
    case todo
    case doing
}

public struct PlannerWidgetTaskPreview: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let renderID: UUID
    public let title: String
    public let status: PlannerWidgetTaskStatus
    public let order: Double

    public init(
        id: UUID,
        renderID: UUID? = nil,
        title: String,
        status: PlannerWidgetTaskStatus,
        order: Double
    ) {
        self.id = id
        self.renderID = renderID ?? id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.status = status
        self.order = order
    }
}

public enum PlannerWidgetRules {
    public static let maximumPreviewCountPerDay = 6

    @MainActor
    public static func makeTaskPreviewsByDayKey(
        tasks: [Task],
        referenceDate: Date = Date()
    ) -> [String: [PlannerWidgetTaskPreview]] {
        let startDate = DayKey.startOfDay(for: referenceDate)
        let representatives = representativeTasks(
            from: tasks.filter {
                $0.supersededAt == nil
                    && $0.archivedAt == nil
                    && snapshotStatus(for: $0.status) != nil
                    && !normalizedTitle($0.title).isEmpty
            }
        )

        return Dictionary(uniqueKeysWithValues: (0..<LockScreenWidgetRules.coverageDayCount).map {
            offset in
            let dayKey = DayKey.key(for: DayKey.addingDays(offset, to: startDate))
            let previews = representatives
                .filter { $0.plannedDayKey == dayKey }
                .sorted(by: taskSort)
                .prefix(maximumPreviewCountPerDay)
                .compactMap(preview)
            return (dayKey, Array(previews))
        })
    }

    @MainActor
    private static func representativeTasks(from tasks: [Task]) -> [Task] {
        Dictionary(grouping: tasks, by: \.id).values.compactMap { candidates in
            candidates.max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.instanceID.uuidString < rhs.instanceID.uuidString
            }
        }
    }

    @MainActor
    private static func taskSort(_ lhs: Task, _ rhs: Task) -> Bool {
        let lhsStatus = snapshotStatus(for: lhs.status)
        let rhsStatus = snapshotStatus(for: rhs.status)
        if lhsStatus != rhsStatus {
            return lhsStatus == .doing
        }
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        let lhsTitle = normalizedTitle(lhs.title)
        let rhsTitle = normalizedTitle(rhs.title)
        if lhsTitle != rhsTitle {
            return lhsTitle < rhsTitle
        }
        if lhs.id != rhs.id {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.instanceID.uuidString < rhs.instanceID.uuidString
    }

    @MainActor
    private static func preview(_ task: Task) -> PlannerWidgetTaskPreview? {
        guard let status = snapshotStatus(for: task.status) else { return nil }
        return PlannerWidgetTaskPreview(
            id: task.id,
            renderID: task.instanceID,
            title: task.title,
            status: status,
            order: task.order
        )
    }

    private static func snapshotStatus(for rawValue: String) -> PlannerWidgetTaskStatus? {
        switch TaskStatus(rawValue: rawValue) {
        case .todo:
            .todo
        case .doing:
            .doing
        case .done, .none:
            nil
        }
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
